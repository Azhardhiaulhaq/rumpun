import uuid
from collections import defaultdict
from datetime import UTC, date, datetime, timedelta, tzinfo
from typing import Annotated, Literal, cast
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import APIRouter, Depends, Query
from sqlalchemy import case, exists, func, or_, select
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import (
    AccountAccessGrant,
    AccountKind,
    AssetValuation,
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
    TrendBucket,
    TrendsResponse,
)
from app.security import AuthContext, get_auth_context

router = APIRouter(tags=["dashboard"])

_INDONESIAN_MONTHS = (
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "Mei",
    "Jun",
    "Jul",
    "Agu",
    "Sep",
    "Okt",
    "Nov",
    "Des",
)


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
    balance_rows = cast(
        list[tuple[FinancialAccount, int]],
        db.execute(
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
        ).all(),
    )
    latest_valuations: dict[uuid.UUID, AssetValuation] = {}
    for valuation in db.scalars(
        select(AssetValuation)
        .where(
            AssetValuation.household_id == auth.household.id,
            AssetValuation.effective_at <= datetime.now(UTC),
        )
        .order_by(AssetValuation.effective_at.desc(), AssetValuation.created_at.desc())
    ):
        latest_valuations.setdefault(valuation.account_id, valuation)
    accounts = [
        AccountBalance(
            account_id=account.id,
            name=account.name,
            kind=account.kind.value,
            currency=account.currency,
            balance_atomic=(
                latest_valuations[account.id].value_atomic
                if account.id in latest_valuations
                else int(balance)
            ),
            minor_unit=account.minor_unit,
            unit=account.unit,
            quantity=(
                latest_valuations[account.id].quantity if account.id in latest_valuations else None
            ),
            valued_at=(
                latest_valuations[account.id].effective_at
                if account.id in latest_valuations
                else None
            ),
        )
        for account, balance in balance_rows
    ]
    totals: dict[str, int] = defaultdict(int)
    for account in accounts:
        if account.kind != "equity":
            totals[account.currency] += account.balance_atomic

    hidden_posting = exists(
        select(Posting.id)
        .join(FinancialAccount, FinancialAccount.id == Posting.account_id)
        .where(
            Posting.transaction_id == LedgerTransaction.id,
            FinancialAccount.kind != AccountKind.EQUITY,
            FinancialAccount.visibility == "restricted",
            ~visible_account,
        )
    )
    has_visible_posting = exists(
        select(Posting.id)
        .join(FinancialAccount, FinancialAccount.id == Posting.account_id)
        .where(
            Posting.transaction_id == LedgerTransaction.id,
            FinancialAccount.kind != AccountKind.EQUITY,
            visible_account,
        )
    )
    recent_rows = db.scalars(
        select(LedgerTransaction)
        .where(
            LedgerTransaction.household_id == auth.household.id,
            LedgerTransaction.status == TransactionStatus.POSTED,
            has_visible_posting,
            ~hidden_posting,
        )
        .order_by(LedgerTransaction.occurred_at.desc(), LedgerTransaction.id.desc())
        .limit(20)
    ).all()
    recent: list[RecentTransaction] = []
    for transaction in recent_rows:
        real_postings = db.execute(
            select(Posting, FinancialAccount)
            .join(FinancialAccount, FinancialAccount.id == Posting.account_id)
            .where(
                Posting.transaction_id == transaction.id,
                FinancialAccount.kind != AccountKind.EQUITY,
            )
        ).all()
        primary, primary_account = (
            next(
                (posting, account)
                for posting, account in real_postings
                if posting.amount_atomic < 0
            )
            if any(posting.amount_atomic < 0 for posting, _ in real_postings)
            else real_postings[0]
        )
        destination = next(
            (
                (posting, account)
                for posting, account in real_postings
                if posting.account_id != primary.account_id and posting.amount_atomic > 0
            ),
            None,
        )
        recent.append(
            RecentTransaction(
                id=transaction.id,
                transaction_type=transaction.transaction_type,
                description=transaction.description,
                occurred_at=transaction.occurred_at,
                # The magnitude, not the signed posting: transaction_type
                # already carries the direction, and returning both would let
                # a client negate it twice.
                amount_atomic=abs(primary.amount_atomic),
                currency=primary.currency,
                direction="out" if primary.amount_atomic < 0 else "in",
                minor_unit=primary_account.minor_unit,
                destination_amount_atomic=(destination[0].amount_atomic if destination else None),
                destination_currency=(destination[0].currency if destination else None),
                destination_minor_unit=(destination[1].minor_unit if destination else None),
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


def _week_start(day: date) -> date:
    """Monday of the week containing [day]."""
    return day - timedelta(days=day.weekday())


def _month_start(day: date) -> date:
    return day.replace(day=1)


def _next_month(day: date) -> date:
    return (day.replace(day=28) + timedelta(days=4)).replace(day=1)


def _periods(granularity: str, newest: date, count: int) -> list[tuple[date, date, str]]:
    """The [count] most recent periods, oldest first, as (start, end, label).

    `end` is inclusive, so a period covers start..end and the next one begins
    the day after.
    """
    periods: list[tuple[date, date, str]] = []
    if granularity == "week":
        start = _week_start(newest)
        for _ in range(count):
            end = start + timedelta(days=6)
            # Day and month, because week numbers mean nothing to a household.
            periods.append((start, end, f"{start.day} {_INDONESIAN_MONTHS[start.month - 1]}"))
            start -= timedelta(days=7)
    else:
        start = _month_start(newest)
        for _ in range(count):
            end = _next_month(start) - timedelta(days=1)
            periods.append((start, end, _INDONESIAN_MONTHS[start.month - 1]))
            start = _month_start(start - timedelta(days=1))
    return list(reversed(periods))


def _change_bps(previous: int, current: int) -> int | None:
    """Growth from [previous] to [current] in basis points.

    Returns None when the base is zero or negative: a percentage change from
    nothing is not a number a person can read, and showing one would invent a
    trend.
    """
    if previous <= 0:
        return None
    return round((current - previous) / previous * 10000)


@router.get("/dashboard/trends", response_model=TrendsResponse)
def trends(
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
    granularity: Annotated[Literal["week", "month"], Query()] = "week",
    periods: Annotated[int, Query(ge=2, le=26)] = 8,
    currency: Annotated[str | None, Query(min_length=3, max_length=12)] = None,
) -> TrendsResponse:
    """Spending flow and closing net worth per period, for the home charts.

    Each request charts one currency. Summing currencies would invent an
    exchange rate, while a shared axis would imply they are comparable.
    """
    currency = currency.upper() if currency else auth.household.base_currency
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

    # Buckets follow the household's own calendar. A payment made at 9pm in
    # Jakarta is already the next day in UTC, so bucketing on UTC would file a
    # Sunday-evening expense into the week that had not started yet.
    try:
        zone: tzinfo = ZoneInfo(auth.household.timezone)
    except ZoneInfoNotFoundError:
        zone = UTC
    today = datetime.now(zone).date()
    window = _periods(granularity, today, periods)
    oldest = window[0][0]

    # Postings against real accounts, not equity: equity is the balancing side
    # of every entry, so including it would net every period to zero.
    rows = db.execute(
        select(
            LedgerTransaction.id,
            LedgerTransaction.reverses_transaction_id,
            LedgerTransaction.occurred_at,
            LedgerTransaction.transaction_type,
            Posting.amount_atomic,
            Posting.account_id,
        )
        .join(Posting, Posting.transaction_id == LedgerTransaction.id)
        .join(FinancialAccount, FinancialAccount.id == Posting.account_id)
        .where(
            LedgerTransaction.household_id == auth.household.id,
            Posting.household_id == auth.household.id,
            LedgerTransaction.status == TransactionStatus.POSTED,
            FinancialAccount.kind != AccountKind.EQUITY,
            FinancialAccount.currency == currency,
            Posting.currency == currency,
            visible_account,
        )
    ).all()
    reversed_ids = set(
        db.scalars(
            select(LedgerTransaction.reverses_transaction_id).where(
                LedgerTransaction.household_id == auth.household.id,
                LedgerTransaction.reverses_transaction_id.is_not(None),
                LedgerTransaction.status == TransactionStatus.POSTED,
            )
        )
    )

    spent: dict[date, int] = defaultdict(int)
    received: dict[date, int] = defaultdict(int)
    movement: dict[date, int] = defaultdict(int)
    opening_by_account: dict[uuid.UUID, int] = defaultdict(int)
    movement_by_account: dict[date, dict[uuid.UUID, int]] = defaultdict(lambda: defaultdict(int))
    # Everything posted before the window still counts toward the opening
    # net worth, otherwise the first bucket would start the household at zero.
    opening = 0
    for transaction_id, reverses_id, occurred_at, kind, amount, account_id in rows:
        if isinstance(occurred_at, datetime):
            # SQLite hands back naive datetimes; treat those as already-UTC
            # rather than as local, which is how they were written.
            moment = occurred_at if occurred_at.tzinfo else occurred_at.replace(tzinfo=UTC)
            day = moment.astimezone(zone).date()
        else:
            day = occurred_at
        # Every posting moves net worth, including transfers and corrections,
        # because the closing balance is simply what the accounts hold.
        if day < oldest:
            opening += amount
            opening_by_account[account_id] += amount
            continue
        # Flows are narrower than that. Moving money from a bank into a spending
        # pocket is not spending it, and a balance correction is a bookkeeping
        # entry rather than money the household chose to move, so both stay out
        # of the bars. Only what actually left or entered the household counts.
        movement[day] += amount
        movement_by_account[day][account_id] += amount
        if transaction_id in reversed_ids or reverses_id is not None:
            continue
        if kind == "expense" and amount < 0:
            spent[day] -= amount
        elif kind in {"income", "refund"} and amount > 0:
            received[day] += amount

    valuations: dict[uuid.UUID, list[tuple[date, int]]] = defaultdict(list)
    for valuation in db.scalars(
        select(AssetValuation)
        .join(FinancialAccount, FinancialAccount.id == AssetValuation.account_id)
        .where(
            AssetValuation.household_id == auth.household.id,
            AssetValuation.effective_at <= datetime.now(UTC),
            FinancialAccount.currency == currency,
            visible_account,
        )
        .order_by(AssetValuation.effective_at, AssetValuation.created_at)
    ):
        moment = valuation.effective_at
        if moment.tzinfo is None:
            moment = moment.replace(tzinfo=UTC)
        valuations[valuation.account_id].append(
            (moment.astimezone(zone).date(), valuation.value_atomic)
        )

    buckets: list[TrendBucket] = []
    running = opening
    running_by_account = dict(opening_by_account)
    for start, end, label in window:
        period_spent = 0
        period_received = 0
        period_movement = 0
        cursor = start
        while cursor <= end:
            period_spent += spent.get(cursor, 0)
            period_received += received.get(cursor, 0)
            period_movement += movement.get(cursor, 0)
            for account_id, amount in movement_by_account.get(cursor, {}).items():
                running_by_account[account_id] = running_by_account.get(account_id, 0) + amount
            cursor += timedelta(days=1)
        running += period_movement
        valued_total = running
        for account_id, observations in valuations.items():
            latest = next(
                (value for day, value in reversed(observations) if day <= min(end, today)),
                None,
            )
            if latest is not None:
                valued_total += latest - running_by_account.get(account_id, 0)
        buckets.append(
            TrendBucket(
                start=start,
                end=end,
                label=label,
                spent_atomic=period_spent,
                received_atomic=period_received,
                net_worth_atomic=valued_total,
                complete=end < today,
            )
        )

    # Growth compares the last two finished periods. The period in progress is
    # excluded: a Tuesday is not a smaller week, and charting it as one would
    # read as a collapse every Monday.
    finished = [b for b in buckets if b.complete]
    change_bps = None
    spend_change_bps = None
    if len(finished) >= 2:
        change_bps = _change_bps(finished[-2].net_worth_atomic, finished[-1].net_worth_atomic)
        spend_change_bps = _change_bps(finished[-2].spent_atomic, finished[-1].spent_atomic)

    return TrendsResponse(
        currency=currency,
        granularity=granularity,
        buckets=buckets,
        change_bps=change_bps,
        spend_change_bps=spend_change_bps,
    )
