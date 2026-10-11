import uuid
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.location_models import LocationPreference, LocationSession
from app.models import Membership, NotificationOutbox, User, utcnow

LOCATION_KINDS = {"location_started", "location_arrival"}


def cancel_session_notifications(db: Session, session_id: uuid.UUID) -> None:
    for event in db.scalars(
        select(NotificationOutbox).where(
            NotificationOutbox.kind.in_(LOCATION_KINDS), NotificationOutbox.status == "pending"
        )
    ):
        if event.data_json.get("session_id") == str(session_id):
            event.status = "cancelled"


def delivery_allowed(db: Session, event: NotificationOutbox) -> bool:
    item = db.get(LocationSession, uuid.UUID(event.data_json["session_id"]))
    if item is None or item.state != "active" or (item.expires_at.replace(tzinfo=UTC) <= utcnow()):
        return False
    preference = db.scalar(
        select(LocationPreference).where(
            LocationPreference.household_id == event.household_id,
            LocationPreference.user_id == event.user_id,
        )
    )
    return preference is None or (
        preference.sharing_started
        if event.kind == "location_started"
        else preference.arrival_alerts
    )


def queue_location_event(
    db: Session,
    item: LocationSession,
    *,
    kind: str,
    event_key: str,
    body: str,
    arrived_at: datetime | None = None,
) -> None:
    user = db.get(User, item.user_id)
    name = user.display_name if user else "Anggota keluarga"
    for recipient in db.scalars(
        select(Membership).where(
            Membership.household_id == item.household_id, Membership.user_id != item.user_id
        )
    ):
        key = f"{event_key}:{recipient.user_id}"
        if db.scalar(select(NotificationOutbox.id).where(NotificationOutbox.event_key == key)):
            continue
        data = {
            "kind": kind,
            "session_id": str(item.id),
            "expires_at": item.expires_at.replace(tzinfo=UTC).isoformat(),
        }
        if arrived_at:
            data["arrived_at"] = arrived_at.isoformat()
        event = NotificationOutbox(
            event_key=key,
            user_id=recipient.user_id,
            household_id=item.household_id,
            kind=kind,
            title=f"Lokasi {name}"[:160],
            body=body[:240],
            data_json=data,
        )
        if delivery_allowed(db, event):
            db.add(event)
