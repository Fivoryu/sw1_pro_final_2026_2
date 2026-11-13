"""Assign agents to listings for the agency chat.

Revision ID: 0031_listing_agent
Revises: 0030_agency_name
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0031_listing_agent"
down_revision: Union[str, Sequence[str], None] = "0030_agency_name"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "listing_agent",
        sa.Column("listing_id", sa.String(length=36), nullable=False),
        sa.Column("agent_id", sa.String(length=36), nullable=False),
        sa.Column("assigned_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["listing_id"], ["listing.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["agent_id"], ["staff_account.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("listing_id", "agent_id"),
    )
    op.create_index("ix_listing_agent_agent_id", "listing_agent", ["agent_id"])


def downgrade() -> None:
    op.drop_index("ix_listing_agent_agent_id", table_name="listing_agent")
    op.drop_table("listing_agent")
