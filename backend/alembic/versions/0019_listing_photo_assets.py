"""Separate listing-photo staging, original, and public asset references.

Revision ID: 0019_listing_photo_assets
Revises: 0018_listing_photos
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0019_listing_photo_assets"
down_revision = "0018_listing_photos"
branch_labels = None
depends_on = None


_OLD_CONTENT_TYPES = "'image/jpeg', 'image/png', 'image/webp'"
_UPLOAD_CONTENT_TYPES = "'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'"
_PUBLIC_CONTENT_TYPES = "'image/jpeg', 'image/png', 'image/webp'"
_OLD_MAX_BYTES = 5 * 1024 * 1024
_MAX_BYTES = 20 * 1024 * 1024


def upgrade() -> None:
    # Existing object keys and bytes are intentionally untouched. In particular,
    # an outstanding legacy upload URL still points at its original object_key.
    with op.batch_alter_table("listing_photo") as batch_op:
        batch_op.add_column(sa.Column("upload_object_key", sa.String(length=255), nullable=True))
        batch_op.add_column(sa.Column("original_object_key", sa.String(length=255), nullable=True))
        batch_op.add_column(sa.Column("public_content_type", sa.String(length=32), nullable=True))
        batch_op.drop_constraint("ck_listing_photo_content_type", type_="check")
        batch_op.create_check_constraint(
            "ck_listing_photo_content_type",
            f"content_type IN ({_UPLOAD_CONTENT_TYPES})",
        )
        batch_op.drop_constraint("ck_listing_photo_size_bytes", type_="check")
        batch_op.create_check_constraint(
            "ck_listing_photo_size_bytes",
            f"size_bytes > 0 AND size_bytes <= {_MAX_BYTES}",
        )
        batch_op.create_check_constraint(
            "ck_listing_photo_public_content_type",
            "public_content_type IS NULL "
            f"OR public_content_type IN ({_PUBLIC_CONTENT_TYPES})",
        )
        batch_op.create_unique_constraint(
            "uq_listing_photo_upload_object_key", ["upload_object_key"]
        )
        batch_op.create_unique_constraint(
            "uq_listing_photo_original_object_key", ["original_object_key"]
        )
    op.create_index(
        "ix_listing_photo_status_expires_at",
        "listing_photo",
        ["status", "expires_at"],
    )


def downgrade() -> None:
    bind = op.get_bind()
    has_new_photo_assets = bind.execute(
        sa.text(
            "SELECT 1 FROM listing_photo "
            "WHERE upload_object_key IS NOT NULL "
            "OR original_object_key IS NOT NULL "
            "OR public_content_type IS NOT NULL "
            f"OR content_type NOT IN ({_OLD_CONTENT_TYPES}) "
            f"OR size_bytes > {_OLD_MAX_BYTES} "
            "LIMIT 1"
        )
    ).first()
    if has_new_photo_assets is not None:
        raise RuntimeError(
            "Cannot downgrade listing-photo policy while new photo assets, formats, or sizes exist"
        )

    op.drop_index("ix_listing_photo_status_expires_at", table_name="listing_photo")
    with op.batch_alter_table("listing_photo") as batch_op:
        batch_op.drop_constraint("uq_listing_photo_upload_object_key", type_="unique")
        batch_op.drop_constraint("uq_listing_photo_original_object_key", type_="unique")
        batch_op.drop_constraint("ck_listing_photo_public_content_type", type_="check")
        batch_op.drop_constraint("ck_listing_photo_content_type", type_="check")
        batch_op.drop_constraint("ck_listing_photo_size_bytes", type_="check")
        batch_op.drop_column("upload_object_key")
        batch_op.drop_column("original_object_key")
        batch_op.drop_column("public_content_type")
        batch_op.create_check_constraint(
            "ck_listing_photo_content_type",
            f"content_type IN ({_OLD_CONTENT_TYPES})",
        )
        batch_op.create_check_constraint(
            "ck_listing_photo_size_bytes",
            f"size_bytes > 0 AND size_bytes <= {_OLD_MAX_BYTES}",
        )
