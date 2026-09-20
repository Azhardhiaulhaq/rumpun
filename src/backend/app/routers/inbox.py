"""Inbound transaction email.

A household forwards its bank mail to an unguessable address. The mail
provider posts each message here, Rumpun parses it into a candidate, and a
person confirms it before anything reaches the ledger.

This exists instead of Gmail OAuth because reading a mailbox needs a
restricted scope, Google verification, and a security assessment. Forwarding
needs none of that, at the cost of a one-time manual setup per household.
"""

import hashlib
import hmac
import re
import secrets
import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Header, Request
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.database import get_db
from app.errors import ApiError
from app.models import (
    AuditEvent,
    CandidateSource,
    CandidateState,
    Household,
    HouseholdInboxAddress,
    InboxAddressState,
    MembershipRole,
    TransactionCandidate,
    utcnow,
)
from app.parsing import PARSER_VERSION, parse_transaction_email
from app.schemas import (
    InboundEmailRequest,
    InboundEmailResult,
    InboxAddressResponse,
)
from app.security import AuthContext, get_auth_context

router = APIRouter(tags=["inbound email"])

MANAGER_ROLES = {MembershipRole.OWNER, MembershipRole.ADMIN}

# Gmail's confirmation mail carries a numeric code the owner must paste back.
_GMAIL_CODE = re.compile(r"\b(\d{9})\b")
_GMAIL_CONFIRM_SENDERS = ("forwarding-noreply@google.com", "noreply@google.com")


def _require_manager(auth: AuthContext) -> None:
    if auth.membership.role not in MANAGER_ROLES:
        raise ApiError(
            403, "inbox_manage_denied", "Only an owner or admin can manage this"
        )


def _new_local_part() -> str:
    """Unguessable, because anyone holding it can post candidates.

    Short enough to retype from a phone screen, long enough that guessing is
    not worth attempting.
    """
    return f"rumpun-{secrets.token_hex(6)}"


def _as_response(
    address: HouseholdInboxAddress, settings: Settings
) -> InboxAddressResponse:
    return InboxAddressResponse(
        address=f"{address.local_part}@{settings.inbound_email_domain}",
        state=address.state,
        verification_code=address.verification_code,
        message_count=address.message_count,
        last_message_at=address.last_message_at,
        created_at=address.created_at,
    )


def _active_address(db: Session, household_id: uuid.UUID) -> HouseholdInboxAddress | None:
    return db.scalar(
        select(HouseholdInboxAddress).where(
            HouseholdInboxAddress.household_id == household_id,
            HouseholdInboxAddress.state != InboxAddressState.DISABLED,
        )
    )


@router.get("/inbox/address", response_model=InboxAddressResponse | None)
def get_address(
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    settings: Annotated[Settings, Depends(get_settings)],
    db: Session = Depends(get_db),
) -> InboxAddressResponse | None:
    """The household's forwarding address, or null when none exists yet."""
    address = _active_address(db, auth.household.id)
    return None if address is None else _as_response(address, settings)


@router.post("/inbox/address", response_model=InboxAddressResponse, status_code=201)
def create_address(
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    settings: Annotated[Settings, Depends(get_settings)],
    db: Session = Depends(get_db),
) -> InboxAddressResponse:
    _require_manager(auth)
    if _active_address(db, auth.household.id) is not None:
        raise ApiError(
            409, "inbox_address_exists", "This household already has an address"
        )
    address = HouseholdInboxAddress(
        household_id=auth.household.id,
        local_part=_new_local_part(),
        created_by_user_id=auth.user.id,
    )
    db.add(address)
    db.add(
        AuditEvent(
            household_id=auth.household.id,
            actor_user_id=auth.user.id,
            event_type="inbox_address.created",
            target_type="household_inbox_address",
            target_id=address.id,
            metadata_json={},
        )
    )
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise ApiError(
            409, "inbox_address_exists", "This household already has an address"
        ) from exc
    return _as_response(address, settings)


@router.post("/inbox/address/rotate", response_model=InboxAddressResponse, status_code=201)
def rotate_address(
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    settings: Annotated[Settings, Depends(get_settings)],
    db: Session = Depends(get_db),
) -> InboxAddressResponse:
    """Retires the current address and issues a new one.

    The old row is disabled rather than deleted so past candidates keep a
    source that still resolves.
    """
    _require_manager(auth)
    current = _active_address(db, auth.household.id)
    if current is not None:
        current.state = InboxAddressState.DISABLED
        db.flush()
    address = HouseholdInboxAddress(
        household_id=auth.household.id,
        local_part=_new_local_part(),
        created_by_user_id=auth.user.id,
    )
    db.add(address)
    db.add(
        AuditEvent(
            household_id=auth.household.id,
            actor_user_id=auth.user.id,
            event_type="inbox_address.rotated",
            target_type="household_inbox_address",
            target_id=address.id,
            metadata_json={"previous": str(current.id) if current else None},
        )
    )
    db.commit()
    return _as_response(address, settings)


@router.post("/inbound/email", response_model=InboundEmailResult)
async def receive_email(
    payload: InboundEmailRequest,
    request: Request,
    settings: Annotated[Settings, Depends(get_settings)],
    db: Session = Depends(get_db),
    signature: Annotated[str | None, Header(alias="X-Rumpun-Signature")] = None,
) -> InboundEmailResult:
    """Webhook for the mail provider.

    Unauthenticated in the session sense, so it is protected by an HMAC over
    the raw body. Without that, anyone who found the URL could inject
    candidates into any household whose address they knew.
    """
    if not settings.inbound_webhook_secret:
        raise ApiError(
            503, "inbound_not_configured", "Inbound email is not configured"
        )
    raw = await request.body()
    expected = hmac.new(
        settings.inbound_webhook_secret.encode(), raw, hashlib.sha256
    ).hexdigest()
    # Constant-time, so a wrong signature cannot be refined byte by byte.
    if not signature or not hmac.compare_digest(expected, signature):
        raise ApiError(401, "invalid_signature", "Signature check failed")

    local_part = payload.to.split("@", 1)[0].strip().lower()
    address = db.scalar(
        select(HouseholdInboxAddress).where(
            HouseholdInboxAddress.local_part == local_part,
            HouseholdInboxAddress.state != InboxAddressState.DISABLED,
        )
    )
    # An unknown or retired address is accepted and dropped: telling the
    # sender which addresses exist would turn this into an oracle.
    if address is None:
        return InboundEmailResult(status="ignored", reason="unknown_address")

    household = db.get(Household, address.household_id)
    if household is None:
        return InboundEmailResult(status="ignored", reason="unknown_address")

    # Gmail's own confirmation mail is not a transaction. Capture the code so
    # the owner can finish setup without digging through a mailbox.
    if _is_gmail_confirmation(payload.sender, payload.subject):
        code = _GMAIL_CODE.search(f"{payload.subject}\n{payload.text or ''}")
        if code:
            address.verification_code = code.group(1)
            address.verification_received_at = utcnow()
            db.commit()
            return InboundEmailResult(status="verification_code", reason=None)
        return InboundEmailResult(status="ignored", reason="no_code_found")

    body = payload.text or payload.html or ""
    is_html = not payload.text and bool(payload.html)
    content_hash = hashlib.sha256(
        f"{payload.sender}|{payload.subject}|{body}".encode()
    ).hexdigest()

    message_id = payload.message_id or content_hash
    existing = db.scalar(
        select(CandidateSource).where(
            CandidateSource.household_id == household.id,
            CandidateSource.provider == "email_forward",
            CandidateSource.provider_message_id == message_id,
        )
    )
    # A provider that retries delivery must not create a second candidate.
    if existing is not None:
        return InboundEmailResult(status="duplicate", reason=None)

    parsed = parse_transaction_email(
        sender=payload.sender,
        subject=payload.subject,
        body=body,
        is_html=is_html,
    )

    source = CandidateSource(
        household_id=household.id,
        provider="email_forward",
        provider_message_id=message_id,
        sender_domain=payload.sender.rsplit("@", 1)[-1].lower().rstrip(">"),
        received_at=payload.received_at or utcnow(),
        content_hash=content_hash,
        parser_version=PARSER_VERSION,
        metadata_json={
            "subject": payload.subject[:240],
            "issuer": parsed.issuer,
            "direction": parsed.direction,
        },
    )
    db.add(source)
    db.flush()

    candidate = TransactionCandidate(
        household_id=household.id,
        source_id=source.id,
        # A candidate missing its amount cannot be confirmed as-is, and saying
        # so up front is more useful than a silent low score.
        state=CandidateState.PENDING if parsed.is_complete else CandidateState.NEEDS_INPUT,
        confidence_bps=parsed.confidence_bps,
        warnings=list(parsed.warnings),
        evidence=list(parsed.evidence),
        proposed_amount_atomic=parsed.amount_atomic,
        proposed_currency=household.base_currency,
        proposed_description=parsed.description,
        proposed_occurred_at=parsed.occurred_at or source.received_at,
    )
    db.add(candidate)

    address.message_count += 1
    address.last_message_at = utcnow()
    # The first real message proves Gmail finished verification, so the
    # address is active whether or not the code was ever shown.
    if address.state == InboxAddressState.PENDING_VERIFICATION:
        address.state = InboxAddressState.ACTIVE

    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        return InboundEmailResult(status="duplicate", reason=None)
    return InboundEmailResult(
        status="candidate_created",
        reason=None,
        candidate_id=candidate.id,
        confidence_bps=candidate.confidence_bps,
    )


def _is_gmail_confirmation(sender: str, subject: str) -> bool:
    address = sender.lower().strip().strip("<>")
    if any(known in address for known in _GMAIL_CONFIRM_SENDERS):
        return True
    return "forwarding confirmation" in subject.lower()
