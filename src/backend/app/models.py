import enum
import uuid
from datetime import UTC, datetime

from sqlalchemy import (
    JSON,
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    Enum,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    Uuid,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


def utcnow() -> datetime:
    return datetime.now(UTC)


class MembershipRole(enum.StrEnum):
    OWNER = "owner"
    ADMIN = "admin"
    MEMBER = "member"
    VIEWER = "viewer"
    CHILD = "child"


class InviteState(enum.StrEnum):
    PENDING = "pending"
    ACCEPTED = "accepted"
    DECLINED = "declined"
    REVOKED = "revoked"


class InboxAddressState(enum.StrEnum):
    # A forwarding address Gmail has not yet confirmed cannot receive mail,
    # so the two states are tracked separately from simply existing.
    PENDING_VERIFICATION = "pending_verification"
    ACTIVE = "active"
    DISABLED = "disabled"


class AccountKind(enum.StrEnum):
    CASH = "cash"
    BANK = "bank"
    EWALLET = "ewallet"
    CREDIT_CARD = "credit_card"
    BUDGET_ENVELOPE = "budget_envelope"
    INVESTMENT = "investment"
    FOREIGN_CURRENCY = "foreign_currency"
    PHYSICAL_ASSET = "physical_asset"
    LOAN = "loan"
    OTHER = "other"
    EQUITY = "equity"


class TransactionStatus(enum.StrEnum):
    DRAFT = "draft"
    POSTED = "posted"
    REVERSED = "reversed"
    VOID = "void"


class CandidateState(enum.StrEnum):
    PENDING = "pending"
    NEEDS_INPUT = "needs_input"
    CONFIRMED = "confirmed"
    REJECTED = "rejected"
    DUPLICATE = "duplicate"
    EXPIRED = "expired"


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(320), nullable=False)
    normalized_email: Mapped[str] = mapped_column(String(320), unique=True, nullable=False)
    display_name: Mapped[str] = mapped_column(String(120), nullable=False)
    google_subject: Mapped[str | None] = mapped_column(String(255), unique=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    password_credential: Mapped["PasswordCredential | None"] = relationship(
        back_populates="user", cascade="all, delete-orphan", uselist=False
    )


class PasswordCredential(Base):
    __tablename__ = "password_credentials"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    password_hash: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    user: Mapped[User] = relationship(back_populates="password_credential")


class RefreshSession(Base):
    __tablename__ = "refresh_sessions"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    family_id: Mapped[uuid.UUID] = mapped_column(Uuid, index=True, nullable=False)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    token_digest: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    replaced_by_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Household(Base):
    __tablename__ = "households"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(160), nullable=False)
    # A household created during sign-in carries a generated name. It stays
    # unnamed until the owner confirms or replaces it in household setup.
    is_named: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    timezone: Mapped[str] = mapped_column(String(64), default="Asia/Jakarta", nullable=False)
    locale: Mapped[str] = mapped_column(String(16), default="id-ID", nullable=False)
    base_currency: Mapped[str] = mapped_column(String(3), default="IDR", nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Membership(Base):
    __tablename__ = "memberships"
    __table_args__ = (UniqueConstraint("household_id", "user_id"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True, nullable=False
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    role: Mapped[MembershipRole] = mapped_column(Enum(MembershipRole), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class HouseholdInvite(Base):
    """An offer for one email address to join one household.

    Invites are matched on the normalized email that Google verified at sign-in,
    so accepting one proves the invitee controls the address that was invited.
    """

    __tablename__ = "household_invites"
    __table_args__ = (
        # One live offer per address per household. Resolved invites are kept
        # for the audit trail, so the constraint only covers pending ones.
        Index(
            "uq_household_invites_pending",
            "household_id",
            "normalized_email",
            unique=True,
            postgresql_where=text("state = 'PENDING'"),
            sqlite_where=text("state = 'PENDING'"),
        ),
        Index("ix_household_invites_lookup", "normalized_email", "state"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True, nullable=False
    )
    email: Mapped[str] = mapped_column(String(320), nullable=False)
    normalized_email: Mapped[str] = mapped_column(String(320), nullable=False)
    role: Mapped[MembershipRole] = mapped_column(Enum(MembershipRole), nullable=False)
    state: Mapped[InviteState] = mapped_column(
        Enum(InviteState), default=InviteState.PENDING, nullable=False
    )
    invited_by_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    household: Mapped[Household] = relationship()
    invited_by: Mapped[User] = relationship()


class Category(Base):
    __tablename__ = "categories"
    __table_args__ = (UniqueConstraint("household_id", "name", "category_type"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True, nullable=False
    )
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    category_type: Mapped[str] = mapped_column(String(16), nullable=False)


class FinancialAccount(Base):
    __tablename__ = "financial_accounts"
    __table_args__ = (UniqueConstraint("household_id", "id"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True, nullable=False
    )
    name: Mapped[str] = mapped_column(String(160), nullable=False)
    kind: Mapped[AccountKind] = mapped_column(Enum(AccountKind), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), default="IDR", nullable=False)
    visibility: Mapped[str] = mapped_column(String(16), default="household", nullable=False)
    status: Mapped[str] = mapped_column(String(16), default="active", nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class AccountAccessGrant(Base):
    __tablename__ = "account_access_grants"
    __table_args__ = (UniqueConstraint("household_id", "account_id", "user_id"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True, nullable=False
    )
    account_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("financial_accounts.id", ondelete="CASCADE"), index=True, nullable=False
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )


class LedgerTransaction(Base):
    __tablename__ = "ledger_transactions"
    __table_args__ = (UniqueConstraint("household_id", "id"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True, nullable=False
    )
    transaction_type: Mapped[str] = mapped_column(String(32), nullable=False)
    status: Mapped[TransactionStatus] = mapped_column(Enum(TransactionStatus), nullable=False)
    description: Mapped[str] = mapped_column(String(240), nullable=False)
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_by_user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    postings: Mapped[list["Posting"]] = relationship(
        back_populates="transaction", cascade="all, delete-orphan"
    )


class Posting(Base):
    __tablename__ = "postings"
    __table_args__ = (CheckConstraint("amount_atomic <> 0", name="posting_amount_nonzero"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True, nullable=False
    )
    transaction_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("ledger_transactions.id", ondelete="RESTRICT"), index=True, nullable=False
    )
    account_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("financial_accounts.id", ondelete="RESTRICT"), index=True, nullable=False
    )
    amount_atomic: Mapped[int] = mapped_column(BigInteger, nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    transaction: Mapped[LedgerTransaction] = relationship(back_populates="postings")


class HouseholdInboxAddress(Base):
    """The address a household forwards its transaction email to.

    One per household, carrying an unguessable local part: anyone who learns
    it can inject candidates, so it is a secret in the same way a webhook URL
    is, and it can be rotated without touching anything else.
    """

    __tablename__ = "household_inbox_addresses"
    __table_args__ = (UniqueConstraint("local_part"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True, nullable=False
    )
    local_part: Mapped[str] = mapped_column(String(64), nullable=False)
    state: Mapped[InboxAddressState] = mapped_column(
        Enum(InboxAddressState), default=InboxAddressState.PENDING_VERIFICATION, nullable=False
    )
    # Gmail mails a confirmation code to the forwarding address before it will
    # send anything there. Rumpun receives that mail, so it captures the code
    # and shows it to the owner instead of making them hunt for it.
    verification_code: Mapped[str | None] = mapped_column(String(64))
    verification_received_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    created_by_user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), nullable=False)
    last_message_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    message_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)


class CandidateSource(Base):
    __tablename__ = "candidate_sources"
    __table_args__ = (UniqueConstraint("household_id", "provider", "provider_message_id"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True, nullable=False
    )
    provider: Mapped[str] = mapped_column(String(32), nullable=False)
    provider_message_id: Mapped[str] = mapped_column(String(255), nullable=False)
    sender_domain: Mapped[str | None] = mapped_column(String(255))
    received_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    content_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    parser_version: Mapped[str] = mapped_column(String(64), nullable=False)
    metadata_json: Mapped[dict[str, object]] = mapped_column(JSON, default=dict, nullable=False)


class TransactionCandidate(Base):
    __tablename__ = "transaction_candidates"
    __table_args__ = (
        UniqueConstraint("household_id", "id"),
        UniqueConstraint("ledger_transaction_id"),
        Index("ix_candidate_inbox", "household_id", "state", "created_at", "id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True, nullable=False
    )
    source_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("candidate_sources.id", ondelete="RESTRICT"), nullable=False
    )
    state: Mapped[CandidateState] = mapped_column(Enum(CandidateState), nullable=False)
    version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    confidence_bps: Mapped[int] = mapped_column(Integer, nullable=False)
    warnings: Mapped[list[object]] = mapped_column(JSON, default=list, nullable=False)
    evidence: Mapped[list[object]] = mapped_column(JSON, default=list, nullable=False)
    proposed_account_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    proposed_amount_atomic: Mapped[int | None] = mapped_column(BigInteger)
    proposed_currency: Mapped[str] = mapped_column(String(3), default="IDR", nullable=False)
    proposed_description: Mapped[str | None] = mapped_column(String(240))
    proposed_occurred_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    ledger_transaction_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("ledger_transactions.id", ondelete="RESTRICT")
    )
    reviewed_by_user_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    source: Mapped[CandidateSource] = relationship()


class IdempotencyRecord(Base):
    __tablename__ = "idempotency_records"
    __table_args__ = (UniqueConstraint("household_id", "operation", "key"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True, nullable=False
    )
    operation: Mapped[str] = mapped_column(String(64), nullable=False)
    key: Mapped[str] = mapped_column(String(255), nullable=False)
    request_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    resource_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class AuditEvent(Base):
    __tablename__ = "audit_events"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    household_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True
    )
    actor_user_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id"), index=True)
    event_type: Mapped[str] = mapped_column(String(100), index=True, nullable=False)
    target_type: Mapped[str | None] = mapped_column(String(64))
    target_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    metadata_json: Mapped[dict[str, object]] = mapped_column(JSON, default=dict, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
