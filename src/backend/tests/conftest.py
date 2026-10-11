import os
import uuid
from collections.abc import Generator
from datetime import UTC, datetime

os.environ.setdefault("RUMPUN_JWT_SECRET", "test-secret-that-is-longer-than-thirty-two-characters")
os.environ.setdefault("RUMPUN_DATABASE_URL", "sqlite:///./test.db")
# The inbound webhook is disabled without a secret, so the tests set one.
# Assigned rather than setdefault because compose passes an empty value
# through, which setdefault would keep.
os.environ["RUMPUN_INBOUND_WEBHOOK_SECRET"] = "test-inbound-secret"

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base, get_db
from app.main import app
from app.models import CandidateSource, CandidateState, Membership, TransactionCandidate
from app.rate_limit import limiter


@pytest.fixture
def settings():
    """The running configuration, so tests sign webhooks with the real secret."""
    from app.config import get_settings

    # Settings are cached for the process; the env above may have been read
    # before this module was imported.
    get_settings.cache_clear()
    return get_settings()


@pytest.fixture
def db() -> Generator[Session, None, None]:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine, expire_on_commit=False)
    with session_factory() as session:
        yield session
    Base.metadata.drop_all(engine)


@pytest.fixture
def client(db: Session) -> Generator[TestClient, None, None]:
    limiter.clear()

    def override_db() -> Generator[Session, None, None]:
        yield db

    app.dependency_overrides[get_db] = override_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


@pytest.fixture
def registered(client: TestClient) -> dict[str, object]:
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": "owner@example.com",
            "password": "correct-horse-battery-staple",
            "display_name": "Owner",
            "household_name": "Our household",
        },
    )
    assert response.status_code == 201
    return response.json()


@pytest.fixture
def auth_headers(registered: dict[str, object]) -> dict[str, str]:
    household = registered["household"]
    assert isinstance(household, dict)
    return {
        "Authorization": f"Bearer {registered['access_token']}",
        "X-Household-ID": str(household["id"]),
    }


@pytest.fixture
def candidate(db: Session, registered: dict[str, object]) -> TransactionCandidate:
    household_data = registered["household"]
    assert isinstance(household_data, dict)
    household_id = uuid.UUID(str(household_data["id"]))
    membership = db.query(Membership).filter_by(household_id=household_id).one()
    account_id = next(
        account.id
        for account in membership_household_accounts(db, household_id)
        if account.kind.value == "cash"
    )
    source = CandidateSource(
        household_id=household_id,
        provider="gmail",
        provider_message_id="message-1",
        sender_domain="bank.example",
        received_at=datetime.now(UTC),
        content_hash="a" * 64,
        parser_version="bank-v1",
        metadata_json={"subject_hint": "purchase"},
    )
    db.add(source)
    db.flush()
    item = TransactionCandidate(
        household_id=household_id,
        source_id=source.id,
        state=CandidateState.PENDING,
        confidence_bps=9200,
        warnings=[{"code": "merchant_normalized"}],
        evidence=[{"field": "amount", "text": "Rp 12.500"}],
        proposed_account_id=account_id,
        proposed_amount_atomic=12500,
        proposed_currency="IDR",
        proposed_description="Groceries",
        proposed_occurred_at=datetime.now(UTC),
        reviewed_by_user_id=membership.user_id,
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


def membership_household_accounts(db: Session, household_id: uuid.UUID):  # type: ignore[no-untyped-def]
    from app.models import FinancialAccount

    return db.query(FinancialAccount).filter_by(household_id=household_id).all()


@pytest.fixture
def partner(db: Session, registered: dict[str, object]) -> dict[str, object]:
    """A second household member, so household-wide notifications have a recipient."""
    from app.config import get_settings
    from app.models import MembershipRole, User
    from app.security import create_access_token

    household = registered["household"]
    assert isinstance(household, dict)
    user = User(
        email="partner@example.com",
        normalized_email="partner@example.com",
        display_name="Partner",
    )
    db.add(user)
    db.flush()
    db.add(
        Membership(
            household_id=uuid.UUID(str(household["id"])),
            user_id=user.id,
            role=MembershipRole.ADMIN,
        )
    )
    db.commit()
    return {
        "user": user,
        "headers": {
            "Authorization": f"Bearer {create_access_token(user.id, get_settings())}",
            "X-Household-ID": str(household["id"]),
        },
    }
