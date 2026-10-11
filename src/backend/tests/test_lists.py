from datetime import timedelta

from sqlalchemy import select

from app.models import Membership, MembershipRole, NotificationOutbox, PushDevice, utcnow
from app.push import dispatch_pending, token_digest


class Recorder:
    def __init__(self) -> None:
        self.messages: list[tuple[str, str, str]] = []

    def send(self, token: str, title: str, body: str, data: dict[str, str], key: str) -> bool:
        self.messages.append((token, title, body))
        return True


def _new(client, headers, name="Belanja bulanan", kind="checklist"):  # type: ignore[no-untyped-def]
    response = client.post("/api/v1/lists", headers=headers, json={"name": name, "kind": kind})
    assert response.status_code == 201
    return response.json()


def _add(client, headers, list_id, text, key, **extra):  # type: ignore[no-untyped-def]
    return client.post(
        f"/api/v1/lists/{list_id}/items",
        headers=headers,
        json={"client_id": key, "text": text, **extra},
    )


def test_checklist_lifecycle_shared_between_members(client, auth_headers, partner):  # type: ignore[no-untyped-def]
    created = _new(client, auth_headers)
    assert created["items"] == [] and created["created_by"] == "Owner"
    first = _add(client, auth_headers, created["id"], "  Telur  ", "k1", quantity="1 kg")
    assert first.status_code == 201
    assert first.json()["text"] == "Telur" and first.json()["quantity"] == "1 kg"
    # A retried add with the same client key returns the same item.
    assert (
        _add(client, auth_headers, created["id"], "Telur", "k1").json()["id"] == first.json()["id"]
    )
    _add(client, partner["headers"], created["id"], "Susu", "k2", note="yang full cream")

    seen = client.get(f"/api/v1/lists/{created['id']}", headers=partner["headers"]).json()
    assert [(i["text"], i["added_by"]) for i in seen["items"]] == [
        ("Telur", "Owner"),
        ("Susu", "Partner"),
    ]
    egg = seen["items"][0]["id"]
    checked = client.patch(
        f"/api/v1/lists/{created['id']}/items/{egg}",
        headers=partner["headers"],
        json={"checked": True},
    ).json()
    assert checked["checked"] and checked["checked_by"] == "Partner"
    summary = client.get("/api/v1/lists", headers=auth_headers).json()
    assert summary[0]["open_count"] == 1 and summary[0]["preview"] == ["Susu"]

    cleared = client.post(
        f"/api/v1/lists/{created['id']}/clear-checked", headers=auth_headers
    ).json()
    assert [i["text"] for i in cleared["items"]] == ["Susu"]
    edited = client.patch(
        f"/api/v1/lists/{created['id']}/items/{cleared['items'][0]['id']}",
        headers=auth_headers,
        json={"quantity": None, "text": "Susu UHT"},
    ).json()
    assert edited["text"] == "Susu UHT" and edited["note"] == "yang full cream"
    assert client.delete(f"/api/v1/lists/{created['id']}", headers=auth_headers).status_code == 204
    assert client.get("/api/v1/lists", headers=auth_headers).json() == []


def test_note_body_uses_version_to_avoid_overwriting(client, auth_headers, partner):  # type: ignore[no-untyped-def]
    note = _new(client, auth_headers, name="Catatan servis AC", kind="note")
    path = f"/api/v1/lists/{note['id']}"
    saved = client.patch(
        path, headers=auth_headers, json={"version": 1, "body": "Teknisi datang Sabtu"}
    )
    assert saved.json()["version"] == 2
    stale = client.patch(path, headers=partner["headers"], json={"version": 1, "body": "Lain"})
    assert stale.status_code == 409
    assert stale.json()["error"]["details"]["current"]["body"] == "Teknisi datang Sabtu"
    assert _add(client, auth_headers, note["id"], "x", "k").status_code == 422


def test_lists_are_household_scoped(client, auth_headers):  # type: ignore[no-untyped-def]
    created = _new(client, auth_headers)
    client.post(
        "/api/v1/auth/register",
        json={
            "email": "other@example.com",
            "password": "correct-horse-battery-staple",
            "display_name": "Other",
            "household_name": "Elsewhere",
        },
    )
    other = client.post(
        "/api/v1/auth/login",
        json={"email": "other@example.com", "password": "correct-horse-battery-staple"},
    ).json()
    headers = {"Authorization": f"Bearer {other['access_token']}"}
    assert client.get("/api/v1/lists", headers=headers).json() == []
    assert client.get(f"/api/v1/lists/{created['id']}", headers=headers).status_code == 404
    assert _add(client, headers, created["id"], "x", "k").status_code == 404


def test_viewer_can_read_but_not_change(client, auth_headers, partner, db):  # type: ignore[no-untyped-def]
    created = _new(client, auth_headers)
    membership = db.scalar(select(Membership).where(Membership.user_id == partner["user"].id))
    membership.role = MembershipRole.VIEWER
    db.commit()
    assert (
        client.get(f"/api/v1/lists/{created['id']}", headers=partner["headers"]).status_code == 200
    )
    assert _add(client, partner["headers"], created["id"], "x", "k").status_code == 403


def test_burst_of_additions_becomes_one_notice(client, auth_headers, partner, db):  # type: ignore[no-untyped-def]
    created = _new(client, auth_headers)
    for index, text in enumerate(["Telur", "Susu", "Beras", "Minyak"]):
        _add(client, auth_headers, created["id"], text, f"k{index}")
    events = db.scalars(
        select(NotificationOutbox).where(NotificationOutbox.kind == "list_items")
    ).all()
    assert len(events) == 1 and events[0].user_id == partner["user"].id
    db.add(
        PushDevice(
            user_id=partner["user"].id,
            household_id=events[0].household_id,
            token="partner",
            token_digest=token_digest("partner"),
            platform="ios",
        )
    )
    db.commit()
    sender = Recorder()
    dispatch_pending(db, sender)
    assert sender.messages == []  # waits for the burst to settle
    events[0].next_attempt_at = utcnow() - timedelta(seconds=1)
    db.commit()
    dispatch_pending(db, sender)
    assert sender.messages == [
        (
            "partner",
            "Belanja bulanan",
            "Owner menambahkan Telur, Susu, dan 2 lainnya ke Belanja bulanan.",
        )
    ]


def test_muted_recipient_and_already_bought_items_are_not_sent(client, auth_headers, partner, db):  # type: ignore[no-untyped-def]
    created = _new(client, auth_headers)
    item = _add(client, auth_headers, created["id"], "Telur", "k").json()
    client.patch(
        f"/api/v1/lists/{created['id']}/items/{item['id']}",
        headers=auth_headers,
        json={"checked": True},
    )
    event = db.scalars(select(NotificationOutbox)).one()
    event.next_attempt_at = utcnow() - timedelta(seconds=1)
    db.commit()
    dispatch_pending(db, Recorder())
    assert event.status == "cancelled"

    assert client.patch(
        "/api/v1/lists/preferences", headers=partner["headers"], json={"items_added": False}
    ).json() == {"items_added": False}
    _add(client, auth_headers, created["id"], "Susu", "k2")
    assert (
        len(
            db.scalars(
                select(NotificationOutbox).where(NotificationOutbox.status == "pending")
            ).all()
        )
        == 0
    )


def test_adding_alone_notifies_nobody(client, auth_headers, db):  # type: ignore[no-untyped-def]
    created = _new(client, auth_headers)
    _add(client, auth_headers, created["id"], "Telur", "k")
    assert db.scalars(select(NotificationOutbox)).all() == []


def test_cover_is_shared_and_validated(client, auth_headers, partner):  # type: ignore[no-untyped-def]
    created = client.post(
        "/api/v1/lists",
        headers=auth_headers,
        json={"name": "Pasar", "icon": "market", "tint": "apricot"},
    ).json()
    assert (created["icon"], created["tint"]) == ("market", "apricot")
    changed = client.patch(
        f"/api/v1/lists/{created['id']}",
        headers=partner["headers"],
        json={"version": 1, "icon": "kitchen", "tint": "sky"},
    ).json()
    assert (changed["icon"], changed["tint"]) == ("kitchen", "sky")
    bad = client.post("/api/v1/lists", headers=auth_headers, json={"name": "x", "icon": "rocket"})
    assert bad.status_code == 422
