"""Add listing photos stored in object storage.

Revision ID: 0018_listing_photos
Revises: 0017_exchange_rate_source
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0018_listing_photos"
down_revision = "0017_exchange_rate_source"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "listing_photo",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("agency_id", sa.String(length=36), sa.ForeignKey("agency.id"), nullable=False),
        sa.Column("listing_id", sa.String(length=36), sa.ForeignKey("listing.id"), nullable=False),
        sa.Column("object_key", sa.String(length=255), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("content_type", sa.String(length=32), nullable=False),
        sa.Column("size_bytes", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("confirmed_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint("status IN ('pending', 'confirmed')", name="ck_listing_photo_status"),
        sa.CheckConstraint(
            "content_type IN ('image/jpeg', 'image/png', 'image/webp')",
            name="ck_listing_photo_content_type",
        ),
        sa.CheckConstraint(
            "size_bytes > 0 AND size_bytes <= 5242880", name="ck_listing_photo_size_bytes"
        ),
        sa.CheckConstraint(
            "(status = 'confirmed') = (confirmed_at IS NOT NULL)",
            name="ck_listing_photo_confirmed_at",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("object_key", name="uq_listing_photo_object_key"),
    )
    op.create_index(
        "ix_listing_photo_listing_id_created_at",
        "listing_photo",
        ["listing_id", "created_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_listing_photo_listing_id_created_at", table_name="listing_photo")
    op.drop_table("listing_photo")
