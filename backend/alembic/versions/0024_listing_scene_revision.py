"""Version listing scenes for optimistic concurrency (F07.5).

Revision ID: 0024_listing_scene_revision
Revises: 0023_furniture_review
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0024_listing_scene_revision"
down_revision = "0023_furniture_review"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Existing scenes start at revision 1, the same value a fresh scene receives.
    op.add_column(
        "listing_scene",
        sa.Column("revision", sa.Integer(), nullable=False, server_default="1"),
    )


def downgrade() -> None:
    op.drop_column("listing_scene", "revision")
