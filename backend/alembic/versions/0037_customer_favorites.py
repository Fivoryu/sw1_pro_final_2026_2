"""Create customer favorites and saved searches (F14.3).

Revision ID: 0037_customer_favorites
Revises: 0036_capture_integrity
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0037_customer_favorites"
down_revision: Union[str, Sequence[str], None] = "0036_capture_integrity"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "customer_favorite",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("customer_id", sa.String(length=36), nullable=False),
        sa.Column("listing_id", sa.String(length=36), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["customer_id"], ["customer_account.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["listing_id"], ["listing.id"], ondelete="CASCADE"),
        sa.UniqueConstraint(
            "customer_id", "listing_id", name="uq_customer_favorite_customer_listing"
        ),
    )
    op.create_index("ix_customer_favorite_listing_id", "customer_favorite", ["listing_id"])

    op.create_table(
        "customer_saved_search",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("customer_id", sa.String(length=36), nullable=False),
        sa.Column("name", sa.String(length=80), nullable=False),
        sa.Column("filters", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["customer_id"], ["customer_account.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("customer_id", "name", name="uq_customer_saved_search_customer_name"),
    )


def downgrade() -> None:
    op.drop_table("customer_saved_search")
    op.drop_index("ix_customer_favorite_listing_id", table_name="customer_favorite")
    op.drop_table("customer_favorite")
