"""Import a finances.json household ledger into one household.

Usage (inside the backend container or venv):
    python import_ledger.py finances.json --email azhar@tantowi.com [--replace] [--dry-run]

Balance policy follows the source file: `opening_balance` at ledger_start_date
is the verified snapshot, so only transactions on or after that date are
POSTED. Older rows are imported as VOID, which keeps them as history while the
dashboard and transaction list, both of which filter on POSTED, ignore them.

Assets without a ledger balance (gold, Bibit, SGD cash) carry their value as
asset valuations. Gold is recorded in grams; an IDR value is not in the file,
so it stays unvalued rather than invented.

Without --replace the import refuses to touch a household that already has
ledger entries. With --replace it deletes that household's accounts, entries,
categories and candidates first. It always runs in one transaction and
verifies every imported balance against a replay of the file before commit.
"""

import argparse
import json
import sys
import uuid
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from decimal import Decimal

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from app.database import SessionLocal
from app.models import (
    AccountAccessGrant,
    AccountKind,
    AssetValuation,
    AuditEvent,
    CandidateSource,
    Category,
    FinancialAccount,
    IdempotencyRecord,
    LedgerTransaction,
    Membership,
    NotificationOutbox,
    Posting,
    TransactionCandidate,
    TransactionStatus,
    User,
)

JAKARTA = timezone(timedelta(hours=7))

KIND_BY_TYPE = {
    "bank": AccountKind.BANK,
    "cash": AccountKind.CASH,
    "expense_tracker": AccountKind.BUDGET_ENVELOPE,
    "investment_cash": AccountKind.INVESTMENT,
    "investment": AccountKind.INVESTMENT,
    "precious_metal": AccountKind.PHYSICAL_ASSET,
    "foreign_currency_cash": AccountKind.FOREIGN_CURRENCY,
}

# Source category slugs are free text typed over months, so near-duplicates
# ("transport" and "transportation", "grocery" and "groceries") are merged into
# one Indonesian label the app shows. Slugs that describe money movement
# rather than spending ("incoming", "savings", "refund") never reach here,
# because only expense rows carry a category into the app.
CATEGORY_LABELS = {
    "food": "Makan",
    "drink": "Minuman",
    "snack": "Jajan",
    "groceries": "Belanja dapur",
    "grocery": "Belanja dapur",
    "transport": "Transportasi",
    "transportation": "Transportasi",
    "travel": "Perjalanan",
    "donation": "Sedekah",
    "house": "Rumah",
    "household": "Rumah",
    "housing": "Sewa rumah",
    "laundry": "Laundry",
    "utilities": "Listrik, air, internet",
    "utility": "Pulsa dan kuota",
    "telecom": "Pulsa dan kuota",
    "subscription": "Langganan",
    "shopping": "Belanja",
    "clothing": "Pakaian",
    "personal": "Pribadi",
    "health": "Kesehatan",
    "fitness": "Olahraga",
    "sports": "Olahraga",
    "jewelry": "Perhiasan",
    "gold": "Emas",
    "appliance": "Perabot",
    "shipping": "Kirim paket",
    "bank_fee": "Biaya bank",
    "fee": "Biaya bank",
    "taxes": "Pajak",
    "payment": "Lain-lain",
    "top_up": "Isi saldo",
    "outgoing": "Lain-lain",
}
FALLBACK_CATEGORY = "Lain-lain"


def occurred(date_str: str) -> datetime:
    return datetime.fromisoformat(date_str).replace(tzinfo=JAKARTA)


def account_name(spec: dict[str, object]) -> str:
    owner = spec.get("owner", "shared")
    return str(spec["name"]) if owner == "shared" else f"{spec['name']} ({owner})"


def expected_balances(data: dict) -> dict[str, int]:
    """Replay the file independently of the database, for verification."""
    start = data["ledger"]["ledger_start_date"]
    balances: dict[str, int] = defaultdict(int)
    for key, spec in data["accounts"].items():
        balances[key] += spec.get("opening_balance", 0)
    for row in data["transactions"]:
        if row["date"] < start:
            continue
        kind, amount = row["type"], row["amount"]
        if kind == "expense":
            balances[row["from"]] -= amount
        elif kind == "income":
            balances[row.get("to") or row["from"]] += amount
        elif kind == "adjustment":
            balances[row["account"]] += amount
        elif kind in ("transfer", "investment"):
            balances[row["from"]] -= amount
            balances[row["to"]] += amount
            if row.get("fee"):
                balances[row.get("fee_on") or row["from"]] -= row["fee"]
    return balances


def wipe(db: Session, hid: uuid.UUID) -> None:
    # Foreign keys decide the order: candidates and postings reference
    # transactions, and transactions restrict account deletion.
    db.execute(delete(NotificationOutbox).where(NotificationOutbox.household_id == hid))
    db.execute(delete(TransactionCandidate).where(TransactionCandidate.household_id == hid))
    db.execute(delete(CandidateSource).where(CandidateSource.household_id == hid))
    db.execute(delete(Posting).where(Posting.household_id == hid))
    db.execute(
        LedgerTransaction.__table__.update()
        .where(LedgerTransaction.household_id == hid)
        .values(reverses_transaction_id=None)
    )
    db.execute(delete(LedgerTransaction).where(LedgerTransaction.household_id == hid))
    db.execute(delete(AssetValuation).where(AssetValuation.household_id == hid))
    db.execute(delete(AccountAccessGrant).where(AccountAccessGrant.household_id == hid))
    db.execute(delete(FinancialAccount).where(FinancialAccount.household_id == hid))
    db.execute(delete(Category).where(Category.household_id == hid))
    db.execute(delete(IdempotencyRecord).where(IdempotencyRecord.household_id == hid))
    db.flush()


def run(path: str, email: str, *, replace: bool, dry_run: bool) -> None:
    with open(path) as handle:
        data = json.load(handle)
    start = data["ledger"]["ledger_start_date"]

    with SessionLocal() as db:
        user = db.scalar(select(User).where(User.normalized_email == email.strip().lower()))
        if user is None:
            raise SystemExit(f"No user {email}. Sign in to the app once first.")
        memberships = list(db.scalars(select(Membership).where(Membership.user_id == user.id)))
        if len(memberships) != 1:
            raise SystemExit(f"{email} belongs to {len(memberships)} households; expected one.")
        hid = memberships[0].household_id

        existing = db.scalar(
            select(func.count(LedgerTransaction.id)).where(LedgerTransaction.household_id == hid)
        )
        if existing and not replace:
            raise SystemExit(f"Household already has {existing} entries. Use --replace.")
        wipe(db, hid)

        equity: dict[str, FinancialAccount] = {}

        def equity_for(currency: str) -> FinancialAccount:
            if currency not in equity:
                label = (
                    "Household equity" if currency == "IDR" else f"Household equity ({currency})"
                )
                equity[currency] = FinancialAccount(
                    household_id=hid, name=label, kind=AccountKind.EQUITY, currency=currency
                )
                db.add(equity[currency])
            return equity[currency]

        equity_for("IDR")
        accounts: dict[str, FinancialAccount] = {}
        for group in (data["accounts"], data["investments"], data["assets"]):
            for key, spec in group.items():
                account = FinancialAccount(
                    household_id=hid,
                    name=account_name(spec),
                    kind=KIND_BY_TYPE[spec["type"]],
                    currency=spec.get("currency") or "IDR",
                    unit="gram" if spec["type"] == "precious_metal" else None,
                )
                db.add(account)
                accounts[key] = account
        db.flush()

        categories: dict[str, Category] = {}

        def category_for(slug: str | None) -> Category:
            label = CATEGORY_LABELS.get(slug or "", FALLBACK_CATEGORY)
            if label not in categories:
                categories[label] = Category(household_id=hid, name=label, category_type="expense")
                db.add(categories[label])
                db.flush()
            return categories[label]

        # The app files uncategorised income under this default.
        db.add(Category(household_id=hid, name="General income", category_type="income"))

        def post(txn: LedgerTransaction, account: FinancialAccount, amount: int) -> None:
            if amount:
                db.add(
                    Posting(
                        household_id=hid,
                        transaction_id=txn.id,
                        account_id=account.id,
                        amount_atomic=amount,
                        currency=account.currency,
                    )
                )

        def entry(
            kind: str,
            description: str,
            when: datetime,
            status: TransactionStatus,
            category: Category | None = None,
        ) -> LedgerTransaction:
            txn = LedgerTransaction(
                id=uuid.uuid4(),
                household_id=hid,
                transaction_type=kind,
                status=status,
                description=description[:240],
                occurred_at=when,
                category_id=category.id if category else None,
                created_by_user_id=user.id,
            )
            db.add(txn)
            db.flush()
            return txn

        opening_at = occurred(start)
        for key, spec in data["accounts"].items():
            balance = spec.get("opening_balance", 0)
            if balance:
                txn = entry(
                    "opening_balance",
                    f"Saldo awal {accounts[key].name}",
                    opening_at,
                    TransactionStatus.POSTED,
                )
                post(txn, accounts[key], balance)
                post(txn, equity_for(accounts[key].currency), -balance)

        counts = {"posted": 0, "history": 0}
        for row in sorted(data["transactions"], key=lambda t: (t["date"], t["id"])):
            historical = row["date"] < start
            status = TransactionStatus.VOID if historical else TransactionStatus.POSTED
            kind, amount, when = row["type"], row["amount"], occurred(row["date"])
            if kind == "expense":
                source = accounts[row["from"]]
                txn = entry(kind, row["note"], when, status, category_for(row.get("category")))
                post(txn, source, -amount)
                post(txn, equity_for(source.currency), amount)
            elif kind == "income":
                target = accounts[row.get("to") or row["from"]]
                txn = entry(kind, row["note"], when, status)
                post(txn, target, amount)
                post(txn, equity_for(target.currency), -amount)
            elif kind == "adjustment":
                target = accounts[row["account"]]
                txn = entry(kind, row["note"], when, status)
                post(txn, target, amount)
                post(txn, equity_for(target.currency), -amount)
            elif kind in ("transfer", "investment"):
                source, target = accounts[row["from"]], accounts[row["to"]]
                txn = entry(kind, row["note"], when, status)
                post(txn, source, -amount)
                post(txn, target, amount)
                if row.get("fee"):
                    charged = accounts[row.get("fee_on") or row["from"]]
                    post(txn, charged, -row["fee"])
                    post(txn, equity_for(charged.currency), row["fee"])
            else:
                raise SystemExit(f"Unhandled transaction type {kind!r} in {row['id']}")
            counts["history" if historical else "posted"] += 1

        valuations = 0
        for row in sorted(data["valuations"], key=lambda v: (v["date"], v["recorded_at"])):
            account = accounts[row["asset"]]
            recorded = datetime.fromisoformat(row["recorded_at"])
            # Effective at the recorded moment, so same-day corrections keep
            # their order and the latest one wins.
            effective = max(occurred(row["date"]), recorded)
            unit = row["unit"]
            if account.kind == AccountKind.FOREIGN_CURRENCY:
                # Read by the account, not the unit label: the last SGD
                # snapshot is labelled "grams" in the file, yet it is the SGD
                # balance of this cash account.
                value = int(round(Decimal(str(row["amount"])) * 10**account.minor_unit))
                quantity = None
            elif unit == "grams":
                value, quantity = 0, Decimal(str(row["amount"]))
            else:
                value, quantity = int(round(row["amount"])), None
            db.add(
                AssetValuation(
                    household_id=hid,
                    account_id=account.id,
                    value_atomic=value,
                    currency=account.currency,
                    quantity=quantity,
                    effective_at=effective,
                    source=row.get("note", "import")[:120],
                    created_by_user_id=user.id,
                )
            )
            valuations += 1
        db.flush()

        # Every ledger account must match an independent replay of the file.
        expected = expected_balances(data)
        mismatches = []
        for key in data["accounts"]:
            actual = db.scalar(
                select(func.coalesce(func.sum(Posting.amount_atomic), 0))
                .join(LedgerTransaction, LedgerTransaction.id == Posting.transaction_id)
                .where(
                    Posting.account_id == accounts[key].id,
                    LedgerTransaction.status == TransactionStatus.POSTED,
                )
            )
            if actual != expected[key]:
                mismatches.append((accounts[key].name, expected[key], actual))
        unbalanced = db.scalar(
            select(func.count()).select_from(
                select(Posting.transaction_id)
                .where(Posting.household_id == hid)
                .group_by(Posting.transaction_id, Posting.currency)
                .having(func.sum(Posting.amount_atomic) != 0)
                .subquery()
            )
        )
        if mismatches or unbalanced:
            db.rollback()
            raise SystemExit(f"Verification failed: {mismatches} unbalanced={unbalanced}")

        db.add(
            AuditEvent(
                household_id=hid,
                actor_user_id=user.id,
                event_type="ledger.imported",
                metadata_json={
                    "source": path.rsplit("/", 1)[-1],
                    "valuations": valuations,
                    **counts,
                },
            )
        )
        if dry_run:
            db.rollback()
        else:
            db.commit()

    print(
        f"{'Dry run, nothing saved. ' if dry_run else ''}"
        f"accounts={len(accounts)} categories={len(categories)} "
        f"posted={counts['posted']} history={counts['history']} valuations={valuations}"
    )
    for key in data["accounts"]:
        print(f"  {accounts[key].name:32} {expected[key]:>14,}")


def main(argv: list[str]) -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("path")
    parser.add_argument("--email", required=True)
    parser.add_argument("--replace", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    run(args.path, args.email, replace=args.replace, dry_run=args.dry_run)


if __name__ == "__main__":
    main(sys.argv[1:])
