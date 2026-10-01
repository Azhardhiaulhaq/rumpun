import hashlib
from datetime import UTC, datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field
from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.database import get_db
from app.errors import ApiError
from app.gmail_integration import (
    GmailProvider,
    authorization_url,
    encrypt_refresh_token,
    new_oauth_values,
    require_gmail_settings,
    validate_grant,
)
from app.models import (
    GmailConnection,
    GmailMessage,
    GmailOAuthAttempt,
    GmailSyncJob,
    Membership,
    utcnow,
)
from app.security import AuthContext, get_auth_context

router = APIRouter(prefix="/gmail", tags=["gmail"])


class GmailConnectResponse(BaseModel):
    authorization_url: str


class GmailConnectionResponse(BaseModel):
    email: str
    status: str
    connected_at: datetime
    last_synced_at: datetime | None
    awaiting_jev_count: int
    classification_enabled: bool


class SyncRequest(BaseModel):
    days: int = Field(ge=1, le=365)


class SyncResponse(BaseModel):
    id: str
    status: str
    days: int
    discovered_count: int
    candidate_count: int
    unclassified_count: int
    error_code: str | None


def _sync_response(job: GmailSyncJob) -> SyncResponse:
    return SyncResponse(
        id=str(job.id),
        status=job.status,
        days=job.days,
        discovered_count=job.discovered_count,
        candidate_count=job.candidate_count,
        unclassified_count=job.unclassified_count,
        error_code=job.error_code,
    )


def _connection(db: Session, auth: AuthContext) -> GmailConnection | None:
    return db.scalar(
        select(GmailConnection).where(
            GmailConnection.user_id == auth.user.id,
            GmailConnection.household_id == auth.household.id,
        )
    )


@router.get("/connection", response_model=GmailConnectionResponse | None)
def get_connection(
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    settings: Annotated[Settings, Depends(get_settings)],
    db: Session = Depends(get_db),
) -> GmailConnectionResponse | None:
    connection = _connection(db, auth)
    if connection is None:
        return None
    pending = db.scalar(
        select(func.count(GmailMessage.id)).where(
            GmailMessage.connection_id == connection.id,
            GmailMessage.state == "awaiting_jev",
        )
    )
    return GmailConnectionResponse(
        email=connection.google_email,
        status=connection.status,
        connected_at=connection.connected_at,
        last_synced_at=connection.last_synced_at,
        awaiting_jev_count=pending or 0,
        classification_enabled=bool(settings.jev_api_key),
    )


@router.post("/sync", response_model=SyncResponse)
def request_sync(
    payload: SyncRequest,
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
) -> SyncResponse:
    connection = _connection(db, auth)
    if connection is None or connection.status != "active":
        raise ApiError(409, "gmail_not_connected", "Connect Gmail before syncing")
    active = db.scalar(
        select(GmailSyncJob)
        .where(
            GmailSyncJob.connection_id == connection.id,
            GmailSyncJob.status.in_(["pending", "running"]),
        )
        .order_by(GmailSyncJob.created_at.desc())
    )
    if active is not None:
        return _sync_response(active)
    job = GmailSyncJob(
        connection_id=connection.id,
        requested_by_user_id=auth.user.id,
        days=payload.days,
        status="pending",
        discovered_count=0,
        candidate_count=0,
        unclassified_count=0,
    )
    db.add(job)
    db.commit()
    return _sync_response(job)


@router.get("/sync/{job_id}", response_model=SyncResponse)
def get_sync(
    job_id: str,
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    db: Session = Depends(get_db),
) -> SyncResponse:
    import uuid

    try:
        parsed_id = uuid.UUID(job_id)
    except ValueError as exc:
        raise ApiError(404, "sync_not_found", "Sync was not found") from exc
    connection = _connection(db, auth)
    job = db.get(GmailSyncJob, parsed_id)
    if connection is None or job is None or job.connection_id != connection.id:
        raise ApiError(404, "sync_not_found", "Sync was not found")
    return _sync_response(job)


@router.post("/connect", response_model=GmailConnectResponse)
def start_connection(
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    settings: Annotated[Settings, Depends(get_settings)],
    db: Session = Depends(get_db),
) -> GmailConnectResponse:
    require_gmail_settings(settings)
    state, verifier, challenge = new_oauth_values()
    db.add(
        GmailOAuthAttempt(
            state_digest=hashlib.sha256(state.encode()).hexdigest(),
            user_id=auth.user.id,
            household_id=auth.household.id,
            code_verifier=verifier,
            expires_at=utcnow() + timedelta(minutes=10),
        )
    )
    db.commit()
    return GmailConnectResponse(
        authorization_url=authorization_url(
            settings, state=state, challenge=challenge, login_hint=auth.user.email
        )
    )


def get_gmail_provider() -> GmailProvider:
    return GmailProvider()


def _result_page(
    connected: bool, *, status_code: int = 200, reason: str | None = None
) -> HTMLResponse:
    destination = "rumpun://gmail-connected" if connected else "rumpun://gmail-cancelled"
    title = (
        "Gmail terhubung"
        if connected
        else "Pilih akun Google yang sama"
        if reason == "gmail_account_mismatch"
        else "Gmail belum terhubung"
    )
    explanation = (
        "Kembali ke Rumpun untuk melihat status koneksi."
        if connected
        else "Kembali ke Rumpun untuk mencoba lagi."
    )
    return HTMLResponse(
        "<!doctype html><html lang='id'><meta name='viewport' "
        "content='width=device-width,initial-scale=1'>"
        "<style>body{font:16px/1.5 sans-serif;background:#f7f1e7;color:#20251f;"
        "max-width:34rem;margin:12vh auto;padding:24px}a{display:inline-block;"
        "background:#234b38;color:white;padding:14px 20px;border-radius:14px;"
        "text-decoration:none;font-weight:bold}</style>"
        f"<h1>{title}</h1><p>{explanation}</p><a href='{destination}'>Buka Rumpun</a>"
        f"<script>window.location.replace('{destination}')</script></html>",
        status_code=status_code,
        headers={"Cache-Control": "no-store"},
    )


@router.get("/oauth/callback", response_class=HTMLResponse)
def oauth_callback(
    state: str,
    code: str | None = None,
    error: str | None = None,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
    provider: GmailProvider = Depends(get_gmail_provider),
) -> HTMLResponse:
    require_gmail_settings(settings)
    if len(state) > 256:
        raise ApiError(400, "gmail_state_invalid", "Gmail connection expired; try again")
    digest = hashlib.sha256(state.encode()).hexdigest()
    attempt = db.scalar(
        select(GmailOAuthAttempt).where(GmailOAuthAttempt.state_digest == digest).with_for_update()
    )
    if attempt is None or attempt.expires_at.replace(tzinfo=UTC) < utcnow():
        raise ApiError(400, "gmail_state_invalid", "Gmail connection expired; try again")
    user_id, household_id, verifier = attempt.user_id, attempt.household_id, attempt.code_verifier
    db.delete(attempt)
    db.commit()
    if error or not code:
        return _result_page(False)
    from app.models import User

    user = db.get(User, user_id)
    if user is None or not user.is_active:
        raise ApiError(403, "gmail_user_missing", "Rumpun account is unavailable")
    if (
        db.scalar(
            select(Membership.id).where(
                Membership.user_id == user_id, Membership.household_id == household_id
            )
        )
        is None
    ):
        return _result_page(False, status_code=403)
    try:
        tokens = provider.exchange_code(code, verifier, settings)
        refresh_token, access_token, subject = validate_grant(
            tokens,
            settings,
            provider,
            expected_subject=user.google_subject,
            expected_email=user.email,
        )
        profile = provider.get("profile", access_token)
    except ApiError as exc:
        return _result_page(False, status_code=exc.status_code, reason=exc.code)
    history_id = str(profile["historyId"])
    google_email = str(profile.get("emailAddress", user.email))
    connection = db.scalar(
        select(GmailConnection)
        .where(GmailConnection.user_id == user_id, GmailConnection.household_id == household_id)
        .with_for_update()
    )
    if connection is None:
        connection = GmailConnection(
            user_id=user_id,
            household_id=household_id,
            google_subject=subject,
            google_email=google_email,
            refresh_token_ciphertext=encrypt_refresh_token(refresh_token, settings),
            history_id=history_id,
            status="active",
            connected_at=utcnow(),
        )
        db.add(connection)
    else:
        if connection.google_subject != subject:
            raise ApiError(
                409, "gmail_account_mismatch", "This connection belongs to another Google account"
            )
        connection.google_email = google_email
        connection.refresh_token_ciphertext = encrypt_refresh_token(refresh_token, settings)
        connection.status = "active"
    db.commit()
    return _result_page(True)


@router.delete("/connection", status_code=204)
def disconnect(
    auth: Annotated[AuthContext, Depends(get_auth_context)],
    settings: Annotated[Settings, Depends(get_settings)],
    db: Session = Depends(get_db),
    provider: GmailProvider = Depends(get_gmail_provider),
) -> None:
    connection = _connection(db, auth)
    if connection is None:
        return
    from app.gmail_integration import decrypt_refresh_token

    token = decrypt_refresh_token(connection.refresh_token_ciphertext, settings)
    db.execute(delete(GmailMessage).where(GmailMessage.connection_id == connection.id))
    db.delete(connection)
    db.commit()
    provider.revoke(token)
