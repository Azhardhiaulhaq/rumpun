"""Push devices, notification outbox, manual Gmail sync, and editable proposals."""

import sqlalchemy as sa
from alembic import op

revision = "d8c4a6e20b19"
down_revision = "9e4c6a21d8b0"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("transaction_candidates", sa.Column("proposed_type", sa.String(16)))
    op.add_column("transaction_candidates", sa.Column("proposed_category_id", sa.Uuid()))
    op.add_column("transaction_candidates", sa.Column("proposed_destination_account_id", sa.Uuid()))
    op.create_table(
        "gmail_sync_jobs",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "connection_id",
            sa.Uuid(),
            sa.ForeignKey("gmail_connections.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("requested_by_user_id", sa.Uuid(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("days", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(24), nullable=False),
        sa.Column("discovered_count", sa.Integer(), nullable=False),
        sa.Column("candidate_count", sa.Integer(), nullable=False),
        sa.Column("error_code", sa.String(80)),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True)),
        sa.Column("completed_at", sa.DateTime(timezone=True)),
    )
    op.create_index("ix_gmail_sync_jobs_pending", "gmail_sync_jobs", ["status", "created_at"])
    op.create_table(
        "push_devices",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column(
            "household_id",
            sa.Uuid(),
            sa.ForeignKey("households.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("token_digest", sa.String(64), unique=True, nullable=False),
        sa.Column("token", sa.Text(), nullable=False),
        sa.Column("platform", sa.String(16), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_push_devices_user", "push_devices", ["user_id", "household_id"])
    op.create_table(
        "notification_outbox",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("event_key", sa.String(255), unique=True, nullable=False),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column(
            "household_id",
            sa.Uuid(),
            sa.ForeignKey("households.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("kind", sa.String(32), nullable=False),
        sa.Column("title", sa.String(160), nullable=False),
        sa.Column("body", sa.String(240), nullable=False),
        sa.Column("data_json", sa.JSON(), nullable=False),
        sa.Column("status", sa.String(24), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("next_attempt_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("sent_at", sa.DateTime(timezone=True)),
    )
    op.create_index(
        "ix_notification_outbox_due", "notification_outbox", ["status", "next_attempt_at"]
    )


def downgrade() -> None:
    op.drop_index("ix_notification_outbox_due", table_name="notification_outbox")
    op.drop_table("notification_outbox")
    op.drop_index("ix_push_devices_user", table_name="push_devices")
    op.drop_table("push_devices")
    op.drop_index("ix_gmail_sync_jobs_pending", table_name="gmail_sync_jobs")
    op.drop_table("gmail_sync_jobs")
    op.drop_column("transaction_candidates", "proposed_destination_account_id")
    op.drop_column("transaction_candidates", "proposed_category_id")
    op.drop_column("transaction_candidates", "proposed_type")
