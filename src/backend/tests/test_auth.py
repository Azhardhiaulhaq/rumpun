from typing import Any

from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.main import app
from app.models import Category, Household, Membership, RefreshSession, User
from app.security import get_google_verifier


class FakeGoogleVerifier:
    def __init__(
        self, claims: dict[str, Any] | None = None, error: Exception | None = None
    ) -> None:
        self.claims = claims or {}
        self.error = error

    def verify(self, token: str) -> dict[str, Any]:
        if self.error:
            raise self.error
        return self.claims


def test_registration_creates_atomic_household_context(client: TestClient, db: Session) -> None:
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": "person@example.com",
            "password": "long-enough-password",
            "display_name": "Person",
            "household_name": "Family",
        },
    )
    assert response.status_code == 201
    assert response.json()["household"]["role"] == "owner"
    assert db.scalar(select(func.count()).select_from(User)) == 1
    assert db.scalar(select(func.count()).select_from(Household)) == 1
    assert db.scalar(select(func.count()).select_from(Membership)) == 1
    assert db.scalar(select(func.count()).select_from(Category)) == 2
    assert "$argon2id$" in db.scalar(select(User)).password_credential.password_hash


def test_duplicate_registration_is_stable_error(
    client: TestClient, registered: dict[str, object]
) -> None:
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": "OWNER@example.com",
            "password": "another-long-password",
            "display_name": "Duplicate",
        },
    )
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "email_already_registered"


def test_login_success_and_failure(client: TestClient, registered: dict[str, object]) -> None:
    success = client.post(
        "/api/v1/auth/login",
        json={"email": "OWNER@example.com", "password": "correct-horse-battery-staple"},
    )
    assert success.status_code == 200
    assert success.json()["access_token"]
    failure = client.post(
        "/api/v1/auth/login",
        json={"email": "owner@example.com", "password": "wrong"},
    )
    assert failure.status_code == 401
    assert failure.json()["error"]["code"] == "invalid_credentials"


def test_refresh_rotation_reuse_and_logout(
    client: TestClient, registered: dict[str, object], db: Session
) -> None:
    first = str(registered["refresh_token"])
    rotated = client.post("/api/v1/auth/refresh", json={"refresh_token": first})
    assert rotated.status_code == 200
    second = rotated.json()["refresh_token"]
    assert second != first
    replay = client.post("/api/v1/auth/refresh", json={"refresh_token": first})
    assert replay.status_code == 401
    assert replay.json()["error"]["code"] == "refresh_token_reused"
    assert all(session.revoked_at for session in db.scalars(select(RefreshSession)))

    login = client.post(
        "/api/v1/auth/login",
        json={"email": "owner@example.com", "password": "correct-horse-battery-staple"},
    ).json()
    logout = client.post("/api/v1/auth/logout", json={"refresh_token": login["refresh_token"]})
    assert logout.status_code == 204
    after_logout = client.post(
        "/api/v1/auth/refresh", json={"refresh_token": login["refresh_token"]}
    )
    assert after_logout.status_code == 401


def test_google_verification_create_link_and_failure(client: TestClient, db: Session) -> None:
    claims = {
        "sub": "google-subject-1",
        "email": "google@example.com",
        "email_verified": True,
        "name": "Google User",
    }
    app.dependency_overrides[get_google_verifier] = lambda: FakeGoogleVerifier(claims)
    created = client.post("/api/v1/auth/google", json={"id_token": "verified-token"})
    assert created.status_code == 200
    assert db.scalar(select(User).where(User.google_subject == "google-subject-1"))

    registration = client.post(
        "/api/v1/auth/register",
        json={
            "email": "linked@example.com",
            "password": "long-enough-password",
            "display_name": "Linked",
        },
    )
    assert registration.status_code == 201
    linked_claims = {**claims, "sub": "google-subject-2", "email": "linked@example.com"}
    app.dependency_overrides[get_google_verifier] = lambda: FakeGoogleVerifier(linked_claims)
    linked = client.post("/api/v1/auth/google", json={"id_token": "verified-token"})
    assert linked.status_code == 200
    assert db.scalar(select(User).where(User.google_subject == "google-subject-2"))

    from app.errors import ApiError

    app.dependency_overrides[get_google_verifier] = lambda: FakeGoogleVerifier(
        error=ApiError(401, "invalid_google_token", "Google ID token is invalid")
    )
    failed = client.post("/api/v1/auth/google", json={"id_token": "bad-token"})
    assert failed.status_code == 401
    assert failed.json()["error"]["code"] == "invalid_google_token"


def test_google_login_rejects_inactive_linked_user(client: TestClient, db: Session) -> None:
    registration = client.post(
        "/api/v1/auth/register",
        json={
            "email": "inactive@example.com",
            "password": "long-enough-password",
            "display_name": "Inactive",
        },
    )
    assert registration.status_code == 201
    user = db.scalar(select(User).where(User.normalized_email == "inactive@example.com"))
    assert user is not None
    user.is_active = False
    db.commit()

    claims = {
        "sub": "inactive-google-subject",
        "email": "inactive@example.com",
        "email_verified": True,
        "name": "Inactive",
    }
    app.dependency_overrides[get_google_verifier] = lambda: FakeGoogleVerifier(claims)
    response = client.post("/api/v1/auth/google", json={"id_token": "verified-token"})

    assert response.status_code == 403
    assert response.json()["error"]["code"] == "user_inactive"
