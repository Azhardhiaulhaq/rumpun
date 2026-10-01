"""Household categories, budgets and transaction assignment."""

from alembic import op
import sqlalchemy as sa

revision = "f319a52c4d91"
down_revision = "e418b9c2f6a0"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("categories", sa.Column("budget_atomic", sa.BigInteger()))
    op.create_check_constraint("category_budget_positive", "categories", "budget_atomic > 0")
    op.add_column("ledger_transactions", sa.Column("category_id", sa.Uuid()))
    op.create_foreign_key(
        "fk_transaction_category",
        "ledger_transactions",
        "categories",
        ["category_id"],
        ["id"],
        ondelete="RESTRICT",
    )
    op.create_index("ix_ledger_transactions_category_id", "ledger_transactions", ["category_id"])
    op.execute(
        "UPDATE ledger_transactions SET category_id = (SELECT id FROM categories WHERE categories.household_id = ledger_transactions.household_id AND categories.category_type = CASE WHEN ledger_transactions.transaction_type = 'expense' THEN 'expense' ELSE 'income' END LIMIT 1) WHERE transaction_type IN ('expense', 'income', 'refund')"
    )


def downgrade() -> None:
    op.drop_index("ix_ledger_transactions_category_id", table_name="ledger_transactions")
    op.drop_constraint("fk_transaction_category", "ledger_transactions", type_="foreignkey")
    op.drop_column("ledger_transactions", "category_id")
    op.drop_constraint("category_budget_positive", "categories", type_="check")
    op.drop_column("categories", "budget_atomic")
