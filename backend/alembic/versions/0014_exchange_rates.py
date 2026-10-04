"""Create the administered exchange-rate history table.

Revision ID: 0014_exchange_rates
Revises: 0013_listing_currency
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0014_exchange_rates"
down_revision = "0013_listing_currency"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "exchange_rate",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("currency", sa.String(length=4), nullable=False),
        sa.Column("units_per_usd", sa.Numeric(precision=18, scale=8), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column("created_by", sa.String(length=36), nullable=False),
        sa.CheckConstraint(
            "currency IN ('BOB', 'USD', 'USDT')",
            name="ck_exchange_rate_currency_supported",
        ),
        sa.CheckConstraint(
            "units_per_usd > 0",
            name="ck_exchange_rate_units_per_usd_positive",
        ),
        sa.ForeignKeyConstraint(["created_by"], ["staff_account.id"]),
        sa.PrimaryKeyConstraint("id"),
    )


def downgrade() -> None:
    op.drop_table("exchange_rate")
