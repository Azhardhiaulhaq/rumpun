import base64
from urllib.parse import parse_qs, urlparse

import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import get_settings
from app.gmail_integration import (
    GMAIL_SCOPE,
    GmailProvider,
    HistoryExpired,
    _new_message_ids,
    encrypt_refresh_token,
    sync_connection,
)
from app.gmail_processing import process_pending
from app.main import app
from app.models import (
    CandidateSource,
    CandidateState,
    GmailConnection,
    GmailMessage,
    GmailSyncJob,
    Membership,
    TransactionCandidate,
    User,
)
from app.routers.gmail import get_gmail_provider


class FakeGmailProvider(GmailProvider):
    def __init__(self) -> None:
        self.revoked: list[str] = []
        self.history_calls = 0

    def exchange_code(self, code: str, verifier: str, settings: object) -> dict[str, str]:
        assert code == "google-code"
        assert verifier
        return {
            "scope": f"openid email {GMAIL_SCOPE}",
            "refresh_token": "private-refresh-token",
            "access_token": "short-lived-access-token",
            "id_token": "identity-token",
        }

    def verify_identity(self, token: str, settings: object) -> dict[str, object]:
        assert token == "identity-token"
        return {
            "iss": "https://accounts.google.com",
            "sub": "google-user-1",
            "email": "owner@example.com",
            "email_verified": True,
        }

    def get(
        self, path: str, access_token: str, *, params: dict[str, str] | None = None
    ) -> dict[str, object]:
        assert access_token in {"short-lived-access-token", "refreshed-access-token"}
        if path == "profile":
            return {"historyId": "100", "emailAddress": "owner@example.com"}
        if path.startswith("messages/"):
            body = "Pembayaran sebesar Rp 50.000 berhasil."
            return {
                "internalDate": "1790470000000",
                "payload": {
                    "mimeType": "text/plain",
                    "headers": [
                        {"name": "From", "value": "noreply@bca.co.id"},
                        {"name": "Subject", "value": "Notifikasi Transaksi BCA"},
                    ],
                    "body": {"data": base64.urlsafe_b64encode(body.encode()).decode()},
                },
            }
        assert path == "history"
        assert params is not None and params["startHistoryId"] in {"100", "102"}
        self.history_calls += 1
        return {
            "historyId": "102",
            "history": [
                {
                    "messagesAdded": [
                        {"message": {"id": "incoming-1", "labelIds": ["INBOX"]}},
                        {"message": {"id": "outgoing-1", "labelIds": ["SENT"]}},
                    ]
                }
            ],
        }

    def refresh(self, refresh_token: str, settings: object) -> str:
        assert refresh_token == "private-refresh-token"
        return "refreshed-access-token"

    def revoke(self, refresh_token: str) -> None:
        self.revoked.append(refresh_token)


def _prepare(fake: FakeGmailProvider) -> object:
    settings = get_settings().model_copy(
        update={
            "gmail_oauth_client_id": "web-client-id",
            "gmail_oauth_client_secret": "server-only-secret",
            "gmail_oauth_redirect_uri": "https://api.example.com/api/v1/gmail/oauth/callback",
            "gmail_token_key": Fernet.generate_key().decode(),
            "jev_api_key": None,
        }
    )
    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_gmail_provider] = lambda: fake
    return settings


def test_manual_lookback_discovers_only_unseen_messages(
    client: TestClient,
    auth_headers: dict[str, str],
    db: Session,
    registered: dict[str, object],
) -> None:
    import uuid
    from datetime import UTC, datetime

    class LookbackProvider(FakeGmailProvider):
        def get(
            self, path: str, access_token: str, *, params: dict[str, str] | None = None
        ) -> dict[str, object]:
            if path == "messages":
                assert params is not None and params["q"].startswith("after:")
                return {"messages": [{"id": "seen-1"}, {"id": "new-2"}]}
            return super().get(path, access_token, params=params)

    fake = LookbackProvider()
    settings = _prepare(fake)
    user = db.scalar(select(User).where(User.email == "owner@example.com"))
    assert user is not None
    household_id = uuid.UUID(str(registered["household"]["id"]))
    connection = GmailConnection(
        user_id=user.id,
        household_id=household_id,
        google_subject="google-user-1",
        google_email=user.email,
        refresh_token_ciphertext=encrypt_refresh_token("private-refresh-token", settings),
        history_id="100",
        status="active",
        connected_at=datetime.now(UTC),
    )
    db.add(connection)
    db.flush()
    db.add(GmailMessage(connection_id=connection.id, gmail_message_id="seen-1", state="ignored"))
    db.commit()

    request = client.post("/api/v1/gmail/sync", headers=auth_headers, json={"days": 2})
    assert request.status_code == 200
    job_id = request.json()["id"]
    assert db.get(GmailSyncJob, uuid.UUID(job_id)) is not None
    assert (
        client.get(f"/api/v1/gmail/sync/{job_id}", headers=auth_headers).json()["status"]
        == "pending"
    )
    assert sync_connection(db, connection.id, settings, fake, lookback_days=2) == 1
    assert connection.history_id == "100"
    assert sync_connection(db, connection.id, settings, fake, lookback_days=2) == 0
    assert (
        db.scalar(
            select(GmailMessage.state).where(
                GmailMessage.connection_id == connection.id,
                GmailMessage.gmail_message_id == "seen-1",
            )
        )
        == "ignored"
    )


def test_connect_sync_and_disconnect(
    client: TestClient, auth_headers: dict[str, str], db: Session
) -> None:
    fake = FakeGmailProvider()
    settings = _prepare(fake)
    assert client.get("/api/v1/gmail/connection", headers=auth_headers).json() is None

    started = client.post("/api/v1/gmail/connect", headers=auth_headers)
    assert started.status_code == 200
    url = urlparse(started.json()["authorization_url"])
    query = parse_qs(url.query)
    assert query["scope"][0].endswith(GMAIL_SCOPE)
    assert query["access_type"] == ["offline"]
    assert query["code_challenge_method"] == ["S256"]
    state = query["state"][0]

    callback = client.get(
        "/api/v1/gmail/oauth/callback", params={"state": state, "code": "google-code"}
    )
    assert callback.status_code == 200
    assert "Gmail terhubung" in callback.text
    assert (
        client.get(
            "/api/v1/gmail/oauth/callback", params={"state": state, "code": "google-code"}
        ).status_code
        == 400
    )

    connection = db.scalar(select(GmailConnection))
    assert connection is not None
    assert "private-refresh-token" not in connection.refresh_token_ciphertext
    assert connection.history_id == "100"
    assert sync_connection(db, connection.id, settings, fake) == 1
    assert sync_connection(db, connection.id, settings, fake) == 0
    messages = list(db.scalars(select(GmailMessage)))
    assert [message.gmail_message_id for message in messages] == ["incoming-1"]

    status = client.get("/api/v1/gmail/connection", headers=auth_headers)
    assert status.status_code == 200
    assert status.json()["awaiting_jev_count"] == 1
    assert status.json()["classification_enabled"] is False
    assert status.json()["last_synced_at"] is not None

    class CertainTransaction:
        def probability(self, *, sender: str, subject: str, body: str) -> float:
            assert sender == "noreply@bca.co.id"
            assert "50.000" in body
            return 0.92

    assert process_pending(db, connection.id, settings, fake, CertainTransaction()).created == 1
    candidate = db.scalar(select(TransactionCandidate))
    assert candidate is not None
    assert candidate.proposed_amount_atomic == 50000
    assert process_pending(db, connection.id, settings, fake, CertainTransaction()).created == 0

    db.add(GmailMessage(connection_id=connection.id, gmail_message_id="unrelated-1"))
    db.commit()

    class NotTransaction:
        def probability(self, *, sender: str, subject: str, body: str) -> float:
            return 0.05

    assert process_pending(db, connection.id, settings, fake, NotTransaction()).created == 0
    assert len(list(db.scalars(select(TransactionCandidate)))) == 1

    db.add_all(
        [
            GmailMessage(connection_id=connection.id, gmail_message_id="failing-1"),
            GmailMessage(connection_id=connection.id, gmail_message_id="following-1"),
        ]
    )
    db.commit()

    class OneFailure:
        calls = 0

        def probability(self, *, sender: str, subject: str, body: str) -> float:
            self.calls += 1
            if self.calls == 1:
                raise RuntimeError("temporary Jev failure")
            return 0.05

    result = process_pending(db, connection.id, settings, fake, OneFailure())
    assert (result.created, result.failed) == (0, 1)
    states = {
        message.gmail_message_id: message.state for message in db.scalars(select(GmailMessage))
    }
    assert states["failing-1"] == "awaiting_jev"
    assert states["following-1"] == "ignored"

    disconnected = client.delete("/api/v1/gmail/connection", headers=auth_headers)
    assert disconnected.status_code == 204
    assert fake.revoked == ["private-refresh-token"]
    assert client.get("/api/v1/gmail/connection", headers=auth_headers).json() is None


@pytest.mark.parametrize(
    ("specific_subject", "specific_body", "expected_state"),
    [
        (
            "You have made a payment to Agreya Coffee ESB",
            "Transaction Summary From 1234567890123456 "
            "To Agreya Coffee ESB 9360091436625580712 "
            "Amount Rp 48.719 Transaction Status Successful",
            CandidateState.PENDING,
        ),
        (
            "Money arrived in your Shared Pocket",
            "A member is adding Rp48.719 into Transport Pocket.",
            # Its accounts are chosen while confirming, so it is reviewable now.
            CandidateState.PENDING,
        ),
    ],
)
def test_jago_mirrored_alerts_make_one_review_item(
    client: TestClient,
    auth_headers: dict[str, str],
    db: Session,
    specific_subject: str,
    specific_body: str,
    expected_state: CandidateState,
) -> None:
    fake = FakeGmailProvider()
    settings = _prepare(fake)
    started = client.post("/api/v1/gmail/connect", headers=auth_headers)
    state = parse_qs(urlparse(started.json()["authorization_url"]).query)["state"][0]
    assert (
        client.get(
            "/api/v1/gmail/oauth/callback", params={"state": state, "code": "google-code"}
        ).status_code
        == 200
    )
    connection = db.scalar(select(GmailConnection))
    assert connection is not None
    db.add_all(
        [
            GmailMessage(connection_id=connection.id, gmail_message_id="payment"),
            GmailMessage(connection_id=connection.id, gmail_message_id="pocket"),
        ]
    )
    db.commit()

    class JagoProvider(FakeGmailProvider):
        def get(
            self, path: str, access_token: str, *, params: dict[str, str] | None = None
        ) -> dict[str, object]:
            if path in {"messages/payment", "messages/pocket"}:
                subject = (
                    specific_subject
                    if path.endswith("payment")
                    else "There was a transaction in your Shared Pocket"
                )
                body = (
                    specific_body
                    if path.endswith("payment")
                    else "A member spent Rp48.719 from your Food and Drink Pocket."
                )
                return {
                    "internalDate": "1790401975000",
                    "payload": {
                        "mimeType": "text/plain",
                        "headers": [
                            {"name": "From", "value": "Jago <noreply@jago.com>"},
                            {"name": "Subject", "value": subject},
                        ],
                        "body": {"data": base64.urlsafe_b64encode(body.encode()).decode()},
                    },
                }
            return super().get(path, access_token, params=params)

    class CertainTransaction:
        def probability(self, *, sender: str, subject: str, body: str) -> float:
            return 0.94

    result = process_pending(db, connection.id, settings, JagoProvider(), CertainTransaction())
    assert result.created == 2
    rows = db.execute(
        select(CandidateSource, TransactionCandidate).join(
            TransactionCandidate, TransactionCandidate.source_id == CandidateSource.id
        )
    ).all()
    states = {source.metadata_json["subject"]: candidate.state for source, candidate in rows}
    assert states[specific_subject] == expected_state
    assert states["There was a transaction in your Shared Pocket"] == CandidateState.DUPLICATE
    if specific_subject.startswith("You have made a payment"):
        payment_source, payment_candidate = next(
            (source, candidate)
            for source, candidate in rows
            if source.metadata_json["subject"] == specific_subject
        )
        assert payment_source.metadata_json["recipient_name"] == "Agreya Coffee ESB"
        assert payment_source.metadata_json["recipient_account"] == "9360091436625580712"
        assert payment_candidate.proposed_description == "Agreya Coffee ESB"
        response = client.get("/api/v1/candidates", headers=auth_headers)
        assert response.status_code == 200
        item = response.json()["items"][0]
        assert item["recipient_name"] == "Agreya Coffee ESB"
        assert item["recipient_account"] == "9360091436625580712"


def test_callback_rejects_different_account(
    client: TestClient, auth_headers: dict[str, str], db: Session
) -> None:
    fake = FakeGmailProvider()
    fake.verify_identity = lambda token, settings: {  # type: ignore[method-assign]
        "sub": "other-user",
        "email": "someone@example.com",
        "email_verified": True,
    }
    _prepare(fake)
    started = client.post("/api/v1/gmail/connect", headers=auth_headers)
    state = parse_qs(urlparse(started.json()["authorization_url"]).query)["state"][0]
    callback = client.get(
        "/api/v1/gmail/oauth/callback", params={"state": state, "code": "google-code"}
    )
    assert callback.status_code == 403
    assert "Pilih akun Google yang sama" in callback.text
    assert db.scalar(select(GmailConnection)) is None


def test_callback_rejects_removed_household_member(
    client: TestClient, auth_headers: dict[str, str], db: Session
) -> None:
    fake = FakeGmailProvider()
    _prepare(fake)
    started = client.post("/api/v1/gmail/connect", headers=auth_headers)
    state = parse_qs(urlparse(started.json()["authorization_url"]).query)["state"][0]
    db.query(Membership).delete()
    db.commit()

    callback = client.get(
        "/api/v1/gmail/oauth/callback", params={"state": state, "code": "google-code"}
    )
    assert callback.status_code == 403
    assert db.scalar(select(GmailConnection)) is None


def test_expired_history_scans_only_mail_since_connection(
    client: TestClient, auth_headers: dict[str, str], db: Session
) -> None:
    fake = FakeGmailProvider()
    _prepare(fake)
    started = client.post("/api/v1/gmail/connect", headers=auth_headers)
    state = parse_qs(urlparse(started.json()["authorization_url"]).query)["state"][0]
    client.get("/api/v1/gmail/oauth/callback", params={"state": state, "code": "google-code"})
    connection = db.scalar(select(GmailConnection))
    assert connection is not None

    class ExpiredHistory(FakeGmailProvider):
        def get(
            self, path: str, access_token: str, *, params: dict[str, str] | None = None
        ) -> dict[str, object]:
            if path == "history":
                raise HistoryExpired
            if path == "messages":
                assert params is not None
                assert f"after:{int(connection.connected_at.timestamp()) - 300}" in params["q"]
                return {"messages": [{"id": "new-1"}]}
            return {"historyId": "200"}

    ids, history = _new_message_ids(ExpiredHistory(), connection, "refreshed-access-token")
    assert ids == {"new-1"}
    assert history == "200"


def _connected(db: Session, registered: dict[str, object], settings: object) -> GmailConnection:
    import uuid
    from datetime import UTC, datetime

    user = db.scalar(select(User).where(User.email == "owner@example.com"))
    assert user is not None
    connection = GmailConnection(
        user_id=user.id,
        household_id=uuid.UUID(str(registered["household"]["id"])),
        google_subject="google-user-1",
        google_email=user.email,
        refresh_token_ciphertext=encrypt_refresh_token("private-refresh-token", settings),
        history_id="100",
        status="active",
        connected_at=datetime.now(UTC),
    )
    db.add(connection)
    db.commit()
    return connection


class LookbackOf(FakeGmailProvider):
    """A mailbox whose lookback search returns the given message IDs.

    Each message body names its ID so a classifier can single one out.
    """

    def __init__(self, ids: list[str]) -> None:
        super().__init__()
        self.ids = ids

    def get(
        self, path: str, access_token: str, *, params: dict[str, str] | None = None
    ) -> dict[str, object]:
        if path == "messages":
            return {"messages": [{"id": value} for value in self.ids]}
        if path.startswith("messages/"):
            body = f"Pembayaran {path.removeprefix('messages/')} sebesar Rp 50.000 berhasil."
            email = super().get(path, access_token, params=params)
            email["payload"]["body"] = {  # type: ignore[index]
                "data": base64.urlsafe_b64encode(body.encode()).decode()
            }
            return email
        return super().get(path, access_token, params=params)


class TimesOutOn:
    """Treats every message as a transaction but times out on the named ones."""

    def __init__(self, *failing: str) -> None:
        self.failing = set(failing)

    def probability(self, *, sender: str, subject: str, body: str) -> float:
        if any(f"Pembayaran {name} " in body for name in self.failing):
            raise TimeoutError("classifier timed out")
        return 0.92


def test_lookback_with_classifier_timeouts_completes_and_keeps_its_count(
    client: TestClient,
    auth_headers: dict[str, str],
    db: Session,
    registered: dict[str, object],
) -> None:
    import uuid

    from app.gmail_sync import run_sync_job

    fake = LookbackOf(["mail-1", "mail-2", "mail-3", "mail-4"])
    settings = _prepare(fake)
    _connected(db, registered, settings)
    job_id = client.post("/api/v1/gmail/sync", headers=auth_headers, json={"days": 7}).json()["id"]

    assert run_sync_job(db, uuid.UUID(job_id), settings, fake, TimesOutOn("mail-4"))
    job = client.get(f"/api/v1/gmail/sync/{job_id}", headers=auth_headers).json()
    assert job["status"] == "complete"
    assert job["error_code"] is None
    assert job["discovered_count"] == 4
    assert job["candidate_count"] == len(list(db.scalars(select(TransactionCandidate)))) == 3
    assert job["unclassified_count"] == 1

    # Once the classifier recovers, the next sync finishes the waiting message
    # without rediscovering any email.
    later = client.post("/api/v1/gmail/sync", headers=auth_headers, json={"days": 7}).json()
    assert run_sync_job(db, uuid.UUID(later["id"]), settings, fake, TimesOutOn())
    second = client.get(f"/api/v1/gmail/sync/{later['id']}", headers=auth_headers).json()
    assert (second["status"], second["discovered_count"], second["candidate_count"]) == (
        "complete",
        0,
        1,
    )
    assert second["unclassified_count"] == 0


def test_lookback_job_keeps_candidates_counted_before_a_failure(
    client: TestClient,
    auth_headers: dict[str, str],
    db: Session,
    registered: dict[str, object],
) -> None:
    import uuid

    from app.gmail_sync import run_sync_job

    class GmailGoesAway(LookbackOf):
        refreshes = 0

        def refresh(self, refresh_token: str, settings: object) -> str:
            # Refresh one serves discovery and refresh two the first
            # classification pass. The retry pass then loses Gmail.
            self.refreshes += 1
            if self.refreshes > 2:
                raise ConnectionError("Gmail unavailable")
            return super().refresh(refresh_token, settings)

    class FirstCallTimesOut:
        calls = 0

        def probability(self, *, sender: str, subject: str, body: str) -> float:
            self.calls += 1
            if self.calls == 1:
                raise TimeoutError("classifier timed out")
            return 0.92

    fake = GmailGoesAway(["mail-1", "mail-2"])
    settings = _prepare(fake)
    _connected(db, registered, settings)
    job_id = client.post("/api/v1/gmail/sync", headers=auth_headers, json={"days": 7}).json()["id"]

    assert not run_sync_job(db, uuid.UUID(job_id), settings, fake, FirstCallTimesOut())
    job = client.get(f"/api/v1/gmail/sync/{job_id}", headers=auth_headers).json()
    assert job["status"] == "failed"
    assert job["error_code"] == "ConnectionError"
    assert job["candidate_count"] == len(list(db.scalars(select(TransactionCandidate)))) == 1


class PickByName:
    """Stands in for Jev, picking accounts and categories by name."""

    def __init__(
        self,
        account: str | None = None,
        destination: str | None = None,
        category: str | None = None,
        confidence: float = 0.95,
        fail: bool = False,
    ) -> None:
        self.names = {"account": account, "destination": destination, "category": category}
        self.confidence = confidence
        self.fail = fail
        self.offered: dict[str, list[str]] = {}

    def suggest(self, *, sender, subject, body, transaction_type, accounts, categories):  # type: ignore[no-untyped-def]
        from app.gmail_processing import Pick, Suggestion

        if self.fail:
            raise TimeoutError("Jev timed out")
        self.offered = {
            "accounts": [o.name for o in accounts],
            "categories": [o.name for o in categories],
        }

        def pick(name: str | None, options):  # type: ignore[no-untyped-def]
            if name is None or self.confidence < 0.6:
                return None
            match = next((o for o in options if o.name == name), None)
            return Pick(match.id, self.confidence) if match else None

        return Suggestion(
            account=pick(self.names["account"], accounts),
            destination=pick(self.names["destination"], accounts),
            category=pick(self.names["category"], categories),
        )


def _pocket_transfer_mailbox() -> FakeGmailProvider:
    class PocketMail(FakeGmailProvider):
        def get(self, path, access_token, *, params=None):  # type: ignore[no-untyped-def]
            if path == "messages/pocket-1":
                body = "A member is adding Rp50.000 into Food and Drink Pocket."
                return {
                    "internalDate": "1790470000000",
                    "payload": {
                        "mimeType": "text/plain",
                        "headers": [
                            {"name": "From", "value": "Jago <noreply@jago.com>"},
                            {"name": "Subject", "value": "Money arrived in your Shared Pocket"},
                        ],
                        "body": {"data": base64.urlsafe_b64encode(body.encode()).decode()},
                    },
                }
            return super().get(path, access_token, params=params)

    return PocketMail()


def _with_accounts(db: Session, connection: GmailConnection, *names: str) -> dict[str, object]:
    from app.models import AccountKind, FinancialAccount

    made = {}
    for name in names:
        account = FinancialAccount(
            household_id=connection.household_id,
            name=name,
            kind=AccountKind.BUDGET_ENVELOPE if "Pocket" in name else AccountKind.BANK,
            currency="IDR",
        )
        db.add(account)
        made[name] = account
    db.add(GmailMessage(connection_id=connection.id, gmail_message_id="pocket-1"))
    db.commit()
    return made


class Transaction:
    def probability(self, *, sender: str, subject: str, body: str) -> float:
        return 0.95


def test_jev_suggests_both_accounts_of_a_pocket_transfer(
    client: TestClient, db: Session, registered: dict[str, object]
) -> None:
    fake = _pocket_transfer_mailbox()
    settings = _prepare(fake)
    connection = _connected(db, registered, settings)
    accounts = _with_accounts(db, connection, "Jago (Azhar)", "Food and Drink Pocket")
    suggester = PickByName(account="Jago (Azhar)", destination="Food and Drink Pocket")

    assert process_pending(db, connection.id, settings, fake, Transaction(), suggester).created == 1
    candidate = db.scalar(select(TransactionCandidate))
    assert candidate is not None
    assert candidate.proposed_type == "transfer"
    assert candidate.proposed_account_id == accounts["Jago (Azhar)"].id  # type: ignore[attr-defined]
    assert candidate.proposed_destination_account_id == accounts["Food and Drink Pocket"].id  # type: ignore[attr-defined]
    assert candidate.state == CandidateState.PENDING
    assert candidate.source.metadata_json["suggested"]["account_id"] == str(
        accounts["Jago (Azhar)"].id  # type: ignore[attr-defined]
    )
    # Equity and other currencies are never offered as an account.
    assert "Household equity" not in suggester.offered["accounts"]


def test_unsure_or_failing_jev_leaves_the_fields_for_the_person(
    client: TestClient, db: Session, registered: dict[str, object]
) -> None:
    fake = _pocket_transfer_mailbox()
    settings = _prepare(fake)
    connection = _connected(db, registered, settings)
    _with_accounts(db, connection, "Jago (Azhar)", "Food and Drink Pocket")

    unsure = PickByName(account="Jago (Azhar)", confidence=0.43)
    assert process_pending(db, connection.id, settings, fake, Transaction(), unsure).created == 1
    candidate = db.scalar(select(TransactionCandidate))
    assert candidate is not None
    assert candidate.proposed_account_id is None
    # Still usable: the accounts are picked while confirming.
    assert candidate.state == CandidateState.PENDING

    db.delete(candidate)
    db.query(CandidateSource).delete()
    message = db.scalar(select(GmailMessage).where(GmailMessage.gmail_message_id == "pocket-1"))
    assert message is not None
    message.state = "awaiting_jev"
    db.commit()
    failing = PickByName(fail=True)
    assert process_pending(db, connection.id, settings, fake, Transaction(), failing).created == 1
    assert db.scalar(select(TransactionCandidate)) is not None


def test_suggested_fields_are_marked_until_a_person_changes_them(
    client: TestClient, auth_headers: dict[str, str], db: Session, registered: dict[str, object]
) -> None:
    fake = _pocket_transfer_mailbox()
    settings = _prepare(fake)
    connection = _connected(db, registered, settings)
    accounts = _with_accounts(
        db, connection, "Jago (Azhar)", "BCA (Azhar)", "Food and Drink Pocket"
    )
    suggester = PickByName(account="Jago (Azhar)", destination="Food and Drink Pocket")
    process_pending(db, connection.id, settings, fake, Transaction(), suggester)
    candidate = db.scalar(select(TransactionCandidate))
    assert candidate is not None

    detail = client.get(f"/api/v1/candidates/{candidate.id}", headers=auth_headers).json()
    assert sorted(detail["suggested_fields"]) == ["account_id", "destination_account_id"]

    client.patch(
        f"/api/v1/candidates/{candidate.id}",
        headers=auth_headers,
        json={"version": detail["version"], "account_id": str(accounts["BCA (Azhar)"].id)},  # type: ignore[attr-defined]
    )
    detail = client.get(f"/api/v1/candidates/{candidate.id}", headers=auth_headers).json()
    assert detail["suggested_fields"] == ["destination_account_id"]
