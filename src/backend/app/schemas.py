import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.models import CandidateState, MembershipRole


class ApiModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class ErrorBody(ApiModel):
    code: str
    message: str
    request_id: str | None = None
    details: dict[str, object] | list[object] | None = None


class ErrorResponse(ApiModel):
    error: ErrorBody


class RegisterRequest(ApiModel):
    email: EmailStr
    password: str = Field(min_length=10, max_length=256)
    display_name: str = Field(min_length=1, max_length=120)
    household_name: str | None = Field(default=None, min_length=1, max_length=160)


class LoginRequest(ApiModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=256)


class GoogleLoginRequest(ApiModel):
    id_token: str = Field(min_length=1, max_length=8192)


class RefreshRequest(ApiModel):
    refresh_token: str = Field(min_length=20, max_length=1024)


class LogoutRequest(RefreshRequest):
    pass


class HouseholdContext(ApiModel):
    id: uuid.UUID
    name: str
    role: MembershipRole
    base_currency: str


class UserResponse(ApiModel):
    id: uuid.UUID
    email: EmailStr
    display_name: str


class TokenResponse(ApiModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    user: UserResponse
    household: HouseholdContext


class AccountBalance(ApiModel):
    account_id: uuid.UUID
    name: str
    kind: str
    currency: str
    balance_atomic: int


class RecentTransaction(ApiModel):
    id: uuid.UUID
    transaction_type: str
    description: str
    occurred_at: datetime
    amount_atomic: int
    currency: str


class DashboardResponse(ApiModel):
    household: HouseholdContext
    totals_by_currency: dict[str, int]
    accounts: list[AccountBalance]
    recent_transactions: list[RecentTransaction]


class CandidateProposed(ApiModel):
    account_id: uuid.UUID | None
    amount_atomic: int | None
    currency: str
    description: str | None
    occurred_at: datetime | None


class CandidateSummary(ApiModel):
    id: uuid.UUID
    state: CandidateState
    version: int
    confidence_bps: int
    proposed: CandidateProposed
    created_at: datetime


class CandidateSourceResponse(ApiModel):
    provider: str
    provider_message_id: str
    sender_domain: str | None
    received_at: datetime
    parser_version: str
    metadata: dict[str, object]


class CandidateDetail(CandidateSummary):
    source: CandidateSourceResponse
    warnings: list[object]
    evidence: list[object]
    ledger_transaction_id: uuid.UUID | None


class CandidateList(ApiModel):
    items: list[CandidateSummary]
    next_cursor: str | None


class CandidateEditRequest(ApiModel):
    version: int = Field(ge=1)
    account_id: uuid.UUID | None = None
    amount_atomic: int | None = Field(default=None, gt=0)
    currency: str | None = Field(default=None, min_length=3, max_length=3)
    description: str | None = Field(default=None, min_length=1, max_length=240)
    occurred_at: datetime | None = None


class CandidateActionRequest(ApiModel):
    version: int = Field(ge=1)


class ConfirmedCandidateResponse(ApiModel):
    candidate_id: uuid.UUID
    candidate_state: CandidateState
    transaction_id: uuid.UUID
    replayed: bool = False
