"""Store per-user Gmail grants and discovered message IDs."""

import sqlalchemy as sa
from alembic import op

revision = "9e4c6a21d8b0"
down_revision = "f319a52c4d91"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "gmail_oauth_attempts",
        sa.Column("state_digest", sa.String(64), primary_key=True),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column(
            "household_id",
            sa.Uuid(),
            sa.ForeignKey("households.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("code_verifier", sa.String(128), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_table(
        "gmail_connections",
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
        sa.Column("google_subject", sa.String(255), nullable=False),
        sa.Column("google_email", sa.String(320), nullable=False),
        sa.Column("refresh_token_ciphertext", sa.Text(), nullable=False),
        sa.Column("history_id", sa.String(128), nullable=False),
        sa.Column("status", sa.String(32), nullable=False),
        sa.Column("connected_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_synced_at", sa.DateTime(timezone=True)),
        sa.UniqueConstraint("user_id", "household_id"),
    )
    op.create_table(
        "gmail_messages",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "connection_id",
            sa.Uuid(),
            sa.ForeignKey("gmail_connections.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("gmail_message_id", sa.String(255), nullable=False),
        sa.Column("state", sa.String(32), nullable=False),
        sa.Column("discovered_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("connection_id", "gmail_message_id"),
    )
    op.create_index("ix_gmail_oauth_attempts_expires", "gmail_oauth_attempts", ["expires_at"])
    op.create_index("ix_gmail_connections_due", "gmail_connections", ["status", "last_synced_at"])
    op.create_index("ix_gmail_messages_pending", "gmail_messages", ["connection_id", "state"])


def downgrade() -> None:
    op.drop_index("ix_gmail_messages_pending", table_name="gmail_messages")
    op.drop_index("ix_gmail_connections_due", table_name="gmail_connections")
    op.drop_index("ix_gmail_oauth_attempts_expires", table_name="gmail_oauth_attempts")
    op.drop_table("gmail_messages")
    op.drop_table("gmail_connections")
    op.drop_table("gmail_oauth_attempts")
