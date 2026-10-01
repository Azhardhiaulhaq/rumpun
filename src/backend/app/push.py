"""Persist app notifications and deliver them through FCM HTTP v1."""

import hashlib
import uuid
from datetime import UTC, datetime, timedelta, tzinfo
from typing import Protocol
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import google.auth
import requests
from google.auth.transport.requests import Request
from sqlalchemy import exists, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, aliased

from app.models import (
    AccountKind,
    CandidateState,
    Category,
    FinancialAccount,
    Household,
    LedgerTransaction,
    Membership,
    NotificationOutbox,
    Posting,
    PushDevice,
    TransactionCandidate,
    TransactionStatus,
    User,
    utcnow,
)


class PushSender(Protocol):
    def send(self, token: str, title: str, body: str, data: dict[str, str], key: str) -> bool: ...


class FirebaseSender:
    def __init__(self, project_id: str) -> None:
        self.project_id = project_id
        self.credentials, _ = google.auth.default(
            scopes=["https://www.googleapis.com/auth/firebase.messaging"]
        )

    def send(self, token: str, title: str, body: str, data: dict[str, str], key: str) -> bool:
        if not self.credentials.valid:
            self.credentials.refresh(Request())  # type: ignore[no-untyped-call]
        response = requests.post(
            f"https://fcm.googleapis.com/v1/projects/{self.project_id}/messages:send",
            headers={"Authorization": f"Bearer {self.credentials.token}"},
            json={
                "message": {
                    "token": token,
                    "notification": {"title": title, "body": body},
                    "data": data,
                    "android": {"collapse_key": key[:64]},
                    "apns": {"headers": {"apns-collapse-id": key[:64]}},
                }
            },
            timeout=12,
        )
        if response.ok:
            return True
        try:
            details = response.json().get("error", {}).get("details", [])
            if any(
                item.get("errorCode") == "UNREGISTERED"
                for item in details
                if isinstance(item, dict)
            ):
                return False
        except ValueError:
            pass
        response.raise_for_status()
        return False


def _queue(
    db: Session,
    *,
    key: str,
    user_id: uuid.UUID,
    household_id: uuid.UUID,
    kind: str,
    title: str,
    body: str,
    data: dict[str, str],
) -> None:
    if db.scalar(select(NotificationOutbox.id).where(NotificationOutbox.event_key == key)):
        return
    try:
        with db.begin_nested():
            db.add(
                NotificationOutbox(
                    event_key=key,
                    user_id=user_id,
                    household_id=household_id,
                    kind=kind,
                    title=title,
                    body=body,
                    data_json=data,
                )
            )
            db.flush()
    except IntegrityError:
        pass


_REVIEW_KIND = "candidate_review"


def queue_candidate_review(
    db: Session, candidate: TransactionCandidate, user_id: uuid.UUID
) -> None:
    """Fold new review items into one undelivered notice per person and household.

    A lookback sync can create dozens of candidates at once, and one push each
    would flood the phone. While a notice is still pending, later candidates join
    it, so a person receives one notice per worker cycle rather than per email.
    """
    if candidate.state not in {CandidateState.PENDING, CandidateState.NEEDS_INPUT}:
        return
    candidate_id = str(candidate.id)
    pending = db.scalar(
        select(NotificationOutbox)
        .where(
            NotificationOutbox.user_id == user_id,
            NotificationOutbox.household_id == candidate.household_id,
            NotificationOutbox.kind == _REVIEW_KIND,
            NotificationOutbox.status == "pending",
        )
        .order_by(NotificationOutbox.created_at)
        .limit(1)
        .with_for_update()
    )
    if pending is not None:
        ids = _review_ids(pending)
        if candidate_id not in ids:
            ids.append(candidate_id)
        pending.data_json = _review_data(ids)
        pending.body = _review_body(len(ids))
        return
    _queue(
        db,
        key=f"candidate:{candidate.id}:{user_id}",
        user_id=user_id,
        household_id=candidate.household_id,
        kind=_REVIEW_KIND,
        title="Transaksi baru untuk ditinjau",
        body=_review_body(1),
        data=_review_data([candidate_id]),
    )


def _review_ids(event: NotificationOutbox) -> list[str]:
    ids = event.data_json.get("candidate_ids")
    if ids:
        return ids.split(",")
    single = event.data_json.get("candidate_id")
    return [single] if single else []


def _review_data(ids: list[str]) -> dict[str, str]:
    # FCM data values must be strings, so the IDs travel comma-separated.
    return {"kind": _REVIEW_KIND, "candidate_ids": ",".join(ids)}


def _review_body(count: int) -> str:
    if count == 1:
        return "Ada usulan dari email yang menunggu keputusanmu."
    return f"Ada {count} usulan dari email yang menunggu keputusanmu."


def queue_budget_alerts(
    db: Session, household: Household, category: Category, occurred_at: datetime
) -> None:
    if category.budget_atomic is None or category.budget_atomic <= 0:
        return
    try:
        zone: tzinfo = ZoneInfo(household.timezone)
    except ZoneInfoNotFoundError:
        zone = UTC
    local = occurred_at.replace(tzinfo=occurred_at.tzinfo or UTC).astimezone(zone)
    today = datetime.now(zone)
    if (local.year, local.month) != (today.year, today.month):
        return
    month_start = datetime(local.year, local.month, 1, tzinfo=zone).astimezone(UTC)
    next_month = (
        datetime(local.year + 1, 1, 1, tzinfo=zone)
        if local.month == 12
        else datetime(local.year, local.month + 1, 1, tzinfo=zone)
    ).astimezone(UTC)
    reversal = aliased(LedgerTransaction)
    reversed_entry = exists(
        select(reversal.id).where(
            reversal.reverses_transaction_id == Posting.transaction_id,
            reversal.status == TransactionStatus.POSTED,
        )
    )
    spent = (
        db.scalar(
            select(func.coalesce(func.sum(-Posting.amount_atomic), 0))
            .join(LedgerTransaction, LedgerTransaction.id == Posting.transaction_id)
            .join(FinancialAccount, FinancialAccount.id == Posting.account_id)
            .where(
                LedgerTransaction.household_id == household.id,
                LedgerTransaction.category_id == category.id,
                LedgerTransaction.transaction_type.in_(["expense", "refund"]),
                LedgerTransaction.status == TransactionStatus.POSTED,
                LedgerTransaction.occurred_at >= month_start,
                LedgerTransaction.occurred_at < next_month,
                FinancialAccount.kind != AccountKind.EQUITY,
                FinancialAccount.visibility == "household",
                Posting.currency == household.base_currency,
                ~reversed_entry,
            )
        )
        or 0
    )
    if spent < category.budget_atomic * 9 // 10:
        return
    level = "over" if spent >= category.budget_atomic else "near"
    title = "Anggaran terlampaui" if level == "over" else "Anggaran hampir habis"
    body = f"Periksa anggaran {category.name} bulan ini."
    user_ids = db.scalars(
        select(Membership.user_id)
        .join(User, User.id == Membership.user_id)
        .where(Membership.household_id == household.id, User.is_active.is_(True))
    ).all()
    for user_id in user_ids:
        _queue(
            db,
            key=f"budget:{category.id}:{local.year:04d}-{local.month:02d}:{level}:{user_id}",
            user_id=user_id,
            household_id=household.id,
            kind="budget_alert",
            title=title,
            body=body,
            data={"kind": "budget_alert", "category_id": str(category.id)},
        )


def dispatch_pending(db: Session, sender: PushSender, *, limit: int = 100) -> int:
    now = utcnow()
    pending = list(
        db.scalars(
            select(NotificationOutbox)
            .where(
                NotificationOutbox.status == "pending",
                NotificationOutbox.next_attempt_at <= now,
            )
            .order_by(NotificationOutbox.created_at)
            .limit(limit)
            .with_for_update(skip_locked=True)
        )
    )
    sent = 0
    for event in pending:
        if event.created_at.replace(tzinfo=UTC) < now - timedelta(days=3):
            event.status = "expired"
            continue
        member = db.scalar(
            select(Membership.id)
            .join(User, User.id == Membership.user_id)
            .where(
                Membership.user_id == event.user_id,
                Membership.household_id == event.household_id,
                User.is_active.is_(True),
            )
        )
        if member is None:
            event.status = "cancelled"
            continue
        if event.kind == _REVIEW_KIND:
            open_ids = _open_candidate_ids(db, _review_ids(event))
            if not open_ids:
                event.status = "cancelled"
                continue
            event.data_json = _review_data(open_ids)
            event.body = _review_body(len(open_ids))
        devices = db.scalars(
            select(PushDevice).where(
                PushDevice.user_id == event.user_id,
                PushDevice.household_id == event.household_id,
            )
        ).all()
        if not devices:
            event.next_attempt_at = now + timedelta(minutes=15)
            continue
        retry = False
        for device in devices:
            try:
                if not sender.send(
                    device.token, event.title, event.body, event.data_json, event.event_key
                ):
                    db.delete(device)
                else:
                    sent += 1
            except Exception:
                retry = True
        if retry:
            event.attempts += 1
            event.next_attempt_at = now + timedelta(minutes=min(60, 2 ** min(event.attempts, 6)))
        else:
            event.status = "sent"
            event.sent_at = now
    db.commit()
    return sent


def _open_candidate_ids(db: Session, ids: list[str]) -> list[str]:
    parsed = [uuid.UUID(value) for value in ids]
    if not parsed:
        return []
    still_open = set(
        db.scalars(
            select(TransactionCandidate.id).where(
                TransactionCandidate.id.in_(parsed),
                TransactionCandidate.state.in_(
                    [CandidateState.PENDING, CandidateState.NEEDS_INPUT]
                ),
            )
        )
    )
    return [str(value) for value in parsed if value in still_open]


def token_digest(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()
