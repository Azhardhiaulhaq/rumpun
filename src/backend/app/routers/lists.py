import uuid
from datetime import UTC, datetime
from typing import Annotated, Any, Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db
from app.errors import ApiError
from app.list_models import HouseholdList, ListItem, ListPreference
from app.list_notifications import queue_item_added
from app.models import MembershipRole, User, utcnow
from app.security import AuthContext, get_auth_context

router = APIRouter(prefix="/lists", tags=["lists"])
Auth = Annotated[AuthContext, Depends(get_auth_context)]

MAX_LISTS = 100
MAX_ITEMS = 500


def _clean(value: str | None) -> str | None:
    if value is None:
        return None
    value = " ".join(value.split())
    return value or None


ICONS = Literal["basket", "market", "home", "kitchen", "baby", "gift", "pill", "note", "cart"]
TINTS = Literal["sage", "apricot", "sky", "lilac", "sun", "clay"]


class ListInput(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    kind: Literal["checklist", "note"] = "checklist"
    icon: ICONS = "basket"
    tint: TINTS = "sage"

    @field_validator("name")
    @classmethod
    def required_name(cls, value: str) -> str:
        cleaned = _clean(value)
        if not cleaned:
            raise ValueError("Name is required")
        return cleaned


class ListEdit(BaseModel):
    version: int = Field(ge=1)
    name: str | None = Field(default=None, min_length=1, max_length=100)
    body: str | None = Field(default=None, max_length=20000)
    icon: ICONS | None = None
    tint: TINTS | None = None

    @field_validator("name")
    @classmethod
    def required_name(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = _clean(value)
        if not cleaned:
            raise ValueError("Name is required")
        return cleaned


class ItemInput(BaseModel):
    client_id: str = Field(min_length=1, max_length=64)
    text: str = Field(min_length=1, max_length=200)
    quantity: str | None = Field(default=None, max_length=40)
    note: str | None = Field(default=None, max_length=240)

    @field_validator("text")
    @classmethod
    def required_text(cls, value: str) -> str:
        cleaned = _clean(value)
        if not cleaned:
            raise ValueError("Item text is required")
        return cleaned

    @field_validator("quantity", "note")
    @classmethod
    def optional(cls, value: str | None) -> str | None:
        return _clean(value)


class ItemEdit(BaseModel):
    text: str | None = Field(default=None, min_length=1, max_length=200)
    quantity: str | None = Field(default=None, max_length=40)
    note: str | None = Field(default=None, max_length=240)
    checked: bool | None = None

    @field_validator("text")
    @classmethod
    def required_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = _clean(value)
        if not cleaned:
            raise ValueError("Item text is required")
        return cleaned

    @field_validator("quantity", "note")
    @classmethod
    def optional(cls, value: str | None) -> str | None:
        return _clean(value)


class PreferenceInput(BaseModel):
    items_added: bool = True


def _utc(value: datetime | None) -> str | None:
    if value is None:
        return None
    return (value.replace(tzinfo=UTC) if value.tzinfo is None else value).isoformat()


def _writer(auth: AuthContext) -> None:
    if auth.membership.role in {MembershipRole.VIEWER, MembershipRole.CHILD}:
        raise ApiError(403, "list_read_only", "Your role can read lists but not change them")


def _names(db: Session, ids: set[uuid.UUID | None]) -> dict[uuid.UUID, str]:
    wanted = {value for value in ids if value}
    if not wanted:
        return {}
    return {
        user.id: user.display_name for user in db.scalars(select(User).where(User.id.in_(wanted)))
    }


def _item_json(item: ListItem, names: dict[uuid.UUID, str]) -> dict[str, Any]:
    return {
        "id": str(item.id),
        "client_id": item.client_id,
        "text": item.text,
        "quantity": item.quantity,
        "note": item.note,
        "checked": item.checked,
        "checked_by": names.get(item.checked_by) if item.checked_by else None,
        "checked_at": _utc(item.checked_at),
        "added_by": names.get(item.added_by) if item.added_by else None,
        "created_at": _utc(item.created_at),
    }


def _summary(db: Session, item_list: HouseholdList) -> dict[str, Any]:
    total, open_count = db.execute(
        select(
            func.count(ListItem.id),
            func.count(ListItem.id).filter(ListItem.checked.is_(False)),
        ).where(ListItem.list_id == item_list.id)
    ).one()
    preview = db.scalars(
        select(ListItem.text)
        .where(ListItem.list_id == item_list.id, ListItem.checked.is_(False))
        .order_by(ListItem.position)
        .limit(3)
    ).all()
    return {
        "id": str(item_list.id),
        "name": item_list.name,
        "kind": item_list.kind,
        "icon": item_list.icon,
        "tint": item_list.tint,
        "version": item_list.version,
        "item_count": total,
        "open_count": open_count,
        "preview": list(preview)
        if item_list.kind == "checklist"
        else ([item_list.body[:120]] if item_list.body.strip() else []),
        "updated_at": _utc(item_list.updated_at),
    }


def _detail(db: Session, item_list: HouseholdList) -> dict[str, Any]:
    items = db.scalars(
        select(ListItem).where(ListItem.list_id == item_list.id).order_by(ListItem.position)
    ).all()
    names = _names(
        db,
        {item_list.created_by}
        | {item.added_by for item in items}
        | {item.checked_by for item in items},
    )
    return {
        **_summary(db, item_list),
        "body": item_list.body,
        "created_by": names.get(item_list.created_by) if item_list.created_by else None,
        "items": [_item_json(item, names) for item in items],
    }


def _owned(
    db: Session, auth: AuthContext, list_id: uuid.UUID, *, lock: bool = False
) -> HouseholdList:
    query = select(HouseholdList).where(
        HouseholdList.id == list_id, HouseholdList.household_id == auth.household.id
    )
    if lock:
        query = query.with_for_update()
    item_list = db.scalar(query)
    if item_list is None:
        raise ApiError(404, "list_not_found", "List not found")
    return item_list


def _item(db: Session, item_list: HouseholdList, item_id: uuid.UUID) -> ListItem:
    item = db.scalar(
        select(ListItem).where(ListItem.id == item_id, ListItem.list_id == item_list.id)
    )
    if item is None:
        raise ApiError(404, "list_item_not_found", "Item not found")
    return item


@router.get("/preferences")
def preferences(auth: Auth, db: Session = Depends(get_db)) -> dict[str, bool]:
    item = db.scalar(
        select(ListPreference).where(
            ListPreference.household_id == auth.household.id,
            ListPreference.user_id == auth.user.id,
        )
    )
    return {"items_added": item.items_added if item else True}


@router.patch("/preferences")
def save_preferences(
    payload: PreferenceInput, auth: Auth, db: Session = Depends(get_db)
) -> dict[str, bool]:
    item = db.scalar(
        select(ListPreference).where(
            ListPreference.household_id == auth.household.id,
            ListPreference.user_id == auth.user.id,
        )
    )
    if item is None:
        item = ListPreference(household_id=auth.household.id, user_id=auth.user.id)
        db.add(item)
    item.items_added = payload.items_added
    db.commit()
    return {"items_added": item.items_added}


@router.get("")
def lists(auth: Auth, db: Session = Depends(get_db)) -> list[dict[str, Any]]:
    return [
        _summary(db, item)
        for item in db.scalars(
            select(HouseholdList)
            .where(HouseholdList.household_id == auth.household.id)
            .order_by(HouseholdList.updated_at.desc())
        )
    ]


@router.post("", status_code=201)
def create_list(payload: ListInput, auth: Auth, db: Session = Depends(get_db)) -> dict[str, Any]:
    _writer(auth)
    count = db.scalar(
        select(func.count(HouseholdList.id)).where(HouseholdList.household_id == auth.household.id)
    )
    if (count or 0) >= MAX_LISTS:
        raise ApiError(422, "list_limit", "Delete an old list before adding another")
    item_list = HouseholdList(
        household_id=auth.household.id,
        name=payload.name,
        kind=payload.kind,
        icon=payload.icon,
        tint=payload.tint,
        body="",
        created_by=auth.user.id,
    )
    db.add(item_list)
    db.commit()
    return _detail(db, item_list)


@router.get("/{list_id}")
def list_detail(list_id: uuid.UUID, auth: Auth, db: Session = Depends(get_db)) -> dict[str, Any]:
    return _detail(db, _owned(db, auth, list_id))


@router.patch("/{list_id}")
def edit_list(
    list_id: uuid.UUID, payload: ListEdit, auth: Auth, db: Session = Depends(get_db)
) -> dict[str, Any]:
    _writer(auth)
    item_list = _owned(db, auth, list_id, lock=True)
    if item_list.version != payload.version:
        raise ApiError(
            409,
            "list_conflict",
            "Someone else changed this list; reload before saving",
            details={"current": _detail(db, item_list)},
        )
    if payload.name is not None:
        item_list.name = payload.name
    if payload.icon is not None:
        item_list.icon = payload.icon
    if payload.tint is not None:
        item_list.tint = payload.tint
    if payload.body is not None:
        if item_list.kind != "note":
            raise ApiError(422, "list_not_note", "Only notes have a body")
        item_list.body = payload.body
    item_list.version += 1
    item_list.updated_at = utcnow()
    db.commit()
    return _detail(db, item_list)


@router.delete("/{list_id}", status_code=204)
def delete_list(list_id: uuid.UUID, auth: Auth, db: Session = Depends(get_db)) -> None:
    _writer(auth)
    item_list = _owned(db, auth, list_id)
    for item in db.scalars(select(ListItem).where(ListItem.list_id == item_list.id)):
        db.delete(item)
    db.delete(item_list)
    db.commit()


@router.post("/{list_id}/items", status_code=201)
def add_item(
    list_id: uuid.UUID, payload: ItemInput, auth: Auth, db: Session = Depends(get_db)
) -> dict[str, Any]:
    _writer(auth)
    item_list = _owned(db, auth, list_id, lock=True)
    if item_list.kind != "checklist":
        raise ApiError(422, "list_not_checklist", "Notes do not have items")
    replay = db.scalar(
        select(ListItem).where(
            ListItem.list_id == item_list.id, ListItem.client_id == payload.client_id
        )
    )
    if replay is not None:
        return _item_json(replay, _names(db, {replay.added_by, replay.checked_by}))
    count, last = db.execute(
        select(func.count(ListItem.id), func.max(ListItem.position)).where(
            ListItem.list_id == item_list.id
        )
    ).one()
    if count >= MAX_ITEMS:
        raise ApiError(422, "list_item_limit", "Clear checked items before adding more")
    item = ListItem(
        list_id=item_list.id,
        client_id=payload.client_id,
        text=payload.text,
        quantity=payload.quantity,
        note=payload.note,
        position=(last or 0) + 1,
        added_by=auth.user.id,
    )
    db.add(item)
    item_list.updated_at = utcnow()
    try:
        db.flush()
    except IntegrityError as error:
        db.rollback()
        raise ApiError(409, "list_item_retry", "Item is being saved; retry") from error
    queue_item_added(db, item_list, item, auth.user)
    db.commit()
    return _item_json(item, _names(db, {item.added_by}))


@router.patch("/{list_id}/items/{item_id}")
def edit_item(
    list_id: uuid.UUID,
    item_id: uuid.UUID,
    payload: ItemEdit,
    auth: Auth,
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    _writer(auth)
    item_list = _owned(db, auth, list_id)
    item = _item(db, item_list, item_id)
    fields = payload.model_fields_set
    if "text" in fields and payload.text is not None:
        item.text = payload.text
    if "quantity" in fields:
        item.quantity = payload.quantity
    if "note" in fields:
        item.note = payload.note
    if payload.checked is not None and payload.checked != item.checked:
        item.checked = payload.checked
        item.checked_by = auth.user.id if payload.checked else None
        item.checked_at = utcnow() if payload.checked else None
    item_list.updated_at = utcnow()
    db.commit()
    return _item_json(item, _names(db, {item.added_by, item.checked_by}))


@router.delete("/{list_id}/items/{item_id}", status_code=204)
def delete_item(
    list_id: uuid.UUID, item_id: uuid.UUID, auth: Auth, db: Session = Depends(get_db)
) -> None:
    _writer(auth)
    item_list = _owned(db, auth, list_id)
    db.delete(_item(db, item_list, item_id))
    item_list.updated_at = utcnow()
    db.commit()


@router.post("/{list_id}/clear-checked")
def clear_checked(list_id: uuid.UUID, auth: Auth, db: Session = Depends(get_db)) -> dict[str, Any]:
    _writer(auth)
    item_list = _owned(db, auth, list_id)
    for item in db.scalars(
        select(ListItem).where(ListItem.list_id == item_list.id, ListItem.checked.is_(True))
    ):
        db.delete(item)
    item_list.updated_at = utcnow()
    db.commit()
    return _detail(db, item_list)
