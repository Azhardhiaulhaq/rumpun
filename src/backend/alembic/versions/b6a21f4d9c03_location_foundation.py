"""Household areas and explicit location sessions."""

import sqlalchemy as sa
from alembic import op

revision = "b6a21f4d9c03"
down_revision = "a7d2e9c41f36"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "location_areas",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("household_id", sa.Uuid(), sa.ForeignKey("households.id"), nullable=False),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("vertices", sa.JSON(), nullable=False),
        sa.Column("version", sa.Integer(), nullable=False),
    )
    op.create_index("ix_location_areas_household_id", "location_areas", ["household_id"])
    op.create_table(
        "location_sessions",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("household_id", sa.Uuid(), sa.ForeignKey("households.id"), nullable=False),
        sa.Column("user_id", sa.Uuid(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("device_id", sa.String(100), nullable=False),
        sa.Column("start_key", sa.String(100), nullable=False),
        sa.Column("state", sa.String(20), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("areas", sa.JSON(), nullable=False),
        sa.Column("position", sa.JSON(), nullable=True),
        sa.Column("sequence", sa.Integer(), nullable=False),
    )
    op.create_index("ix_location_sessions_household_id", "location_sessions", ["household_id"])
    op.create_index("ix_location_sessions_user_id", "location_sessions", ["user_id"])
    op.create_index(
        "uq_location_active_user",
        "location_sessions",
        ["user_id"],
        unique=True,
        postgresql_where=sa.text("state = 'active'"),
        sqlite_where=sa.text("state = 'active'"),
    )


def downgrade() -> None:
    op.drop_table("location_sessions")
    op.drop_table("location_areas")
