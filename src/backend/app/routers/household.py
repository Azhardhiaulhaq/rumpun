import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.currency import default_minor_unit, normalize_currency
from app.database import get_db
from app.errors import ApiError
from app.models import (
    AccountKind,
    AuditEvent,
    FinancialAccount,
    HouseholdInvite,
    InviteState,
    Membership,
    MembershipRole,
    Posting,
    User,
    utcnow,
)
from app.schemas import (
    HouseholdContext,
    HouseholdMember,
    HouseholdPeople,
    HouseholdUpdateRequest,
    InviteCreateRequest,
    InviteResponse,
    PendingInvite,
)
from app.security import AuthContext, get_auth_context, normalize_email

router = APIRouter(prefix="/household", tags=["household"])


@router.get("", response_model=HouseholdContext)
def read_household(
    auth: Annotated[AuthContext, Depends(get_auth_context)],
) -> HouseholdContext:
    return HouseholdContext(
        id=auth.household.id,
        name=auth.household.name,
        role=auth.membership.role,
        base_currency=auth.household.base_currency,
        is_named=auth.household.is_named,
    )


@router.patch("", response_model=HouseholdContext)
def update_household(
    payload: HouseholdUpdateRequest,
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
) -> HouseholdContext:
    if auth.membership.role not in {MembershipRole.OWNER, MembershipRole.ADMIN}:
        raise ApiError(
            403, "household_edit_denied", "Only an owner or admin can edit this household"
        )

    currency = normalize_currency(payload.base_currency)

    household = auth.household
    previous_currency = household.base_currency
    household.name = payload.name.strip()
    household.timezone = payload.timezone
    household.is_named = True

    # The seeded accounts were created in the household's original currency. If
    # the owner picks a different one during setup, those untouched accounts
    # follow, otherwise the dashboard would total mixed currencies.
    if currency != previous_currency:
        household.base_currency = currency
        accounts = db.scalars(
            select(FinancialAccount).where(
                FinancialAccount.household_id == household.id,
            )
        ).all()
        untouched_defaults = (
            len(accounts) == 2
            and {(a.name, a.kind) for a in accounts}
            == {("Cash", AccountKind.CASH), ("Household equity", AccountKind.EQUITY)}
            and db.scalar(select(Posting.id).where(Posting.household_id == household.id).limit(1))
            is None
        )
        if untouched_defaults:
            for account in accounts:
                account.currency = currency
                account.minor_unit = default_minor_unit(currency)

    db.add(
        AuditEvent(
            household_id=household.id,
            actor_user_id=auth.user.id,
            event_type="household.updated",
            target_type="household",
            target_id=household.id,
        )
    )
    db.commit()
    db.refresh(household)

    return HouseholdContext(
        id=household.id,
        name=household.name,
        role=auth.membership.role,
        base_currency=household.base_currency,
        is_named=household.is_named,
    )


def _require_manager(auth: AuthContext) -> None:
    if auth.membership.role not in {MembershipRole.OWNER, MembershipRole.ADMIN}:
        raise ApiError(403, "household_edit_denied", "Only an owner or admin can manage members")


@router.get("/people", response_model=HouseholdPeople)
def list_people(
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
) -> HouseholdPeople:
    """Everyone in the household, plus invitations still waiting for an answer."""
    rows = db.execute(
        select(Membership, User)
        .join(User, User.id == Membership.user_id)
        .where(Membership.household_id == auth.household.id)
        .order_by(Membership.created_at)
    ).all()
    members = [
        HouseholdMember(
            user_id=user.id,
            display_name=user.display_name,
            email=user.email,
            role=membership.role,
            is_you=user.id == auth.user.id,
        )
        for membership, user in rows
    ]

    # Only a manager needs to see who has been invited but has not answered.
    invites: list[PendingInvite] = []
    if auth.membership.role in {MembershipRole.OWNER, MembershipRole.ADMIN}:
        invites = [
            PendingInvite(
                id=invite.id,
                email=invite.email,
                role=invite.role,
                created_at=invite.created_at,
            )
            for invite in db.scalars(
                select(HouseholdInvite)
                .where(
                    HouseholdInvite.household_id == auth.household.id,
                    HouseholdInvite.state == InviteState.PENDING,
                )
                .order_by(HouseholdInvite.created_at)
            )
        ]

    return HouseholdPeople(members=members, invites=invites)


@router.post(
    "/invites",
    response_model=InviteResponse,
    status_code=status.HTTP_201_CREATED,
)
def invite_member(
    payload: InviteCreateRequest,
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
) -> InviteResponse:
    _require_manager(auth)
    normalized = normalize_email(str(payload.email))

    if normalized == auth.user.normalized_email:
        raise ApiError(422, "cannot_invite_yourself", "You are already in this household")

    # An address that already belongs to this household needs no invitation.
    already_member = db.scalar(
        select(Membership.id)
        .join(User, User.id == Membership.user_id)
        .where(
            Membership.household_id == auth.household.id,
            User.normalized_email == normalized,
        )
    )
    if already_member:
        raise ApiError(409, "already_a_member", "That person is already in this household")

    invite = HouseholdInvite(
        household_id=auth.household.id,
        email=str(payload.email),
        normalized_email=normalized,
        role=payload.role,
        invited_by_id=auth.user.id,
    )
    db.add(invite)
    db.add(
        AuditEvent(
            household_id=auth.household.id,
            actor_user_id=auth.user.id,
            event_type="invite.created",
            target_type="invite",
            target_id=invite.id,
        )
    )
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise ApiError(
            409, "invite_already_sent", "That address already has an open invitation"
        ) from exc
    db.refresh(invite)

    return InviteResponse(
        id=invite.id,
        email=invite.email,
        role=invite.role,
        state=invite.state,
        created_at=invite.created_at,
    )


@router.delete(
    "/invites/{invite_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
def revoke_invite(
    invite_id: uuid.UUID,
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
) -> None:
    _require_manager(auth)
    invite = db.get(HouseholdInvite, invite_id)
    if invite is None or invite.household_id != auth.household.id:
        raise ApiError(404, "invite_not_found", "Invitation not found")
    if invite.state != InviteState.PENDING:
        raise ApiError(409, "invite_already_resolved", "This invitation is no longer open")

    invite.state = InviteState.REVOKED
    invite.resolved_at = utcnow()
    db.add(
        AuditEvent(
            household_id=auth.household.id,
            actor_user_id=auth.user.id,
            event_type="invite.revoked",
            target_type="invite",
            target_id=invite.id,
        )
    )
    db.commit()
