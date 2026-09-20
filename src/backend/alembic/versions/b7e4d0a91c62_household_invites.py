"""household invites

Lets an owner invite a specific email address into their household, so a second
family member joins the existing ledger instead of getting a new empty one.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "b7e4d0a91c62"
down_revision: Union[str, None] = "a3f9c17b2e84"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

INVITE_STATE = sa.Enum(
    "PENDING", "ACCEPTED", "DECLINED", "REVOKED", name="invitestate"
)


def _membership_role() -> sa.types.TypeEngine[str]:
    """Reuses the membershiprole type from the initial schema.

    On PostgreSQL the enum type already exists, so it must not be created again.
    SQLite has no enum types and stores the values as text.
    """
    if op.get_bind().dialect.name == "postgresql":
        return postgresql.ENUM(
            "OWNER",
            "ADMIN",
            "MEMBER",
            "VIEWER",
            "CHILD",
            name="membershiprole",
            create_type=False,
        )
    return sa.Enum("OWNER", "ADMIN", "MEMBER", "VIEWER", "CHILD", name="membershiprole")


def upgrade() -> None:
    # create_table creates invitestate as a side effect; checkfirst makes the
    # step safe to re-run after a partially applied migration.
    INVITE_STATE.create(op.get_bind(), checkfirst=True)

    op.create_table(
        "household_invites",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("household_id", sa.Uuid(), nullable=False),
        sa.Column("email", sa.String(length=320), nullable=False),
        sa.Column("normalized_email", sa.String(length=320), nullable=False),
        sa.Column("role", _membership_role(), nullable=False),
        sa.Column(
            "state",
            postgresql.ENUM(
                "PENDING",
                "ACCEPTED",
                "DECLINED",
                "REVOKED",
                name="invitestate",
                create_type=False,
            )
            if op.get_bind().dialect.name == "postgresql"
            else INVITE_STATE,
            nullable=False,
        ),
        sa.Column("invited_by_id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["household_id"], ["households.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["invited_by_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_household_invites_household_id", "household_invites", ["household_id"]
    )
    op.create_index(
        "ix_household_invites_lookup",
        "household_invites",
        ["normalized_email", "state"],
    )
    # Only one live offer per address per household; resolved rows stay for the
    # audit trail, so the uniqueness is partial.
    op.create_index(
        "uq_household_invites_pending",
        "household_invites",
        ["household_id", "normalized_email"],
        unique=True,
        postgresql_where=sa.text("state = 'PENDING'"),
        sqlite_where=sa.text("state = 'PENDING'"),
    )


def downgrade() -> None:
    op.drop_index("uq_household_invites_pending", table_name="household_invites")
    op.drop_index("ix_household_invites_lookup", table_name="household_invites")
    op.drop_index("ix_household_invites_household_id", table_name="household_invites")
    op.drop_table("household_invites")
    INVITE_STATE.drop(op.get_bind(), checkfirst=True)
