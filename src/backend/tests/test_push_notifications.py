import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import (
    AccountKind,
    CandidateState,
    Category,
    FinancialAccount,
    Household,
    LedgerTransaction,
    NotificationOutbox,
    Posting,
    PushDevice,
    TransactionCandidate,
    TransactionStatus,
    User,
    utcnow,
)
from app.push import dispatch_pending, queue_budget_alerts, queue_candidate_review, token_digest


class RecordingSender:
    def __init__(self) -> None:
        self.messages: list[tuple[str, str]] = []

    def send(self, token: str, title: str, body: str, data: dict[str, str], key: str) -> bool:
        self.messages.append((token, key))
        return True


def test_new_review_candidate_is_queued_once_and_cancelled_after_review(
    db: Session, candidate: TransactionCandidate, registered: dict[str, object]
) -> None:
    user_id = uuid.UUID(str(registered["user"]["id"]))
    token = "test-fcm-token-for-a-specific-device"
    db.add(
        PushDevice(
            user_id=user_id,
            household_id=candidate.household_id,
            token_digest=token_digest(token),
            token=token,
            platform="android",
        )
    )
    queue_candidate_review(db, candidate, user_id)
    queue_candidate_review(db, candidate, user_id)
    db.commit()
    assert len(db.scalars(select(NotificationOutbox)).all()) == 1
    sender = RecordingSender()
    assert dispatch_pending(db, sender) == 1
    assert len(sender.messages) == 1

    candidate.state = CandidateState.REJECTED
    db.add(
        NotificationOutbox(
            event_key="candidate:late",
            user_id=user_id,
            household_id=candidate.household_id,
            kind="candidate_review",
            title="Review",
            body="Review",
            data_json={"candidate_id": str(candidate.id)},
        )
    )
    db.commit()
    assert dispatch_pending(db, sender) == 0
    assert len(sender.messages) == 1


def test_budget_alerts_at_near_and_over_threshold(
    db: Session, registered: dict[str, object]
) -> None:
    household_id = uuid.UUID(str(registered["household"]["id"]))
    household = db.get(Household, household_id)
    assert household is not None
    user = db.scalar(select(User).where(User.email == "owner@example.com"))
    assert user is not None
    category = db.scalar(
        select(Category).where(
            Category.household_id == household_id,
            Category.category_type == "expense",
        )
    )
    assert category is not None
    category.budget_atomic = 100
    cash = db.scalar(
        select(FinancialAccount).where(
            FinancialAccount.household_id == household_id,
            FinancialAccount.kind == AccountKind.CASH,
        )
    )
    equity = db.scalar(
        select(FinancialAccount).where(
            FinancialAccount.household_id == household_id,
            FinancialAccount.kind == AccountKind.EQUITY,
        )
    )
    assert cash is not None and equity is not None

    for amount in (90, 10):
        transaction = LedgerTransaction(
            household_id=household_id,
            transaction_type="expense",
            category_id=category.id,
            status=TransactionStatus.POSTED,
            description="Budget check",
            occurred_at=utcnow(),
            created_by_user_id=user.id,
        )
        db.add(transaction)
        db.flush()
        db.add_all(
            [
                Posting(
                    household_id=household_id,
                    transaction_id=transaction.id,
                    account_id=cash.id,
                    amount_atomic=-amount,
                    currency="IDR",
                ),
                Posting(
                    household_id=household_id,
                    transaction_id=transaction.id,
                    account_id=equity.id,
                    amount_atomic=amount,
                    currency="IDR",
                ),
            ]
        )
        db.flush()
        queue_budget_alerts(db, household, category, transaction.occurred_at)
        db.commit()
    events = db.scalars(
        select(NotificationOutbox).where(NotificationOutbox.kind == "budget_alert")
    ).all()
    assert {event.title for event in events} == {
        "Anggaran hampir habis",
        "Anggaran terlampaui",
    }


def _review_candidates(
    db: Session, template: TransactionCandidate, count: int
) -> list[TransactionCandidate]:
    from datetime import UTC, datetime

    from app.models import CandidateSource

    items = []
    for index in range(count):
        source = CandidateSource(
            household_id=template.household_id,
            provider="gmail",
            provider_message_id=f"burst-{index}",
            sender_domain="bank.example",
            received_at=datetime.now(UTC),
            content_hash=f"{index:064d}",
            parser_version="bank-v1",
            metadata_json={},
        )
        db.add(source)
        db.flush()
        item = TransactionCandidate(
            household_id=template.household_id,
            source_id=source.id,
            state=CandidateState.PENDING,
            confidence_bps=9000,
            warnings=[],
            evidence=[],
            proposed_amount_atomic=1000 + index,
            proposed_currency="IDR",
        )
        db.add(item)
        db.flush()
        items.append(item)
    return items


def test_review_burst_sends_one_summary_per_device(
    db: Session, candidate: TransactionCandidate, registered: dict[str, object]
) -> None:
    user_id = uuid.UUID(str(registered["user"]["id"]))
    token = "test-fcm-token-for-a-burst-device"
    db.add(
        PushDevice(
            user_id=user_id,
            household_id=candidate.household_id,
            token_digest=token_digest(token),
            token=token,
            platform="android",
        )
    )
    burst = _review_candidates(db, candidate, 44)
    for item in burst:
        queue_candidate_review(db, item, user_id)
        db.commit()
    events = db.scalars(select(NotificationOutbox)).all()
    assert len(events) == 1
    assert events[0].body == "Ada 44 usulan dari email yang menunggu keputusanmu."

    burst[0].state = CandidateState.REJECTED
    db.commit()
    sender = RecordingSender()
    assert dispatch_pending(db, sender) == 1
    assert len(sender.messages) == 1
    sent = db.scalars(select(NotificationOutbox)).one()
    assert sent.status == "sent"
    assert sent.body == "Ada 43 usulan dari email yang menunggu keputusanmu."
    assert len(sent.data_json["candidate_ids"].split(",")) == 43

    # After delivery, a new candidate starts a fresh notice instead of
    # reopening the one already on the phone.
    queue_candidate_review(db, candidate, user_id)
    db.commit()
    assert dispatch_pending(db, sender) == 1
    assert len(sender.messages) == 2
    latest = db.scalars(
        select(NotificationOutbox).order_by(NotificationOutbox.created_at.desc())
    ).first()
    assert latest is not None
    assert latest.body == "Ada usulan dari email yang menunggu keputusanmu."
