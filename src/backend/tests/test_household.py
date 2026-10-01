import uuid
from typing import Any

from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.main import app
from app.models import FinancialAccount, Household, Membership, MembershipRole, User
from app.security import get_google_verifier

from .test_auth import FakeGoogleVerifier


def google_sign_in(
    client: TestClient,
    *,
    sub: str = "google-1",
    email: str = "ratna@example.com",
    name: str = "Ratna",
) -> dict[str, Any]:
    claims = {"sub": sub, "email": email, "email_verified": True, "name": name}
    app.dependency_overrides[get_google_verifier] = lambda: FakeGoogleVerifier(claims)
    response = client.post("/api/v1/auth/google", json={"id_token": "verified"})
    assert response.status_code == 200
    return response.json()


def bearer(body: dict[str, Any]) -> dict[str, str]:
    return {"Authorization": f"Bearer {body['access_token']}"}


def create_household(
    client: TestClient,
    body: dict[str, Any],
    *,
    name: str = "Keluarga Santoso",
    currency: str = "IDR",
) -> dict[str, Any]:
    response = client.post(
        "/api/v1/onboarding/household",
        headers=bearer(body),
        json={"name": name, "base_currency": currency},
    )
    assert response.status_code == 201, response.text
    return response.json()


class TestSignInWithoutHousehold:
    def test_a_first_sign_in_leaves_the_user_without_a_household(self, client: TestClient) -> None:
        body = google_sign_in(client)

        assert body["is_new_user"] is True
        assert body["household"] is None, (
            "auto-creating a household would strand an invited member in an "
            "empty ledger of their own"
        )
        assert body["pending_invites"] == []

    def test_creating_a_household_makes_the_user_its_owner(
        self, client: TestClient, db: Session
    ) -> None:
        body = google_sign_in(client)
        household = create_household(client, body)

        assert household["role"] == MembershipRole.OWNER
        assert household["name"] == "Keluarga Santoso"
        assert household["is_named"] is True

        accounts = db.scalars(
            select(FinancialAccount).where(
                FinancialAccount.household_id == uuid.UUID(household["id"])
            )
        ).all()
        assert len(accounts) == 2, "a new household starts with its seed accounts"

    def test_the_next_sign_in_carries_the_household(self, client: TestClient) -> None:
        create_household(client, google_sign_in(client))

        again = google_sign_in(client)
        assert again["is_new_user"] is False
        assert again["household"]["name"] == "Keluarga Santoso"

    def test_a_second_household_is_refused(self, client: TestClient) -> None:
        body = google_sign_in(client)
        create_household(client, body)

        response = client.post(
            "/api/v1/onboarding/household",
            headers=bearer(body),
            json={"name": "Rumah Kedua", "base_currency": "IDR"},
        )
        assert response.status_code == 409
        assert response.json()["error"]["code"] == "household_already_joined"

    def test_a_blank_household_name_is_refused(self, client: TestClient) -> None:
        response = client.post(
            "/api/v1/onboarding/household",
            headers=bearer(google_sign_in(client)),
            json={"name": "   ", "base_currency": "IDR"},
        )
        assert response.status_code == 422

    def test_onboarding_requires_authentication(self, client: TestClient) -> None:
        response = client.post(
            "/api/v1/onboarding/household", json={"name": "Rumah", "base_currency": "IDR"}
        )
        assert response.status_code == 401


class TestInviting:
    def _owner_with_household(self, client: TestClient) -> dict[str, Any]:
        owner = google_sign_in(client, sub="owner-1", email="budi@example.com", name="Budi")
        create_household(client, owner)
        return owner

    def _invite(
        self,
        client: TestClient,
        owner: dict[str, Any],
        email: str,
        role: str = "member",
    ) -> Any:
        return client.post(
            "/api/v1/household/invites",
            headers=bearer(owner),
            json={"email": email, "role": role},
        )

    def test_an_invited_member_joins_the_same_household(
        self, client: TestClient, db: Session
    ) -> None:
        owner = self._owner_with_household(client)
        invite = self._invite(client, owner, "siti@example.com").json()

        member = google_sign_in(client, sub="member-1", email="siti@example.com", name="Siti")
        assert member["household"] is None
        assert len(member["pending_invites"]) == 1
        assert member["pending_invites"][0]["household_name"] == "Keluarga Santoso"
        assert member["pending_invites"][0]["invited_by_name"] == "Budi"

        accepted = client.post(
            f"/api/v1/onboarding/invites/{invite['id']}/accept",
            headers=bearer(member),
        )
        assert accepted.status_code == 200
        assert accepted.json()["id"] == owner_household_id(client, owner)
        assert accepted.json()["role"] == MembershipRole.MEMBER

        memberships = db.scalars(
            select(Membership).where(Membership.household_id == uuid.UUID(accepted.json()["id"]))
        ).all()
        assert len(memberships) == 2
        assert db.scalar(select(Household).where(Household.name == "Rumah Siti")) is None

    def test_declining_leaves_the_user_free_to_start_their_own(self, client: TestClient) -> None:
        owner = self._owner_with_household(client)
        invite = self._invite(client, owner, "siti@example.com").json()
        member = google_sign_in(client, sub="member-1", email="siti@example.com")

        declined = client.post(
            f"/api/v1/onboarding/invites/{invite['id']}/decline",
            headers=bearer(member),
        )
        assert declined.status_code == 204

        assert client.get("/api/v1/onboarding/invites", headers=bearer(member)).json() == []

        own = create_household(client, member, name="Rumah Siti")
        assert own["role"] == MembershipRole.OWNER

    def test_an_invite_cannot_be_accepted_by_a_different_address(self, client: TestClient) -> None:
        owner = self._owner_with_household(client)
        invite = self._invite(client, owner, "siti@example.com").json()
        stranger = google_sign_in(client, sub="stranger", email="rina@example.com")

        response = client.post(
            f"/api/v1/onboarding/invites/{invite['id']}/accept",
            headers=bearer(stranger),
        )
        assert response.status_code == 404, "reporting 403 would confirm the invitation exists"
        assert response.json()["error"]["code"] == "invite_not_found"

    def test_an_invite_is_matched_case_insensitively(self, client: TestClient) -> None:
        owner = self._owner_with_household(client)
        self._invite(client, owner, "Siti.Rahayu@Example.COM")

        member = google_sign_in(client, sub="member-1", email="siti.rahayu@example.com")
        assert len(member["pending_invites"]) == 1

    def test_an_accepted_invite_cannot_be_reused(self, client: TestClient) -> None:
        owner = self._owner_with_household(client)
        invite = self._invite(client, owner, "siti@example.com").json()
        member = google_sign_in(client, sub="member-1", email="siti@example.com")

        client.post(f"/api/v1/onboarding/invites/{invite['id']}/accept", headers=bearer(member))
        again = client.post(
            f"/api/v1/onboarding/invites/{invite['id']}/accept", headers=bearer(member)
        )
        assert again.status_code == 409
        assert again.json()["error"]["code"] == "household_already_joined"

    def test_a_revoked_invite_cannot_be_accepted(self, client: TestClient) -> None:
        owner = self._owner_with_household(client)
        invite = self._invite(client, owner, "siti@example.com").json()

        revoked = client.delete(f"/api/v1/household/invites/{invite['id']}", headers=bearer(owner))
        assert revoked.status_code == 204

        member = google_sign_in(client, sub="member-1", email="siti@example.com")
        assert member["pending_invites"] == []

        response = client.post(
            f"/api/v1/onboarding/invites/{invite['id']}/accept", headers=bearer(member)
        )
        assert response.status_code == 409
        assert response.json()["error"]["code"] == "invite_already_resolved"

    def test_a_duplicate_invite_is_refused(self, client: TestClient) -> None:
        owner = self._owner_with_household(client)
        self._invite(client, owner, "siti@example.com")

        again = self._invite(client, owner, "siti@example.com", role="viewer")
        assert again.status_code == 409
        assert again.json()["error"]["code"] == "invite_already_sent"

    def test_inviting_an_existing_member_is_refused(self, client: TestClient) -> None:
        owner = self._owner_with_household(client)
        invite = self._invite(client, owner, "siti@example.com").json()
        member = google_sign_in(client, sub="member-1", email="siti@example.com")
        client.post(f"/api/v1/onboarding/invites/{invite['id']}/accept", headers=bearer(member))

        again = self._invite(client, owner, "siti@example.com")
        assert again.status_code == 409
        assert again.json()["error"]["code"] == "already_a_member"

    def test_inviting_yourself_is_refused(self, client: TestClient) -> None:
        owner = self._owner_with_household(client)

        response = self._invite(client, owner, "budi@example.com")
        assert response.status_code == 422
        assert response.json()["error"]["code"] == "cannot_invite_yourself"

    def test_a_second_owner_cannot_be_invited(self, client: TestClient) -> None:
        owner = self._owner_with_household(client)

        response = self._invite(client, owner, "siti@example.com", role="owner")
        assert response.status_code == 422

    def test_a_plain_member_cannot_invite(self, client: TestClient) -> None:
        owner = self._owner_with_household(client)
        invite = self._invite(client, owner, "siti@example.com").json()
        member = google_sign_in(client, sub="member-1", email="siti@example.com")
        client.post(f"/api/v1/onboarding/invites/{invite['id']}/accept", headers=bearer(member))

        response = self._invite(client, member, "rina@example.com")
        assert response.status_code == 403
        assert response.json()["error"]["code"] == "household_edit_denied"

    def test_a_user_without_a_household_cannot_invite(self, client: TestClient) -> None:
        stranger = google_sign_in(client, sub="stranger", email="rina@example.com")

        response = client.post(
            "/api/v1/household/invites",
            headers=bearer(stranger),
            json={"email": "x@example.com", "role": "member"},
        )
        assert response.status_code == 403


class TestPeopleList:
    def test_the_owner_sees_members_and_open_invites(self, client: TestClient) -> None:
        owner = google_sign_in(client, sub="owner-1", email="budi@example.com", name="Budi")
        create_household(client, owner)
        client.post(
            "/api/v1/household/invites",
            headers=bearer(owner),
            json={"email": "siti@example.com", "role": "member"},
        )

        people = client.get("/api/v1/household/people", headers=bearer(owner)).json()
        assert len(people["members"]) == 1
        assert people["members"][0]["is_you"] is True
        assert people["members"][0]["role"] == MembershipRole.OWNER
        assert len(people["invites"]) == 1
        assert people["invites"][0]["email"] == "siti@example.com"

    def test_a_member_sees_people_but_not_open_invites(self, client: TestClient) -> None:
        owner = google_sign_in(client, sub="owner-1", email="budi@example.com", name="Budi")
        create_household(client, owner)
        invite = client.post(
            "/api/v1/household/invites",
            headers=bearer(owner),
            json={"email": "siti@example.com", "role": "member"},
        ).json()
        member = google_sign_in(client, sub="member-1", email="siti@example.com", name="Siti")
        client.post(f"/api/v1/onboarding/invites/{invite['id']}/accept", headers=bearer(member))
        client.post(
            "/api/v1/household/invites",
            headers=bearer(owner),
            json={"email": "rina@example.com", "role": "viewer"},
        )

        people = client.get("/api/v1/household/people", headers=bearer(member)).json()
        assert len(people["members"]) == 2
        assert people["invites"] == [], "a member has no business seeing open invites"


class TestHouseholdSettings:
    def test_renaming_and_changing_currency_moves_seeded_accounts(
        self, client: TestClient, db: Session
    ) -> None:
        owner = google_sign_in(client)
        household = create_household(client, owner)

        response = client.patch(
            "/api/v1/household",
            headers=bearer(owner),
            json={"name": "  Rumah Baru  ", "base_currency": "sgd"},
        )
        assert response.status_code == 200
        assert response.json()["name"] == "Rumah Baru"
        assert response.json()["base_currency"] == "SGD"

        accounts = db.scalars(
            select(FinancialAccount).where(
                FinancialAccount.household_id == uuid.UUID(household["id"])
            )
        ).all()
        assert {account.currency for account in accounts} == {"SGD"}

    def test_a_valid_currency_outside_the_old_shortlist_is_accepted(
        self, client: TestClient
    ) -> None:
        owner = google_sign_in(client)
        create_household(client, owner)

        response = client.patch(
            "/api/v1/household",
            headers=bearer(owner),
            json={"name": "Rumah", "base_currency": "CHF"},
        )
        assert response.status_code == 200
        assert response.json()["base_currency"] == "CHF"

        invalid = client.patch(
            "/api/v1/household",
            headers=bearer(owner),
            json={"name": "Rumah", "base_currency": "!2!"},
        )
        assert invalid.status_code == 422
        assert invalid.json()["error"]["code"] == "invalid_currency"

    def test_a_viewer_cannot_rename_the_household(self, client: TestClient, db: Session) -> None:
        owner = google_sign_in(client)
        create_household(client, owner)
        user = db.scalar(select(User).where(User.normalized_email == "ratna@example.com"))
        assert user is not None
        membership = db.scalar(select(Membership).where(Membership.user_id == user.id))
        assert membership is not None
        membership.role = MembershipRole.VIEWER
        db.commit()

        response = client.patch(
            "/api/v1/household",
            headers=bearer(owner),
            json={"name": "Coba Ubah", "base_currency": "IDR"},
        )
        assert response.status_code == 403
        assert response.json()["error"]["code"] == "household_edit_denied"


def owner_household_id(client: TestClient, owner: dict[str, Any]) -> str:
    return client.get("/api/v1/household", headers=bearer(owner)).json()["id"]
