"""Server-side arrival state and shared household lists."""

import sqlalchemy as sa
from alembic import op

revision = "e5a7c3d1b820"
down_revision = "c9d312efab04"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "location_sessions",
        sa.Column("arrival_state", sa.JSON(), nullable=False, server_default="{}"),
    )
    op.create_table(
        "household_lists",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "household_id",
            sa.Uuid(),
            sa.ForeignKey("households.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("kind", sa.String(16), nullable=False),
        sa.Column("body", sa.Text(), nullable=False, server_default=""),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
        sa.Column(
            "created_by", sa.Uuid(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_household_lists_household_id", "household_lists", ["household_id"])
    op.create_table(
        "list_items",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "list_id",
            sa.Uuid(),
            sa.ForeignKey("household_lists.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("client_id", sa.String(64), nullable=False),
        sa.Column("text", sa.String(200), nullable=False),
        sa.Column("quantity", sa.String(40), nullable=True),
        sa.Column("note", sa.String(240), nullable=True),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("checked", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column(
            "checked_by", sa.Uuid(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True
        ),
        sa.Column("checked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "added_by", sa.Uuid(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("list_id", "client_id"),
    )
    op.create_index("ix_list_items_list_position", "list_items", ["list_id", "position"])
    op.create_table(
        "list_preferences",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "household_id",
            sa.Uuid(),
            sa.ForeignKey("households.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("items_added", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.UniqueConstraint("household_id", "user_id"),
    )


def downgrade() -> None:
    op.drop_table("list_preferences")
    op.drop_index("ix_list_items_list_position", table_name="list_items")
    op.drop_table("list_items")
    op.drop_index("ix_household_lists_household_id", table_name="household_lists")
    op.drop_table("household_lists")
    op.drop_column("location_sessions", "arrival_state")
