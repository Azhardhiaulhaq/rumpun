from datetime import UTC, datetime, timedelta

from app.location_models import LocationSession

POLYGON = [[-6.2, 106.8], [-6.2, 106.801], [-6.201, 106.801], [-6.201, 106.8]]


def test_area_validation_and_session_snapshot(client, auth_headers):
    area = client.post(
        "/api/v1/location/areas",
        headers=auth_headers,
        json={"name": "Meeting", "vertices": POLYGON},
    )
    assert area.status_code == 201
    session = client.post(
        "/api/v1/location/sessions",
        headers=auth_headers,
        json={"device_id": "phone", "request_key": "start"},
    )
    assert session.status_code == 201
    body = session.json()
    assert body["areas"][0]["name"] == "Meeting"
    updated = client.patch(
        f"/api/v1/location/areas/{area.json()['id']}",
        headers=auth_headers,
        json={"name": "Changed", "vertices": POLYGON, "version": 1},
    )
    assert updated.status_code == 200
    replay = client.post(
        "/api/v1/location/sessions",
        headers=auth_headers,
        json={"device_id": "phone", "request_key": "start"},
    )
    assert replay.json()["id"] == body["id"]
    assert replay.json()["areas"][0]["name"] == "Meeting"
    conflict = client.post(
        "/api/v1/location/sessions",
        headers=auth_headers,
        json={"device_id": "phone", "request_key": "second"},
    )
    assert conflict.status_code == 409


def test_position_privacy_stop_and_expiry(client, auth_headers, db):
    session = client.post(
        "/api/v1/location/sessions",
        headers=auth_headers,
        json={"device_id": "phone", "request_key": "start"},
    ).json()
    path = f"/api/v1/location/sessions/{session['id']}"
    payload = {
        "device_id": "phone",
        "latitude": -6.2,
        "longitude": 106.8,
        "accuracy": 10,
        "observed_at": datetime.now(UTC).isoformat(),
        "sequence": 1,
    }
    assert client.put(path + "/position", headers=auth_headers, json=payload).status_code == 204
    assert client.get("/api/v1/location/sessions", headers=auth_headers).json()[0]["position"]
    assert client.post(path + "/stop", headers=auth_headers).status_code == 200
    assert db.query(LocationSession).one().position is None
    assert client.put(path + "/position", headers=auth_headers, json=payload).status_code == 409
    client.post(
        "/api/v1/location/sessions",
        headers=auth_headers,
        json={"device_id": "phone", "request_key": "new"},
    )
    active = db.query(LocationSession).filter_by(state="active").one()
    active.expires_at = datetime.now(UTC) - timedelta(seconds=1)
    db.commit()
    assert client.get("/api/v1/location/sessions", headers=auth_headers).json() == []
    assert active.position is None


def test_extension_arrival_replay_and_preferences(client, auth_headers, db):
    area = client.post(
        "/api/v1/location/areas",
        headers=auth_headers,
        json={"name": "Meeting", "vertices": POLYGON},
    ).json()
    item = client.post(
        "/api/v1/location/sessions",
        headers=auth_headers,
        json={"device_id": "phone", "request_key": "start"},
    ).json()
    path = f"/api/v1/location/sessions/{item['id']}"
    extended = client.post(
        path + "/extend", headers=auth_headers, json={"minutes": 30, "request_key": "extend"}
    ).json()
    replay = client.post(
        path + "/extend", headers=auth_headers, json={"minutes": 30, "request_key": "extend"}
    ).json()
    assert replay["expires_at"] == extended["expires_at"]
    assert replay["areas"] == item["areas"]
    arrival = {
        "device_id": "phone",
        "area_ids": [area["id"]],
        "arrived_at": datetime.now(UTC).isoformat(),
    }
    assert client.post(path + "/arrivals", headers=auth_headers, json=arrival).json()[
        "accepted_area_ids"
    ] == [area["id"]]
    assert (
        client.post(path + "/arrivals", headers=auth_headers, json=arrival).json()[
            "accepted_area_ids"
        ]
        == []
    )
    assert client.patch(
        "/api/v1/location/preferences",
        headers=auth_headers,
        json={"sharing_started": False, "arrival_alerts": False},
    ).json() == {"sharing_started": False, "arrival_alerts": False}
    client.post(path + "/stop", headers=auth_headers)
    assert client.post(path + "/arrivals", headers=auth_headers, json=arrival).status_code == 409
    assert client.get("/api/v1/location/sessions/current", headers=auth_headers).json() is None


def test_invalid_polygon(client, auth_headers):
    for vertices in [
        POLYGON[:2],
        [POLYGON[0]] * 3,
        [POLYGON[0], POLYGON[2], POLYGON[1], POLYGON[3]],
    ]:
        response = client.post(
            "/api/v1/location/areas",
            headers=auth_headers,
            json={"name": "Invalid", "vertices": vertices},
        )
        assert response.status_code == 422
