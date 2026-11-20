"""Add the inclusion mode to listing extras.

Revision ID: 0028_extra_inclusion
Revises: 0027_merge_f09_heads
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0028_extra_inclusion"
down_revision = "0027_merge_f09_heads"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Additive and defaulted: every existing extra stays optional, so quotes and prices do not
    # change. A plain ADD COLUMN is used instead of batch mode on purpose: SQLite batch mode
    # rebuilds the table and would drop the offer-version triggers installed by 0007.
    op.add_column(
        "listing_extra",
        sa.Column(
            "inclusion",
            sa.String(length=10),
            nullable=False,
            server_default="optional",
        ),
    )
    if op.get_bind().dialect.name == "postgresql":
        op.create_check_constraint(
            "ck_listing_extra_inclusion_known",
            "listing_extra",
            "inclusion IN ('optional', 'included')",
        )


def downgrade() -> None:
    if op.get_bind().dialect.name == "postgresql":
        op.drop_constraint("ck_listing_extra_inclusion_known", "listing_extra", type_="check")
    op.drop_column("listing_extra", "inclusion")
