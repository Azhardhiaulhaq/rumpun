import base64
import hashlib
import json
import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, Header, Query
from sqlalchemy import and_, exists, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app.candidate_rules import settle_state
from app.candidate_rules import transaction_type as transaction_type_of
from app.database import get_db
from app.errors import ApiError
from app.models import (
    AccountAccessGrant,
    AccountKind,
    AuditEvent,
    CandidateState,
    Category,
    FinancialAccount,
    IdempotencyRecord,
    LedgerTransaction,
    MembershipRole,
    Posting,
    TransactionCandidate,
    TransactionStatus,
    utcnow,
)
from app.push import queue_budget_alerts
from app.schemas import (
    CandidateActionRequest,
    CandidateConfirmRequest,
    CandidateDetail,
    CandidateEditRequest,
    CandidateList,
    CandidateProposed,
    CandidateSourceResponse,
    CandidateSummary,
    ConfirmedCandidateResponse,
)
from app.security import AuthContext, get_auth_context

router = APIRouter(prefix="/candidates", tags=["transaction candidates"])
EDITABLE_STATES = {CandidateState.PENDING, CandidateState.NEEDS_INPUT}
REVIEWER_ROLES = {MembershipRole.OWNER, MembershipRole.ADMIN, MembershipRole.MEMBER}


def _ensure_reviewer(auth: AuthContext) -> None:
    if auth.membership.role not in REVIEWER_ROLES:
        raise ApiError(403, "candidate_review_denied", "Candidate review is not permitted")


def _candidate(
    db: Session,
    household_id: uuid.UUID,
    user_id: uuid.UUID,
    candidate_id: uuid.UUID,
    *,
    for_update: bool = False,
) -> TransactionCandidate:
    accessible_restricted_account = exists(
        select(AccountAccessGrant.id).where(
            AccountAccessGrant.household_id == household_id,
            AccountAccessGrant.account_id == TransactionCandidate.proposed_account_id,
            AccountAccessGrant.user_id == user_id,
        )
    )
    household_account = exists(
        select(FinancialAccount.id).where(
            FinancialAccount.id == TransactionCandidate.proposed_account_id,
            FinancialAccount.household_id == household_id,
            or_(FinancialAccount.visibility == "household", accessible_restricted_account),
        )
    )
    query = select(TransactionCandidate).where(
        TransactionCandidate.id == candidate_id,
        TransactionCandidate.household_id == household_id,
        or_(TransactionCandidate.proposed_account_id.is_(None), household_account),
    )
    if for_update:
        query = query.with_for_update()
    item = db.scalar(query)
    if item is None:
        raise ApiError(404, "candidate_not_found", "Candidate was not found")
    return item


def _proposed(item: TransactionCandidate) -> CandidateProposed:
    return CandidateProposed(
        account_id=item.proposed_account_id,
        amount_atomic=item.proposed_amount_atomic,
        currency=item.proposed_currency,
        description=item.proposed_description,
        occurred_at=item.proposed_occurred_at,
        transaction_type=item.proposed_type
        or _text(item.source.metadata_json, "direction")
        or "expense",
        category_id=item.proposed_category_id,
        destination_account_id=item.proposed_destination_account_id,
    )


def _text(metadata: dict[str, object], key: str) -> str | None:
    value = metadata.get(key)
    return value if isinstance(value, str) else None


def _summary(item: TransactionCandidate) -> CandidateSummary:
    metadata = item.source.metadata_json
    return CandidateSummary(
        id=item.id,
        state=item.state,
        version=item.version,
        confidence_bps=item.confidence_bps,
        proposed=_proposed(item),
        created_at=item.created_at,
        recipient_name=_text(metadata, "recipient_name"),
        recipient_account=_text(metadata, "recipient_account"),
        direction=_text(metadata, "direction"),
        issuer=_text(metadata, "issuer"),
        suggested_fields=_suggested_fields(item),
    )


def _suggested_fields(item: TransactionCandidate) -> list[str]:
    """Fields still holding Jev's pick; one a person changed is theirs."""
    suggested = item.source.metadata_json.get("suggested")
    if not isinstance(suggested, dict):
        return []
    current = {
        "account_id": item.proposed_account_id,
        "destination_account_id": item.proposed_destination_account_id,
        "category_id": item.proposed_category_id,
    }
    return [field for field, value in suggested.items() if str(current.get(field)) == value]


def _detail(item: TransactionCandidate) -> CandidateDetail:
    return CandidateDetail(
        **_summary(item).model_dump(),
        source=CandidateSourceResponse(
            provider=item.source.provider,
            provider_message_id=item.source.provider_message_id,
            sender_domain=item.source.sender_domain,
            received_at=item.source.received_at,
            parser_version=item.source.parser_version,
            metadata=item.source.metadata_json,
        ),
        warnings=item.warnings,
        evidence=item.evidence,
        ledger_transaction_id=item.ledger_transaction_id,
    )


def _encode_cursor(item: TransactionCandidate) -> str:
    value = json.dumps([item.created_at.isoformat(), str(item.id)]).encode()
    return base64.urlsafe_b64encode(value).decode().rstrip("=")


def _decode_cursor(cursor: str) -> tuple[datetime, uuid.UUID]:
    try:
        padded = cursor + "=" * (-len(cursor) % 4)
        created_at, item_id = json.loads(base64.urlsafe_b64decode(padded).decode())
        return datetime.fromisoformat(created_at), uuid.UUID(item_id)
    except (ValueError, TypeError, json.JSONDecodeError) as exc:
        raise ApiError(400, "invalid_cursor", "Cursor is invalid") from exc


@router.get("", response_model=CandidateList)
def list_candidates(
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
    cursor: str | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
) -> CandidateList:
    accessible_restricted_account = exists(
        select(AccountAccessGrant.id).where(
            AccountAccessGrant.household_id == auth.household.id,
            AccountAccessGrant.account_id == TransactionCandidate.proposed_account_id,
            AccountAccessGrant.user_id == auth.user.id,
        )
    )
    visible_account = exists(
        select(FinancialAccount.id).where(
            FinancialAccount.id == TransactionCandidate.proposed_account_id,
            FinancialAccount.household_id == auth.household.id,
            or_(FinancialAccount.visibility == "household", accessible_restricted_account),
        )
    )
    query = (
        select(TransactionCandidate)
        .options(selectinload(TransactionCandidate.source))
        .where(
            TransactionCandidate.household_id == auth.household.id,
            TransactionCandidate.state.in_([CandidateState.PENDING, CandidateState.NEEDS_INPUT]),
            or_(TransactionCandidate.proposed_account_id.is_(None), visible_account),
        )
    )
    if cursor:
        created_at, item_id = _decode_cursor(cursor)
        query = query.where(
            or_(
                TransactionCandidate.created_at < created_at,
                and_(
                    TransactionCandidate.created_at == created_at,
                    TransactionCandidate.id < item_id,
                ),
            )
        )
    items = list(
        db.scalars(
            query.order_by(
                TransactionCandidate.created_at.desc(), TransactionCandidate.id.desc()
            ).limit(limit + 1)
        )
    )
    has_more = len(items) > limit
    page = items[:limit]
    return CandidateList(
        items=[_summary(item) for item in page],
        next_cursor=_encode_cursor(page[-1]) if has_more else None,
    )


@router.get("/{candidate_id}", response_model=CandidateDetail)
def get_candidate(
    candidate_id: uuid.UUID,
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
) -> CandidateDetail:
    return _detail(_candidate(db, auth.household.id, auth.user.id, candidate_id))


@router.patch("/{candidate_id}", response_model=CandidateDetail)
def edit_candidate(
    candidate_id: uuid.UUID,
    payload: CandidateEditRequest,
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
) -> CandidateDetail:
    _ensure_reviewer(auth)
    item = _candidate(db, auth.household.id, auth.user.id, candidate_id, for_update=True)
    if item.state not in EDITABLE_STATES:
        raise ApiError(409, "candidate_state_conflict", "Candidate cannot be edited in this state")
    if item.version != payload.version:
        raise ApiError(409, "candidate_version_conflict", "Candidate version has changed")
    changes = payload.model_dump(exclude_unset=True, exclude={"version"})
    account_id = changes.pop("account_id", None)
    transaction_type = changes.pop("transaction_type", None)
    category_id = changes.pop("category_id", None)
    destination_account_id = changes.pop("destination_account_id", None)
    if "account_id" in payload.model_fields_set:
        if account_id is not None:
            selected_account = db.scalar(
                select(FinancialAccount).where(
                    FinancialAccount.id == account_id,
                    FinancialAccount.household_id == auth.household.id,
                    FinancialAccount.status == "active",
                )
            )
            if selected_account is None:
                raise ApiError(400, "invalid_candidate_account", "Account is invalid")
            if (
                selected_account.visibility == "restricted"
                and db.scalar(
                    select(AccountAccessGrant.id).where(
                        AccountAccessGrant.household_id == auth.household.id,
                        AccountAccessGrant.account_id == selected_account.id,
                        AccountAccessGrant.user_id == auth.user.id,
                    )
                )
                is None
            ):
                raise ApiError(403, "account_access_denied", "Account access is denied")
        item.proposed_account_id = account_id
    if "transaction_type" in payload.model_fields_set:
        item.proposed_type = transaction_type
        if transaction_type == "transfer":
            item.proposed_category_id = None
        else:
            item.proposed_destination_account_id = None
    if "category_id" in payload.model_fields_set:
        if category_id is not None:
            category = db.scalar(
                select(Category).where(
                    Category.id == category_id,
                    Category.household_id == auth.household.id,
                    Category.category_type == (item.proposed_type or "expense"),
                )
            )
            if category is None:
                raise ApiError(422, "invalid_category", "Category is invalid")
        item.proposed_category_id = category_id
    if "destination_account_id" in payload.model_fields_set:
        if destination_account_id is not None:
            destination = db.scalar(
                select(FinancialAccount).where(
                    FinancialAccount.id == destination_account_id,
                    FinancialAccount.household_id == auth.household.id,
                    FinancialAccount.status == "active",
                )
            )
            if destination is None:
                raise ApiError(422, "invalid_candidate_account", "Destination account is invalid")
        item.proposed_destination_account_id = destination_account_id
    field_map = {
        "amount_atomic": "proposed_amount_atomic",
        "currency": "proposed_currency",
        "description": "proposed_description",
        "occurred_at": "proposed_occurred_at",
    }
    for field, value in changes.items():
        setattr(item, field_map[field], value)
    settle_state(item)
    item.version += 1
    item.updated_at = utcnow()
    item.reviewed_by_user_id = auth.user.id
    db.add(
        AuditEvent(
            household_id=auth.household.id,
            actor_user_id=auth.user.id,
            event_type="candidate.edited",
            target_type="candidate",
            target_id=item.id,
        )
    )
    db.commit()
    db.refresh(item)
    return _detail(item)


def _transition(
    candidate_id: uuid.UUID,
    payload: CandidateActionRequest,
    target_state: CandidateState,
    auth: AuthContext,
    db: Session,
) -> CandidateDetail:
    _ensure_reviewer(auth)
    item = _candidate(db, auth.household.id, auth.user.id, candidate_id, for_update=True)
    if item.state not in EDITABLE_STATES:
        raise ApiError(409, "candidate_state_conflict", "Candidate cannot change from this state")
    if item.version != payload.version:
        raise ApiError(409, "candidate_version_conflict", "Candidate version has changed")
    item.state = target_state
    item.version += 1
    item.updated_at = utcnow()
    item.reviewed_by_user_id = auth.user.id
    db.add(
        AuditEvent(
            household_id=auth.household.id,
            actor_user_id=auth.user.id,
            event_type=f"candidate.{target_state.value}",
            target_type="candidate",
            target_id=item.id,
        )
    )
    db.commit()
    db.refresh(item)
    return _detail(item)


@router.post("/{candidate_id}/reject", response_model=CandidateDetail)
def reject_candidate(
    candidate_id: uuid.UUID,
    payload: CandidateActionRequest,
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
) -> CandidateDetail:
    return _transition(candidate_id, payload, CandidateState.REJECTED, auth, db)


@router.post("/{candidate_id}/duplicate", response_model=CandidateDetail)
def mark_duplicate(
    candidate_id: uuid.UUID,
    payload: CandidateActionRequest,
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
) -> CandidateDetail:
    return _transition(candidate_id, payload, CandidateState.DUPLICATE, auth, db)


@router.post("/{candidate_id}/confirm", response_model=ConfirmedCandidateResponse)
def confirm_candidate(
    candidate_id: uuid.UUID,
    payload: CandidateConfirmRequest,
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> ConfirmedCandidateResponse:
    _ensure_reviewer(auth)
    if not idempotency_key or len(idempotency_key) > 255:
        raise ApiError(400, "idempotency_key_required", "A valid Idempotency-Key is required")
    request_hash = hashlib.sha256(
        f"{candidate_id}:{payload.version}:{payload.account_id}:{payload.category_id}:{payload.destination_account_id}".encode()
    ).hexdigest()
    operation = "candidate.confirm"
    existing = db.scalar(
        select(IdempotencyRecord).where(
            IdempotencyRecord.household_id == auth.household.id,
            IdempotencyRecord.operation == operation,
            IdempotencyRecord.key == idempotency_key,
        )
    )
    if existing:
        if existing.request_hash != request_hash or existing.resource_id is None:
            raise ApiError(409, "idempotency_key_conflict", "Idempotency key was reused")
        item = _candidate(db, auth.household.id, auth.user.id, candidate_id)
        return ConfirmedCandidateResponse(
            candidate_id=item.id,
            candidate_state=item.state,
            transaction_id=existing.resource_id,
            replayed=True,
        )

    item = _candidate(db, auth.household.id, auth.user.id, candidate_id, for_update=True)
    if item.ledger_transaction_id is not None or item.state == CandidateState.CONFIRMED:
        raise ApiError(409, "candidate_already_confirmed", "Candidate is already confirmed")
    if item.state not in EDITABLE_STATES:
        raise ApiError(
            409, "candidate_state_conflict", "Candidate cannot be confirmed in this state"
        )
    if item.version != payload.version:
        raise ApiError(409, "candidate_version_conflict", "Candidate version has changed")
    transaction_type = transaction_type_of(item)
    if transaction_type not in {"expense", "income", "transfer"}:
        raise ApiError(422, "candidate_type_invalid", "Choose a transaction type")
    account_id = payload.account_id or item.proposed_account_id
    if account_id is None:
        raise ApiError(422, "candidate_account_required", "Choose the account that paid")
    if not all(
        [
            item.proposed_amount_atomic,
            item.proposed_description,
            item.proposed_occurred_at,
        ]
    ):
        raise ApiError(422, "candidate_incomplete", "Candidate needs all proposed fields")
    account = db.scalar(
        select(FinancialAccount).where(
            FinancialAccount.id == account_id,
            FinancialAccount.household_id == auth.household.id,
            FinancialAccount.status == "active",
        )
    )
    if account is None or account.currency != item.proposed_currency:
        raise ApiError(422, "invalid_candidate_account", "Candidate account or currency is invalid")
    if (
        account.visibility == "restricted"
        and db.scalar(
            select(AccountAccessGrant.id).where(
                AccountAccessGrant.household_id == auth.household.id,
                AccountAccessGrant.account_id == account.id,
                AccountAccessGrant.user_id == auth.user.id,
            )
        )
        is None
    ):
        raise ApiError(403, "account_access_denied", "Account access is denied")
    assert item.proposed_amount_atomic is not None
    amount = item.proposed_amount_atomic
    category = None
    destination = None
    counterpart: FinancialAccount | None
    if transaction_type == "transfer":
        destination_id = payload.destination_account_id or item.proposed_destination_account_id
        if destination_id is None or destination_id == account.id:
            raise ApiError(
                422, "candidate_destination_required", "Choose another destination account"
            )
        destination = db.scalar(
            select(FinancialAccount).where(
                FinancialAccount.id == destination_id,
                FinancialAccount.household_id == auth.household.id,
                FinancialAccount.status == "active",
                FinancialAccount.currency == account.currency,
            )
        )
        if destination is None:
            raise ApiError(422, "invalid_candidate_account", "Destination account is invalid")
        if (
            destination.visibility == "restricted"
            and db.scalar(
                select(AccountAccessGrant.id).where(
                    AccountAccessGrant.household_id == auth.household.id,
                    AccountAccessGrant.account_id == destination.id,
                    AccountAccessGrant.user_id == auth.user.id,
                )
            )
            is None
        ):
            raise ApiError(403, "account_access_denied", "Account access is denied")
        counterpart = destination
    else:
        counterpart = db.scalar(
            select(FinancialAccount).where(
                FinancialAccount.household_id == auth.household.id,
                FinancialAccount.kind == AccountKind.EQUITY,
                FinancialAccount.currency == item.proposed_currency,
                FinancialAccount.status == "active",
            )
        )
        if counterpart is None:
            raise ApiError(422, "counterpart_account_missing", "A balancing account is required")
        selected_category_id = payload.category_id or item.proposed_category_id
        category_type = transaction_type
        if selected_category_id is not None:
            category = db.scalar(
                select(Category).where(
                    Category.id == selected_category_id,
                    Category.household_id == auth.household.id,
                    Category.category_type == category_type,
                )
            )
            if category is None:
                raise ApiError(
                    422, "invalid_category", "Choose a matching category in this household"
                )
        else:
            category = db.scalar(
                select(Category).where(
                    Category.household_id == auth.household.id,
                    Category.category_type == category_type,
                    Category.name
                    == ("General expense" if transaction_type == "expense" else "General income"),
                )
            ) or db.scalar(
                select(Category)
                .where(
                    Category.household_id == auth.household.id,
                    Category.category_type == category_type,
                )
                .order_by(Category.name)
            )
        if category is None:
            raise ApiError(422, "category_required", "Add a category before confirming")
    transaction = LedgerTransaction(
        household_id=auth.household.id,
        transaction_type=transaction_type,
        category_id=category.id if category is not None else None,
        status=TransactionStatus.POSTED,
        description=item.proposed_description or "",
        occurred_at=item.proposed_occurred_at or utcnow(),
        created_by_user_id=auth.user.id,
    )
    db.add(transaction)
    db.flush()
    db.add_all(
        [
            Posting(
                household_id=auth.household.id,
                transaction_id=transaction.id,
                account_id=account.id,
                amount_atomic=amount if transaction_type == "income" else -amount,
                currency=item.proposed_currency,
            ),
            Posting(
                household_id=auth.household.id,
                transaction_id=transaction.id,
                account_id=counterpart.id,
                amount_atomic=-amount if transaction_type == "income" else amount,
                currency=item.proposed_currency,
            ),
        ]
    )
    item.proposed_account_id = account.id
    item.proposed_category_id = category.id if category is not None else None
    item.proposed_destination_account_id = destination.id if destination is not None else None
    item.proposed_type = transaction_type
    item.state = CandidateState.CONFIRMED
    item.ledger_transaction_id = transaction.id
    item.reviewed_by_user_id = auth.user.id
    item.version += 1
    item.updated_at = utcnow()
    db.add(
        IdempotencyRecord(
            household_id=auth.household.id,
            operation=operation,
            key=idempotency_key,
            request_hash=request_hash,
            resource_id=transaction.id,
        )
    )
    db.add(
        AuditEvent(
            household_id=auth.household.id,
            actor_user_id=auth.user.id,
            event_type="candidate.confirmed",
            target_type="ledger_transaction",
            target_id=transaction.id,
            metadata_json={"candidate_id": str(item.id)},
        )
    )
    if transaction_type == "expense" and category is not None:
        db.flush()
        queue_budget_alerts(db, auth.household, category, transaction.occurred_at)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        replay = db.scalar(
            select(IdempotencyRecord).where(
                IdempotencyRecord.household_id == auth.household.id,
                IdempotencyRecord.operation == operation,
                IdempotencyRecord.key == idempotency_key,
            )
        )
        if replay and replay.request_hash == request_hash and replay.resource_id:
            return ConfirmedCandidateResponse(
                candidate_id=candidate_id,
                candidate_state=CandidateState.CONFIRMED,
                transaction_id=replay.resource_id,
                replayed=True,
            )
        raise ApiError(409, "candidate_confirmation_conflict", "Candidate was confirmed") from exc
    return ConfirmedCandidateResponse(
        candidate_id=item.id,
        candidate_state=item.state,
        transaction_id=transaction.id,
    )
