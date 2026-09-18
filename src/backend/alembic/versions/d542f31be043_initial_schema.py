"""initial schema"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "d542f31be043"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "households",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=160), nullable=False),
        sa.Column("timezone", sa.String(length=64), nullable=False),
        sa.Column("locale", sa.String(length=16), nullable=False),
        sa.Column("base_currency", sa.String(length=3), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_table(
        "users",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("email", sa.String(length=320), nullable=False),
        sa.Column("normalized_email", sa.String(length=320), nullable=False),
        sa.Column("display_name", sa.String(length=120), nullable=False),
        sa.Column("google_subject", sa.String(length=255), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("google_subject"),
        sa.UniqueConstraint("normalized_email"),
    )
    op.create_table(
        "audit_events",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("household_id", sa.Uuid(), nullable=True),
        sa.Column("actor_user_id", sa.Uuid(), nullable=True),
        sa.Column("event_type", sa.String(length=100), nullable=False),
        sa.Column("target_type", sa.String(length=64), nullable=True),
        sa.Column("target_id", sa.Uuid(), nullable=True),
        sa.Column("metadata_json", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["actor_user_id"],
            ["users.id"],
        ),
        sa.ForeignKeyConstraint(["household_id"], ["households.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_audit_events_actor_user_id"), "audit_events", ["actor_user_id"], unique=False
    )
    op.create_index(
        op.f("ix_audit_events_event_type"), "audit_events", ["event_type"], unique=False
    )
    op.create_index(
        op.f("ix_audit_events_household_id"), "audit_events", ["household_id"], unique=False
    )
    op.create_table(
        "candidate_sources",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("household_id", sa.Uuid(), nullable=False),
        sa.Column("provider", sa.String(length=32), nullable=False),
        sa.Column("provider_message_id", sa.String(length=255), nullable=False),
        sa.Column("sender_domain", sa.String(length=255), nullable=True),
        sa.Column("received_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("content_hash", sa.String(length=64), nullable=False),
        sa.Column("parser_version", sa.String(length=64), nullable=False),
        sa.Column("metadata_json", sa.JSON(), nullable=False),
        sa.ForeignKeyConstraint(["household_id"], ["households.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("household_id", "provider", "provider_message_id"),
    )
    op.create_index(
        op.f("ix_candidate_sources_household_id"),
        "candidate_sources",
        ["household_id"],
        unique=False,
    )
    op.create_table(
        "categories",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("household_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=100), nullable=False),
        sa.Column("category_type", sa.String(length=16), nullable=False),
        sa.ForeignKeyConstraint(["household_id"], ["households.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("household_id", "name", "category_type"),
    )
    op.create_index(
        op.f("ix_categories_household_id"), "categories", ["household_id"], unique=False
    )
    op.create_table(
        "financial_accounts",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("household_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=160), nullable=False),
        sa.Column(
            "kind",
            sa.Enum(
                "CASH",
                "BANK",
                "EWALLET",
                "CREDIT_CARD",
                "BUDGET_ENVELOPE",
                "INVESTMENT",
                "FOREIGN_CURRENCY",
                "PHYSICAL_ASSET",
                "LOAN",
                "OTHER",
                "EQUITY",
                name="accountkind",
            ),
            nullable=False,
        ),
        sa.Column("currency", sa.String(length=3), nullable=False),
        sa.Column("visibility", sa.String(length=16), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["household_id"], ["households.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("household_id", "id"),
    )
    op.create_index(
        op.f("ix_financial_accounts_household_id"),
        "financial_accounts",
        ["household_id"],
        unique=False,
    )
    op.create_table(
        "idempotency_records",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("household_id", sa.Uuid(), nullable=False),
        sa.Column("operation", sa.String(length=64), nullable=False),
        sa.Column("key", sa.String(length=255), nullable=False),
        sa.Column("request_hash", sa.String(length=64), nullable=False),
        sa.Column("resource_id", sa.Uuid(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["household_id"], ["households.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("household_id", "operation", "key"),
    )
    op.create_index(
        op.f("ix_idempotency_records_household_id"),
        "idempotency_records",
        ["household_id"],
        unique=False,
    )
    op.create_table(
        "ledger_transactions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("household_id", sa.Uuid(), nullable=False),
        sa.Column("transaction_type", sa.String(length=32), nullable=False),
        sa.Column(
            "status",
            sa.Enum("DRAFT", "POSTED", "REVERSED", "VOID", name="transactionstatus"),
            nullable=False,
        ),
        sa.Column("description", sa.String(length=240), nullable=False),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_by_user_id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["created_by_user_id"],
            ["users.id"],
        ),
        sa.ForeignKeyConstraint(["household_id"], ["households.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("household_id", "id"),
    )
    op.create_index(
        op.f("ix_ledger_transactions_household_id"),
        "ledger_transactions",
        ["household_id"],
        unique=False,
    )
    op.create_table(
        "memberships",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("household_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column(
            "role",
            sa.Enum("OWNER", "ADMIN", "MEMBER", "VIEWER", "CHILD", name="membershiprole"),
            nullable=False,
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["household_id"], ["households.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("household_id", "user_id"),
    )
    op.create_index(
        op.f("ix_memberships_household_id"), "memberships", ["household_id"], unique=False
    )
    op.create_index(op.f("ix_memberships_user_id"), "memberships", ["user_id"], unique=False)
    op.create_table(
        "password_credentials",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("password_hash", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("user_id"),
    )
    op.create_table(
        "refresh_sessions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("family_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("token_digest", sa.String(length=64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("replaced_by_id", sa.Uuid(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("token_digest"),
    )
    op.create_index(
        op.f("ix_refresh_sessions_family_id"), "refresh_sessions", ["family_id"], unique=False
    )
    op.create_index(
        op.f("ix_refresh_sessions_user_id"), "refresh_sessions", ["user_id"], unique=False
    )
    op.create_table(
        "postings",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("household_id", sa.Uuid(), nullable=False),
        sa.Column("transaction_id", sa.Uuid(), nullable=False),
        sa.Column("account_id", sa.Uuid(), nullable=False),
        sa.Column("amount_atomic", sa.BigInteger(), nullable=False),
        sa.Column("currency", sa.String(length=3), nullable=False),
        sa.CheckConstraint("amount_atomic <> 0", name="posting_amount_nonzero"),
        sa.ForeignKeyConstraint(["account_id"], ["financial_accounts.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["household_id"], ["households.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["transaction_id"], ["ledger_transactions.id"], ondelete="RESTRICT"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_postings_account_id"), "postings", ["account_id"], unique=False)
    op.create_index(op.f("ix_postings_household_id"), "postings", ["household_id"], unique=False)
    op.create_index(
        op.f("ix_postings_transaction_id"), "postings", ["transaction_id"], unique=False
    )
    op.create_table(
        "transaction_candidates",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("household_id", sa.Uuid(), nullable=False),
        sa.Column("source_id", sa.Uuid(), nullable=False),
        sa.Column(
            "state",
            sa.Enum(
                "PENDING",
                "NEEDS_INPUT",
                "CONFIRMED",
                "REJECTED",
                "DUPLICATE",
                "EXPIRED",
                name="candidatestate",
            ),
            nullable=False,
        ),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("confidence_bps", sa.Integer(), nullable=False),
        sa.Column("warnings", sa.JSON(), nullable=False),
        sa.Column("evidence", sa.JSON(), nullable=False),
        sa.Column("proposed_account_id", sa.Uuid(), nullable=True),
        sa.Column("proposed_amount_atomic", sa.BigInteger(), nullable=True),
        sa.Column("proposed_currency", sa.String(length=3), nullable=False),
        sa.Column("proposed_description", sa.String(length=240), nullable=True),
        sa.Column("proposed_occurred_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("ledger_transaction_id", sa.Uuid(), nullable=True),
        sa.Column("reviewed_by_user_id", sa.Uuid(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["household_id"], ["households.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["ledger_transaction_id"], ["ledger_transactions.id"], ondelete="RESTRICT"
        ),
        sa.ForeignKeyConstraint(
            ["reviewed_by_user_id"],
            ["users.id"],
        ),
        sa.ForeignKeyConstraint(["source_id"], ["candidate_sources.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("household_id", "id"),
        sa.UniqueConstraint("ledger_transaction_id"),
    )
    op.create_index(
        "ix_candidate_inbox",
        "transaction_candidates",
        ["household_id", "state", "created_at", "id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_transaction_candidates_household_id"),
        "transaction_candidates",
        ["household_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        op.f("ix_transaction_candidates_household_id"), table_name="transaction_candidates"
    )
    op.drop_index("ix_candidate_inbox", table_name="transaction_candidates")
    op.drop_table("transaction_candidates")
    op.drop_index(op.f("ix_postings_transaction_id"), table_name="postings")
    op.drop_index(op.f("ix_postings_household_id"), table_name="postings")
    op.drop_index(op.f("ix_postings_account_id"), table_name="postings")
    op.drop_table("postings")
    op.drop_index(op.f("ix_refresh_sessions_user_id"), table_name="refresh_sessions")
    op.drop_index(op.f("ix_refresh_sessions_family_id"), table_name="refresh_sessions")
    op.drop_table("refresh_sessions")
    op.drop_table("password_credentials")
    op.drop_index(op.f("ix_memberships_user_id"), table_name="memberships")
    op.drop_index(op.f("ix_memberships_household_id"), table_name="memberships")
    op.drop_table("memberships")
    op.drop_index(op.f("ix_ledger_transactions_household_id"), table_name="ledger_transactions")
    op.drop_table("ledger_transactions")
    op.drop_index(op.f("ix_idempotency_records_household_id"), table_name="idempotency_records")
    op.drop_table("idempotency_records")
    op.drop_index(op.f("ix_financial_accounts_household_id"), table_name="financial_accounts")
    op.drop_table("financial_accounts")
    op.drop_index(op.f("ix_categories_household_id"), table_name="categories")
    op.drop_table("categories")
    op.drop_index(op.f("ix_candidate_sources_household_id"), table_name="candidate_sources")
    op.drop_table("candidate_sources")
    op.drop_index(op.f("ix_audit_events_household_id"), table_name="audit_events")
    op.drop_index(op.f("ix_audit_events_event_type"), table_name="audit_events")
    op.drop_index(op.f("ix_audit_events_actor_user_id"), table_name="audit_events")
    op.drop_table("audit_events")
    op.drop_table("users")
    op.drop_table("households")
