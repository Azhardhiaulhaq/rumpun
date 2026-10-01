"""asset valuations and currency units"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "e418b9c2f6a0"
down_revision: Union[str, None] = "c81d5a3f7b20"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.alter_column("financial_accounts", "currency", type_=sa.String(12))
    op.alter_column("postings", "currency", type_=sa.String(12))
    op.add_column(
        "financial_accounts",
        sa.Column("minor_unit", sa.Integer(), nullable=False, server_default="2"),
    )
    op.add_column("financial_accounts", sa.Column("unit", sa.String(40)))
    op.execute(
        "UPDATE financial_accounts SET minor_unit = CASE "
        "WHEN currency IN ('BIF','CLP','DJF','GNF','ISK','JPY','KMF','KRW','PYG','RWF','UGX','UYI','VND','VUV','XAF','XOF','XPF','IDR') THEN 0 "
        "WHEN currency IN ('BHD','IQD','JOD','KWD','LYD','OMR','TND') THEN 3 ELSE 2 END"
    )
    op.alter_column("financial_accounts", "minor_unit", server_default=None)
    op.add_column("ledger_transactions", sa.Column("reverses_transaction_id", sa.Uuid()))
    op.create_foreign_key(
        "fk_ledger_transactions_reverses",
        "ledger_transactions",
        "ledger_transactions",
        ["reverses_transaction_id"],
        ["id"],
        ondelete="RESTRICT",
    )
    op.create_unique_constraint(
        "uq_ledger_transactions_reverses", "ledger_transactions", ["reverses_transaction_id"]
    )
    op.create_index(
        "uq_household_equity_currency",
        "financial_accounts",
        ["household_id", "currency"],
        unique=True,
        postgresql_where=sa.text("kind = 'EQUITY'"),
        sqlite_where=sa.text("kind = 'EQUITY'"),
    )
    op.create_table(
        "asset_valuations",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "household_id",
            sa.Uuid(),
            sa.ForeignKey("households.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "account_id",
            sa.Uuid(),
            sa.ForeignKey("financial_accounts.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("value_atomic", sa.BigInteger(), nullable=False),
        sa.Column("currency", sa.String(12), nullable=False),
        sa.Column("quantity", sa.Numeric(38, 18)),
        sa.Column("effective_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("source", sa.String(120), nullable=False),
        sa.Column("created_by_user_id", sa.Uuid(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("value_atomic >= 0", name="valuation_nonnegative"),
    )
    op.create_index(
        "ix_asset_valuations_latest",
        "asset_valuations",
        ["household_id", "account_id", "effective_at"],
    )


def downgrade() -> None:
    op.drop_constraint("uq_ledger_transactions_reverses", "ledger_transactions", type_="unique")
    op.drop_constraint("fk_ledger_transactions_reverses", "ledger_transactions", type_="foreignkey")
    op.drop_column("ledger_transactions", "reverses_transaction_id")
    op.drop_index("uq_household_equity_currency", table_name="financial_accounts")
    op.drop_index("ix_asset_valuations_latest", table_name="asset_valuations")
    op.drop_table("asset_valuations")
    op.drop_column("financial_accounts", "unit")
    op.drop_column("financial_accounts", "minor_unit")
    op.alter_column("postings", "currency", type_=sa.String(3))
    op.alter_column("financial_accounts", "currency", type_=sa.String(3))
