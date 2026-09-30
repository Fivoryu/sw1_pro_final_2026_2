"""Add append-only agency listing transition history.

Revision ID: 0012_listing_transitions
Revises: 0011_reservation_chain_txns
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0012_listing_transitions"
down_revision = "0011_reservation_chain_txns"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "listing_transition",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("agency_id", sa.String(length=36), sa.ForeignKey("agency.id"), nullable=False),
        sa.Column("listing_id", sa.String(length=36), sa.ForeignKey("listing.id"), nullable=False),
        sa.Column("action", sa.String(length=16), nullable=False),
        sa.Column("from_status", sa.String(length=16), nullable=True),
        sa.Column("from_published", sa.Boolean(), nullable=True),
        sa.Column("to_status", sa.String(length=16), nullable=False),
        sa.Column("to_published", sa.Boolean(), nullable=False),
        sa.Column("observation", sa.Text(), nullable=True),
        sa.Column("actor_id", sa.String(length=36), nullable=False),
        sa.Column("actor_role", sa.String(length=32), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "action IN ('create', 'edit', 'submit', 'approve', 'reject', 'publish', 'unpublish')",
            name="ck_listing_transition_action",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_listing_transition_listing_id", "listing_transition", ["listing_id"])
    op.create_index(
        "ix_listing_transition_listing_id_created_at",
        "listing_transition",
        ["listing_id", "created_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_listing_transition_listing_id_created_at", table_name="listing_transition")
    op.drop_index("ix_listing_transition_listing_id", table_name="listing_transition")
    op.drop_table("listing_transition")
