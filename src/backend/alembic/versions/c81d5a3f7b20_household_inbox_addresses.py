"""household inbox addresses

Gives each household an unguessable address to forward transaction email to,
so candidates can arrive without Gmail OAuth and its restricted scopes.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "c81d5a3f7b20"
down_revision: Union[str, None] = "b7e4d0a91c62"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

INBOX_STATE = sa.Enum(
    "PENDING_VERIFICATION",
    "ACTIVE",
    "DISABLED",
    name="inboxaddressstate",
)


def _state_type() -> sa.types.TypeEngine[str]:
    """Creates the enum once, then reuses it.

    checkfirst on the type is not enough inside create_table: SQLAlchemy would
    emit CREATE TYPE a second time. create_type=False says the column should
    reference a type that already exists.
    """
    if op.get_bind().dialect.name == "postgresql":
        from sqlalchemy.dialects import postgresql

        return postgresql.ENUM(
            "PENDING_VERIFICATION",
            "ACTIVE",
            "DISABLED",
            name="inboxaddressstate",
            create_type=False,
        )
    return INBOX_STATE


def upgrade() -> None:
    bind = op.get_bind()
    INBOX_STATE.create(bind, checkfirst=True)
    op.create_table(
        "household_inbox_addresses",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("household_id", sa.Uuid(), nullable=False),
        sa.Column("local_part", sa.String(length=64), nullable=False),
        sa.Column("state", _state_type(), nullable=False),
        sa.Column("verification_code", sa.String(length=64), nullable=True),
        sa.Column(
            "verification_received_at", sa.DateTime(timezone=True), nullable=True
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_by_user_id", sa.Uuid(), nullable=False),
        sa.Column("last_message_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("message_count", sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(
            ["household_id"], ["households.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
        # The local part is how an inbound message is routed to a household,
        # so it has to be unique across every household, not just within one.
        sa.UniqueConstraint("local_part"),
    )
    op.create_index(
        "ix_household_inbox_addresses_household_id",
        "household_inbox_addresses",
        ["household_id"],
    )
    # One live address per household. Rotating replaces the row rather than
    # leaving two addresses that both deliver.
    op.create_index(
        "uq_household_inbox_active",
        "household_inbox_addresses",
        ["household_id"],
        unique=True,
        postgresql_where=sa.text("state <> 'DISABLED'"),
        sqlite_where=sa.text("state <> 'DISABLED'"),
    )


def downgrade() -> None:
    op.drop_index("uq_household_inbox_active", table_name="household_inbox_addresses")
    op.drop_index(
        "ix_household_inbox_addresses_household_id",
        table_name="household_inbox_addresses",
    )
    op.drop_table("household_inbox_addresses")
    INBOX_STATE.drop(op.get_bind(), checkfirst=True)
