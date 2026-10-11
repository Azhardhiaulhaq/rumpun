import uuid
from typing import Annotated

import jwt
from fastapi import Depends, Header
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.database import get_db
from app.errors import ApiError
from app.location_models import LocationSession
from app.models import Household, Membership, User
from app.security import AuthContext, get_auth_context


def tracking_token(item: LocationSession) -> str:
    settings = get_settings()
    return jwt.encode(
        {
            "type": "location",
            "sub": str(item.user_id),
            "session": str(item.id),
            "exp": item.expires_at,
        },
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )


def tracking_auth(
    session_id: uuid.UUID,
    authorization: Annotated[str | None, Header()] = None,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> AuthContext:
    if not authorization or not authorization.startswith("Bearer "):
        raise ApiError(401, "authentication_required", "Authentication required")
    token = authorization.removeprefix("Bearer ")
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except jwt.PyJWTError as error:
        raise ApiError(401, "invalid_location_token", "Location credential expired") from error
    if payload.get("type") == "access":
        return get_auth_context(authorization=authorization, db=db, settings=settings)
    if payload.get("type") != "location" or payload.get("session") != str(session_id):
        raise ApiError(403, "location_token_scope", "Credential is scoped to another session")
    item = db.get(LocationSession, session_id)
    if item is None or str(item.user_id) != payload.get("sub"):
        raise ApiError(403, "location_token_scope", "Invalid session owner")
    member = db.scalar(
        select(Membership).where(
            Membership.user_id == item.user_id, Membership.household_id == item.household_id
        )
    )
    user, household = db.get(User, item.user_id), db.get(Household, item.household_id)
    if member is None or user is None or not user.is_active or household is None:
        raise ApiError(403, "location_membership_lost", "Household membership unavailable")
    return AuthContext(user=user, membership=member, household=household)
