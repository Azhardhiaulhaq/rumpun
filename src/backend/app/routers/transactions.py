"""Manual ledger entry.

Every transaction is double-entry: the money leaves one account and arrives in
another, and the two postings always sum to zero. An expense is balanced
against the household equity account rather than vanishing, so the ledger can
always be reconciled.
"""

import base64
import binascii
import hashlib
import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, Header, Query
from sqlalchemy import and_, exists, func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from sqlalchemy.sql.elements import ColumnElement

from app.currency import default_minor_unit, normalize_currency
from app.database import get_db
from app.errors import ApiError
from app.models import (
    AccountAccessGrant,
    AccountKind,
    AssetValuation,
    AuditEvent,
    Category,
    FinancialAccount,
    IdempotencyRecord,
    LedgerTransaction,
    MembershipRole,
    Posting,
    TransactionStatus,
    utcnow,
)
from app.push import queue_budget_alerts
from app.schemas import (
    AccountCreateRequest,
    AccountResponse,
    BalanceCorrectionRequest,
    TransactionCreateRequest,
    TransactionList,
    TransactionResponse,
    TransactionReverseRequest,
    TransferCreateRequest,
    ValuationCreateRequest,
    ValuationResponse,
)
from app.security import AuthContext, get_auth_context

router = APIRouter(tags=["ledger"])

# A viewer can read the ledger but never write to it; a child cannot either,
# because pocket-money visibility is not permission to post.
WRITER_ROLES = {MembershipRole.OWNER, MembershipRole.ADMIN, MembershipRole.MEMBER}


def _ensure_writer(auth: AuthContext) -> None:
    if auth.membership.role not in WRITER_ROLES:
        raise ApiError(403, "ledger_write_denied", "Recording money is not permitted")


def _visible_account_filter(auth: AuthContext) -> ColumnElement[bool]:
    return exists(
        select(AccountAccessGrant.id).where(
            AccountAccessGrant.household_id == auth.household.id,
            AccountAccessGrant.account_id == FinancialAccount.id,
            AccountAccessGrant.user_id == auth.user.id,
        )
    )


def _account_for(db: Session, auth: AuthContext, account_id: uuid.UUID) -> FinancialAccount:
    account = db.scalar(
        select(FinancialAccount).where(
            FinancialAccount.id == account_id,
            FinancialAccount.household_id == auth.household.id,
            FinancialAccount.status == "active",
        )
    )
    # A missing account and an account in another household read the same, so
    # probing an id cannot confirm that it exists elsewhere.
    if account is None:
        raise ApiError(404, "account_not_found", "Account not found")
    if account.visibility == "restricted" and not db.scalar(
        select(
            exists().where(
                AccountAccessGrant.household_id == auth.household.id,
                AccountAccessGrant.account_id == account.id,
                AccountAccessGrant.user_id == auth.user.id,
            )
        )
    ):
        raise ApiError(403, "account_access_denied", "Account access is denied")
    return account


def _equity_account(
    db: Session, auth: AuthContext, currency: str, minor_unit: int | None = None
) -> FinancialAccount:
    counterpart = db.scalar(
        select(FinancialAccount).where(
            FinancialAccount.household_id == auth.household.id,
            FinancialAccount.kind == AccountKind.EQUITY,
            FinancialAccount.currency == currency,
            FinancialAccount.status == "active",
        )
    )
    if counterpart is None:
        counterpart = FinancialAccount(
            household_id=auth.household.id,
            name=f"Household equity ({currency})",
            kind=AccountKind.EQUITY,
            currency=currency,
            minor_unit=minor_unit if minor_unit is not None else default_minor_unit(currency),
        )
        db.add(counterpart)
        db.flush()
    return counterpart


def _claim_idempotency(
    db: Session,
    auth: AuthContext,
    operation: str,
    key: str | None,
    request_hash: str,
) -> uuid.UUID | None:
    """Returns the id of an earlier identical request, or None to proceed."""
    if not key or len(key) > 255:
        raise ApiError(400, "idempotency_key_required", "A valid Idempotency-Key is required")
    existing = db.scalar(
        select(IdempotencyRecord).where(
            IdempotencyRecord.household_id == auth.household.id,
            IdempotencyRecord.operation == operation,
            IdempotencyRecord.key == key,
        )
    )
    if existing is None:
        return None
    # Same key with a different body means the client reused it by mistake.
    # Replaying the first result would silently drop the second transaction.
    if existing.request_hash != request_hash or existing.resource_id is None:
        raise ApiError(409, "idempotency_key_conflict", "Idempotency key was reused")
    return existing.resource_id


def _as_response(
    db: Session, transaction: LedgerTransaction, postings: list[Posting]
) -> TransactionResponse:
    accounts = {
        account.id: account
        for account in db.scalars(
            select(FinancialAccount).where(
                FinancialAccount.id.in_([p.account_id for p in postings])
            )
        )
    }
    real = [p for p in postings if accounts[p.account_id].kind != AccountKind.EQUITY]
    primary = next((p for p in real if p.amount_atomic < 0), real[0])
    destination = next(
        (p for p in real if p.account_id != primary.account_id and p.amount_atomic > 0),
        None,
    )
    return TransactionResponse(
        id=transaction.id,
        transaction_type=transaction.transaction_type,
        status=transaction.status,
        description=transaction.description,
        occurred_at=transaction.occurred_at,
        amount_atomic=abs(primary.amount_atomic),
        currency=primary.currency,
        direction="out" if primary.amount_atomic < 0 else "in",
        minor_unit=accounts[primary.account_id].minor_unit,
        account_id=primary.account_id,
        destination_account_id=destination.account_id if destination else None,
        destination_amount_atomic=destination.amount_atomic if destination else None,
        destination_currency=destination.currency if destination else None,
        destination_minor_unit=(
            accounts[destination.account_id].minor_unit if destination else None
        ),
        reverses_transaction_id=transaction.reverses_transaction_id,
        category_id=transaction.category_id,
        created_at=transaction.created_at,
    )


@router.get("/accounts", response_model=list[AccountResponse])
def list_accounts(
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
) -> list[AccountResponse]:
    """Accounts the caller may post against, for the picker in the app."""
    rows = db.scalars(
        select(FinancialAccount)
        .where(
            FinancialAccount.household_id == auth.household.id,
            FinancialAccount.status == "active",
            # Equity is the balancing side of every entry, not somewhere a
            # person chooses to spend from.
            FinancialAccount.kind != AccountKind.EQUITY,
            (FinancialAccount.visibility == "household") | _visible_account_filter(auth),
        )
        .order_by(FinancialAccount.name)
    ).all()
    return [
        AccountResponse(
            id=a.id,
            name=a.name,
            kind=a.kind,
            currency=a.currency,
            visibility=a.visibility,
            minor_unit=a.minor_unit,
            unit=a.unit,
        )
        for a in rows
    ]


@router.post("/accounts", response_model=AccountResponse, status_code=201)
def create_account(
    payload: AccountCreateRequest,
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> AccountResponse:
    _ensure_writer(auth)
    request_hash = hashlib.sha256(payload.model_dump_json(exclude_none=False).encode()).hexdigest()
    if idempotency_key is not None:
        replayed = _claim_idempotency(db, auth, "account.create", idempotency_key, request_hash)
        if replayed is not None:
            existing_account = _account_for(db, auth, replayed)
            return AccountResponse(
                id=existing_account.id,
                name=existing_account.name,
                kind=existing_account.kind,
                currency=existing_account.currency,
                visibility=existing_account.visibility,
                minor_unit=existing_account.minor_unit,
                unit=existing_account.unit,
            )
    if payload.kind == AccountKind.EQUITY:
        raise ApiError(422, "account_kind_reserved", "Equity accounts are managed by the ledger")
    currency = normalize_currency(payload.currency or auth.household.base_currency)
    minor_unit = payload.minor_unit
    existing = db.scalar(
        select(FinancialAccount).where(
            FinancialAccount.household_id == auth.household.id,
            FinancialAccount.currency == currency,
        )
    )
    if existing is not None:
        minor_unit = minor_unit if minor_unit is not None else existing.minor_unit
        if minor_unit != existing.minor_unit:
            raise ApiError(
                422,
                "currency_unit_mismatch",
                "Accounts in one currency must use the same minor unit",
            )
    else:
        minor_unit = minor_unit if minor_unit is not None else default_minor_unit(currency)
    account = FinancialAccount(
        household_id=auth.household.id,
        name=payload.name.strip(),
        kind=payload.kind,
        currency=currency,
        minor_unit=minor_unit,
        unit=payload.unit.strip() if payload.unit else None,
        visibility=payload.visibility,
    )
    db.add(account)
    if payload.visibility == "restricted":
        db.flush()
        db.add(
            AccountAccessGrant(
                household_id=auth.household.id, account_id=account.id, user_id=auth.user.id
            )
        )
    _equity_account(db, auth, currency, minor_unit)
    if idempotency_key is not None:
        db.add(
            IdempotencyRecord(
                household_id=auth.household.id,
                operation="account.create",
                key=idempotency_key,
                request_hash=request_hash,
                resource_id=account.id,
            )
        )
    db.add(
        AuditEvent(
            household_id=auth.household.id,
            actor_user_id=auth.user.id,
            event_type="account.created",
            target_type="financial_account",
            target_id=account.id,
            metadata_json={"name": account.name, "kind": str(account.kind)},
        )
    )
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise ApiError(409, "account_create_conflict", "Account creation conflicted") from exc
    return AccountResponse(
        id=account.id,
        name=account.name,
        kind=account.kind,
        currency=account.currency,
        visibility=account.visibility,
        minor_unit=account.minor_unit,
        unit=account.unit,
    )


def _valuation_response(account: FinancialAccount, valuation: AssetValuation) -> ValuationResponse:
    return ValuationResponse(
        id=valuation.id,
        account_id=account.id,
        value_atomic=valuation.value_atomic,
        currency=valuation.currency,
        minor_unit=account.minor_unit,
        quantity=valuation.quantity,
        unit=account.unit,
        effective_at=valuation.effective_at,
        source=valuation.source,
        created_at=valuation.created_at,
    )


@router.get("/accounts/{account_id}/valuations", response_model=list[ValuationResponse])
def list_valuations(
    account_id: uuid.UUID,
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
) -> list[ValuationResponse]:
    account = _account_for(db, auth, account_id)
    rows = db.scalars(
        select(AssetValuation)
        .where(
            AssetValuation.household_id == auth.household.id,
            AssetValuation.account_id == account.id,
        )
        .order_by(AssetValuation.effective_at.desc(), AssetValuation.created_at.desc())
    ).all()
    return [_valuation_response(account, row) for row in rows]


@router.post("/accounts/{account_id}/valuations", response_model=ValuationResponse, status_code=201)
def create_valuation(
    account_id: uuid.UUID,
    payload: ValuationCreateRequest,
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> ValuationResponse:
    _ensure_writer(auth)
    request_hash = hashlib.sha256(
        f"{account_id}:{payload.model_dump_json(exclude_none=False)}".encode()
    ).hexdigest()
    replayed = _claim_idempotency(db, auth, "valuation.create", idempotency_key, request_hash)
    if replayed is not None:
        previous = db.get(AssetValuation, replayed)
        if previous is not None:
            account = _account_for(db, auth, account_id)
            return _valuation_response(account, previous)

    account = _account_for(db, auth, account_id)
    if account.kind not in {AccountKind.INVESTMENT, AccountKind.PHYSICAL_ASSET, AccountKind.OTHER}:
        raise ApiError(422, "not_valued_asset", "This account uses its ledger balance")
    if payload.quantity is not None and account.unit is None:
        raise ApiError(422, "asset_unit_required", "Set the asset unit before recording quantity")
    valuation = AssetValuation(
        household_id=auth.household.id,
        account_id=account.id,
        value_atomic=payload.value_atomic,
        currency=account.currency,
        quantity=payload.quantity,
        effective_at=payload.effective_at or utcnow(),
        source=payload.source.strip(),
        created_by_user_id=auth.user.id,
    )
    db.add(valuation)
    db.flush()
    db.add(
        IdempotencyRecord(
            household_id=auth.household.id,
            operation="valuation.create",
            key=idempotency_key or "",
            request_hash=request_hash,
            resource_id=valuation.id,
        )
    )
    db.add(
        AuditEvent(
            household_id=auth.household.id,
            actor_user_id=auth.user.id,
            event_type="asset.valued",
            target_type="asset_valuation",
            target_id=valuation.id,
            metadata_json={"account_id": str(account.id), "currency": account.currency},
        )
    )
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise ApiError(409, "idempotency_key_conflict", "Idempotency key was reused") from exc
    return _valuation_response(account, valuation)


@router.get("/transactions", response_model=TransactionList)
def list_transactions(
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    cursor: Annotated[str | None, Query(max_length=300)] = None,
) -> TransactionList:
    before_at: datetime | None = None
    before_id: uuid.UUID | None = None
    if cursor is not None:
        try:
            timestamp, identifier = base64.urlsafe_b64decode(cursor + "===").decode().split("|", 1)
            before_at = datetime.fromisoformat(timestamp)
            before_id = uuid.UUID(identifier)
        except (ValueError, UnicodeDecodeError, binascii.Error) as exc:
            raise ApiError(422, "invalid_cursor", "Transaction cursor is invalid") from exc
    hidden_posting = exists(
        select(Posting.id)
        .join(FinancialAccount, FinancialAccount.id == Posting.account_id)
        .where(
            Posting.transaction_id == LedgerTransaction.id,
            FinancialAccount.kind != AccountKind.EQUITY,
            FinancialAccount.visibility == "restricted",
            ~_visible_account_filter(auth),
        )
    )
    query = select(LedgerTransaction).where(
        LedgerTransaction.household_id == auth.household.id,
        LedgerTransaction.status == TransactionStatus.POSTED,
        ~hidden_posting,
    )
    if before_at is not None and before_id is not None:
        query = query.where(
            or_(
                LedgerTransaction.occurred_at < before_at,
                and_(LedgerTransaction.occurred_at == before_at, LedgerTransaction.id < before_id),
            )
        )
    rows = db.scalars(
        query.order_by(LedgerTransaction.occurred_at.desc(), LedgerTransaction.id.desc()).limit(
            limit + 1
        )
    ).all()
    has_more = len(rows) > limit
    rows = rows[:limit]
    items = []
    for transaction in rows:
        postings = db.scalars(select(Posting).where(Posting.transaction_id == transaction.id)).all()
        if postings:
            items.append(_as_response(db, transaction, list(postings)))
    next_cursor = None
    if has_more and rows:
        token = f"{rows[-1].occurred_at.isoformat()}|{rows[-1].id}".encode()
        next_cursor = base64.urlsafe_b64encode(token).decode().rstrip("=")
    return TransactionList(items=items, next_cursor=next_cursor)


@router.post("/transactions", response_model=TransactionResponse, status_code=201)
def create_transaction(
    payload: TransactionCreateRequest,
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> TransactionResponse:
    """Records income or an expense against one account.

    Retrying on a flaky phone connection must not post the money twice, so the
    Idempotency-Key is required rather than optional.
    """
    _ensure_writer(auth)
    request_hash = hashlib.sha256(payload.model_dump_json(exclude_none=False).encode()).hexdigest()
    replayed = _claim_idempotency(db, auth, "transaction.create", idempotency_key, request_hash)
    if replayed is not None:
        transaction = db.get(LedgerTransaction, replayed)
        if transaction is not None:
            postings = list(
                db.scalars(select(Posting).where(Posting.transaction_id == transaction.id))
            )
            return _as_response(db, transaction, postings)

    account = _account_for(db, auth, payload.account_id)
    if payload.currency and payload.currency != account.currency:
        raise ApiError(
            422,
            "currency_mismatch",
            "The amount currency must match the account currency",
        )
    currency = account.currency
    category = None
    if payload.transaction_type in {"expense", "income", "refund"}:
        category_type = "expense" if payload.transaction_type in {"expense", "refund"} else "income"
        category = (
            db.scalar(
                select(Category).where(
                    Category.id == payload.category_id, Category.household_id == auth.household.id
                )
            )
            if payload.category_id
            else db.scalar(
                select(Category).where(
                    Category.household_id == auth.household.id,
                    Category.category_type == category_type,
                    Category.name
                    == ("General expense" if category_type == "expense" else "General income"),
                )
            )
        )
        if category is None and payload.category_id is None:
            category = db.scalar(
                select(Category)
                .where(
                    Category.household_id == auth.household.id,
                    Category.category_type == category_type,
                )
                .order_by(Category.name)
            )
        if category is None or category.category_type != category_type:
            raise ApiError(
                422, "invalid_category", "Choose a category in this household for this transaction"
            )
    elif payload.category_id is not None:
        raise ApiError(
            422, "category_not_applicable", "This kind of transaction cannot have a category"
        )
    counterpart = _equity_account(db, auth, currency, account.minor_unit)

    # Income moves value into the account; an expense moves it out. The equity
    # side always takes the opposite sign so the pair nets to zero.
    direction = payload.direction or ("out" if payload.transaction_type == "expense" else "in")
    signed = payload.amount_atomic if direction == "in" else -payload.amount_atomic

    transaction = LedgerTransaction(
        household_id=auth.household.id,
        transaction_type=payload.transaction_type,
        category_id=category.id if category else None,
        status=TransactionStatus.POSTED,
        description=payload.description.strip(),
        occurred_at=payload.occurred_at or utcnow(),
        created_by_user_id=auth.user.id,
    )
    db.add(transaction)
    db.flush()
    postings = [
        Posting(
            household_id=auth.household.id,
            transaction_id=transaction.id,
            account_id=account.id,
            amount_atomic=signed,
            currency=currency,
        ),
        Posting(
            household_id=auth.household.id,
            transaction_id=transaction.id,
            account_id=counterpart.id,
            amount_atomic=-signed,
            currency=currency,
        ),
    ]
    db.add_all(postings)
    db.add(
        IdempotencyRecord(
            household_id=auth.household.id,
            operation="transaction.create",
            key=idempotency_key or "",
            request_hash=request_hash,
            resource_id=transaction.id,
        )
    )
    db.add(
        AuditEvent(
            household_id=auth.household.id,
            actor_user_id=auth.user.id,
            event_type="transaction.created",
            target_type="ledger_transaction",
            target_id=transaction.id,
            metadata_json={
                "amount_atomic": payload.amount_atomic,
                "currency": currency,
                "account_id": str(account.id),
            },
        )
    )
    if payload.transaction_type == "expense" and category is not None:
        db.flush()
        queue_budget_alerts(db, auth.household, category, transaction.occurred_at)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        # Two devices racing the same key both passed the read above; the
        # unique index is what actually decides.
        raise ApiError(409, "idempotency_key_conflict", "Idempotency key was reused") from exc
    return _as_response(db, transaction, postings)


@router.post(
    "/transactions/{transaction_id}/reverse",
    response_model=TransactionResponse,
    status_code=201,
)
def reverse_transaction(
    transaction_id: uuid.UUID,
    payload: TransactionReverseRequest,
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> TransactionResponse:
    _ensure_writer(auth)
    request_hash = hashlib.sha256(
        f"{transaction_id}:{payload.model_dump_json()}".encode()
    ).hexdigest()
    replayed = _claim_idempotency(db, auth, "transaction.reverse", idempotency_key, request_hash)
    if replayed is not None:
        previous = db.get(LedgerTransaction, replayed)
        if previous is not None:
            previous_postings = list(
                db.scalars(select(Posting).where(Posting.transaction_id == previous.id))
            )
            return _as_response(db, previous, previous_postings)

    original = db.scalar(
        select(LedgerTransaction).where(
            LedgerTransaction.id == transaction_id,
            LedgerTransaction.household_id == auth.household.id,
            LedgerTransaction.status == TransactionStatus.POSTED,
        )
    )
    if original is None:
        raise ApiError(404, "transaction_not_found", "Transaction not found")
    if original.reverses_transaction_id is not None:
        raise ApiError(422, "reversal_cannot_be_reversed", "A reversal cannot be reversed")
    if (
        db.scalar(
            select(LedgerTransaction.id).where(
                LedgerTransaction.household_id == auth.household.id,
                LedgerTransaction.reverses_transaction_id == original.id,
            )
        )
        is not None
    ):
        raise ApiError(409, "transaction_already_reversed", "Transaction was already reversed")
    postings = list(db.scalars(select(Posting).where(Posting.transaction_id == original.id)))
    for posting in postings:
        _account_for(db, auth, posting.account_id)
    reversal = LedgerTransaction(
        household_id=auth.household.id,
        transaction_type="reversal",
        category_id=original.category_id,
        status=TransactionStatus.POSTED,
        description=payload.reason.strip(),
        occurred_at=utcnow(),
        created_by_user_id=auth.user.id,
        reverses_transaction_id=original.id,
    )
    db.add(reversal)
    db.flush()
    inverse = [
        Posting(
            household_id=auth.household.id,
            transaction_id=reversal.id,
            account_id=posting.account_id,
            amount_atomic=-posting.amount_atomic,
            currency=posting.currency,
        )
        for posting in postings
    ]
    db.add_all(inverse)
    db.add(
        IdempotencyRecord(
            household_id=auth.household.id,
            operation="transaction.reverse",
            key=idempotency_key or "",
            request_hash=request_hash,
            resource_id=reversal.id,
        )
    )
    db.add(
        AuditEvent(
            household_id=auth.household.id,
            actor_user_id=auth.user.id,
            event_type="transaction.reversed",
            target_type="ledger_transaction",
            target_id=original.id,
            metadata_json={"reversal_id": str(reversal.id)},
        )
    )
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise ApiError(
            409, "transaction_already_reversed", "Transaction was already reversed"
        ) from exc
    return _as_response(db, reversal, inverse)


@router.post("/accounts/{account_id}/correct", response_model=TransactionResponse, status_code=201)
def correct_balance(
    account_id: uuid.UUID,
    payload: BalanceCorrectionRequest,
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> TransactionResponse:
    _ensure_writer(auth)
    request_hash = hashlib.sha256(f"{account_id}:{payload.model_dump_json()}".encode()).hexdigest()
    replayed = _claim_idempotency(db, auth, "account.correct", idempotency_key, request_hash)
    if replayed is not None:
        previous = db.get(LedgerTransaction, replayed)
        if previous is not None:
            return _as_response(db, previous, list(previous.postings))
    account = _account_for(db, auth, account_id)
    db.execute(
        select(FinancialAccount.id).where(FinancialAccount.id == account.id).with_for_update()
    ).first()
    if account.kind in {
        AccountKind.INVESTMENT,
        AccountKind.PHYSICAL_ASSET,
        AccountKind.OTHER,
        AccountKind.EQUITY,
    }:
        raise ApiError(422, "account_uses_valuation", "Record an asset value for this account")
    current = (
        db.scalar(
            select(func.coalesce(func.sum(Posting.amount_atomic), 0))
            .join(LedgerTransaction, LedgerTransaction.id == Posting.transaction_id)
            .where(
                Posting.account_id == account.id,
                LedgerTransaction.status == TransactionStatus.POSTED,
            )
        )
        or 0
    )
    delta = payload.balance_atomic - int(current)
    if delta == 0:
        raise ApiError(422, "balance_unchanged", "The account already has this balance")
    counterpart = _equity_account(db, auth, account.currency, account.minor_unit)
    transaction = LedgerTransaction(
        household_id=auth.household.id,
        transaction_type="adjustment",
        status=TransactionStatus.POSTED,
        description=payload.description.strip(),
        occurred_at=utcnow(),
        created_by_user_id=auth.user.id,
    )
    db.add(transaction)
    db.flush()
    postings = [
        Posting(
            household_id=auth.household.id,
            transaction_id=transaction.id,
            account_id=account.id,
            amount_atomic=delta,
            currency=account.currency,
        ),
        Posting(
            household_id=auth.household.id,
            transaction_id=transaction.id,
            account_id=counterpart.id,
            amount_atomic=-delta,
            currency=account.currency,
        ),
    ]
    db.add_all(postings)
    db.add(
        IdempotencyRecord(
            household_id=auth.household.id,
            operation="account.correct",
            key=idempotency_key or "",
            request_hash=request_hash,
            resource_id=transaction.id,
        )
    )
    db.add(
        AuditEvent(
            household_id=auth.household.id,
            actor_user_id=auth.user.id,
            event_type="account.corrected",
            target_type="ledger_transaction",
            target_id=transaction.id,
            metadata_json={"account_id": str(account.id), "balance_atomic": payload.balance_atomic},
        )
    )
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise ApiError(
            409,
            "idempotency_key_conflict",
            "Balance changed while correcting; refresh and try again",
        ) from exc
    return _as_response(db, transaction, postings)


@router.post("/transfers", response_model=TransactionResponse, status_code=201)
def create_transfer(
    payload: TransferCreateRequest,
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> TransactionResponse:
    """Moves money between two accounts the household already owns.

    Net worth does not change, so no equity posting is involved.
    """
    _ensure_writer(auth)
    if payload.from_account_id == payload.to_account_id:
        raise ApiError(422, "same_account_transfer", "Choose two different accounts")

    request_hash = hashlib.sha256(payload.model_dump_json(exclude_none=False).encode()).hexdigest()
    replayed = _claim_idempotency(db, auth, "transfer.create", idempotency_key, request_hash)
    if replayed is not None:
        transaction = db.get(LedgerTransaction, replayed)
        if transaction is not None:
            postings = list(
                db.scalars(select(Posting).where(Posting.transaction_id == transaction.id))
            )
            return _as_response(db, transaction, postings)

    source = _account_for(db, auth, payload.from_account_id)
    target = _account_for(db, auth, payload.to_account_id)
    cross_currency = source.currency != target.currency
    if cross_currency and payload.destination_amount_atomic is None:
        raise ApiError(
            422,
            "destination_amount_required",
            "Enter the amount received in the destination currency",
        )
    if not cross_currency and payload.destination_amount_atomic not in (
        None,
        payload.amount_atomic,
    ):
        raise ApiError(
            422, "same_currency_amount_mismatch", "The amount received must equal the amount sent"
        )
    destination_amount = payload.destination_amount_atomic or payload.amount_atomic

    transaction = LedgerTransaction(
        household_id=auth.household.id,
        transaction_type="transfer",
        status=TransactionStatus.POSTED,
        description=payload.description.strip(),
        occurred_at=payload.occurred_at or utcnow(),
        created_by_user_id=auth.user.id,
    )
    db.add(transaction)
    db.flush()
    postings = [
        Posting(
            household_id=auth.household.id,
            transaction_id=transaction.id,
            account_id=source.id,
            amount_atomic=-payload.amount_atomic,
            currency=source.currency,
        ),
        Posting(
            household_id=auth.household.id,
            transaction_id=transaction.id,
            account_id=target.id,
            amount_atomic=destination_amount,
            currency=target.currency,
        ),
    ]
    if cross_currency:
        source_equity = _equity_account(db, auth, source.currency, source.minor_unit)
        target_equity = _equity_account(db, auth, target.currency, target.minor_unit)
        postings.extend(
            [
                Posting(
                    household_id=auth.household.id,
                    transaction_id=transaction.id,
                    account_id=source_equity.id,
                    amount_atomic=payload.amount_atomic,
                    currency=source.currency,
                ),
                Posting(
                    household_id=auth.household.id,
                    transaction_id=transaction.id,
                    account_id=target_equity.id,
                    amount_atomic=-destination_amount,
                    currency=target.currency,
                ),
            ]
        )
    db.add_all(postings)
    db.add(
        IdempotencyRecord(
            household_id=auth.household.id,
            operation="transfer.create",
            key=idempotency_key or "",
            request_hash=request_hash,
            resource_id=transaction.id,
        )
    )
    db.add(
        AuditEvent(
            household_id=auth.household.id,
            actor_user_id=auth.user.id,
            event_type="transfer.created",
            target_type="ledger_transaction",
            target_id=transaction.id,
            metadata_json={
                "amount_atomic": payload.amount_atomic,
                "destination_amount_atomic": destination_amount,
                "destination_currency": target.currency,
                "from": str(source.id),
                "to": str(target.id),
            },
        )
    )
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise ApiError(409, "idempotency_key_conflict", "Idempotency key was reused") from exc
    return _as_response(db, transaction, postings)
