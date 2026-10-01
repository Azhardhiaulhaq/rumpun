import uuid
from datetime import UTC, datetime, tzinfo
from typing import Annotated
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import APIRouter, Depends, Query
from sqlalchemy import exists, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, aliased

from app.currency import default_minor_unit
from app.database import get_db
from app.errors import ApiError
from app.models import (
    AccountAccessGrant,
    AccountKind,
    Category,
    FinancialAccount,
    LedgerTransaction,
    Posting,
    TransactionStatus,
)
from app.push import queue_budget_alerts
from app.routers.transactions import _ensure_writer
from app.schemas import (
    CategoryBudgetRequest,
    CategoryCreateRequest,
    CategoryResponse,
    CategorySpending,
    CategorySpendingResponse,
)
from app.security import AuthContext, get_auth_context

router = APIRouter(tags=["categories"])


@router.get("/categories", response_model=list[CategoryResponse])
def list_categories(
    auth: Annotated[AuthContext, Depends(get_auth_context)], db: Session = Depends(get_db)
) -> list[Category]:
    return list(
        db.scalars(
            select(Category)
            .where(Category.household_id == auth.household.id)
            .order_by(Category.category_type, Category.name)
        )
    )


@router.post("/categories", response_model=CategoryResponse, status_code=201)
def create_category(
    payload: CategoryCreateRequest,
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
) -> Category:
    _ensure_writer(auth)
    category = Category(
        household_id=auth.household.id,
        name=payload.name,
        category_type=payload.category_type,
        budget_atomic=payload.budget_atomic,
    )
    db.add(category)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise ApiError(409, "category_exists", "Category already exists") from exc
    return category


@router.patch("/categories/{category_id}/budget", response_model=CategoryResponse)
def update_budget(
    category_id: uuid.UUID,
    payload: CategoryBudgetRequest,
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
) -> Category:
    _ensure_writer(auth)
    category = db.scalar(
        select(Category).where(
            Category.id == category_id, Category.household_id == auth.household.id
        )
    )
    if category is None:
        raise ApiError(404, "category_not_found", "Category not found")
    if category.category_type != "expense":
        raise ApiError(422, "budget_only_expense", "Only spending categories can have a budget")
    category.budget_atomic = payload.budget_atomic
    db.flush()
    queue_budget_alerts(db, auth.household, category, datetime.now(UTC))
    db.commit()
    return category


@router.get("/dashboard/categories", response_model=CategorySpendingResponse)
def category_spending(
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
    month: Annotated[str | None, Query(pattern=r"^\d{4}-(0[1-9]|1[0-2])$")] = None,
) -> CategorySpendingResponse:
    try:
        zone: tzinfo = ZoneInfo(auth.household.timezone)
    except ZoneInfoNotFoundError:
        zone = UTC
    today = datetime.now(zone)
    month = month or f"{today.year:04d}-{today.month:02d}"
    year, month_number = map(int, month.split("-"))
    if not 1 <= year <= 9999:
        raise ApiError(422, "invalid_month", "Month is invalid")
    totals: dict[uuid.UUID, int] = {}
    currency = auth.household.base_currency
    visible_account = or_(
        FinancialAccount.visibility == "household",
        exists(
            select(AccountAccessGrant.id).where(
                AccountAccessGrant.household_id == auth.household.id,
                AccountAccessGrant.account_id == FinancialAccount.id,
                AccountAccessGrant.user_id == auth.user.id,
            )
        ),
    )
    hidden_account = aliased(FinancialAccount)
    hidden_posting = exists(
        select(Posting.id)
        .join(hidden_account, hidden_account.id == Posting.account_id)
        .where(
            Posting.transaction_id == LedgerTransaction.id,
            hidden_account.kind != AccountKind.EQUITY,
            hidden_account.visibility == "restricted",
            ~exists(
                select(AccountAccessGrant.id).where(
                    AccountAccessGrant.household_id == auth.household.id,
                    AccountAccessGrant.account_id == hidden_account.id,
                    AccountAccessGrant.user_id == auth.user.id,
                )
            ),
        )
    )
    rows = db.execute(
        select(LedgerTransaction, Posting, FinancialAccount)
        .join(Posting, Posting.transaction_id == LedgerTransaction.id)
        .join(FinancialAccount, FinancialAccount.id == Posting.account_id)
        .where(
            LedgerTransaction.household_id == auth.household.id,
            LedgerTransaction.status == TransactionStatus.POSTED,
            LedgerTransaction.transaction_type.in_(["expense", "refund", "reversal"]),
            FinancialAccount.kind != AccountKind.EQUITY,
            FinancialAccount.currency == currency,
            visible_account,
            ~hidden_posting,
        )
    ).all()
    reversed_ids = set(
        db.scalars(
            select(LedgerTransaction.reverses_transaction_id).where(
                LedgerTransaction.household_id == auth.household.id,
                LedgerTransaction.status == TransactionStatus.POSTED,
                LedgerTransaction.reverses_transaction_id.is_not(None),
            )
        )
    )
    for transaction, posting, _ in rows:
        if transaction.id in reversed_ids or transaction.transaction_type == "reversal":
            continue
        if transaction.category_id is None:
            continue
        moment = transaction.occurred_at
        if moment.tzinfo is None:
            moment = moment.replace(tzinfo=UTC)
        local = moment.astimezone(zone)
        if local.year != year or local.month != month_number:
            continue
        totals[transaction.category_id] = (
            totals.get(transaction.category_id, 0) - posting.amount_atomic
        )
    categories = db.scalars(
        select(Category)
        .where(Category.household_id == auth.household.id, Category.category_type == "expense")
        .order_by(Category.name)
    ).all()
    return CategorySpendingResponse(
        month=month,
        currency=currency,
        minor_unit=default_minor_unit(currency),
        items=[
            CategorySpending(
                id=c.id,
                name=c.name,
                category_type=c.category_type,
                budget_atomic=c.budget_atomic,
                spent_atomic=max(0, totals.get(c.id, 0)),
            )
            for c in categories
        ],
    )
