from functools import lru_cache

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_prefix="RUMPUN_", extra="ignore")

    environment: str = "development"
    database_url: str = "postgresql+psycopg://rumpun:rumpun@localhost:5432/rumpun"
    jwt_secret: str = Field(min_length=32)
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 15
    refresh_token_days: int = 30
    google_client_id: str | None = None
    google_issuers: tuple[str, ...] = ("accounts.google.com", "https://accounts.google.com")
    rate_limit_attempts: int = 10
    rate_limit_window_seconds: int = 60

    # Inbound email forwarding. The domain is what household addresses are
    # built on; the secret authenticates the mail provider's webhook, because
    # anything that can call it can create candidates.
    # Deliberately unroutable: an install that forgets to set this should
    # produce an address that cannot receive mail, not one pointing at a
    # domain somebody else owns.
    inbound_email_domain: str = "invalid.example"
    inbound_webhook_secret: str | None = None
    # Bodies are kept only long enough for a person to review the candidate.
    inbound_retain_body_days: int = 30

    @field_validator("jwt_secret")
    @classmethod
    def reject_default_secret(cls, value: str) -> str:
        if value in {"change-me", "secret", "development-secret"}:
            raise ValueError("RUMPUN_JWT_SECRET must not use a known default")
        return value


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
