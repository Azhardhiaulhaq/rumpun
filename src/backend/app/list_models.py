import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base
from app.models import utcnow

LIST_KINDS = ("checklist", "note")


class HouseholdList(Base):
    """A shared checklist (groceries, errands) or a free-form note."""

    __tablename__ = "household_lists"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(100))
    kind: Mapped[str] = mapped_column(String(16))
    body: Mapped[str] = mapped_column(Text, default="")
    # Cover icon and tint picked in the app; free-form keys validated by the API.
    icon: Mapped[str] = mapped_column(String(24), default="basket")
    tint: Mapped[str] = mapped_column(String(24), default="sage")
    version: Mapped[int] = mapped_column(Integer, default=1)
    created_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class ListItem(Base):
    __tablename__ = "list_items"
    __table_args__ = (
        UniqueConstraint("list_id", "client_id"),
        Index("ix_list_items_list_position", "list_id", "position"),
    )
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    list_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("household_lists.id", ondelete="CASCADE"))
    # Lets a phone retry an add on a weak connection without creating a twin.
    client_id: Mapped[str] = mapped_column(String(64))
    text: Mapped[str] = mapped_column(String(200))
    quantity: Mapped[str | None] = mapped_column(String(40), nullable=True)
    note: Mapped[str | None] = mapped_column(String(240), nullable=True)
    position: Mapped[int] = mapped_column(Integer)
    checked: Mapped[bool] = mapped_column(Boolean, default=False)
    checked_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    checked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    added_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class ListPreference(Base):
    __tablename__ = "list_preferences"
    __table_args__ = (UniqueConstraint("household_id", "user_id"),)
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    household_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("households.id", ondelete="CASCADE"))
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    items_added: Mapped[bool] = mapped_column(Boolean, default=True)
