import uuid
from datetime import UTC, datetime

from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import (
    AccountKind,
    CandidateState,
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
