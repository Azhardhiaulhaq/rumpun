"""household is_named flag

Marks households whose name is still the one generated at sign-in, so the
client can ask the owner to name it instead of showing a placeholder forever.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "a3f9c17b2e84"
down_revision: Union[str, None] = "17695d210d59"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Existing households were named through the register form, so they are
    # already named; only new sign-in households start as False.
    op.add_column(
        "households",
        sa.Column("is_named", sa.Boolean(), nullable=False, server_default=sa.true()),
    )
    op.alter_column("households", "is_named", server_default=None)


def downgrade() -> None:
    op.drop_column("households", "is_named")
