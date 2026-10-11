from typing import Any

import pytest

from app.config import Settings
from app.errors import ApiError
from app.security import StandardGoogleTokenVerifier


@pytest.mark.parametrize("token_audience", ["android-web", "ios-web"])
def test_google_verifier_accepts_both_mobile_server_audiences(
    monkeypatch: pytest.MonkeyPatch, token_audience: str
) -> None:
    settings = Settings(
        _env_file=None,
        jwt_secret="test-secret-with-more-than-32-characters",
        google_client_id="android-web",
        google_ios_client_id="ios-web",
    )

    def verify_token(token: str, request: Any, audience: str | list[str]) -> dict[str, Any]:
        assert token == "signed-token"
        assert audience == ["android-web", "ios-web"]
        return {
            "iss": "https://accounts.google.com",
            "aud": token_audience,
            "email_verified": True,
            "sub": "person-id",
            "email": "person@example.com",
        }

    monkeypatch.setattr("app.security.id_token.verify_oauth2_token", verify_token)
    assert StandardGoogleTokenVerifier(settings).verify("signed-token")["aud"] == token_audience


def test_google_verifier_rejects_other_audience(monkeypatch: pytest.MonkeyPatch) -> None:
    settings = Settings(
        _env_file=None,
        jwt_secret="test-secret-with-more-than-32-characters",
        google_client_id="android-web",
        google_ios_client_id="ios-web",
    )
    monkeypatch.setattr(
        "app.security.id_token.verify_oauth2_token",
        lambda token, request, audience: {
            "iss": "https://accounts.google.com",
            "aud": "unknown-web",
            "email_verified": True,
            "sub": "person-id",
            "email": "person@example.com",
        },
    )

    with pytest.raises(ApiError) as error:
        StandardGoogleTokenVerifier(settings).verify("signed-token")
    assert error.value.code == "invalid_google_audience"
