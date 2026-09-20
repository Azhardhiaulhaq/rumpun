"""Manual ledger entry and the forwarding inbox.

The ledger is the part a family trusts with real numbers, so these tests are
mostly about what must not happen: double posting, cross-household writes, and
money appearing or vanishing.
"""

import hashlib
import hmac
import json

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
        names = [
            a["name"] for a in client.get("/api/v1/accounts", headers=_auth(token)).json()
        ]
        assert "Bank utama" in names


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

    def test_the_dashboard_reports_a_magnitude_not_a_signed_posting(
        self, client
    ) -> None:
        # transaction_type already carries the direction; returning a negative
        # amount as well would let a client negate it twice.
        token = _household(client, "tx3@rumpun.app")
        account = _first_account(client, token)
        _post(client, token, account, amount_atomic=50000, key="k3")

        recent = client.get("/api/v1/dashboard", headers=_auth(token)).json()[
            "recent_transactions"
        ]
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
            client.get(
                "/api/v1/dashboard", headers=_auth(viewer["access_token"])
            ).status_code
            == 200
        )


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
            client.get(
                "/api/v1/inbox/address", headers=_auth(member["access_token"])
            ).status_code
            == 200
        )
        rotate = client.post(
            "/api/v1/inbox/address/rotate", headers=_auth(member["access_token"])
        )
        assert rotate.status_code == 403

    def test_an_unsigned_message_is_rejected(self, client, settings) -> None:
        response = client.post(
            "/api/v1/inbound/email",
            json={"to": "x@mail.example.com", "sender": "a@bca.co.id", "subject": "T"},
        )
        assert response.status_code == 401

    def test_a_forwarded_bank_email_becomes_a_candidate(
        self, client, settings
    ) -> None:
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

    def test_mail_to_an_unknown_address_reveals_nothing(
        self, client, settings
    ) -> None:
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

    def test_gmails_confirmation_code_is_captured_for_the_owner(
        self, client, settings
    ) -> None:
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
        candidate = client.get("/api/v1/candidates", headers=_auth(token)).json()[
            "items"
        ][0]

        # The parser cannot know which account paid, so a person chooses it.
        client.patch(
            f"/api/v1/candidates/{candidate['id']}",
            json={"version": candidate["version"], "account_id": account},
            headers=_auth(token),
        )
        updated = client.get(
            f"/api/v1/candidates/{candidate['id']}", headers=_auth(token)
        ).json()
        confirmed = client.post(
            f"/api/v1/candidates/{candidate['id']}/confirm",
            json={"version": updated["version"]},
            headers={**_auth(token), "Idempotency-Key": "confirm-end-1"},
        )
        assert confirmed.status_code == 200

        dashboard = client.get("/api/v1/dashboard", headers=_auth(token)).json()
        assert dashboard["totals_by_currency"]["IDR"] == -286500
