"""Add repeatable, clearly labelled graph examples to one development household."""

import os
import uuid
from datetime import datetime

from fastapi.testclient import TestClient
from sqlalchemy import select

from app.config import get_settings
from app.database import SessionLocal
from app.main import app
from app.models import Household, Membership
from app.security import create_access_token


def main() -> None:
    settings = get_settings()
    if settings.environment != "development":
        raise SystemExit("Demo entries are allowed only in development")
    household_id = uuid.UUID(os.environ["RUMPUN_DEMO_HOUSEHOLD_ID"])
    with SessionLocal() as db:
        household = db.get(Household, household_id)
        if household is None or household.name != "Azhar - Lita":
            raise SystemExit("The intended test household was not found")
        user_id = db.scalar(
            select(Membership.user_id).where(Membership.household_id == household_id)
        )
        if user_id is None:
            raise SystemExit("The test household has no member")

    headers = {
        "Authorization": f"Bearer {create_access_token(user_id, settings)}",
        "X-Household-ID": str(household_id),
    }
    with TestClient(app, base_url="http://testserver/api/v1") as client:
        accounts_response = client.get("/accounts", headers=headers)
        accounts_response.raise_for_status()
        accounts = {a["name"]: a for a in accounts_response.json()}
        usd_response = client.post(
            "/accounts",
            json={
                "name": "USD contoh",
                "kind": "foreign_currency",
                "currency": "USD",
            },
            headers={**headers, "Idempotency-Key": "graph-demo-2026-usd-account"},
        )
        usd_response.raise_for_status()
        accounts["USD contoh"] = usd_response.json()

        # Amounts are atomic: whole rupiah, and cents for SGD and USD.
        entries = [
            ("BCA Azhar", "2026-08-03", "opening_balance", 12000000, "Saldo awal contoh"),
            ("BCA Azhar", "2026-08-05", "income", 8500000, "Pemasukan contoh Agustus"),
            ("BCA Azhar", "2026-08-06", "expense", 640000, "Belanja contoh"),
            ("BCA Azhar", "2026-08-13", "expense", 950000, "Kebutuhan rumah contoh"),
            ("BCA Azhar", "2026-08-20", "income", 2400000, "Pemasukan tambahan contoh"),
            ("BCA Azhar", "2026-08-21", "expense", 480000, "Makan di luar contoh"),
            ("BCA Azhar", "2026-08-27", "expense", 1250000, "Belanja bulanan contoh"),
            ("BCA Azhar", "2026-09-02", "income", 8500000, "Pemasukan contoh September"),
            ("BCA Azhar", "2026-09-03", "expense", 720000, "Transport contoh"),
            ("BCA Azhar", "2026-09-10", "expense", 1650000, "Keperluan keluarga contoh"),
            ("BCA Azhar", "2026-09-18", "income", 1750000, "Pemasukan tambahan contoh"),
            ("BCA Azhar", "2026-09-19", "expense", 530000, "Belanja harian contoh"),
            ("BCA Azhar", "2026-09-23", "expense", 910000, "Kebutuhan rumah contoh"),
            ("SGD Mandiri", "2026-08-03", "opening_balance", 60000, "Saldo awal SGD contoh"),
            ("SGD Mandiri", "2026-08-06", "expense", 3400, "Belanja SGD contoh"),
            ("SGD Mandiri", "2026-08-11", "income", 22000, "Pemasukan SGD contoh"),
            ("SGD Mandiri", "2026-08-13", "expense", 7800, "Makan SGD contoh"),
            ("SGD Mandiri", "2026-08-21", "expense", 4200, "Transport SGD contoh"),
            ("SGD Mandiri", "2026-08-27", "expense", 9500, "Belanja SGD contoh"),
            ("SGD Mandiri", "2026-09-03", "expense", 3800, "Makan SGD contoh"),
            ("SGD Mandiri", "2026-09-08", "income", 18000, "Pemasukan SGD contoh"),
            ("SGD Mandiri", "2026-09-10", "expense", 8400, "Belanja SGD contoh"),
            ("SGD Mandiri", "2026-09-19", "expense", 5100, "Transport SGD contoh"),
            ("SGD Mandiri", "2026-09-23", "expense", 6600, "Makan SGD contoh"),
            ("USD contoh", "2026-08-03", "opening_balance", 35000, "Saldo awal USD contoh"),
            ("USD contoh", "2026-08-06", "expense", 2500, "Belanja USD contoh"),
            ("USD contoh", "2026-08-13", "expense", 4500, "Transport USD contoh"),
            ("USD contoh", "2026-08-18", "income", 12000, "Pemasukan USD contoh"),
            ("USD contoh", "2026-08-21", "expense", 7800, "Belanja USD contoh"),
            ("USD contoh", "2026-08-27", "expense", 3300, "Makan USD contoh"),
            ("USD contoh", "2026-09-03", "expense", 8500, "Belanja USD contoh"),
            ("USD contoh", "2026-09-10", "expense", 1800, "Transport USD contoh"),
            ("USD contoh", "2026-09-15", "income", 23000, "Pemasukan USD contoh"),
            ("USD contoh", "2026-09-19", "expense", 6200, "Belanja USD contoh"),
            ("USD contoh", "2026-09-23", "expense", 4100, "Makan USD contoh"),
        ]
        for index, (account, day, kind, amount, description) in enumerate(entries):
            timestamp = datetime.fromisoformat(day).replace(hour=12).isoformat() + "+07:00"
            response = client.post(
                "/transactions",
                json={
                    "account_id": accounts[account]["id"],
                    "transaction_type": kind,
                    "amount_atomic": amount,
                    "description": description,
                    "occurred_at": timestamp,
                },
                headers={**headers, "Idempotency-Key": f"graph-demo-2026-entry-{index:02d}"},
            )
            response.raise_for_status()

        for currency in ("IDR", "SGD", "USD"):
            response = client.get(f"/dashboard/trends?currency={currency}", headers=headers)
            response.raise_for_status()
            buckets = response.json()["buckets"]
            print(
                currency,
                "weeks with spending:",
                sum(bucket["spent_atomic"] > 0 for bucket in buckets),
                "latest net worth:",
                buckets[-1]["net_worth_atomic"],
            )
        print(f"Ready: {len(entries)} labelled demo entries in household {household_id}")


if __name__ == "__main__":
    main()
