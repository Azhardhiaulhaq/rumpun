"""Gmail authorization and message discovery for Rumpun."""

import base64
import hashlib
import secrets
from contextlib import suppress
from datetime import UTC, datetime, timedelta
from typing import Any, cast
from urllib.parse import urlencode

import requests
from cryptography.fernet import Fernet, InvalidToken
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import Settings
from app.errors import ApiError
from app.models import GmailConnection, GmailMessage, Membership, User
from app.security import normalize_email

GMAIL_SCOPE = "https://www.googleapis.com/auth/gmail.readonly"
AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"
GMAIL_API = "https://gmail.googleapis.com/gmail/v1/users/me"


def require_gmail_settings(settings: Settings) -> None:
    if not all(
        (
            settings.gmail_oauth_client_id,
            settings.gmail_oauth_client_secret,
            settings.gmail_oauth_redirect_uri,
            settings.gmail_token_key,
        )
    ):
        raise ApiError(503, "gmail_not_configured", "Gmail connection is not configured")
    try:
        Fernet(settings.gmail_token_key.encode())  # type: ignore[union-attr]
    except (ValueError, TypeError) as exc:
        raise ApiError(503, "gmail_not_configured", "Gmail token encryption is invalid") from exc


def encrypt_refresh_token(token: str, settings: Settings) -> str:
    require_gmail_settings(settings)
    key = cast(str, settings.gmail_token_key)
    return Fernet(key.encode()).encrypt(token.encode()).decode()


def decrypt_refresh_token(ciphertext: str, settings: Settings) -> str:
    require_gmail_settings(settings)
    key = cast(str, settings.gmail_token_key)
    try:
        return Fernet(key.encode()).decrypt(ciphertext.encode()).decode()
    except InvalidToken as exc:
        raise ApiError(503, "gmail_token_unreadable", "Gmail token cannot be read") from exc


def new_oauth_values() -> tuple[str, str, str]:
    state = secrets.token_urlsafe(32)
    verifier = secrets.token_urlsafe(64)
    challenge = (
        base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    )
    return state, verifier, challenge


def authorization_url(settings: Settings, *, state: str, challenge: str, login_hint: str) -> str:
    require_gmail_settings(settings)
    query = urlencode(
        {
            "client_id": settings.gmail_oauth_client_id,
            "redirect_uri": settings.gmail_oauth_redirect_uri,
            "response_type": "code",
            "scope": f"openid email {GMAIL_SCOPE}",
            "access_type": "offline",
            "prompt": "consent",
            "state": state,
            "code_challenge": challenge,
            "code_challenge_method": "S256",
            "login_hint": login_hint,
        }
    )
    return f"{AUTH_URL}?{query}"


class GmailProvider:
    def _post_token(self, payload: dict[str, str]) -> dict[str, Any]:
        try:
            response = requests.post(TOKEN_URL, data=payload, timeout=15)
        except requests.RequestException as exc:
            raise ApiError(
                502, "google_unavailable", "Google authorization is unavailable"
            ) from exc
        if not response.ok:
            error = response.json().get("error") if response.status_code == 400 else None
            code = (
                "gmail_reauthorization_required"
                if error == "invalid_grant"
                else "google_unavailable"
            )
            raise ApiError(502, code, "Google did not issue a Gmail token")
        return cast(dict[str, Any], response.json())

    def exchange_code(self, code: str, verifier: str, settings: Settings) -> dict[str, Any]:
        require_gmail_settings(settings)
        return self._post_token(
            {
                "code": code,
                "client_id": cast(str, settings.gmail_oauth_client_id),
                "client_secret": cast(str, settings.gmail_oauth_client_secret),
                "redirect_uri": cast(str, settings.gmail_oauth_redirect_uri),
                "grant_type": "authorization_code",
                "code_verifier": verifier,
            }
        )

    def refresh(self, refresh_token: str, settings: Settings) -> str:
        result = self._post_token(
            {
                "client_id": cast(str, settings.gmail_oauth_client_id),
                "client_secret": cast(str, settings.gmail_oauth_client_secret),
                "refresh_token": refresh_token,
                "grant_type": "refresh_token",
            }
        )
        access_token = result.get("access_token")
        if not isinstance(access_token, str):
            raise ApiError(502, "google_unavailable", "Google did not issue an access token")
        return access_token

    def verify_identity(self, token: str, settings: Settings) -> dict[str, Any]:
        try:
            claims = id_token.verify_oauth2_token(  # type: ignore[no-untyped-call]
                token,
                google_requests.Request(),
                audience=settings.gmail_oauth_client_id,
            )
        except ValueError as exc:
            raise ApiError(401, "invalid_google_token", "Google identity is invalid") from exc
        if (
            claims.get("iss") not in settings.google_issuers
            or not claims.get("email_verified")
            or not claims.get("sub")
            or not claims.get("email")
        ):
            raise ApiError(401, "invalid_google_token", "Google identity is invalid")
        return cast(dict[str, Any], claims)

    def get(
        self, path: str, access_token: str, *, params: dict[str, str] | None = None
    ) -> dict[str, Any]:
        try:
            response = requests.get(
                f"{GMAIL_API}/{path}",
                headers={"Authorization": f"Bearer {access_token}"},
                params=params,
                timeout=20,
            )
        except requests.RequestException as exc:
            raise ApiError(502, "gmail_unavailable", "Gmail is unavailable") from exc
        if response.status_code == 404:
            if path == "history":
                raise HistoryExpired
            if path.startswith("messages/"):
                raise GmailMessageGone
        if not response.ok:
            raise ApiError(502, "gmail_unavailable", "Gmail request failed")
        return cast(dict[str, Any], response.json())

    def revoke(self, refresh_token: str) -> None:
        with suppress(requests.RequestException):
            requests.post(
                "https://oauth2.googleapis.com/revoke",
                data={"token": refresh_token},
                timeout=10,
            )


class HistoryExpired(Exception):
    pass


class GmailMessageGone(Exception):
    pass


def validate_grant(
    tokens: dict[str, Any],
    settings: Settings,
    provider: GmailProvider,
    *,
    expected_subject: str | None,
    expected_email: str,
) -> tuple[str, str, str]:
    scopes = set(str(tokens.get("scope", "")).split())
    refresh_token = tokens.get("refresh_token")
    identity_token = tokens.get("id_token")
    access_token = tokens.get("access_token")
    if GMAIL_SCOPE not in scopes or not all(
        isinstance(value, str) for value in (refresh_token, identity_token, access_token)
    ):
        raise ApiError(400, "gmail_grant_incomplete", "Gmail permission was not fully granted")
    claims = provider.verify_identity(cast(str, identity_token), settings)
    if expected_subject and claims["sub"] != expected_subject:
        raise ApiError(403, "gmail_account_mismatch", "Choose the account used to sign in")
    if not expected_subject and normalize_email(str(claims["email"])) != normalize_email(
        expected_email
    ):
        raise ApiError(403, "gmail_account_mismatch", "Choose the account used to sign in")
    return cast(str, refresh_token), cast(str, access_token), str(claims["sub"])


def _new_message_ids(
    provider: GmailProvider, connection: GmailConnection, access_token: str
) -> tuple[set[str], str]:
    discovered: set[str] = set()
    page_token: str | None = None
    latest_history_id = connection.history_id
    try:
        while True:
            params = {"startHistoryId": connection.history_id, "historyTypes": "messageAdded"}
            if page_token:
                params["pageToken"] = page_token
            result = provider.get("history", access_token, params=params)
            latest_history_id = str(result.get("historyId", latest_history_id))
            for item in result.get("history", []):
                for added in item.get("messagesAdded", []):
                    message = added.get("message", {})
                    labels = set(message.get("labelIds", []))
                    if not {"SENT", "DRAFT", "SPAM", "TRASH"} & labels and message.get("id"):
                        discovered.add(str(message["id"]))
            page_token = result.get("nextPageToken")
            if not page_token:
                return discovered, latest_history_id
    except HistoryExpired:
        discovered.clear()
        page_token = None
        while True:
            since = int(connection.connected_at.timestamp()) - 300
            params = {
                "maxResults": "500",
                "q": f"after:{since} -in:sent -in:drafts",
            }
            if page_token:
                params["pageToken"] = page_token
            result = provider.get("messages", access_token, params=params)
            discovered.update(str(item["id"]) for item in result.get("messages", []))
            page_token = result.get("nextPageToken")
            if not page_token:
                profile = provider.get("profile", access_token)
                return discovered, str(profile["historyId"])


def sync_connection(
    db: Session,
    connection_id: Any,
    settings: Settings,
    provider: GmailProvider,
    *,
    lookback_days: int | None = None,
) -> int:
    connection = db.scalar(
        select(GmailConnection).where(GmailConnection.id == connection_id).with_for_update()
    )
    if connection is None or connection.status != "active":
        return 0
    membership = db.scalar(
        select(Membership.id).where(
            Membership.user_id == connection.user_id,
            Membership.household_id == connection.household_id,
        )
    )
    user_active = db.scalar(select(User.is_active).where(User.id == connection.user_id))
    if membership is None or not user_active:
        token = decrypt_refresh_token(connection.refresh_token_ciphertext, settings)
        db.query(GmailMessage).filter(GmailMessage.connection_id == connection.id).delete()
        db.delete(connection)
        db.commit()
        provider.revoke(token)
        return 0
    try:
        access_token = provider.refresh(
            decrypt_refresh_token(connection.refresh_token_ciphertext, settings), settings
        )
    except ApiError as exc:
        if exc.code == "gmail_reauthorization_required":
            connection.status = "reauthorization_required"
            db.commit()
        raise
    if lookback_days is None:
        ids, latest_history_id = _new_message_ids(provider, connection, access_token)
    else:
        ids = set()
        page_token = None
        since = int((datetime.now(UTC) - timedelta(days=lookback_days)).timestamp())
        while True:
            params = {"maxResults": "500", "q": f"after:{since} -in:sent -in:drafts"}
            if page_token:
                params["pageToken"] = page_token
            result = provider.get("messages", access_token, params=params)
            ids.update(str(item["id"]) for item in result.get("messages", []))
            page_token = result.get("nextPageToken")
            if not page_token:
                break
        latest_history_id = connection.history_id
    if ids:
        existing = set(
            db.scalars(
                select(GmailMessage.gmail_message_id).where(
                    GmailMessage.connection_id == connection.id,
                    GmailMessage.gmail_message_id.in_(ids),
                )
            )
        )
        for message_id in ids - existing:
            db.add(GmailMessage(connection_id=connection.id, gmail_message_id=message_id))
    if lookback_days is None:
        connection.history_id = latest_history_id
    connection.last_synced_at = datetime.now(UTC)
    db.commit()
    return len(ids - existing) if ids else 0
