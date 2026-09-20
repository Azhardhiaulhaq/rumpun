import uuid
from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, Depends, status
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.database import get_db
from app.errors import ApiError
from app.models import (
    AccountKind,
    AuditEvent,
    Category,
    FinancialAccount,
    Household,
    HouseholdInvite,
    InviteState,
    Membership,
    MembershipRole,
    PasswordCredential,
    RefreshSession,
    User,
    utcnow,
)
from app.rate_limit import sensitive_endpoint
from app.schemas import (
    GoogleLoginRequest,
    HouseholdContext,
    InviteSummary,
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    RegisterRequest,
    TokenResponse,
    UserResponse,
)
from app.security import (
    GoogleTokenVerifier,
    create_access_token,
    create_refresh_session,
    get_google_verifier,
    hash_password,
    normalize_email,
    token_digest,
    verify_password,
)

router = APIRouter(prefix="/auth", tags=["authentication"])


def _first_context(
    db: Session, user_id: uuid.UUID
) -> tuple[Membership, Household] | None:
    """The user's default household, or None while they have not joined one."""
    row = db.execute(
        select(Membership, Household)
        .join(Household, Household.id == Membership.household_id)
        .where(Membership.user_id == user_id)
        .order_by(Membership.created_at)
    ).first()
    return (row[0], row[1]) if row is not None else None


def pending_invites_for(db: Session, email: str) -> list[InviteSummary]:
    rows = db.execute(
        select(HouseholdInvite, Household, User)
        .join(Household, Household.id == HouseholdInvite.household_id)
        .join(User, User.id == HouseholdInvite.invited_by_id)
        .where(
            HouseholdInvite.normalized_email == normalize_email(email),
            HouseholdInvite.state == InviteState.PENDING,
        )
        .order_by(HouseholdInvite.created_at)
    ).all()
    return [
        InviteSummary(
            id=invite.id,
            household_name=household.name,
            role=invite.role,
            invited_by_name=inviter.display_name,
            created_at=invite.created_at,
        )
        for invite, household, inviter in rows
    ]


def _token_response(
    db: Session,
    user: User,
    settings: Settings,
    *,
    family_id: uuid.UUID | None = None,
    is_new_user: bool = False,
) -> TokenResponse:
    context = _first_context(db, user.id)
    refresh_token, refresh_session = create_refresh_session(user.id, settings)
    if family_id:
        refresh_session.family_id = family_id
    db.add(refresh_session)
    db.flush()

    household_context = None
    if context is not None:
        membership, household = context
        household_context = HouseholdContext(
            id=household.id,
            name=household.name,
            role=membership.role,
            base_currency=household.base_currency,
            is_named=household.is_named,
        )

    return TokenResponse(
        access_token=create_access_token(user.id, settings),
        refresh_token=refresh_token,
        expires_in=settings.access_token_minutes * 60,
        user=UserResponse.model_validate(user),
        household=household_context,
        is_new_user=is_new_user,
        # Only offered while the user has nowhere to land; a member who already
        # belongs somewhere reviews invites from inside the app instead.
        pending_invites=(
            pending_invites_for(db, user.email) if household_context is None else []
        ),
    )


def _create_household(db: Session, user: User, requested_name: str | None) -> Household:
    household = Household(
        name=requested_name or f"Rumah {user.display_name}",
        is_named=requested_name is not None,
    )
    db.add(household)
    db.flush()
    db.add(Membership(household_id=household.id, user_id=user.id, role=MembershipRole.OWNER))
    db.add_all(
        [
            Category(household_id=household.id, name="General expense", category_type="expense"),
            Category(household_id=household.id, name="General income", category_type="income"),
            FinancialAccount(
                household_id=household.id,
                name="Cash",
                kind=AccountKind.CASH,
                currency=household.base_currency,
            ),
            FinancialAccount(
                household_id=household.id,
                name="Household equity",
                kind=AccountKind.EQUITY,
                currency=household.base_currency,
            ),
        ]
    )
    return household


@router.post(
    "/register",
    response_model=TokenResponse,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(sensitive_endpoint("register"))],
)
def register(
    payload: RegisterRequest,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> TokenResponse:
    normalized = normalize_email(str(payload.email))
    if db.scalar(select(User.id).where(User.normalized_email == normalized)):
        raise ApiError(409, "email_already_registered", "Email is already registered")
    user = User(
        email=str(payload.email),
        normalized_email=normalized,
        display_name=payload.display_name.strip(),
    )
    try:
        db.add(user)
        db.flush()
        db.add(PasswordCredential(user_id=user.id, password_hash=hash_password(payload.password)))
        # A household is only created when the caller names one. Registering
        # without a name leaves the user in onboarding, where they can accept a
        # pending invitation instead of starting a household they do not want.
        household = (
            _create_household(db, user, payload.household_name)
            if payload.household_name
            else None
        )
        db.add(
            AuditEvent(
                household_id=household.id if household else None,
                actor_user_id=user.id,
                event_type="user.registered",
                target_type="user",
                target_id=user.id,
            )
        )
        response = _token_response(db, user, settings, is_new_user=True)
        db.commit()
        return response
    except IntegrityError as exc:
        db.rollback()
        raise ApiError(409, "email_already_registered", "Email is already registered") from exc


@router.post(
    "/login",
    response_model=TokenResponse,
    dependencies=[Depends(sensitive_endpoint("login"))],
)
def login(
    payload: LoginRequest,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> TokenResponse:
    user = db.scalar(
        select(User).where(User.normalized_email == normalize_email(str(payload.email)))
    )
    valid = bool(
        user
        and user.is_active
        and user.password_credential
        and verify_password(user.password_credential.password_hash, payload.password)
    )
    if not valid or user is None:
        raise ApiError(401, "invalid_credentials", "Email or password is invalid")
    response = _token_response(db, user, settings)
    db.add(AuditEvent(actor_user_id=user.id, event_type="session.login"))
    db.commit()
    return response


@router.post(
    "/google",
    response_model=TokenResponse,
    dependencies=[Depends(sensitive_endpoint("google-login"))],
)
def google_login(
    payload: GoogleLoginRequest,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
    verifier: GoogleTokenVerifier = Depends(get_google_verifier),
) -> TokenResponse:
    claims: dict[str, Any] = verifier.verify(payload.id_token)
    subject = str(claims["sub"])
    normalized = normalize_email(str(claims["email"]))
    user = db.scalar(select(User).where(User.google_subject == subject))
    created = False
    if user is None:
        user = db.scalar(select(User).where(User.normalized_email == normalized))
        if user and user.google_subject and user.google_subject != subject:
            raise ApiError(
                409, "google_identity_conflict", "Google identity conflicts with this user"
            )
        if user:
            user.google_subject = subject
        else:
            created = True
            display_name = str(claims.get("name") or normalized.split("@", 1)[0])[:120]
            user = User(
                email=str(claims["email"]),
                normalized_email=normalized,
                display_name=display_name,
                google_subject=subject,
            )
            db.add(user)
            db.flush()
            # No household is created here. A first-time user chooses between
            # starting one and accepting an invite, otherwise an invited member
            # would land in an empty household of their own.
    if not user.is_active:
        raise ApiError(403, "user_inactive", "User account is inactive")
    response = _token_response(db, user, settings, is_new_user=created)
    db.add(AuditEvent(actor_user_id=user.id, event_type="session.google_login"))
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise ApiError(
            409, "google_identity_conflict", "Google identity is already linked"
        ) from exc
    return response


@router.post(
    "/refresh",
    response_model=TokenResponse,
    dependencies=[Depends(sensitive_endpoint("refresh"))],
)
def refresh(
    payload: RefreshRequest,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> TokenResponse:
    session = db.scalar(
        select(RefreshSession)
        .where(RefreshSession.token_digest == token_digest(payload.refresh_token))
        .with_for_update()
    )
    now = datetime.now(UTC)
    expires_at = session.expires_at if session is not None else None
    if expires_at is not None and expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=UTC)
    if session is None or expires_at is None or expires_at <= now:
        raise ApiError(401, "invalid_refresh_token", "Refresh token is invalid")
    if session.revoked_at:
        db.execute(
            update(RefreshSession)
            .where(RefreshSession.family_id == session.family_id)
            .values(revoked_at=now)
        )
        db.commit()
        raise ApiError(401, "refresh_token_reused", "Refresh token has already been used")
    user = db.get(User, session.user_id)
    if user is None or not user.is_active:
        raise ApiError(401, "invalid_refresh_token", "Refresh token is invalid")
    session.revoked_at = now
    response = _token_response(db, user, settings, family_id=session.family_id)
    replacement = db.scalar(
        select(RefreshSession)
        .where(RefreshSession.family_id == session.family_id, RefreshSession.revoked_at.is_(None))
        .order_by(RefreshSession.created_at.desc())
    )
    session.replaced_by_id = replacement.id if replacement else None
    db.add(AuditEvent(actor_user_id=user.id, event_type="session.refreshed"))
    db.commit()
    return response


@router.post(
    "/logout",
    status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(sensitive_endpoint("logout"))],
)
def logout(payload: LogoutRequest, db: Session = Depends(get_db)) -> None:
    session = db.scalar(
        select(RefreshSession).where(
            RefreshSession.token_digest == token_digest(payload.refresh_token)
        )
    )
    if session and session.revoked_at is None:
        session.revoked_at = utcnow()
        db.add(AuditEvent(actor_user_id=session.user_id, event_type="session.logout"))
        db.commit()
