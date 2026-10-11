"""Tell other household members when items are added to a shared list.

Adding groceries usually happens in bursts, so a notice waits a minute and
later additions by the same person to the same list fold into it.
"""

import uuid
from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.list_models import HouseholdList, ListItem, ListPreference
from app.models import Membership, NotificationOutbox, User, utcnow

LIST_KIND = "list_items"
FOLD_DELAY = timedelta(seconds=60)


def _ids(event: NotificationOutbox) -> list[str]:
    raw = event.data_json.get("item_ids", "")
    return [value for value in raw.split(",") if value]


def _body(actor: str, list_name: str, texts: list[str]) -> str:
    if len(texts) == 1:
        shown = texts[0]
    elif len(texts) == 2:
        shown = f"{texts[0]} dan {texts[1]}"
    else:
        shown = f"{texts[0]}, {texts[1]}, dan {len(texts) - 2} lainnya"
    return f"{actor} menambahkan {shown} ke {list_name}."[:240]


def wants_items(db: Session, household_id: uuid.UUID, user_id: uuid.UUID) -> bool:
    preference = db.scalar(
        select(ListPreference).where(
            ListPreference.household_id == household_id, ListPreference.user_id == user_id
        )
    )
    return preference is None or preference.items_added


def queue_item_added(db: Session, item_list: HouseholdList, item: ListItem, actor: User) -> None:
    recipients = db.scalars(
        select(Membership.user_id)
        .join(User, User.id == Membership.user_id)
        .where(
            Membership.household_id == item_list.household_id,
            Membership.user_id != actor.id,
            User.is_active.is_(True),
        )
    ).all()
    for user_id in recipients:
        if not wants_items(db, item_list.household_id, user_id):
            continue
        pending = next(
            (
                event
                for event in db.scalars(
                    select(NotificationOutbox)
                    .where(
                        NotificationOutbox.user_id == user_id,
                        NotificationOutbox.household_id == item_list.household_id,
                        NotificationOutbox.kind == LIST_KIND,
                        NotificationOutbox.status == "pending",
                    )
                    .with_for_update()
                )
                if event.data_json.get("list_id") == str(item_list.id)
                and event.data_json.get("actor_id") == str(actor.id)
            ),
            None,
        )
        if pending is not None:
            ids = _ids(pending)
            if str(item.id) not in ids:
                ids.append(str(item.id))
            pending.data_json = {**pending.data_json, "item_ids": ",".join(ids)}
            pending.next_attempt_at = utcnow() + FOLD_DELAY
            continue
        db.add(
            NotificationOutbox(
                event_key=f"list-item:{item.id}:{user_id}",
                user_id=user_id,
                household_id=item_list.household_id,
                kind=LIST_KIND,
                title=item_list.name[:160],
                body=_body(actor.display_name, item_list.name, [item.text]),
                data_json={
                    "kind": LIST_KIND,
                    "list_id": str(item_list.id),
                    "actor_id": str(actor.id),
                    "item_ids": str(item.id),
                },
                next_attempt_at=utcnow() + FOLD_DELAY,
            )
        )


def refresh_for_delivery(db: Session, event: NotificationOutbox) -> bool:
    """Rewrite the notice from current data; False means it is no longer worth sending."""
    if not wants_items(db, event.household_id, event.user_id):
        return False
    item_list = db.get(HouseholdList, uuid.UUID(event.data_json["list_id"]))
    if item_list is None or item_list.household_id != event.household_id:
        return False
    ids = [uuid.UUID(value) for value in _ids(event)]
    items = db.scalars(
        select(ListItem)
        .where(ListItem.id.in_(ids), ListItem.list_id == item_list.id, ListItem.checked.is_(False))
        .order_by(ListItem.position)
    ).all()
    if not items:
        return False
    actor = db.get(User, uuid.UUID(event.data_json["actor_id"]))
    event.title = item_list.name[:160]
    event.body = _body(
        actor.display_name if actor else "Anggota keluarga",
        item_list.name,
        [item.text for item in items],
    )
    event.data_json = {**event.data_json, "item_ids": ",".join(str(item.id) for item in items)}
    return True
