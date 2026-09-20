"""One-off import of the finances.json household ledger.

Balance policy follows the source file: `opening_balance` at ledger_start_date
is the verified snapshot, so only transactions on or after that date are POSTED.
Older rows are imported as VOID, which keeps them searchable as history while
the dashboard and transaction list, both of which filter on POSTED, ignore them.
That mirrors the file's own migration_note instead of double-counting.
"""

import json
import sys
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, select

from app.database import SessionLocal
from app.models import (
    AccountAccessGrant,
    AccountKind,
    AuditEvent,
    Category,
    FinancialAccount,
    IdempotencyRecord,
    LedgerTransaction,
    Posting,
    TransactionCandidate,
    TransactionStatus,
    User,
)

JAKARTA = timezone(timedelta(hours=7))
OWNER_EMAIL = "azhar@tantowi.com"

KIND_BY_TYPE = {
    "bank": AccountKind.BANK,
    "cash": AccountKind.CASH,
    "expense_tracker": AccountKind.BUDGET_ENVELOPE,
    "investment_cash": AccountKind.INVESTMENT,
    "investment": AccountKind.INVESTMENT,
    "precious_metal": AccountKind.PHYSICAL_ASSET,
    "foreign_currency_cash": AccountKind.FOREIGN_CURRENCY,
}


def occurred(date_str: str) -> datetime:
    return datetime.fromisoformat(date_str).replace(tzinfo=JAKARTA)


def main(path: str) -> None:
    with open(path) as handle:
        data = json.load(handle)
    start = data["ledger"]["ledger_start_date"]
    db = SessionLocal()

    user = db.scalar(select(User).where(User.normalized_email == OWNER_EMAIL))
    if user is None:
        raise SystemExit(f"no user {OWNER_EMAIL}")
    from app.models import Membership

    membership = db.scalar(select(Membership).where(Membership.user_id == user.id))
    hid = membership.household_id

    # Wipe in FK order. Postings and candidates both reference transactions,
    # and transactions restrict deletion, so they go before accounts.
    db.execute(delete(Posting).where(Posting.household_id == hid))
    db.execute(delete(TransactionCandidate).where(TransactionCandidate.household_id == hid))
    db.execute(delete(LedgerTransaction).where(LedgerTransaction.household_id == hid))
    db.execute(delete(AccountAccessGrant).where(AccountAccessGrant.household_id == hid))
    db.execute(delete(FinancialAccount).where(FinancialAccount.household_id == hid))
    db.execute(delete(Category).where(Category.household_id == hid))
    db.execute(delete(IdempotencyRecord).where(IdempotencyRecord.household_id == hid))
    db.execute(delete(AuditEvent).where(AuditEvent.household_id == hid))
    db.flush()

    # Equity is the balancing side of every non-transfer entry, one per currency.
    equity: dict[str, FinancialAccount] = {}
    for currency in ("IDR", "SGD"):
        account = FinancialAccount(
            household_id=hid,
            name="Household equity" if currency == "IDR" else f"Household equity ({currency})",
            kind=AccountKind.EQUITY,
            currency=currency,
        )
        db.add(account)
        equity[currency] = account

    accounts: dict[str, FinancialAccount] = {}
    sources = [
        (data["accounts"], True),
        (data["investments"], False),
        (data["assets"], False),
    ]
    for group, _ in sources:
        for key, spec in group.items():
            owner = spec.get("owner", "shared")
            name = spec["name"] if owner == "shared" else f"{spec['name']} ({owner})"
            account = FinancialAccount(
                household_id=hid,
                name=name,
                kind=KIND_BY_TYPE[spec["type"]],
                currency=spec.get("currency") or "IDR",
            )
            db.add(account)
            accounts[key] = account
    db.flush()

    for name in sorted({t["category"] for t in data["transactions"] if t.get("category")}):
        db.add(Category(household_id=hid, name=name, category_type="expense"))

    def post(txn: LedgerTransaction, account: FinancialAccount, amount: int) -> None:
        if amount == 0:
            return
        db.add(
            Posting(
                household_id=hid,
                transaction_id=txn.id,
                account_id=account.id,
                amount_atomic=amount,
                currency=account.currency,
            )
        )

    def new_txn(kind: str, description: str, when: datetime, status) -> LedgerTransaction:
        txn = LedgerTransaction(
            id=uuid.uuid4(),
            household_id=hid,
            transaction_type=kind,
            status=status,
            description=description[:240],
            occurred_at=when,
            created_by_user_id=user.id,
        )
        db.add(txn)
        return txn

    opening_at = occurred(start)
    for key, spec in data["accounts"].items():
        balance = spec.get("opening_balance", 0)
        if balance == 0:
            continue
        txn = new_txn(
            "opening_balance",
            f"Opening balance {accounts[key].name}",
            opening_at,
            TransactionStatus.POSTED,
        )
        db.flush()
        post(txn, accounts[key], balance)
        post(txn, equity[accounts[key].currency], -balance)

    counts = {"posted": 0, "void": 0}
    for row in sorted(data["transactions"], key=lambda t: (t["date"], t["id"])):
        historical = row["date"] < start
        status = TransactionStatus.VOID if historical else TransactionStatus.POSTED
        kind, amount = row["type"], row["amount"]
        txn = new_txn(kind, row["note"], occurred(row["date"]), status)
        db.flush()

        if kind == "expense":
            source = accounts[row["from"]]
            post(txn, source, -amount)
            post(txn, equity[source.currency], amount)
        elif kind == "income":
            target = accounts[row.get("to") or row["from"]]
            post(txn, target, amount)
            post(txn, equity[target.currency], -amount)
        elif kind == "adjustment":
            target = accounts[row["account"]]
            post(txn, target, amount)
            post(txn, equity[target.currency], -amount)
        elif kind in ("transfer", "investment"):
            source, target = accounts[row["from"]], accounts[row["to"]]
            post(txn, source, -amount)
            post(txn, target, amount)
            fee = row.get("fee")
            if fee:
                charged = accounts[row.get("fee_on") or row["from"]]
                post(txn, charged, -fee)
                post(txn, equity[charged.currency], fee)
        else:
            raise SystemExit(f"unhandled type {kind}")
        counts["void" if historical else "posted"] += 1

    db.add(
        AuditEvent(
            household_id=hid,
            actor_user_id=user.id,
            event_type="ledger.imported",
            metadata_json={"source": "finances.json", **counts},
        )
    )
    db.commit()
    print(f"accounts={len(accounts)} {counts}")


if __name__ == "__main__":
    main(sys.argv[1])
