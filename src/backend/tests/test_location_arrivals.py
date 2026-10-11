"""Arrival alerts confirmed by the server from ordinary position uploads."""

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select

from app.location_arrivals import advance, classify
from app.location_models import LocationArrival, LocationSession
from app.models import NotificationOutbox, PushDevice
from app.push import dispatch_pending, token_digest

# Roughly the shape and size of the real "apartment" area: about 66 x 47 m.
APARTMENT = [
    [-6.2000, 106.8000],
    [-6.2000, 106.8006],
    [-6.2004, 106.8006],
    [-6.2004, 106.8000],
]
CENTRE = (-6.2002, 106.8003)
FAR_AWAY = (-6.2050, 106.8003)  # about 530 m south


class Recorder:
    def __init__(self) -> None:
        self.messages: list[tuple[str, str, dict[str, str]]] = []

    def send(self, token: str, title: str, body: str, data: dict[str, str], key: str) -> bool:
        self.messages.append((token, body, data))
        return True


def test_indoor_accuracy_still_counts_as_inside() -> None:
    # The old rule needed the whole 35 m uncertainty circle inside a 47 m wide
    # polygon, which an indoor phone never manages.
    assert classify(APARTMENT, *CENTRE, 35) == "inside"
    assert classify(APARTMENT, *CENTRE, 90) == "inside"
    assert classify(APARTMENT, *FAR_AWAY, 40) == "outside"
    assert classify(APARTMENT, *CENTRE, 150) is None
    # Just past the edge with poor accuracy is ambiguous, not outside.
    assert classify(APARTMENT, -6.20045, 106.8003, 40) == "inside"
    assert classify(APARTMENT, -6.2006, 106.8003, 40) is None


def _run(readings: list[tuple[int, tuple[float, float], float]]) -> list[str]:
    areas = [{"id": "home", "name": "Rumah", "vertices": APARTMENT}]
    states: dict[str, dict[str, str]] = {}
    start = datetime(2026, 10, 10, 10, tzinfo=UTC)
    arrived: list[str] = []
    for seconds, (lat, lng), accuracy in readings:
        states, confirmed = advance(
            areas,
            states,
            lat=lat,
            lng=lng,
            accuracy=accuracy,
            observed=start + timedelta(seconds=seconds),
        )
        arrived += [area_id for area_id, _ in confirmed]
    return arrived


def test_starting_inside_does_not_notify_until_leaving_and_returning() -> None:
    assert _run([(0, CENTRE, 10), (30, CENTRE, 10), (90, CENTRE, 10)]) == []
    assert _run([(0, CENTRE, 10), (30, FAR_AWAY, 10), (60, CENTRE, 30), (95, CENTRE, 30)]) == [
        "home"
    ]


def test_poor_readings_pause_rather_than_restart_dwell() -> None:
    assert _run(
        [
            (0, FAR_AWAY, 15),
            (40, CENTRE, 40),
            (55, CENTRE, 250),  # uncertain indoor fix
            (75, CENTRE, 45),
        ]
    ) == ["home"]


def test_long_silence_while_entering_restarts_dwell() -> None:
    assert _run([(0, FAR_AWAY, 15), (10, CENTRE, 20), (400, CENTRE, 20)]) == []


def test_brief_pass_through_does_not_notify() -> None:
    assert _run([(0, FAR_AWAY, 15), (10, CENTRE, 20), (25, FAR_AWAY, 20)]) == []


def _upload(client, headers, path, seq, point, accuracy, when):  # type: ignore[no-untyped-def]
    response = client.put(
        path + "/position",
        headers=headers,
        json={
            "device_id": "phone",
            "latitude": point[0],
            "longitude": point[1],
            "accuracy": accuracy,
            "observed_at": when.isoformat(),
            "sequence": seq,
        },
    )
    assert response.status_code == 204


@pytest.fixture
def sharing(client, auth_headers, db):  # type: ignore[no-untyped-def]
    client.post(
        "/api/v1/location/areas",
        headers=auth_headers,
        json={"name": "Apartemen", "vertices": APARTMENT},
    )
    item = client.post(
        "/api/v1/location/sessions",
        headers=auth_headers,
        json={"device_id": "phone", "request_key": "start"},
    ).json()
    # Uploads below are backdated by up to 70 s, so the session must predate them.
    session = db.get(LocationSession, uuid.UUID(item["id"]))
    session.started_at = datetime.now(UTC) - timedelta(minutes=5)
    db.commit()
    return item


def test_partner_is_notified_when_uploads_show_an_arrival(
    client, auth_headers, db, partner, sharing
):  # type: ignore[no-untyped-def]
    path = f"/api/v1/location/sessions/{sharing['id']}"
    now = datetime.now(UTC)
    _upload(client, auth_headers, path, 1, FAR_AWAY, 12, now - timedelta(seconds=70))
    _upload(client, auth_headers, path, 2, CENTRE, 38, now - timedelta(seconds=40))
    assert db.scalars(select(LocationArrival)).all() == []
    _upload(client, auth_headers, path, 3, CENTRE, 42, now - timedelta(seconds=5))
    arrivals = db.scalars(select(LocationArrival)).all()
    assert len(arrivals) == 1
    events = db.scalars(
        select(NotificationOutbox).where(NotificationOutbox.kind == "location_arrival")
    ).all()
    assert [event.user_id for event in events] == [partner["user"].id]
    assert events[0].body == "Tiba di Apartemen."

    # More readings inside, and a late phone report, must not alert twice.
    _upload(client, auth_headers, path, 4, CENTRE, 20, now)
    late = client.post(
        path + "/arrivals",
        headers=auth_headers,
        json={
            "device_id": "phone",
            "area_ids": [arrivals[0].area_id],
            "arrived_at": now.isoformat(),
        },
    )
    assert late.json()["accepted_area_ids"] == []
    assert (
        len(
            db.scalars(
                select(NotificationOutbox).where(NotificationOutbox.kind == "location_arrival")
            ).all()
        )
        == 1
    )

    db.add(
        PushDevice(
            user_id=partner["user"].id,
            household_id=events[0].household_id,
            token="partner-token",
            token_digest=token_digest("partner-token"),
            platform="ios",
        )
    )
    db.commit()
    sender = Recorder()
    dispatch_pending(db, sender)
    assert [(token, body) for token, body, _ in sender.messages][-1] == (
        "partner-token",
        "Tiba di Apartemen.",
    )


def test_sharer_is_never_the_recipient(client, auth_headers, db, sharing):  # type: ignore[no-untyped-def]
    path = f"/api/v1/location/sessions/{sharing['id']}"
    now = datetime.now(UTC)
    _upload(client, auth_headers, path, 1, FAR_AWAY, 12, now - timedelta(seconds=70))
    _upload(client, auth_headers, path, 2, CENTRE, 20, now - timedelta(seconds=35))
    _upload(client, auth_headers, path, 3, CENTRE, 20, now)
    assert len(db.scalars(select(LocationArrival)).all()) == 1
    assert (
        db.scalars(
            select(NotificationOutbox).where(NotificationOutbox.kind == "location_arrival")
        ).all()
        == []
    )


def test_start_notice_uses_household_local_time(client, auth_headers, db, partner):  # type: ignore[no-untyped-def]
    client.post(
        "/api/v1/location/sessions",
        headers=auth_headers,
        json={"device_id": "phone", "request_key": "start"},
    )
    event = db.scalars(
        select(NotificationOutbox).where(NotificationOutbox.kind == "location_started")
    ).one()
    assert event.body.startswith("Mulai berbagi lokasi sampai pukul ")
    assert "+00:00" not in event.body
