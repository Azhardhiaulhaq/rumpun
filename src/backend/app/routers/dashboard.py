import uuid
from collections import defaultdict
from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy import case, exists, func, or_, select
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import (
    AccountAccessGrant,
    AccountKind,
    FinancialAccount,
    LedgerTransaction,
    Posting,
    TransactionStatus,
)
from app.schemas import (
    AccountBalance,
    DashboardResponse,
    HouseholdContext,
    RecentTransaction,
)
from app.security import AuthContext, get_auth_context

router = APIRouter(tags=["dashboard"])


@router.get("/dashboard", response_model=DashboardResponse)
def dashboard(
    auth: Annotated[AuthContext, Depends(get_auth_context)], db: Session = Depends(get_db)
) -> DashboardResponse:
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
    balance_rows = db.execute(
        select(
            FinancialAccount,
            func.coalesce(
                func.sum(
                    case(
                        (
                            LedgerTransaction.status == TransactionStatus.POSTED,
                            Posting.amount_atomic,
                        ),
                        else_=0,
                    )
                ),
                0,
            ).label("balance"),
        )
        .outerjoin(
            Posting,
            (Posting.account_id == FinancialAccount.id)
            & (Posting.household_id == auth.household.id),
        )
        .outerjoin(
            LedgerTransaction,
            (LedgerTransaction.id == Posting.transaction_id)
            & (LedgerTransaction.household_id == auth.household.id)
            & (LedgerTransaction.status == TransactionStatus.POSTED),
        )
        .where(FinancialAccount.household_id == auth.household.id, visible_account)
        .group_by(FinancialAccount.id)
        .order_by(FinancialAccount.created_at, FinancialAccount.id)
    ).all()
    accounts = [
        AccountBalance(
            account_id=account.id,
            name=account.name,
            kind=account.kind.value,
            currency=account.currency,
            balance_atomic=int(balance),
        )
        for account, balance in balance_rows
    ]
    totals: dict[str, int] = defaultdict(int)
    for account in accounts:
        if account.kind != "equity":
            totals[account.currency] += account.balance_atomic

    recent_rows = db.execute(
        select(LedgerTransaction, Posting.amount_atomic, Posting.currency)
        .join(Posting, Posting.transaction_id == LedgerTransaction.id)
        .join(FinancialAccount, FinancialAccount.id == Posting.account_id)
        .where(
            LedgerTransaction.household_id == auth.household.id,
            Posting.household_id == auth.household.id,
            LedgerTransaction.status == TransactionStatus.POSTED,
            FinancialAccount.kind != AccountKind.EQUITY,
            visible_account,
        )
        .order_by(LedgerTransaction.occurred_at.desc(), LedgerTransaction.id.desc())
        .limit(20)
    ).all()
    seen: set[uuid.UUID] = set()
    recent: list[RecentTransaction] = []
    for transaction, amount, currency in recent_rows:
        if transaction.id in seen:
            continue
        seen.add(transaction.id)
        recent.append(
            RecentTransaction(
                id=transaction.id,
                transaction_type=transaction.transaction_type,
                description=transaction.description,
                occurred_at=transaction.occurred_at,
                amount_atomic=amount,
                currency=currency,
            )
        )
    return DashboardResponse(
        household=HouseholdContext(
            id=auth.household.id,
            name=auth.household.name,
            role=auth.membership.role,
            base_currency=auth.household.base_currency,
        ),
        totals_by_currency=dict(totals),
        accounts=accounts,
        recent_transactions=recent,
    )
