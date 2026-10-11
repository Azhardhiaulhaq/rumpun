import uuid
from datetime import UTC, datetime, timedelta
from typing import Annotated, Any, Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field, model_validator
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db
from app.errors import ApiError
from app.location_arrivals import advance
from app.location_auth import tracking_auth, tracking_token
from app.location_geometry import validate_polygon
from app.location_models import LocationArea, LocationArrival, LocationPreference, LocationSession
from app.location_notifications import cancel_session_notifications, queue_location_event
from app.models import Household, utcnow
from app.security import AuthContext, get_auth_context

router = APIRouter(prefix="/location", tags=["location"])
Auth = Annotated[AuthContext, Depends(get_auth_context)]
TrackingAuth = Annotated[AuthContext, Depends(tracking_auth)]


class AreaInput(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    vertices: list[tuple[float, float]]

    @model_validator(mode="after")
    def validate_shape(self) -> "AreaInput":
        self.name = self.name.strip()
        if not self.name:
            raise ValueError("Area name is required")
        validate_polygon(self.vertices)
        return self


class AreaEdit(AreaInput):
    version: int = Field(ge=1)


class StartInput(BaseModel):
    minutes: Literal[30, 60, 120, 240] = 60
    device_id: str = Field(min_length=1, max_length=100)
    request_key: str = Field(min_length=1, max_length=100)


class ExtendInput(BaseModel):
    minutes: Literal[30, 60, 120, 240]
    request_key: str = Field(min_length=1, max_length=100)


class ArrivalInput(BaseModel):
    device_id: str = Field(min_length=1, max_length=100)
    area_ids: list[str] = Field(min_length=1, max_length=64)
    arrived_at: datetime


class PreferenceInput(BaseModel):
    sharing_started: bool = True
    arrival_alerts: bool = True


class PositionInput(BaseModel):
    device_id: str = Field(min_length=1, max_length=100)
    latitude: float = Field(ge=-85, le=85, allow_inf_nan=False)
    longitude: float = Field(ge=-180, le=180, allow_inf_nan=False)
    accuracy: float = Field(gt=0, le=10000, allow_inf_nan=False)
    observed_at: datetime
    sequence: int = Field(ge=0)


def _utc(value: datetime) -> datetime:
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


def expire_sessions(db: Session) -> None:
    for item in db.scalars(
        select(LocationSession).where(
            LocationSession.state == "active", LocationSession.expires_at <= utcnow()
        )
    ):
        item.state = "expired"
        item.position = None
        cancel_session_notifications(db, item.id)


def _local_time(db: Session, household_id: uuid.UUID, value: datetime) -> str:
    household = db.get(Household, household_id)
    try:
        zone = ZoneInfo(household.timezone if household else "Asia/Jakarta")
    except ZoneInfoNotFoundError:
        zone = ZoneInfo("UTC")
    return _utc(value).astimezone(zone).strftime("%H.%M")


def record_arrivals(
    db: Session, item: LocationSession, area_ids: list[str], arrived_at: datetime
) -> list[str]:
    """Store first arrivals for the session and queue one combined notification.

    Both the phone's own report and the server-side detector land here, and the
    per-session area uniqueness means whichever comes first wins.
    """
    snapshot = {area["id"]: area for area in item.areas}
    confirmed = set(
        db.scalars(select(LocationArrival.area_id).where(LocationArrival.session_id == item.id))
    )
    fresh = sorted(set(area_ids) - confirmed)
    if not fresh:
        return []
    for area_id in fresh:
        db.add(LocationArrival(session_id=item.id, area_id=area_id, arrived_at=arrived_at))
    state = dict(item.arrival_state or {})
    for area_id in fresh:
        state[area_id] = {"phase": "notified"}
    item.arrival_state = state
    delayed = utcnow() - arrived_at > timedelta(seconds=90)
    names = ", ".join(snapshot[area_id]["name"] for area_id in fresh)
    body = f"Tiba di {names}"
    body += f" pukul {_local_time(db, item.household_id, arrived_at)}." if delayed else "."
    queue_location_event(
        db,
        item,
        kind="location_arrival",
        event_key=f"location-arrival:{item.id}:{fresh[0]}",
        body=body,
        arrived_at=arrived_at,
    )
    return fresh


def _area_json(area: LocationArea) -> dict[str, Any]:
    return {
        "id": str(area.id),
        "name": area.name,
        "vertices": area.vertices,
        "version": area.version,
    }


def _session_json(item: LocationSession, *, owner: bool) -> dict[str, Any]:
    position = item.position
    if item.state != "active" or _utc(item.expires_at) <= utcnow():
        position = None
    if position and _utc(datetime.fromisoformat(position["observed_at"])) < (
        utcnow() - timedelta(minutes=2)
    ):
        position = None
    result: dict[str, Any] = {
        "id": str(item.id),
        "user_id": str(item.user_id),
        "state": item.state,
        "started_at": _utc(item.started_at).isoformat(),
        "expires_at": _utc(item.expires_at).isoformat(),
        "position": position,
    }
    if owner:
        result["areas"] = item.areas
        if item.state == "active":
            result["tracking_token"] = tracking_token(item)
    return result


def _owned(db: Session, auth: AuthContext, session_id: uuid.UUID) -> LocationSession:
    item = db.scalar(
        select(LocationSession)
        .where(
            LocationSession.id == session_id,
            LocationSession.household_id == auth.household.id,
            LocationSession.user_id == auth.user.id,
        )
        .with_for_update()
    )
    if item is None:
        raise ApiError(404, "location_session_not_found", "Session not found")
    return item


@router.get("/areas")
def areas(auth: Auth, db: Session = Depends(get_db)) -> list[dict[str, Any]]:
    return [
        _area_json(a)
        for a in db.scalars(
            select(LocationArea)
            .where(LocationArea.household_id == auth.household.id)
            .order_by(LocationArea.name)
        )
    ]


@router.post("/areas", status_code=201)
def create_area(payload: AreaInput, auth: Auth, db: Session = Depends(get_db)) -> dict[str, Any]:
    area = LocationArea(
        household_id=auth.household.id,
        name=payload.name,
        vertices=[list(p) for p in payload.vertices],
    )
    db.add(area)
    db.commit()
    return _area_json(area)


@router.patch("/areas/{area_id}")
def edit_area(
    area_id: uuid.UUID, payload: AreaEdit, auth: Auth, db: Session = Depends(get_db)
) -> dict[str, Any]:
    area = db.scalar(
        select(LocationArea)
        .where(LocationArea.id == area_id, LocationArea.household_id == auth.household.id)
        .with_for_update()
    )
    if area is None:
        raise ApiError(404, "location_area_not_found", "Area not found")
    if area.version != payload.version:
        raise ApiError(409, "location_area_conflict", "Area changed; reload before editing")
    area.name, area.vertices = payload.name, [list(p) for p in payload.vertices]
    area.version += 1
    db.commit()
    return _area_json(area)


@router.delete("/areas/{area_id}", status_code=204)
def delete_area(area_id: uuid.UUID, auth: Auth, db: Session = Depends(get_db)) -> None:
    area = db.scalar(
        select(LocationArea).where(
            LocationArea.id == area_id, LocationArea.household_id == auth.household.id
        )
    )
    if area is None:
        raise ApiError(404, "location_area_not_found", "Area not found")
    db.delete(area)
    db.commit()


@router.get("/sessions")
def sessions(auth: Auth, db: Session = Depends(get_db)) -> list[dict[str, Any]]:
    expire_sessions(db)
    db.commit()
    return [
        _session_json(s, owner=s.user_id == auth.user.id)
        for s in db.scalars(
            select(LocationSession).where(
                LocationSession.household_id == auth.household.id, LocationSession.state == "active"
            )
        )
    ]


@router.get("/sessions/current")
def current(auth: Auth, db: Session = Depends(get_db)) -> dict[str, Any] | None:
    expire_sessions(db)
    db.commit()
    item = db.scalar(
        select(LocationSession).where(
            LocationSession.user_id == auth.user.id,
            LocationSession.household_id == auth.household.id,
            LocationSession.state == "active",
        )
    )
    return _session_json(item, owner=True) if item else None


@router.post("/sessions/{session_id}/extend")
def extend(
    session_id: uuid.UUID, payload: ExtendInput, auth: Auth, db: Session = Depends(get_db)
) -> dict[str, Any]:
    item = _owned(db, auth, session_id)
    if item.state != "active" or _utc(item.expires_at) <= utcnow():
        raise ApiError(409, "location_session_ended", "Sharing has ended")
    if payload.request_key not in item.extension_keys:
        if len(item.extension_keys) >= 100:
            raise ApiError(422, "location_extension_limit", "Start a new session")
        item.expires_at = _utc(item.expires_at) + timedelta(minutes=payload.minutes)
        item.extension_keys = [*item.extension_keys, payload.request_key]
    db.commit()
    return _session_json(item, owner=True)


@router.get("/preferences")
def preferences(auth: Auth, db: Session = Depends(get_db)) -> dict[str, bool]:
    item = db.scalar(
        select(LocationPreference).where(
            LocationPreference.household_id == auth.household.id,
            LocationPreference.user_id == auth.user.id,
        )
    )
    return {
        "sharing_started": item.sharing_started if item else True,
        "arrival_alerts": item.arrival_alerts if item else True,
    }


@router.patch("/preferences")
def save_preferences(
    payload: PreferenceInput, auth: Auth, db: Session = Depends(get_db)
) -> dict[str, bool]:
    item = db.scalar(
        select(LocationPreference).where(
            LocationPreference.household_id == auth.household.id,
            LocationPreference.user_id == auth.user.id,
        )
    )
    if item is None:
        item = LocationPreference(household_id=auth.household.id, user_id=auth.user.id)
        db.add(item)
    item.sharing_started, item.arrival_alerts = payload.sharing_started, payload.arrival_alerts
    db.commit()
    return preferences(auth, db)


@router.post("/sessions/{session_id}/arrivals")
def arrivals(
    session_id: uuid.UUID, payload: ArrivalInput, auth: TrackingAuth, db: Session = Depends(get_db)
) -> dict[str, list[str]]:
    item = _owned(db, auth, session_id)
    now = utcnow()
    if item.state != "active" or _utc(item.expires_at) <= now:
        raise ApiError(409, "location_session_ended", "Sharing has ended")
    if item.device_id != payload.device_id:
        raise ApiError(
            403, "location_device_mismatch", "Only the sharing device can report arrivals"
        )
    if payload.arrived_at.tzinfo is None or not (
        _utc(item.started_at) <= _utc(payload.arrived_at) <= now
    ):
        raise ApiError(422, "invalid_arrival_time", "Arrival is outside the session")
    snapshot = {area["id"]: area for area in item.areas}
    if any(area_id not in snapshot for area_id in payload.area_ids):
        raise ApiError(422, "invalid_arrival_area", "Area is not in the session snapshot")
    fresh = record_arrivals(db, item, payload.area_ids, _utc(payload.arrived_at))
    db.commit()
    return {"accepted_area_ids": fresh}


@router.post("/sessions", status_code=201)
def start(payload: StartInput, auth: Auth, db: Session = Depends(get_db)) -> dict[str, Any]:
    expire_sessions(db)
    replay = db.scalar(
        select(LocationSession).where(
            LocationSession.user_id == auth.user.id,
            LocationSession.household_id == auth.household.id,
            LocationSession.start_key == payload.request_key,
        )
    )
    if replay:
        db.commit()
        return _session_json(replay, owner=True)
    item = LocationSession(
        household_id=auth.household.id,
        user_id=auth.user.id,
        device_id=payload.device_id,
        start_key=payload.request_key,
        expires_at=utcnow() + timedelta(minutes=payload.minutes),
        areas=areas(auth, db),
        position=None,
    )
    db.add(item)
    try:
        db.flush()
        queue_location_event(
            db,
            item,
            kind="location_started",
            event_key=f"location-start:{item.id}",
            body=(
                "Mulai berbagi lokasi sampai pukul "
                f"{_local_time(db, item.household_id, item.expires_at)}."
            ),
        )
        db.commit()
    except IntegrityError as error:
        db.rollback()
        raise ApiError(
            409, "location_session_active", "A sharing session is already active"
        ) from error
    return _session_json(item, owner=True)


@router.post("/sessions/{session_id}/stop")
def stop(
    session_id: uuid.UUID, auth: TrackingAuth, db: Session = Depends(get_db)
) -> dict[str, Any]:
    item = _owned(db, auth, session_id)
    item.state = "stopped"
    item.position = None
    cancel_session_notifications(db, item.id)
    db.commit()
    return _session_json(item, owner=True)


@router.put("/sessions/{session_id}/position", status_code=204)
def position(
    session_id: uuid.UUID, payload: PositionInput, auth: TrackingAuth, db: Session = Depends(get_db)
) -> None:
    item = _owned(db, auth, session_id)
    now = utcnow()
    if item.state != "active" or _utc(item.expires_at) <= now:
        raise ApiError(409, "location_session_ended", "Sharing has ended")
    if item.device_id != payload.device_id:
        raise ApiError(403, "location_device_mismatch", "Only the sharing device can upload")
    if payload.observed_at.tzinfo is None:
        raise ApiError(422, "invalid_position_time", "Observation time must include timezone")
    observed = _utc(payload.observed_at)
    if not _utc(item.started_at) <= observed <= now + timedelta(seconds=10):
        raise ApiError(422, "invalid_position_time", "Observation is outside the session")
    if observed < now - timedelta(minutes=2):
        raise ApiError(422, "stale_position", "Upload only a fresh position")
    if payload.sequence <= item.sequence:
        return
    if item.position and observed < datetime.fromisoformat(item.position["observed_at"]):
        return
    item.sequence = payload.sequence
    states, arrived = advance(
        item.areas,
        item.arrival_state or {},
        lat=payload.latitude,
        lng=payload.longitude,
        accuracy=payload.accuracy,
        observed=observed,
    )
    item.arrival_state = states
    if arrived:
        record_arrivals(db, item, [area_id for area_id, _ in arrived], min(t for _, t in arrived))
    item.position = {
        "latitude": payload.latitude,
        "longitude": payload.longitude,
        "accuracy": payload.accuracy,
        "observed_at": observed.isoformat(),
    }
    db.commit()
