import hashlib
import secrets
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Annotated, Any, Protocol, cast

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError
from fastapi import Depends, Header
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.database import get_db
from app.errors import ApiError
from app.models import Household, Membership, RefreshSession, User, utcnow

password_hasher = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=4)


def normalize_email(email: str) -> str:
    return email.strip().casefold()


def hash_password(password: str) -> str:
    return password_hasher.hash(password)


def verify_password(password_hash: str, password: str) -> bool:
    try:
        return password_hasher.verify(password_hash, password)
    except (VerifyMismatchError, InvalidHashError):
        return False


def token_digest(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def create_access_token(user_id: uuid.UUID, settings: Settings) -> str:
    now = datetime.now(UTC)
    payload = {
        "sub": str(user_id),
        "type": "access",
        "iat": now,
        "exp": now + timedelta(minutes=settings.access_token_minutes),
        "jti": str(uuid.uuid4()),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def create_refresh_session(user_id: uuid.UUID, settings: Settings) -> tuple[str, RefreshSession]:
    raw_token = secrets.token_urlsafe(48)
    session = RefreshSession(
        family_id=uuid.uuid4(),
        user_id=user_id,
        token_digest=token_digest(raw_token),
        expires_at=utcnow() + timedelta(days=settings.refresh_token_days),
    )
    return raw_token, session


@dataclass(frozen=True)
class AuthContext:
    user: User
    membership: Membership
    household: Household


@dataclass(frozen=True)
class UserContext:
    """A signed-in user who may not belong to a household yet."""

    user: User


def decode_access_token(token: str, settings: Settings) -> uuid.UUID:
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
        if payload.get("type") != "access":
            raise ApiError(401, "invalid_access_token", "Access token is invalid")
        return uuid.UUID(payload["sub"])
    except (jwt.PyJWTError, ValueError, KeyError) as exc:
        raise ApiError(401, "invalid_access_token", "Access token is invalid") from exc


def get_user_context(
    authorization: Annotated[str | None, Header()] = None,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> UserContext:
    """Authentication without requiring a household.

    Used by the endpoints a user reaches between signing in and joining a
    household, where `get_auth_context` would reject them.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise ApiError(401, "authentication_required", "Authentication is required")
    user_id = decode_access_token(authorization.removeprefix("Bearer "), settings)
    user = db.get(User, user_id)
    if user is None or not user.is_active:
        raise ApiError(401, "authentication_required", "Authentication is required")
    return UserContext(user=user)


def get_auth_context(
    authorization: Annotated[str | None, Header()] = None,
    active_household_id: Annotated[uuid.UUID | None, Header(alias="X-Household-ID")] = None,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> AuthContext:
    if not authorization or not authorization.startswith("Bearer "):
        raise ApiError(401, "authentication_required", "Authentication is required")
    user_id = decode_access_token(authorization.removeprefix("Bearer "), settings)
    membership_query = (
        select(Membership, Household, User)
        .join(Household, Household.id == Membership.household_id)
        .join(User, User.id == Membership.user_id)
        .where(Membership.user_id == user_id, User.is_active.is_(True))
        .order_by(Membership.created_at)
    )
    if active_household_id:
        membership_query = membership_query.where(Membership.household_id == active_household_id)
    row = db.execute(membership_query).first()
    if row is None:
        raise ApiError(403, "household_access_denied", "Household access is denied")
    membership, household, user = row
    return AuthContext(user=user, membership=membership, household=household)


class GoogleTokenVerifier(Protocol):
    def verify(self, token: str) -> dict[str, Any]: ...


class StandardGoogleTokenVerifier:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def verify(self, token: str) -> dict[str, Any]:
        audiences = tuple(
            client_id
            for client_id in (
                self.settings.google_client_id,
                self.settings.google_ios_client_id,
            )
            if client_id
        )
        if not audiences:
            raise ApiError(503, "google_login_not_configured", "Google login is not configured")
        try:
            claims = id_token.verify_oauth2_token(  # type: ignore[no-untyped-call]
                token,
                google_requests.Request(),
                audience=audiences[0] if len(audiences) == 1 else list(audiences),
            )
        except ValueError as exc:
            raise ApiError(401, "invalid_google_token", "Google ID token is invalid") from exc
        if claims.get("iss") not in self.settings.google_issuers:
            raise ApiError(401, "invalid_google_issuer", "Google ID token issuer is invalid")
        if claims.get("aud") not in audiences:
            raise ApiError(401, "invalid_google_audience", "Google ID token audience is invalid")
        if not claims.get("email_verified") or not claims.get("sub") or not claims.get("email"):
            raise ApiError(401, "unverified_google_identity", "Google identity is not verified")
        return cast(dict[str, Any], claims)


def get_google_verifier(settings: Settings = Depends(get_settings)) -> GoogleTokenVerifier:
    return StandardGoogleTokenVerifier(settings)
