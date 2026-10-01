"""Manual ledger entry and the forwarding inbox.

The ledger is the part a family trusts with real numbers, so these tests are
mostly about what must not happen: double posting, cross-household writes, and
money appearing or vanishing.
"""

import hashlib
import hmac
import json
from decimal import Decimal

import pytest


def _household(client, email: str, name: str = "Keluarga Uji") -> str:
    registered = client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "Sandi-Rumah-2026",
            "display_name": "Budi",
        },
    ).json()
    token = registered["access_token"]
    client.post(
        "/api/v1/onboarding/household",
        json={"name": name, "base_currency": "IDR"},
        headers={"Authorization": f"Bearer {token}"},
    )
    return token


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _first_account(client, token: str) -> str:
    accounts = client.get("/api/v1/accounts", headers=_auth(token)).json()
    return accounts[0]["id"]


def _post(client, token: str, account_id: str, **overrides):
    body = {
        "account_id": account_id,
        "transaction_type": "expense",
        "amount_atomic": 100000,
        "description": "Belanja",
    }
    body.update(overrides)
    key = overrides.pop("key", None) or f"key-{hash(json.dumps(body, default=str))}"
    return client.post(
        "/api/v1/transactions",
        json=body,
        headers={**_auth(token), "Idempotency-Key": str(key)},
    )


class TestAccounts:
    def test_a_new_household_can_spend_from_its_cash_account(self, client) -> None:
        token = _household(client, "acc1@rumpun.app")
        accounts = client.get("/api/v1/accounts", headers=_auth(token)).json()
        assert [a["name"] for a in accounts] == ["Cash"]

    def test_the_equity_account_is_never_offered(self, client) -> None:
        # Equity balances every entry; it is not somewhere a person spends.
        token = _household(client, "acc2@rumpun.app")
        accounts = client.get("/api/v1/accounts", headers=_auth(token)).json()
        assert all(a["kind"] != "equity" for a in accounts)

    def test_an_added_account_appears(self, client) -> None:
        token = _household(client, "acc3@rumpun.app")
        created = client.post(
            "/api/v1/accounts",
            json={"name": "Bank utama", "kind": "bank"},
            headers=_auth(token),
        )
        assert created.status_code == 201
        names = [a["name"] for a in client.get("/api/v1/accounts", headers=_auth(token)).json()]
        assert "Bank utama" in names

    def test_account_creation_retry_returns_one_account(self, client) -> None:
        token = _household(client, "account-retry@rumpun.app")
        headers = {**_auth(token), "Idempotency-Key": "account-retry"}
        body = {"name": "Savings", "kind": "bank", "currency": "CHF"}
        first = client.post("/api/v1/accounts", json=body, headers=headers)
        second = client.post("/api/v1/accounts", json=body, headers=headers)
        assert first.status_code == 201
        assert second.json()["id"] == first.json()["id"]
        assert (
            sum(
                account["name"] == "Savings"
                for account in client.get("/api/v1/accounts", headers=_auth(token)).json()
            )
            == 1
        )


class TestRecording:
    def test_an_expense_lowers_the_household_total(self, client) -> None:
        token = _household(client, "tx1@rumpun.app")
        account = _first_account(client, token)
        _post(client, token, account, amount_atomic=286500, key="k1")

        dashboard = client.get("/api/v1/dashboard", headers=_auth(token)).json()
        assert dashboard["totals_by_currency"]["IDR"] == -286500

    def test_income_raises_it(self, client) -> None:
        token = _household(client, "tx2@rumpun.app")
        account = _first_account(client, token)
        _post(
            client,
            token,
            account,
            transaction_type="income",
            amount_atomic=4000000,
            key="k2",
        )

        dashboard = client.get("/api/v1/dashboard", headers=_auth(token)).json()
        assert dashboard["totals_by_currency"]["IDR"] == 4000000

    def test_opening_debt_and_adjustment_keep_their_meaning(self, client) -> None:
        token = _household(client, "opening@rumpun.app")
        loan = client.post(
            "/api/v1/accounts",
            json={"name": "Home loan", "kind": "loan"},
            headers=_auth(token),
        ).json()["id"]
        opening = _post(
            client,
            token,
            loan,
            transaction_type="opening_balance",
            direction="out",
            amount_atomic=100000000,
            key="opening-debt",
        )
        assert opening.status_code == 201
        assert opening.json()["direction"] == "out"
        adjustment = _post(
            client,
            token,
            loan,
            transaction_type="adjustment",
            direction="in",
            amount_atomic=1000000,
            key="debt-adjustment",
        )
        assert adjustment.status_code == 201
        assert (
            client.get("/api/v1/dashboard", headers=_auth(token)).json()["totals_by_currency"][
                "IDR"
            ]
            == -99000000
        )

    def test_the_dashboard_reports_a_magnitude_not_a_signed_posting(self, client) -> None:
        # transaction_type already carries the direction; returning a negative
        # amount as well would let a client negate it twice.
        token = _household(client, "tx3@rumpun.app")
        account = _first_account(client, token)
        _post(client, token, account, amount_atomic=50000, key="k3")

        recent = client.get("/api/v1/dashboard", headers=_auth(token)).json()["recent_transactions"]
        assert recent[0]["amount_atomic"] == 50000
        assert recent[0]["transaction_type"] == "expense"

    def test_a_retry_with_the_same_key_posts_once(self, client) -> None:
        token = _household(client, "tx4@rumpun.app")
        account = _first_account(client, token)
        first = _post(client, token, account, amount_atomic=50000, key="same")
        second = _post(client, token, account, amount_atomic=50000, key="same")

        assert first.json()["id"] == second.json()["id"]
        dashboard = client.get("/api/v1/dashboard", headers=_auth(token)).json()
        assert dashboard["totals_by_currency"]["IDR"] == -50000

    def test_transaction_history_pages_without_losing_entries(self, client) -> None:
        token = _household(client, "history@rumpun.app")
        account = _first_account(client, token)
        for index in range(3):
            response = _post(
                client,
                token,
                account,
                amount_atomic=1000 + index,
                description=f"Expense {index}",
                key=f"history-{index}",
            )
            assert response.status_code == 201
        first = client.get("/api/v1/transactions?limit=2", headers=_auth(token)).json()
        assert len(first["items"]) == 2
        assert first["next_cursor"] is not None
        second = client.get(
            "/api/v1/transactions",
            params={"limit": 2, "cursor": first["next_cursor"]},
            headers=_auth(token),
        ).json()
        assert len(second["items"]) == 1
        assert second["next_cursor"] is None
        assert len({item["id"] for item in first["items"] + second["items"]}) == 3

    def test_reversal_keeps_history_and_restores_the_balance(self, client) -> None:
        token = _household(client, "reverse@rumpun.app")
        account = _first_account(client, token)
        original = _post(
            client,
            token,
            account,
            transaction_type="income",
            amount_atomic=250000,
            key="original-income",
        ).json()
        url = f"/api/v1/transactions/{original['id']}/reverse"
        headers = {**_auth(token), "Idempotency-Key": "reverse-income"}
        reversal = client.post(url, json={"reason": "Entered twice"}, headers=headers)
        assert reversal.status_code == 201
        assert reversal.json()["reverses_transaction_id"] == original["id"]
        assert (
            client.post(url, json={"reason": "Entered twice"}, headers=headers).json()["id"]
            == reversal.json()["id"]
        )
        duplicate = client.post(
            url,
            json={"reason": "Again"},
            headers={**_auth(token), "Idempotency-Key": "reverse-other"},
        )
        assert duplicate.status_code == 409
        dashboard = client.get("/api/v1/dashboard", headers=_auth(token)).json()
        assert dashboard["totals_by_currency"]["IDR"] == 0
        trends = client.get("/api/v1/dashboard/trends", headers=_auth(token)).json()
        assert sum(bucket["received_atomic"] for bucket in trends["buckets"]) == 0
        history = client.get("/api/v1/transactions", headers=_auth(token)).json()["items"]
        assert len(history) == 2

    def test_the_same_key_with_a_different_body_is_refused(self, client) -> None:
        # Replaying the first result would silently drop the second payment.
        token = _household(client, "tx5@rumpun.app")
        account = _first_account(client, token)
        _post(client, token, account, amount_atomic=50000, key="reused")
        conflict = _post(client, token, account, amount_atomic=99999, key="reused")

        assert conflict.status_code == 409
        assert conflict.json()["error"]["code"] == "idempotency_key_conflict"

    def test_a_missing_key_is_refused(self, client) -> None:
        token = _household(client, "tx6@rumpun.app")
        account = _first_account(client, token)
        response = client.post(
            "/api/v1/transactions",
            json={
                "account_id": account,
                "transaction_type": "expense",
                "amount_atomic": 1000,
                "description": "Tanpa kunci",
            },
            headers=_auth(token),
        )
        assert response.status_code == 400
        assert response.json()["error"]["code"] == "idempotency_key_required"

    @pytest.mark.parametrize(
        "field,value",
        [
            ("amount_atomic", 0),
            ("amount_atomic", -500),
            ("description", "   "),
            ("transaction_type", "withdrawal"),
        ],
    )
    def test_nonsense_is_rejected_before_it_reaches_the_ledger(
        self, client, field: str, value: object
    ) -> None:
        token = _household(client, f"tx7{field}{value}@rumpun.app".replace(" ", ""))
        account = _first_account(client, token)
        response = _post(client, token, account, key=f"bad{field}{value}", **{field: value})
        assert response.status_code == 422


class TestIsolation:
    def test_another_household_account_reads_as_missing(self, client) -> None:
        # Not 403: confirming the id exists would leak another household.
        mine = _household(client, "iso1@rumpun.app", "A")
        theirs = _household(client, "iso2@rumpun.app", "B")
        their_account = _first_account(client, theirs)

        response = _post(client, mine, their_account, key="cross")
        assert response.status_code == 404
        assert response.json()["error"]["code"] == "account_not_found"

    def test_a_viewer_cannot_record_money(self, client) -> None:
        owner = _household(client, "iso3@rumpun.app")
        account = _first_account(client, owner)
        client.post(
            "/api/v1/household/invites",
            json={"email": "viewer@rumpun.app", "role": "viewer"},
            headers=_auth(owner),
        )
        viewer = client.post(
            "/api/v1/auth/register",
            json={
                "email": "viewer@rumpun.app",
                "password": "Sandi-Rumah-2026",
                "display_name": "Rina",
            },
        ).json()
        invite = client.get(
            "/api/v1/onboarding/invites", headers=_auth(viewer["access_token"])
        ).json()[0]
        client.post(
            f"/api/v1/onboarding/invites/{invite['id']}/accept",
            headers=_auth(viewer["access_token"]),
        )

        response = _post(client, viewer["access_token"], account, key="viewer")
        assert response.status_code == 403
        assert response.json()["error"]["code"] == "ledger_write_denied"

        # Reading is still allowed: a viewer watches the ledger, it just
        # cannot change it.
        assert (
            client.get("/api/v1/dashboard", headers=_auth(viewer["access_token"])).status_code
            == 200
        )

    def test_restricted_asset_and_history_are_private(self, client) -> None:
        owner = _household(client, "private-owner@rumpun.app")
        account = client.post(
            "/api/v1/accounts",
            json={
                "name": "Private property",
                "kind": "physical_asset",
                "visibility": "restricted",
            },
            headers=_auth(owner),
        ).json()["id"]
        client.post(
            f"/api/v1/accounts/{account}/valuations",
            json={"value_atomic": 900000000},
            headers={**_auth(owner), "Idempotency-Key": "private-value"},
        )
        _post(client, owner, account, transaction_type="opening_balance", key="private-open")
        client.post(
            "/api/v1/household/invites",
            json={"email": "private-viewer@rumpun.app", "role": "viewer"},
            headers=_auth(owner),
        )
        viewer = client.post(
            "/api/v1/auth/register",
            json={
                "email": "private-viewer@rumpun.app",
                "password": "Sandi-Rumah-2026",
                "display_name": "Viewer",
            },
        ).json()
        viewer_token = viewer["access_token"]
        invitation = client.get("/api/v1/onboarding/invites", headers=_auth(viewer_token)).json()[0]
        client.post(
            f"/api/v1/onboarding/invites/{invitation['id']}/accept",
            headers=_auth(viewer_token),
        )

        assert all(
            item["id"] != account
            for item in client.get("/api/v1/accounts", headers=_auth(viewer_token)).json()
        )
        assert (
            client.get(
                f"/api/v1/accounts/{account}/valuations", headers=_auth(viewer_token)
            ).status_code
            == 403
        )
        assert client.get("/api/v1/transactions", headers=_auth(viewer_token)).json()["items"] == []
        dashboard = client.get("/api/v1/dashboard", headers=_auth(viewer_token)).json()
        assert all(item["account_id"] != account for item in dashboard["accounts"])
        assert dashboard["recent_transactions"] == []


class TestTransfers:
    def test_moving_money_does_not_change_the_total(self, client) -> None:
        token = _household(client, "xf1@rumpun.app")
        cash = _first_account(client, token)
        bank = client.post(
            "/api/v1/accounts",
            json={"name": "Bank", "kind": "bank"},
            headers=_auth(token),
        ).json()["id"]
        _post(
            client,
            token,
            bank,
            transaction_type="income",
            amount_atomic=5000000,
            key="seed",
        )

        before = client.get("/api/v1/dashboard", headers=_auth(token)).json()
        client.post(
            "/api/v1/transfers",
            json={
                "from_account_id": bank,
                "to_account_id": cash,
                "amount_atomic": 1000000,
                "description": "Tarik tunai",
            },
            headers={**_auth(token), "Idempotency-Key": "xf"},
        )
        after = client.get("/api/v1/dashboard", headers=_auth(token)).json()

        assert before["totals_by_currency"] == after["totals_by_currency"]
        balances = {a["name"]: a["balance_atomic"] for a in after["accounts"]}
        assert balances["Bank"] == 4000000
        assert balances["Cash"] == 1000000

    def test_a_transfer_to_the_same_account_is_refused(self, client) -> None:
        token = _household(client, "xf2@rumpun.app")
        cash = _first_account(client, token)
        response = client.post(
            "/api/v1/transfers",
            json={
                "from_account_id": cash,
                "to_account_id": cash,
                "amount_atomic": 1000,
                "description": "Ke diri sendiri",
            },
            headers={**_auth(token), "Idempotency-Key": "self"},
        )
        assert response.status_code == 422
        assert response.json()["error"]["code"] == "same_account_transfer"

    def test_cross_currency_transfer_uses_the_two_entered_amounts(self, client) -> None:
        token = _household(client, "fx1@rumpun.app")
        rupiah = _first_account(client, token)
        dollars = client.post(
            "/api/v1/accounts",
            json={"name": "Dollar wallet", "kind": "foreign_currency", "currency": "USD"},
            headers=_auth(token),
        ).json()["id"]
        response = client.post(
            "/api/v1/transfers",
            json={
                "from_account_id": rupiah,
                "to_account_id": dollars,
                "amount_atomic": 1630000,
                "destination_amount_atomic": 10000,
                "description": "Buy dollars",
            },
            headers={**_auth(token), "Idempotency-Key": "fx-idem"},
        )
        assert response.status_code == 201
        assert response.json()["destination_amount_atomic"] == 10000
        assert response.json()["destination_currency"] == "USD"
        replay = client.post(
            "/api/v1/transfers",
            json={
                "from_account_id": rupiah,
                "to_account_id": dollars,
                "amount_atomic": 1630000,
                "destination_amount_atomic": 10000,
                "description": "Buy dollars",
            },
            headers={**_auth(token), "Idempotency-Key": "fx-idem"},
        )
        assert replay.json()["id"] == response.json()["id"]
        balances = client.get("/api/v1/dashboard", headers=_auth(token)).json()[
            "totals_by_currency"
        ]
        assert balances == {"IDR": -1630000, "USD": 10000}
        history = client.get("/api/v1/transactions", headers=_auth(token)).json()["items"]
        assert len(history) == 1
        assert history[0]["destination_minor_unit"] == 2

    def test_cross_currency_transfer_needs_received_amount(self, client) -> None:
        token = _household(client, "fx2@rumpun.app")
        dollars = client.post(
            "/api/v1/accounts",
            json={"name": "Dollar wallet", "kind": "foreign_currency", "currency": "USD"},
            headers=_auth(token),
        ).json()["id"]
        response = client.post(
            "/api/v1/transfers",
            json={
                "from_account_id": _first_account(client, token),
                "to_account_id": dollars,
                "amount_atomic": 1630000,
                "description": "Buy dollars",
            },
            headers={**_auth(token), "Idempotency-Key": "fx-missing"},
        )
        assert response.status_code == 422
        assert response.json()["error"]["code"] == "destination_amount_required"


class TestAssets:
    def test_a_gold_holding_has_exact_quantity_and_valuation_history(self, client) -> None:
        token = _household(client, "asset1@rumpun.app")
        account = client.post(
            "/api/v1/accounts",
            json={
                "name": "Gold",
                "kind": "physical_asset",
                "currency": "IDR",
                "unit": "gram",
            },
            headers=_auth(token),
        ).json()
        assert account["minor_unit"] == 0
        url = f"/api/v1/accounts/{account['id']}/valuations"
        first = client.post(
            url,
            json={"value_atomic": 1500000, "quantity": "1.2500000000"},
            headers={**_auth(token), "Idempotency-Key": "gold-1"},
        )
        assert first.status_code == 201
        assert first.json()["quantity"] == "1.2500000000"
        again = client.post(
            url,
            json={"value_atomic": 1700000, "quantity": "1.2500000000"},
            headers={**_auth(token), "Idempotency-Key": "gold-2"},
        )
        assert again.status_code == 201
        assert len(client.get(url, headers=_auth(token)).json()) == 2
        replay = client.post(
            url,
            json={"value_atomic": 1700000, "quantity": "1.2500000000"},
            headers={**_auth(token), "Idempotency-Key": "gold-2"},
        )
        assert replay.json()["id"] == again.json()["id"]
        dashboard = client.get("/api/v1/dashboard", headers=_auth(token)).json()
        gold = next(a for a in dashboard["accounts"] if a["account_id"] == account["id"])
        assert gold["balance_atomic"] == 1700000
        assert Decimal(gold["quantity"]) == Decimal("1.25")
        assert dashboard["totals_by_currency"]["IDR"] == 1700000
        trends = client.get("/api/v1/dashboard/trends", headers=_auth(token)).json()
        assert trends["buckets"][-1]["net_worth_atomic"] == 1700000

    def test_currency_precision_must_match_other_accounts(self, client) -> None:
        token = _household(client, "asset2@rumpun.app")
        first = client.post(
            "/api/v1/accounts",
            json={"name": "Bitcoin", "kind": "investment", "currency": "BTC", "minor_unit": 8},
            headers=_auth(token),
        )
        assert first.status_code == 201
        second = client.post(
            "/api/v1/accounts",
            json={
                "name": "Other Bitcoin",
                "kind": "investment",
                "currency": "BTC",
                "minor_unit": 2,
            },
            headers=_auth(token),
        )
        assert second.status_code == 422
        assert second.json()["error"]["code"] == "currency_unit_mismatch"


def _signed(client, secret: str, body: dict) -> object:
    raw = json.dumps(body).encode()
    signature = hmac.new(secret.encode(), raw, hashlib.sha256).hexdigest()
    return client.post(
        "/api/v1/inbound/email",
        content=raw,
        headers={
            "Content-Type": "application/json",
            "X-Rumpun-Signature": signature,
        },
    )


class TestForwardingInbox:
    def test_an_address_is_issued_once_per_household(self, client) -> None:
        token = _household(client, "in1@rumpun.app")
        assert client.get("/api/v1/inbox/address", headers=_auth(token)).json() is None

        created = client.post("/api/v1/inbox/address", headers=_auth(token))
        assert created.status_code == 201
        assert created.json()["state"] == "pending_verification"

        again = client.post("/api/v1/inbox/address", headers=_auth(token))
        assert again.status_code == 409

    def test_a_member_can_read_the_address_but_not_rotate_it(self, client) -> None:
        owner = _household(client, "in2@rumpun.app")
        client.post("/api/v1/inbox/address", headers=_auth(owner))
        client.post(
            "/api/v1/household/invites",
            json={"email": "member2@rumpun.app", "role": "member"},
            headers=_auth(owner),
        )
        member = client.post(
            "/api/v1/auth/register",
            json={
                "email": "member2@rumpun.app",
                "password": "Sandi-Rumah-2026",
                "display_name": "Siti",
            },
        ).json()
        invite = client.get(
            "/api/v1/onboarding/invites", headers=_auth(member["access_token"])
        ).json()[0]
        client.post(
            f"/api/v1/onboarding/invites/{invite['id']}/accept",
            headers=_auth(member["access_token"]),
        )

        assert (
            client.get("/api/v1/inbox/address", headers=_auth(member["access_token"])).status_code
            == 200
        )
        rotate = client.post("/api/v1/inbox/address/rotate", headers=_auth(member["access_token"]))
        assert rotate.status_code == 403

    def test_an_unsigned_message_is_rejected(self, client, settings) -> None:
        response = client.post(
            "/api/v1/inbound/email",
            json={"to": "x@mail.example.com", "sender": "a@bca.co.id", "subject": "T"},
        )
        assert response.status_code == 401

    def test_a_forwarded_bank_email_becomes_a_candidate(self, client, settings) -> None:
        token = _household(client, "in3@rumpun.app")
        address = client.post("/api/v1/inbox/address", headers=_auth(token)).json()

        result = _signed(
            client,
            settings.inbound_webhook_secret,
            {
                "to": address["address"],
                "sender": "noreply@bca.co.id",
                "subject": "Notifikasi Transaksi BCA",
                "text": "Pembayaran sebesar Rp 286.500 pada 19/09/2026 14:23. "
                "Saldo akhir Rp 4.213.500.",
                "message_id": "bca-1",
            },
        )
        assert result.json()["status"] == "candidate_created"

        items = client.get("/api/v1/candidates", headers=_auth(token)).json()["items"]
        assert len(items) == 1
        # The purchase, not the closing balance.
        assert items[0]["proposed"]["amount_atomic"] == 286500
        assert items[0]["state"] == "pending"

    def test_a_redelivered_message_does_not_duplicate(self, client, settings) -> None:
        token = _household(client, "in4@rumpun.app")
        address = client.post("/api/v1/inbox/address", headers=_auth(token)).json()
        body = {
            "to": address["address"],
            "sender": "noreply@bca.co.id",
            "subject": "Transaksi",
            "text": "Sebesar Rp 10.000",
            "message_id": "retry-1",
        }
        _signed(client, settings.inbound_webhook_secret, body)
        again = _signed(client, settings.inbound_webhook_secret, body)

        assert again.json()["status"] == "duplicate"
        items = client.get("/api/v1/candidates", headers=_auth(token)).json()["items"]
        assert len(items) == 1

    def test_an_unreadable_email_waits_for_a_person(self, client, settings) -> None:
        token = _household(client, "in5@rumpun.app")
        address = client.post("/api/v1/inbox/address", headers=_auth(token)).json()

        _signed(
            client,
            settings.inbound_webhook_secret,
            {
                "to": address["address"],
                "sender": "news@random.com",
                "subject": "Newsletter",
                "text": "Nothing financial here.",
                "message_id": "news-1",
            },
        )
        items = client.get("/api/v1/candidates", headers=_auth(token)).json()["items"]
        # It still appears, so nothing is silently dropped, but it cannot be
        # confirmed until someone supplies the amount.
        assert items[0]["state"] == "needs_input"
        assert items[0]["proposed"]["amount_atomic"] is None

    def test_mail_to_an_unknown_address_reveals_nothing(self, client, settings) -> None:
        result = _signed(
            client,
            settings.inbound_webhook_secret,
            {
                "to": "rumpun-000000000000@mail.example.com",
                "sender": "noreply@bca.co.id",
                "subject": "Transaksi",
                "text": "Sebesar Rp 10.000",
                "message_id": "ghost-1",
            },
        )
        assert result.status_code == 200
        assert result.json()["status"] == "ignored"

    def test_gmails_confirmation_code_is_captured_for_the_owner(self, client, settings) -> None:
        token = _household(client, "in6@rumpun.app")
        address = client.post("/api/v1/inbox/address", headers=_auth(token)).json()

        _signed(
            client,
            settings.inbound_webhook_secret,
            {
                "to": address["address"],
                "sender": "forwarding-noreply@google.com",
                "subject": "(#123456789) Gmail Forwarding Confirmation",
                "text": "Confirmation code: 123456789",
                "message_id": "gmail-1",
            },
        )
        current = client.get("/api/v1/inbox/address", headers=_auth(token)).json()
        assert current["verification_code"] == "123456789"
        # A confirmation email is not a transaction.
        assert client.get("/api/v1/candidates", headers=_auth(token)).json()["items"] == []

    def test_a_rotated_address_stops_accepting_mail(self, client, settings) -> None:
        token = _household(client, "in7@rumpun.app")
        old = client.post("/api/v1/inbox/address", headers=_auth(token)).json()
        client.post("/api/v1/inbox/address/rotate", headers=_auth(token))

        result = _signed(
            client,
            settings.inbound_webhook_secret,
            {
                "to": old["address"],
                "sender": "noreply@bca.co.id",
                "subject": "Transaksi",
                "text": "Sebesar Rp 10.000",
                "message_id": "old-1",
            },
        )
        assert result.json()["status"] == "ignored"

    def test_a_confirmed_candidate_reaches_the_ledger(self, client, settings) -> None:
        """The whole point of C: forwarded email to a real balance."""
        token = _household(client, "in8@rumpun.app")
        address = client.post("/api/v1/inbox/address", headers=_auth(token)).json()
        account = _first_account(client, token)

        _signed(
            client,
            settings.inbound_webhook_secret,
            {
                "to": address["address"],
                "sender": "noreply@bca.co.id",
                "subject": "Belanja rumah",
                "text": "Pembayaran sebesar Rp 286.500 pada 19/09/2026 14:23",
                "message_id": "end-1",
            },
        )
        candidate = client.get("/api/v1/candidates", headers=_auth(token)).json()["items"][0]

        # The parser cannot know which account paid, so a person chooses it.
        client.patch(
            f"/api/v1/candidates/{candidate['id']}",
            json={"version": candidate["version"], "account_id": account},
            headers=_auth(token),
        )
        updated = client.get(f"/api/v1/candidates/{candidate['id']}", headers=_auth(token)).json()
        confirmed = client.post(
            f"/api/v1/candidates/{candidate['id']}/confirm",
            json={"version": updated["version"]},
            headers={**_auth(token), "Idempotency-Key": "confirm-end-1"},
        )
        assert confirmed.status_code == 200

        dashboard = client.get("/api/v1/dashboard", headers=_auth(token)).json()
        assert dashboard["totals_by_currency"]["IDR"] == -286500
