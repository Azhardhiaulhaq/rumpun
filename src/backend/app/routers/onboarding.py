"""Endpoints a user reaches between signing in and belonging to a household.

Google sign-in no longer creates a household, so a first-time user arrives here
to either start one or accept an invitation that is waiting for their email.
"""

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.currency import normalize_currency
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
    User,
    utcnow,
)
from app.schemas import (
    HouseholdContext,
    HouseholdCreateRequest,
    InviteSummary,
)
from app.security import UserContext, get_user_context

router = APIRouter(prefix="/onboarding", tags=["onboarding"])


def create_household_for(db: Session, user: User, name: str, base_currency: str) -> Household:
    """Creates a household with its starting categories and accounts."""
    household = Household(name=name.strip(), base_currency=base_currency, is_named=True)
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


def _reject_if_already_joined(db: Session, user: User) -> None:
    if db.scalar(select(Membership.id).where(Membership.user_id == user.id)):
        raise ApiError(
            409,
            "household_already_joined",
            "This account already belongs to a household",
        )


def _invite_for(db: Session, invite_id: uuid.UUID, user: User) -> HouseholdInvite:
    invite = db.get(HouseholdInvite, invite_id)
    # An invite belonging to another address is reported as missing rather than
    # forbidden, so a wrong guess does not confirm that the invite exists.
    if invite is None or invite.normalized_email != user.normalized_email:
        raise ApiError(404, "invite_not_found", "Invitation not found")
    if invite.state != InviteState.PENDING:
        raise ApiError(409, "invite_already_resolved", "This invitation is no longer open")
    return invite


@router.get("/invites", response_model=list[InviteSummary])
def list_my_invites(
    context: Annotated[UserContext, Depends(get_user_context)],
    db: Session = Depends(get_db),
) -> list[InviteSummary]:
    from app.routers.auth import pending_invites_for

    return pending_invites_for(db, context.user.email)


@router.post(
    "/household",
    response_model=HouseholdContext,
    status_code=status.HTTP_201_CREATED,
)
def create_my_household(
    payload: HouseholdCreateRequest,
    context: Annotated[UserContext, Depends(get_user_context)],
    db: Session = Depends(get_db),
) -> HouseholdContext:
    user = context.user
    _reject_if_already_joined(db, user)

    household = create_household_for(
        db, user, payload.name, normalize_currency(payload.base_currency)
    )
    db.add(
        AuditEvent(
            household_id=household.id,
            actor_user_id=user.id,
            event_type="household.created",
            target_type="household",
            target_id=household.id,
        )
    )
    db.commit()
    db.refresh(household)

    return HouseholdContext(
        id=household.id,
        name=household.name,
        role=MembershipRole.OWNER,
        base_currency=household.base_currency,
        is_named=True,
    )


@router.post("/invites/{invite_id}/accept", response_model=HouseholdContext)
def accept_invite(
    invite_id: uuid.UUID,
    context: Annotated[UserContext, Depends(get_user_context)],
    db: Session = Depends(get_db),
) -> HouseholdContext:
    user = context.user
    _reject_if_already_joined(db, user)
    invite = _invite_for(db, invite_id, user)

    invite.state = InviteState.ACCEPTED
    invite.resolved_at = utcnow()
    db.add(Membership(household_id=invite.household_id, user_id=user.id, role=invite.role))
    db.add(
        AuditEvent(
            household_id=invite.household_id,
            actor_user_id=user.id,
            event_type="invite.accepted",
            target_type="invite",
            target_id=invite.id,
        )
    )
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise ApiError(
            409, "household_already_joined", "This account already belongs to a household"
        ) from exc

    household = db.get(Household, invite.household_id)
    assert household is not None
    return HouseholdContext(
        id=household.id,
        name=household.name,
        role=invite.role,
        base_currency=household.base_currency,
        is_named=household.is_named,
    )


@router.post(
    "/invites/{invite_id}/decline",
    status_code=status.HTTP_204_NO_CONTENT,
)
def decline_invite(
    invite_id: uuid.UUID,
    context: Annotated[UserContext, Depends(get_user_context)],
    db: Session = Depends(get_db),
) -> None:
    invite = _invite_for(db, invite_id, context.user)
    invite.state = InviteState.DECLINED
    invite.resolved_at = utcnow()
    db.add(
        AuditEvent(
            household_id=invite.household_id,
            actor_user_id=context.user.id,
            event_type="invite.declined",
            target_type="invite",
            target_id=invite.id,
        )
    )
    db.commit()
