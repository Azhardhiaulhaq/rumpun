"""Record how many Gmail messages a sync job left for a later classification pass."""

import sqlalchemy as sa
from alembic import op

revision = "a7d2e9c41f36"
down_revision = "d8c4a6e20b19"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "gmail_sync_jobs",
        sa.Column("unclassified_count", sa.Integer(), nullable=False, server_default="0"),
    )


def downgrade() -> None:
    op.drop_column("gmail_sync_jobs", "unclassified_count")
