"""account access grants"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "17695d210d59"
down_revision: Union[str, None] = "d542f31be043"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "account_access_grants",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("household_id", sa.Uuid(), nullable=False),
        sa.Column("account_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(["account_id"], ["financial_accounts.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["household_id"], ["households.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("household_id", "account_id", "user_id"),
    )
    op.create_index(
        op.f("ix_account_access_grants_account_id"),
        "account_access_grants",
        ["account_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_account_access_grants_household_id"),
        "account_access_grants",
        ["household_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_account_access_grants_user_id"), "account_access_grants", ["user_id"], unique=False
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_account_access_grants_user_id"), table_name="account_access_grants")
    op.drop_index(op.f("ix_account_access_grants_household_id"), table_name="account_access_grants")
    op.drop_index(op.f("ix_account_access_grants_account_id"), table_name="account_access_grants")
    op.drop_table("account_access_grants")
