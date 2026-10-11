import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import (
    JSON,
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
    Uuid,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base
from app.models import utcnow


class LocationArea(Base):
    __tablename__ = "location_areas"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    household_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("households.id"), index=True)
    name: Mapped[str] = mapped_column(String(100))
    vertices: Mapped[list[list[float]]] = mapped_column(JSON)
    version: Mapped[int] = mapped_column(Integer, default=1)


class LocationSession(Base):
    __tablename__ = "location_sessions"
    __table_args__ = (
        Index(
            "uq_location_active_user",
            "user_id",
            unique=True,
            sqlite_where=text("state = 'active'"),
            postgresql_where=text("state = 'active'"),
        ),
    )
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    household_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("households.id"), index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), index=True)
    device_id: Mapped[str] = mapped_column(String(100))
    start_key: Mapped[str] = mapped_column(String(100))
    state: Mapped[str] = mapped_column(String(20), default="active")
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    areas: Mapped[list[dict[str, Any]]] = mapped_column(JSON)
    position: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)
    sequence: Mapped[int] = mapped_column(Integer, default=-1)
    extension_keys: Mapped[list[str]] = mapped_column(JSON, default=list)
    # Per-area arrival phase derived from uploaded positions; never a route.
    arrival_state: Mapped[dict[str, dict[str, str]]] = mapped_column(JSON, default=dict)


class LocationArrival(Base):
    __tablename__ = "location_arrivals"
    __table_args__ = (UniqueConstraint("session_id", "area_id"),)
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    session_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("location_sessions.id"))
    area_id: Mapped[str] = mapped_column(String(36))
    arrived_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class LocationPreference(Base):
    __tablename__ = "location_preferences"
    __table_args__ = (UniqueConstraint("household_id", "user_id"),)
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    household_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("households.id"))
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"))
    sharing_started: Mapped[bool] = mapped_column(Boolean, default=True)
    arrival_alerts: Mapped[bool] = mapped_column(Boolean, default=True)
