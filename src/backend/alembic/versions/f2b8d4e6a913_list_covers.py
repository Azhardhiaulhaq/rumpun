"""Cover icon and tint for household lists."""

import sqlalchemy as sa
from alembic import op

revision = "f2b8d4e6a913"
down_revision = "e5a7c3d1b820"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "household_lists",
        sa.Column("icon", sa.String(24), nullable=False, server_default="basket"),
    )
    op.add_column(
        "household_lists",
        sa.Column("tint", sa.String(24), nullable=False, server_default="sage"),
    )


def downgrade() -> None:
    op.drop_column("household_lists", "tint")
    op.drop_column("household_lists", "icon")
