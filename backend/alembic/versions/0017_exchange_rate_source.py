"""Track the origin of each exchange-rate row and allow system-ingested rates.

Revision ID: 0017_exchange_rate_source
Revises: 0016_listing_extra_details

Adds the ``source`` label to ``exchange_rate`` (``manual`` for rows authored from the
panel; official ingestion labels rows ``coinbase``/``bcb-static``) and relaxes
``created_by`` to nullable, because automatically ingested rows have no authoring
staff account. The downgrade fails if system rows exist, because they cannot be
rewritten to a staff account.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0017_exchange_rate_source"
down_revision = "0016_listing_extra_details"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("exchange_rate") as batch_op:
        batch_op.add_column(
            sa.Column(
                "source",
                sa.String(length=32),
                nullable=False,
                server_default=sa.text("'manual'"),
            )
        )
        batch_op.alter_column(
            "created_by",
            existing_type=sa.String(length=36),
            nullable=True,
        )


def downgrade() -> None:
    with op.batch_alter_table("exchange_rate") as batch_op:
        batch_op.alter_column(
            "created_by",
            existing_type=sa.String(length=36),
            nullable=False,
        )
        batch_op.drop_column("source")
