import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

from app.models import (
    AccountKind,
    CandidateState,
    InboxAddressState,
    InviteState,
    MembershipRole,
    TransactionStatus,
)


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
    # False until the owner has named the household themselves. Clients use this
    # to decide whether to ask for the household details after sign-in.
    is_named: bool = True


class HouseholdCreateRequest(ApiModel):
    name: str = Field(min_length=1, max_length=160)
    base_currency: str = Field(default="IDR", min_length=3, max_length=3)

    @field_validator("name")
    @classmethod
    def reject_blank_name(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("Household name cannot be blank")
        return value


class HouseholdUpdateRequest(ApiModel):
    name: str = Field(min_length=1, max_length=160)
    base_currency: str = Field(default="IDR", min_length=3, max_length=3)
    timezone: str = Field(default="Asia/Jakarta", min_length=1, max_length=64)

    @field_validator("name")
    @classmethod
    def reject_blank_name(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("Household name cannot be blank")
        return value


class UserResponse(ApiModel):
    id: uuid.UUID
    email: EmailStr
    display_name: str


class InviteSummary(ApiModel):
    id: uuid.UUID
    household_name: str
    role: MembershipRole
    invited_by_name: str
    created_at: datetime


class HouseholdMember(ApiModel):
    user_id: uuid.UUID
    display_name: str
    email: EmailStr
    role: MembershipRole
    is_you: bool = False


class PendingInvite(ApiModel):
    id: uuid.UUID
    email: EmailStr
    role: MembershipRole
    created_at: datetime


class HouseholdPeople(ApiModel):
    members: list[HouseholdMember]
    invites: list[PendingInvite]


class InviteCreateRequest(ApiModel):
    email: EmailStr
    role: MembershipRole = MembershipRole.MEMBER

    @field_validator("role")
    @classmethod
    def reject_second_owner(cls, value: MembershipRole) -> MembershipRole:
        # A household has exactly one owner, the person who created it.
        if value == MembershipRole.OWNER:
            raise ValueError("A household can only have one owner")
        return value


class InviteResponse(ApiModel):
    id: uuid.UUID
    email: EmailStr
    role: MembershipRole
    state: InviteState
    created_at: datetime


class TokenResponse(ApiModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    user: UserResponse
    # None while a signed-in user has no household yet: they are choosing
    # between creating one and accepting an invite.
    household: HouseholdContext | None = None
    # True only on the request that created the account, so the client can route
    # a first-time user into onboarding instead of the dashboard.
    is_new_user: bool = False
    # Invites waiting for this user's email, so the client can offer them
    # immediately after sign-in.
    pending_invites: list[InviteSummary] = Field(default_factory=list)


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


class AccountResponse(ApiModel):
    id: uuid.UUID
    name: str
    kind: AccountKind
    currency: str
    visibility: str


class AccountCreateRequest(ApiModel):
    name: str = Field(min_length=1, max_length=160)
    kind: AccountKind
    currency: str | None = Field(default=None, min_length=3, max_length=3)


class TransactionResponse(ApiModel):
    id: uuid.UUID
    transaction_type: str
    status: TransactionStatus
    description: str
    occurred_at: datetime
    amount_atomic: int
    currency: str
    created_at: datetime


class TransactionList(ApiModel):
    items: list[TransactionResponse]


class TransactionCreateRequest(ApiModel):
    account_id: uuid.UUID
    transaction_type: str
    # Amounts are unsigned; the type carries the direction. A negative amount
    # would let an "income" quietly reduce a balance.
    amount_atomic: int = Field(gt=0)
    currency: str | None = Field(default=None, min_length=3, max_length=3)
    description: str = Field(min_length=1, max_length=240)
    occurred_at: datetime | None = None

    @field_validator("transaction_type")
    @classmethod
    def known_type(cls, value: str) -> str:
        if value not in {"income", "expense"}:
            raise ValueError("transaction_type must be income or expense")
        return value

    @field_validator("description")
    @classmethod
    def described(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("description must not be blank")
        return value


class TransferCreateRequest(ApiModel):
    from_account_id: uuid.UUID
    to_account_id: uuid.UUID
    amount_atomic: int = Field(gt=0)
    description: str = Field(min_length=1, max_length=240)
    occurred_at: datetime | None = None

    @field_validator("description")
    @classmethod
    def described(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("description must not be blank")
        return value


class InboxAddressResponse(ApiModel):
    address: str
    state: InboxAddressState
    # Shown only while setup is unfinished, so the owner can paste Gmail's
    # confirmation code without searching their mailbox.
    verification_code: str | None
    message_count: int
    last_message_at: datetime | None
    created_at: datetime


class InboundEmailRequest(ApiModel):
    """One forwarded message, as posted by the mail provider."""

    to: str = Field(max_length=320)
    sender: str = Field(max_length=320)
    subject: str = Field(default="", max_length=998)
    text: str | None = None
    html: str | None = None
    message_id: str | None = Field(default=None, max_length=255)
    received_at: datetime | None = None


class InboundEmailResult(ApiModel):
    status: str
    reason: str | None = None
    candidate_id: uuid.UUID | None = None
    confidence_bps: int | None = None
