"""Location arrivals, preferences, and replay-safe extensions."""

import sqlalchemy as sa
from alembic import op

revision = "c9d312efab04"
down_revision = "b6a21f4d9c03"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "location_sessions",
        sa.Column("extension_keys", sa.JSON(), nullable=False, server_default="[]"),
    )
    op.create_table(
        "location_arrivals",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("session_id", sa.Uuid(), sa.ForeignKey("location_sessions.id"), nullable=False),
        sa.Column("area_id", sa.String(36), nullable=False),
        sa.Column("arrived_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("session_id", "area_id"),
    )
    op.create_table(
        "location_preferences",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("household_id", sa.Uuid(), sa.ForeignKey("households.id"), nullable=False),
        sa.Column("user_id", sa.Uuid(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("sharing_started", sa.Boolean(), nullable=False),
        sa.Column("arrival_alerts", sa.Boolean(), nullable=False),
        sa.UniqueConstraint("household_id", "user_id"),
    )


def downgrade() -> None:
    op.drop_table("location_preferences")
    op.drop_table("location_arrivals")
    op.drop_column("location_sessions", "extension_keys")
