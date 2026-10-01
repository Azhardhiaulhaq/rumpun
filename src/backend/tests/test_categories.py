from datetime import UTC, datetime

from tests.test_transactions import _auth, _first_account, _household, _post


def test_categories_budget_month_and_reversal(client):
    token = _household(client, "categories@rumpun.app")
    account = _first_account(client, token)
    headers = _auth(token)
    created = client.post(
        "/api/v1/categories",
        json={"name": "Pangan", "category_type": "expense", "budget_atomic": 100000},
        headers=headers,
    )
    assert created.status_code == 201
    category = created.json()
    assert category["budget_atomic"] == 100000
    entry = _post(
        client, token, account, category_id=category["id"], amount_atomic=90000, key="food"
    )
    assert entry.status_code == 201
    assert entry.json()["category_id"] == category["id"]
    month = datetime.now(UTC).strftime("%Y-%m")
    report = client.get(f"/api/v1/dashboard/categories?month={month}", headers=headers).json()
    assert (
        next(row for row in report["items"] if row["id"] == category["id"])["spent_atomic"] == 90000
    )
    assert (
        client.post(
            f"/api/v1/transactions/{entry.json()['id']}/reverse",
            json={"reason": "Salah"},
            headers={**headers, "Idempotency-Key": "undo-food"},
        ).status_code
        == 201
    )
    report = client.get(f"/api/v1/dashboard/categories?month={month}", headers=headers).json()
    assert next(row for row in report["items"] if row["id"] == category["id"])["spent_atomic"] == 0


def test_correct_balance_uses_target_in_both_directions(client):
    token = _household(client, "balance-target@rumpun.app")
    account = _first_account(client, token)
    _post(
        client, token, account, transaction_type="income", amount_atomic=100000, key="seed-balance"
    )
    url = f"/api/v1/accounts/{account}/correct"
    first = client.post(
        url, json={"balance_atomic": 150000}, headers={**_auth(token), "Idempotency-Key": "up"}
    )
    assert first.status_code == 201
    assert first.json()["amount_atomic"] == 50000
    assert first.json()["direction"] == "in"
    assert (
        client.post(
            url, json={"balance_atomic": 150000}, headers={**_auth(token), "Idempotency-Key": "up"}
        ).json()["id"]
        == first.json()["id"]
    )
    second = client.post(
        url, json={"balance_atomic": 20000}, headers={**_auth(token), "Idempotency-Key": "down"}
    )
    assert second.status_code == 201
    assert second.json()["amount_atomic"] == 130000
    assert second.json()["direction"] == "out"
    assert (
        client.get("/api/v1/dashboard", headers=_auth(token)).json()["totals_by_currency"]["IDR"]
        == 20000
    )


def test_category_household_and_type_are_checked(client):
    first = _household(client, "categories-first@rumpun.app")
    second = _household(client, "categories-second@rumpun.app")
    account = _first_account(client, first)
    foreign = client.get("/api/v1/categories", headers=_auth(second)).json()[0]
    assert (
        _post(client, first, account, category_id=foreign["id"], key="foreign").status_code == 422
    )
    income = next(
        c
        for c in client.get("/api/v1/categories", headers=_auth(first)).json()
        if c["category_type"] == "income"
    )
    assert (
        _post(client, first, account, category_id=income["id"], key="wrong-type").status_code == 422
    )
    assert _post(client, first, account, key="legacy-category").json()["category_id"] is not None
