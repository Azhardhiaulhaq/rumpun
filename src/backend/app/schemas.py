import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator, model_validator

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
    minor_unit: int = 2
    unit: str | None = None
    quantity: Decimal | None = None
    valued_at: datetime | None = None


class RecentTransaction(ApiModel):
    id: uuid.UUID
    transaction_type: str
    description: str
    occurred_at: datetime
    amount_atomic: int
    currency: str
    direction: str = "in"
    minor_unit: int = 2
    destination_amount_atomic: int | None = None
    destination_currency: str | None = None
    destination_minor_unit: int | None = None


class DashboardResponse(ApiModel):
    household: HouseholdContext
    totals_by_currency: dict[str, int]
    accounts: list[AccountBalance]
    recent_transactions: list[RecentTransaction]


class TrendBucket(ApiModel):
    """One period on the dashboard charts.

    `net_worth_atomic` is the closing balance at the end of the period, so a
    run of buckets reads as a line. `spent_atomic` and `received_atomic` are
    flows within the period, so they read as bars. Mixing the two on one axis
    would compare a stock against a flow.
    """

    start: date
    end: date
    label: str
    spent_atomic: int
    received_atomic: int
    net_worth_atomic: int
    # False while the period is still running, so the client can mark the last
    # bar as incomplete instead of showing it as a real drop.
    complete: bool


class TrendsResponse(ApiModel):
    currency: str
    granularity: str
    buckets: list[TrendBucket]
    # Absent until two complete periods exist; a change needs something to
    # change from.
    change_bps: int | None = None
    spend_change_bps: int | None = None


class CandidateProposed(ApiModel):
    account_id: uuid.UUID | None
    amount_atomic: int | None
    currency: str
    description: str | None
    occurred_at: datetime | None
    transaction_type: str | None = None
    category_id: uuid.UUID | None = None
    destination_account_id: uuid.UUID | None = None


class CandidateSummary(ApiModel):
    id: uuid.UUID
    state: CandidateState
    version: int
    confidence_bps: int
    proposed: CandidateProposed
    created_at: datetime
    recipient_name: str | None = None
    recipient_account: str | None = None
    # What the parser read from the email: "expense", "income", or "transfer".
    # Only expenses can be confirmed today, so the app needs it on the card.
    direction: str | None = None
    # The bank or wallet that sent the email, used to suggest the paying account.
    issuer: str | None = None
    # Proposed fields that Jev filled in rather than the email itself, so the
    # app can mark them as suggestions to check.
    suggested_fields: list[str] = Field(default_factory=list)


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
    transaction_type: Literal["expense", "income", "transfer"] | None = None
    category_id: uuid.UUID | None = None
    destination_account_id: uuid.UUID | None = None


class CandidateActionRequest(ApiModel):
    version: int = Field(ge=1)


class CandidateConfirmRequest(ApiModel):
    version: int = Field(ge=1)
    # Email rarely says which of the household's accounts paid, so the person
    # confirming names it here instead of in a separate edit round trip.
    account_id: uuid.UUID | None = None
    category_id: uuid.UUID | None = None
    destination_account_id: uuid.UUID | None = None


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
    minor_unit: int
    unit: str | None = None


class AccountCreateRequest(ApiModel):
    name: str = Field(min_length=1, max_length=160)
    kind: AccountKind
    currency: str | None = Field(default=None, min_length=3, max_length=12)
    minor_unit: int | None = Field(default=None, ge=0, le=8)
    unit: str | None = Field(default=None, min_length=1, max_length=40)
    visibility: str = "household"

    @field_validator("name")
    @classmethod
    def nonblank_name(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("name must not be blank")
        return value

    @field_validator("visibility")
    @classmethod
    def known_visibility(cls, value: str) -> str:
        if value not in {"household", "restricted"}:
            raise ValueError("visibility must be household or restricted")
        return value

    @field_validator("unit")
    @classmethod
    def nonblank_unit(cls, value: str | None) -> str | None:
        if value is not None and not value.strip():
            raise ValueError("unit must not be blank")
        return value


class CategoryResponse(ApiModel):
    id: uuid.UUID
    name: str
    category_type: str
    budget_atomic: int | None = None


class CategoryCreateRequest(ApiModel):
    name: str = Field(min_length=1, max_length=100)
    category_type: str
    budget_atomic: int | None = Field(default=None, gt=0)

    @field_validator("name")
    @classmethod
    def nonblank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("Category name cannot be blank")
        return value.strip()

    @model_validator(mode="after")
    def valid_type(self) -> "CategoryCreateRequest":
        if self.category_type not in {"expense", "income"}:
            raise ValueError("Category type must be expense or income")
        if self.category_type == "income" and self.budget_atomic is not None:
            raise ValueError("Only expense categories can have budgets")
        return self


class CategoryBudgetRequest(ApiModel):
    budget_atomic: int | None = Field(gt=0)


class CategorySpending(CategoryResponse):
    spent_atomic: int


class CategorySpendingResponse(ApiModel):
    month: str
    currency: str
    minor_unit: int
    items: list[CategorySpending]


class TransactionResponse(ApiModel):
    id: uuid.UUID
    transaction_type: str
    status: TransactionStatus
    description: str
    occurred_at: datetime
    amount_atomic: int
    currency: str
    direction: str = "in"
    minor_unit: int = 2
    account_id: uuid.UUID | None = None
    destination_account_id: uuid.UUID | None = None
    destination_amount_atomic: int | None = None
    destination_currency: str | None = None
    destination_minor_unit: int | None = None
    reverses_transaction_id: uuid.UUID | None = None
    category_id: uuid.UUID | None = None
    created_at: datetime


class TransactionList(ApiModel):
    items: list[TransactionResponse]
    next_cursor: str | None = None


class BalanceCorrectionRequest(ApiModel):
    balance_atomic: int
    description: str = Field(default="Koreksi saldo", min_length=1, max_length=240)


class TransactionReverseRequest(ApiModel):
    reason: str = Field(min_length=1, max_length=240)

    @field_validator("reason")
    @classmethod
    def nonblank_reason(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("reason must not be blank")
        return value


class TransactionCreateRequest(ApiModel):
    account_id: uuid.UUID
    category_id: uuid.UUID | None = None
    transaction_type: str
    direction: str | None = None
    # Amounts are unsigned; the type carries the direction. A negative amount
    # would let an "income" quietly reduce a balance.
    amount_atomic: int = Field(gt=0)
    currency: str | None = Field(default=None, min_length=3, max_length=12)
    description: str = Field(min_length=1, max_length=240)
    occurred_at: datetime | None = None

    @field_validator("transaction_type")
    @classmethod
    def known_type(cls, value: str) -> str:
        if value not in {"income", "expense", "refund", "opening_balance", "adjustment"}:
            raise ValueError("unknown transaction_type")
        return value

    @model_validator(mode="after")
    def valid_direction(self) -> "TransactionCreateRequest":
        if self.direction not in {None, "in", "out"}:
            raise ValueError("direction must be in or out")
        if self.transaction_type == "adjustment" and self.direction is None:
            raise ValueError("adjustment needs a direction")
        if self.transaction_type == "income" and self.direction == "out":
            raise ValueError("income must increase an account")
        if self.transaction_type == "expense" and self.direction == "in":
            raise ValueError("expense must decrease an account")
        if self.transaction_type == "refund" and self.direction == "out":
            raise ValueError("refund must increase an account")
        return self

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
    destination_amount_atomic: int | None = Field(default=None, gt=0)
    description: str = Field(min_length=1, max_length=240)
    occurred_at: datetime | None = None

    @field_validator("description")
    @classmethod
    def described(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("description must not be blank")
        return value


class ValuationCreateRequest(ApiModel):
    value_atomic: int = Field(ge=0)
    quantity: Decimal | None = Field(default=None, ge=0, max_digits=38, decimal_places=18)
    effective_at: datetime | None = None
    source: str = Field(default="manual", min_length=1, max_length=120)

    @field_validator("source")
    @classmethod
    def nonblank_source(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("source must not be blank")
        return value


class ValuationResponse(ApiModel):
    id: uuid.UUID
    account_id: uuid.UUID
    value_atomic: int
    currency: str
    minor_unit: int
    quantity: Decimal | None
    unit: str | None
    effective_at: datetime
    source: str
    created_at: datetime


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
