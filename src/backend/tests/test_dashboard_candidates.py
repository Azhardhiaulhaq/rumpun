import uuid
from datetime import UTC, datetime

from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import (
    AccountKind,
    CandidateState,
    Category,
    FinancialAccount,
    LedgerTransaction,
    Membership,
    MembershipRole,
    Posting,
    TransactionCandidate,
    TransactionStatus,
    User,
)


def test_cross_household_access_is_denied(
    client: TestClient, registered: dict[str, object]
) -> None:
    other = client.post(
        "/api/v1/auth/register",
        json={
            "email": "other@example.com",
            "password": "other-long-password",
            "display_name": "Other",
            "household_name": "Their household",
        },
    ).json()
    response = client.get(
        "/api/v1/dashboard",
        headers={
            "Authorization": f"Bearer {registered['access_token']}",
            "X-Household-ID": other["household"]["id"],
        },
    )
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "household_access_denied"


def test_dashboard_balance_is_derived_from_posted_postings(
    client: TestClient,
    db: Session,
    registered: dict[str, object],
    auth_headers: dict[str, str],
) -> None:
    household_id = uuid.UUID(str(registered["household"]["id"]))  # type: ignore[index]
    membership = db.scalar(select(Membership).where(Membership.household_id == household_id))
    accounts = list(
        db.scalars(select(FinancialAccount).where(FinancialAccount.household_id == household_id))
    )
    cash = next(account for account in accounts if account.kind == AccountKind.CASH)
    equity = next(account for account in accounts if account.kind == AccountKind.EQUITY)
    posted = LedgerTransaction(
        household_id=household_id,
        transaction_type="opening_balance",
        status=TransactionStatus.POSTED,
        description="Opening balance",
        occurred_at=datetime.now(UTC),
        created_by_user_id=membership.user_id,
    )
    draft = LedgerTransaction(
        household_id=household_id,
        transaction_type="adjustment",
        status=TransactionStatus.DRAFT,
        description="Unposted",
        occurred_at=datetime.now(UTC),
        created_by_user_id=membership.user_id,
    )
    db.add_all([posted, draft])
    db.flush()
    for transaction, amount in [(posted, 50000), (draft, 90000)]:
        db.add_all(
            [
                Posting(
                    household_id=household_id,
                    transaction_id=transaction.id,
                    account_id=cash.id,
                    amount_atomic=amount,
                    currency="IDR",
                ),
                Posting(
                    household_id=household_id,
                    transaction_id=transaction.id,
                    account_id=equity.id,
                    amount_atomic=-amount,
                    currency="IDR",
                ),
            ]
        )
    db.commit()
    response = client.get("/api/v1/dashboard", headers=auth_headers)
    assert response.status_code == 200
    body = response.json()
    cash_result = next(account for account in body["accounts"] if account["kind"] == "cash")
    assert cash_result["balance_atomic"] == 50000
    assert body["totals_by_currency"] == {"IDR": 50000}
    assert len(body["recent_transactions"]) == 1


def test_candidate_list_detail_and_edit_conflict(
    client: TestClient,
    candidate: TransactionCandidate,
    auth_headers: dict[str, str],
) -> None:
    listing = client.get("/api/v1/candidates?limit=1", headers=auth_headers)
    assert listing.status_code == 200
    assert listing.json()["items"][0]["id"] == str(candidate.id)
    detail = client.get(f"/api/v1/candidates/{candidate.id}", headers=auth_headers)
    assert detail.status_code == 200
    assert detail.json()["source"]["provider"] == "gmail"
    assert detail.json()["confidence_bps"] == 9200
    assert listing.json()["items"][0]["direction"] is None

    edit = client.patch(
        f"/api/v1/candidates/{candidate.id}",
        headers=auth_headers,
        json={"version": 1, "description": "Edited groceries", "amount_atomic": 13000},
    )
    assert edit.status_code == 200
    assert edit.json()["version"] == 2
    stale = client.patch(
        f"/api/v1/candidates/{candidate.id}",
        headers=auth_headers,
        json={"version": 1, "description": "Stale"},
    )
    assert stale.status_code == 409
    assert stale.json()["error"]["code"] == "candidate_version_conflict"


def test_confirmation_is_idempotent_and_balanced(
    client: TestClient,
    db: Session,
    candidate: TransactionCandidate,
    auth_headers: dict[str, str],
) -> None:
    headers = {**auth_headers, "Idempotency-Key": "confirm-candidate-1"}
    first = client.post(
        f"/api/v1/candidates/{candidate.id}/confirm", headers=headers, json={"version": 1}
    )
    assert first.status_code == 200
    second = client.post(
        f"/api/v1/candidates/{candidate.id}/confirm", headers=headers, json={"version": 1}
    )
    assert second.status_code == 200
    assert second.json()["replayed"] is True
    assert second.json()["transaction_id"] == first.json()["transaction_id"]
    transaction_id = uuid.UUID(first.json()["transaction_id"])
    postings = list(db.scalars(select(Posting).where(Posting.transaction_id == transaction_id)))
    assert len(postings) == 2
    assert sum(posting.amount_atomic for posting in postings) == 0
    assert db.scalar(select(func.count()).select_from(LedgerTransaction)) == 1
    different_key = client.post(
        f"/api/v1/candidates/{candidate.id}/confirm",
        headers={**auth_headers, "Idempotency-Key": "different-key"},
        json={"version": 2},
    )
    assert different_key.status_code == 409
    assert different_key.json()["error"]["code"] == "candidate_already_confirmed"


def test_gmail_transfer_requires_a_destination(
    client: TestClient,
    db: Session,
    candidate: TransactionCandidate,
    auth_headers: dict[str, str],
) -> None:
    candidate.source.metadata_json = {"direction": "transfer"}
    db.commit()
    response = client.post(
        f"/api/v1/candidates/{candidate.id}/confirm",
        headers={**auth_headers, "Idempotency-Key": "transfer-not-expense"},
        json={"version": candidate.version},
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "candidate_destination_required"
    assert db.scalar(select(func.count()).select_from(LedgerTransaction)) == 0


def test_reject_duplicate_and_forbidden_transitions(
    client: TestClient,
    db: Session,
    candidate: TransactionCandidate,
    auth_headers: dict[str, str],
    registered: dict[str, object],
) -> None:
    rejected = client.post(
        f"/api/v1/candidates/{candidate.id}/reject", headers=auth_headers, json={"version": 1}
    )
    assert rejected.status_code == 200
    assert rejected.json()["state"] == "rejected"
    forbidden = client.post(
        f"/api/v1/candidates/{candidate.id}/duplicate",
        headers=auth_headers,
        json={"version": 2},
    )
    assert forbidden.status_code == 409
    assert forbidden.json()["error"]["code"] == "candidate_state_conflict"

    source = candidate.source
    duplicate_candidate = TransactionCandidate(
        household_id=candidate.household_id,
        source_id=source.id,
        state=CandidateState.NEEDS_INPUT,
        confidence_bps=5000,
        warnings=[],
        evidence=[],
    )
    db.add(duplicate_candidate)
    db.commit()
    duplicate = client.post(
        f"/api/v1/candidates/{duplicate_candidate.id}/duplicate",
        headers=auth_headers,
        json={"version": 1},
    )
    assert duplicate.status_code == 200
    assert duplicate.json()["state"] == "duplicate"


def test_viewer_cannot_review_candidate(
    client: TestClient,
    db: Session,
    candidate: TransactionCandidate,
    registered: dict[str, object],
) -> None:
    user = User(
        email="viewer@example.com", normalized_email="viewer@example.com", display_name="Viewer"
    )
    db.add(user)
    db.flush()
    db.add(
        Membership(household_id=candidate.household_id, user_id=user.id, role=MembershipRole.VIEWER)
    )
    db.commit()
    from app.config import get_settings
    from app.security import create_access_token

    headers = {
        "Authorization": f"Bearer {create_access_token(user.id, get_settings())}",
        "X-Household-ID": str(candidate.household_id),
    }
    response = client.post(
        f"/api/v1/candidates/{candidate.id}/reject", headers=headers, json={"version": 1}
    )
    assert response.status_code == 403


def _post(
    db: Session,
    household_id: uuid.UUID,
    user_id: uuid.UUID,
    kind: str,
    occurred_at: datetime,
    legs: list[tuple[FinancialAccount, int]],
) -> None:
    transaction = LedgerTransaction(
        household_id=household_id,
        transaction_type=kind,
        status=TransactionStatus.POSTED,
        description=kind,
        occurred_at=occurred_at,
        created_by_user_id=user_id,
    )
    db.add(transaction)
    db.flush()
    for account, amount in legs:
        db.add(
            Posting(
                household_id=household_id,
                transaction_id=transaction.id,
                account_id=account.id,
                amount_atomic=amount,
                currency=account.currency,
            )
        )


def test_trends_counts_spending_but_not_transfers(
    client: TestClient,
    db: Session,
    registered: dict[str, object],
    auth_headers: dict[str, str],
) -> None:
    """Moving money between your own pockets is not spending it.

    Both sides of a transfer are real postings, one of them negative, so a
    naive "every negative posting is an expense" reading would report a
    household that moved savings into a spending envelope as having spent it.
    """
    household_id = uuid.UUID(str(registered["household"]["id"]))  # type: ignore[index]
    membership = db.scalar(select(Membership).where(Membership.household_id == household_id))
    accounts = list(
        db.scalars(select(FinancialAccount).where(FinancialAccount.household_id == household_id))
    )
    cash = next(a for a in accounts if a.kind == AccountKind.CASH)
    equity = next(a for a in accounts if a.kind == AccountKind.EQUITY)
    pocket = FinancialAccount(
        household_id=household_id,
        name="Pos belanja",
        kind=AccountKind.BUDGET_ENVELOPE,
        currency="IDR",
    )
    db.add(pocket)
    db.flush()

    now = datetime.now(UTC)
    _post(db, household_id, membership.user_id, "income", now, [(cash, 900000), (equity, -900000)])
    _post(db, household_id, membership.user_id, "expense", now, [(cash, -150000), (equity, 150000)])
    # Same money, different pocket: net worth is unchanged and nothing was spent.
    _post(
        db,
        household_id,
        membership.user_id,
        "transfer",
        now,
        [(cash, -400000), (pocket, 400000)],
    )
    db.commit()

    body = client.get("/api/v1/dashboard/trends", headers=auth_headers).json()
    current = body["buckets"][-1]
    assert current["spent_atomic"] == 150000, "the transfer must not count as spending"
    assert current["received_atomic"] == 900000
    # Net worth still moves with every posting, transfers included, because it
    # is simply what the accounts hold.
    assert current["net_worth_atomic"] == 750000


def test_trends_keeps_currency_series_separate(
    client: TestClient,
    db: Session,
    registered: dict[str, object],
    auth_headers: dict[str, str],
) -> None:
    household_id = uuid.UUID(str(registered["household"]["id"]))  # type: ignore[index]
    membership = db.scalar(select(Membership).where(Membership.household_id == household_id))
    dollar_cash = FinancialAccount(
        household_id=household_id,
        name="Dollar cash",
        kind=AccountKind.FOREIGN_CURRENCY,
        currency="USD",
    )
    dollar_equity = FinancialAccount(
        household_id=household_id,
        name="Dollar equity",
        kind=AccountKind.EQUITY,
        currency="USD",
    )
    db.add_all([dollar_cash, dollar_equity])
    db.flush()
    now = datetime.now(UTC)
    _post(
        db,
        household_id,
        membership.user_id,
        "income",
        now,
        [(dollar_cash, 25000), (dollar_equity, -25000)],
    )
    _post(
        db,
        household_id,
        membership.user_id,
        "expense",
        now,
        [(dollar_cash, -3500), (dollar_equity, 3500)],
    )
    db.commit()

    base = client.get("/api/v1/dashboard/trends", headers=auth_headers).json()
    dollars = client.get("/api/v1/dashboard/trends?currency=usd", headers=auth_headers).json()
    assert base["currency"] == "IDR"
    assert all(bucket["spent_atomic"] == 0 for bucket in base["buckets"])
    assert dollars["currency"] == "USD"
    assert dollars["buckets"][-1]["spent_atomic"] == 3500
    assert dollars["buckets"][-1]["received_atomic"] == 25000
    assert dollars["buckets"][-1]["net_worth_atomic"] == 21500


def test_trends_marks_the_running_period_and_withholds_a_comparison(
    client: TestClient,
    registered: dict[str, object],
    auth_headers: dict[str, str],
) -> None:
    """A period in progress is not a smaller period.

    Charting today's partial week against last week's whole one would show a
    collapse every Monday, so the last bucket is flagged and kept out of the
    change figure.
    """
    body = client.get("/api/v1/dashboard/trends", headers=auth_headers).json()
    assert body["buckets"][-1]["complete"] is False
    assert all(b["complete"] for b in body["buckets"][:-1])
    # A household with no finished history has nothing to compare against, and
    # inventing a percentage from zero would be a fabricated trend.
    assert body["change_bps"] is None
    assert body["spend_change_bps"] is None


def test_confirm_names_the_paying_account_when_email_did_not(
    client: TestClient,
    db: Session,
    candidate: TransactionCandidate,
    auth_headers: dict[str, str],
) -> None:
    """Gmail candidates arrive without an account; the reviewer supplies it."""
    account_id = candidate.proposed_account_id
    candidate.proposed_account_id = None
    db.commit()
    headers = {**auth_headers, "Idempotency-Key": "confirm-with-account"}

    missing = client.post(
        f"/api/v1/candidates/{candidate.id}/confirm",
        headers={**auth_headers, "Idempotency-Key": "confirm-without-account"},
        json={"version": 1},
    )
    assert missing.status_code == 422
    assert missing.json()["error"]["code"] == "candidate_account_required"

    body = {"version": 1, "account_id": str(account_id)}
    first = client.post(f"/api/v1/candidates/{candidate.id}/confirm", headers=headers, json=body)
    assert first.status_code == 200
    retry = client.post(f"/api/v1/candidates/{candidate.id}/confirm", headers=headers, json=body)
    assert retry.json()["replayed"] is True
    postings = list(
        db.scalars(
            select(Posting).where(
                Posting.transaction_id == uuid.UUID(first.json()["transaction_id"])
            )
        )
    )
    assert {p.account_id: p.amount_atomic for p in postings}[account_id] == -12500
    db.refresh(candidate)
    assert candidate.proposed_account_id == account_id


def test_confirm_files_the_expense_under_the_chosen_category(
    client: TestClient,
    db: Session,
    candidate: TransactionCandidate,
    auth_headers: dict[str, str],
) -> None:
    groceries = Category(
        household_id=candidate.household_id, name="Groceries", category_type="expense"
    )
    salary = Category(household_id=candidate.household_id, name="Salary", category_type="income")
    db.add_all([groceries, salary])
    db.commit()

    wrong_type = client.post(
        f"/api/v1/candidates/{candidate.id}/confirm",
        headers={**auth_headers, "Idempotency-Key": "confirm-income-category"},
        json={"version": 1, "category_id": str(salary.id)},
    )
    assert wrong_type.status_code == 422
    assert wrong_type.json()["error"]["code"] == "invalid_category"

    confirmed = client.post(
        f"/api/v1/candidates/{candidate.id}/confirm",
        headers={**auth_headers, "Idempotency-Key": "confirm-groceries"},
        json={"version": 1, "category_id": str(groceries.id)},
    )
    assert confirmed.status_code == 200
    transaction = db.get(LedgerTransaction, uuid.UUID(confirmed.json()["transaction_id"]))
    assert transaction is not None
    assert transaction.category_id == groceries.id


def test_forwarded_income_is_booked_as_income(
    client: TestClient,
    db: Session,
    candidate: TransactionCandidate,
    auth_headers: dict[str, str],
) -> None:
    candidate.source.provider = "email_forward"
    candidate.source.metadata_json = {"direction": "income"}
    db.commit()
    response = client.post(
        f"/api/v1/candidates/{candidate.id}/confirm",
        headers={**auth_headers, "Idempotency-Key": "forwarded-income"},
        json={"version": candidate.version},
    )
    assert response.status_code == 200
    transaction = db.get(LedgerTransaction, uuid.UUID(response.json()["transaction_id"]))
    assert transaction is not None
    assert transaction.transaction_type == "income"
    postings = list(db.scalars(select(Posting).where(Posting.transaction_id == transaction.id)))
    assert sum(posting.amount_atomic for posting in postings) == 0
    assert any(posting.amount_atomic > 0 for posting in postings)


def test_card_carries_direction_and_issuer(
    client: TestClient,
    db: Session,
    candidate: TransactionCandidate,
    auth_headers: dict[str, str],
) -> None:
    candidate.source.metadata_json = {"direction": "income", "issuer": "GoPay"}
    db.commit()
    item = client.get("/api/v1/candidates", headers=auth_headers).json()["items"][0]
    assert item["direction"] == "income"
    assert item["issuer"] == "GoPay"


def _household_accounts(db: Session, household_id: uuid.UUID) -> list[FinancialAccount]:
    return list(
        db.scalars(
            select(FinancialAccount).where(
                FinancialAccount.household_id == household_id,
                FinancialAccount.kind != AccountKind.EQUITY,
            )
        )
    )


def test_completing_a_needs_input_transfer_makes_it_confirmable(
    client: TestClient,
    db: Session,
    candidate: TransactionCandidate,
    auth_headers: dict[str, str],
) -> None:
    # A Jago "Money arrived in your Shared Pocket" email: the parser reads the
    # amount but cannot name either account, so the card needs input.
    candidate.state = CandidateState.NEEDS_INPUT
    candidate.proposed_type = "transfer"
    candidate.proposed_account_id = None
    candidate.warnings = ["transfer_needs_account_mapping", "date_not_found"]
    db.add(
        FinancialAccount(
            household_id=candidate.household_id,
            name="Food and Drink Pocket",
            kind=AccountKind.BUDGET_ENVELOPE,
            currency="IDR",
        )
    )
    db.commit()
    accounts = _household_accounts(db, candidate.household_id)
    source, destination = accounts[0], accounts[-1]

    half = client.patch(
        f"/api/v1/candidates/{candidate.id}",
        headers=auth_headers,
        json={"version": 1, "account_id": str(source.id)},
    )
    assert half.status_code == 200
    # The destination is chosen while confirming, so the card is already usable.
    assert half.json()["state"] == "pending"

    complete = client.patch(
        f"/api/v1/candidates/{candidate.id}",
        headers=auth_headers,
        json={"version": 2, "destination_account_id": str(destination.id)},
    )
    assert complete.status_code == 200
    assert complete.json()["state"] == "pending"

    confirmed = client.post(
        f"/api/v1/candidates/{candidate.id}/confirm",
        headers={**auth_headers, "Idempotency-Key": "complete-transfer"},
        json={"version": 3},
    )
    assert confirmed.status_code == 200
    postings = {
        posting.account_id: posting.amount_atomic
        for posting in db.scalars(
            select(Posting).where(
                Posting.transaction_id == uuid.UUID(confirmed.json()["transaction_id"])
            )
        )
    }
    assert postings == {source.id: -12500, destination.id: 12500}


def test_transfer_to_the_same_account_still_needs_input(
    client: TestClient,
    db: Session,
    candidate: TransactionCandidate,
    auth_headers: dict[str, str],
) -> None:
    candidate.proposed_type = "transfer"
    db.commit()
    account_id = str(candidate.proposed_account_id)
    response = client.patch(
        f"/api/v1/candidates/{candidate.id}",
        headers=auth_headers,
        json={"version": 1, "destination_account_id": account_id},
    )
    assert response.status_code == 200
    assert response.json()["state"] == "needs_input"
