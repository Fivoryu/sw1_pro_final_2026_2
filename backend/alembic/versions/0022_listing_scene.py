"""Persist complete editable scenes for listings.

Revision ID: 0022_listing_scene
Revises: 0021_merge_photos_detection
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "0022_listing_scene"
down_revision = "0021_merge_photos_detection"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "listing_scene",
        sa.Column("listing_id", sa.String(length=36), nullable=False),
        sa.Column("scene", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_by", sa.String(length=36), nullable=True),
        sa.ForeignKeyConstraint(["listing_id"], ["listing.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("listing_id"),
    )


def downgrade() -> None:
    op.drop_table("listing_scene")
