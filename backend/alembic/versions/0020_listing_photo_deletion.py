"""Persist confirmed listing-photo deletion intents.

Revision ID: 0020_listing_photo_deletion
Revises: 0019_listing_photo_assets
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0020_listing_photo_deletion"
down_revision = "0019_listing_photo_assets"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Intents deliberately have no foreign keys: they must outlive the photo,
    # listing, or agency records whose objects still need deleting.
    op.create_table(
        "listing_photo_deletion",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("agency_id", sa.String(length=36), nullable=False),
        sa.Column("listing_id", sa.String(length=36), nullable=False),
        sa.Column("photo_id", sa.String(length=36), nullable=False),
        sa.Column("actor_id", sa.String(length=36), nullable=False),
        sa.Column("object_key", sa.String(length=255), nullable=False),
        sa.Column("original_object_key", sa.String(length=255), nullable=True),
        sa.Column("upload_object_key", sa.String(length=255), nullable=True),
        sa.Column("requested_at", sa.DateTime(timezone=True), nullable=False),
        # Moment the signed staging PUT stops being authorized. The intent is kept
        # until then so a late upload cannot leave an untracked object behind.
        sa.Column("upload_expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("attempts", sa.Integer(), server_default="0", nullable=False),
        sa.Column("next_attempt_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_error", sa.String(length=64), nullable=True),
        sa.CheckConstraint("attempts >= 0", name="ck_listing_photo_deletion_attempts"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("photo_id", name="uq_listing_photo_deletion_photo_id"),
    )
    op.create_index(
        "ix_listing_photo_deletion_due",
        "listing_photo_deletion",
        ["next_attempt_at", "id"],
    )


def downgrade() -> None:
    bind = op.get_bind()
    has_pending_intents = bind.execute(
        sa.text("SELECT 1 FROM listing_photo_deletion LIMIT 1")
    ).first()
    if has_pending_intents is not None:
        raise RuntimeError("Cannot downgrade while pending photo deletion intents exist")

    op.drop_index("ix_listing_photo_deletion_due", table_name="listing_photo_deletion")
    op.drop_table("listing_photo_deletion")
