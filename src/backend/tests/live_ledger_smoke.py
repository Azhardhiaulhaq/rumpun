"""Exercise the public API path against an isolated development backend."""

import os
import uuid

import httpx


def main() -> None:
    base_url = os.environ.get("RUMPUN_TEST_API_URL")
    if not base_url:
        raise SystemExit("Set RUMPUN_TEST_API_URL to an isolated development API")

    with httpx.Client(base_url=base_url, timeout=15) as client:
        email = f"smoke-{uuid.uuid4().hex[:12]}@example.com"
        registered = client.post(
            "/auth/register",
            json={
                "email": email,
                "password": "Test-only-password-2026",
                "display_name": "API Smoke",
            },
        )
        registered.raise_for_status()
        headers = {"Authorization": f"Bearer {registered.json()['access_token']}"}
        household = client.post(
            "/onboarding/household",
            json={"name": "Isolated smoke household", "base_currency": "USD"},
            headers=headers,
        )
        household.raise_for_status()
        cash = next(
            account
            for account in client.get("/accounts", headers=headers).json()
            if account["kind"] == "cash"
        )
        yen_response = client.post(
            "/accounts",
            json={"name": "Yen wallet", "kind": "foreign_currency", "currency": "JPY"},
            headers={**headers, "Idempotency-Key": "yen-account"},
        )
        yen_response.raise_for_status()
        yen = yen_response.json()
        gold_response = client.post(
            "/accounts",
            json={"name": "Gold", "kind": "physical_asset", "currency": "USD", "unit": "gram"},
            headers={**headers, "Idempotency-Key": "gold-account"},
        )
        gold_response.raise_for_status()
        gold = gold_response.json()
        opening = client.post(
            "/transactions",
            json={
                "account_id": cash["id"],
                "transaction_type": "opening_balance",
                "amount_atomic": 50000,
                "description": "Test opening",
            },
            headers={**headers, "Idempotency-Key": "opening"},
        )
        opening.raise_for_status()
        exchange_response = client.post(
            "/transfers",
            json={
                "from_account_id": cash["id"],
                "to_account_id": yen["id"],
                "amount_atomic": 10000,
                "destination_amount_atomic": 1500000,
                "description": "Test exchange",
            },
            headers={**headers, "Idempotency-Key": "exchange"},
        )
        exchange_response.raise_for_status()
        exchange = exchange_response.json()
        valuation = client.post(
            f"/accounts/{gold['id']}/valuations",
            json={"value_atomic": 25000, "quantity": "2.125"},
            headers={**headers, "Idempotency-Key": "gold-value"},
        )
        valuation.raise_for_status()
        dashboard = client.get("/dashboard", headers=headers)
        dashboard.raise_for_status()
        assert dashboard.json()["totals_by_currency"] == {"USD": 65000, "JPY": 1500000}
        history = client.get("/transactions", headers=headers)
        history.raise_for_status()
        assert len(history.json()["items"]) == 2
        reversal = client.post(
            f"/transactions/{exchange['id']}/reverse",
            json={"reason": "Smoke test reversal"},
            headers={**headers, "Idempotency-Key": "reverse"},
        )
        reversal.raise_for_status()
        dashboard = client.get("/dashboard", headers=headers)
        dashboard.raise_for_status()
        assert dashboard.json()["totals_by_currency"] == {"USD": 75000, "JPY": 0}

    print("PASS: ngrok sign-up, accounts, exchange, asset valuation, history, reversal")


if __name__ == "__main__":
    main()
