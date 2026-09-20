"""Manual ledger entry.

Every transaction is double-entry: the money leaves one account and arrives in
another, and the two postings always sum to zero. An expense is balanced
against the household equity account rather than vanishing, so the ledger can
always be reconciled.
"""

import hashlib
import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Header, Query
from sqlalchemy import exists, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db
from app.errors import ApiError
from app.models import (
    AccountAccessGrant,
    AccountKind,
    AuditEvent,
    FinancialAccount,
    IdempotencyRecord,
    LedgerTransaction,
    MembershipRole,
    Posting,
    TransactionStatus,
    utcnow,
)
from app.schemas import (
    AccountCreateRequest,
    AccountResponse,
    TransactionCreateRequest,
    TransactionList,
    TransactionResponse,
    TransferCreateRequest,
)
from app.security import AuthContext, get_auth_context

router = APIRouter(tags=["ledger"])

# A viewer can read the ledger but never write to it; a child cannot either,
# because pocket-money visibility is not permission to post.
WRITER_ROLES = {MembershipRole.OWNER, MembershipRole.ADMIN, MembershipRole.MEMBER}


def _ensure_writer(auth: AuthContext) -> None:
    if auth.membership.role not in WRITER_ROLES:
        raise ApiError(403, "ledger_write_denied", "Recording money is not permitted")


def _visible_account_filter(auth: AuthContext):
    return exists(
        select(AccountAccessGrant.id).where(
            AccountAccessGrant.household_id == auth.household.id,
            AccountAccessGrant.account_id == FinancialAccount.id,
            AccountAccessGrant.user_id == auth.user.id,
        )
    )


def _account_for(
    db: Session, auth: AuthContext, account_id: uuid.UUID
) -> FinancialAccount:
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


def _equity_account(db: Session, auth: AuthContext, currency: str) -> FinancialAccount:
    counterpart = db.scalar(
        select(FinancialAccount).where(
            FinancialAccount.household_id == auth.household.id,
            FinancialAccount.kind == AccountKind.EQUITY,
            FinancialAccount.currency == currency,
            FinancialAccount.status == "active",
        )
    )
    if counterpart is None:
        raise ApiError(
            422,
            "counterpart_account_missing",
            "A balancing account in that currency is required",
        )
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
    transaction: LedgerTransaction, postings: list[Posting]
) -> TransactionResponse:
    # The signed amount is an implementation detail of double entry; the app
    # wants the magnitude plus a direction it can render.
    primary = next((p for p in postings if p.amount_atomic != 0), postings[0])
    return TransactionResponse(
        id=transaction.id,
        transaction_type=transaction.transaction_type,
        status=transaction.status,
        description=transaction.description,
        occurred_at=transaction.occurred_at,
        amount_atomic=abs(primary.amount_atomic),
        currency=primary.currency,
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
            (FinancialAccount.visibility == "household")
            | _visible_account_filter(auth),
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
        )
        for a in rows
    ]


@router.post("/accounts", response_model=AccountResponse, status_code=201)
def create_account(
    payload: AccountCreateRequest,
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
) -> AccountResponse:
    _ensure_writer(auth)
    account = FinancialAccount(
        household_id=auth.household.id,
        name=payload.name.strip(),
        kind=payload.kind,
        currency=payload.currency or auth.household.base_currency,
    )
    db.add(account)
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
    db.commit()
    return AccountResponse(
        id=account.id,
        name=account.name,
        kind=account.kind,
        currency=account.currency,
        visibility=account.visibility,
    )


@router.get("/transactions", response_model=TransactionList)
def list_transactions(
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
) -> TransactionList:
    rows = db.scalars(
        select(LedgerTransaction)
        .where(
            LedgerTransaction.household_id == auth.household.id,
            LedgerTransaction.status == TransactionStatus.POSTED,
        )
        .order_by(LedgerTransaction.occurred_at.desc(), LedgerTransaction.id.desc())
        .limit(limit)
    ).all()
    items = []
    for transaction in rows:
        postings = db.scalars(
            select(Posting).where(Posting.transaction_id == transaction.id)
        ).all()
        if postings:
            items.append(_as_response(transaction, list(postings)))
    return TransactionList(items=items)


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
    request_hash = hashlib.sha256(
        payload.model_dump_json(exclude_none=False).encode()
    ).hexdigest()
    replayed = _claim_idempotency(
        db, auth, "transaction.create", idempotency_key, request_hash
    )
    if replayed is not None:
        transaction = db.get(LedgerTransaction, replayed)
        if transaction is not None:
            postings = list(
                db.scalars(select(Posting).where(Posting.transaction_id == transaction.id))
            )
            return _as_response(transaction, postings)

    account = _account_for(db, auth, payload.account_id)
    if payload.currency and payload.currency != account.currency:
        raise ApiError(
            422,
            "currency_mismatch",
            "The amount currency must match the account currency",
        )
    currency = account.currency
    counterpart = _equity_account(db, auth, currency)

    # Income moves value into the account; an expense moves it out. The equity
    # side always takes the opposite sign so the pair nets to zero.
    income = payload.transaction_type == "income"
    signed = payload.amount_atomic if income else -payload.amount_atomic

    transaction = LedgerTransaction(
        household_id=auth.household.id,
        transaction_type=payload.transaction_type,
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
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        # Two devices racing the same key both passed the read above; the
        # unique index is what actually decides.
        raise ApiError(409, "idempotency_key_conflict", "Idempotency key was reused") from exc
    return _as_response(transaction, postings)


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

    request_hash = hashlib.sha256(
        payload.model_dump_json(exclude_none=False).encode()
    ).hexdigest()
    replayed = _claim_idempotency(
        db, auth, "transfer.create", idempotency_key, request_hash
    )
    if replayed is not None:
        transaction = db.get(LedgerTransaction, replayed)
        if transaction is not None:
            postings = list(
                db.scalars(select(Posting).where(Posting.transaction_id == transaction.id))
            )
            return _as_response(transaction, postings)

    source = _account_for(db, auth, payload.from_account_id)
    target = _account_for(db, auth, payload.to_account_id)
    # Cross-currency movement needs an exchange rate, and inventing one would
    # silently misstate the balances.
    if source.currency != target.currency:
        raise ApiError(
            422,
            "cross_currency_transfer",
            "Both accounts must use the same currency",
        )

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
            amount_atomic=payload.amount_atomic,
            currency=target.currency,
        ),
    ]
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
    return _as_response(transaction, postings)
