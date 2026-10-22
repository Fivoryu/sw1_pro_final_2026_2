"""Store class suggestions for reconstructed volumes and let reviews reference them.

Revision ID: 0026_capture_volume_suggestions
Revises: 0025_capture_reconstruction
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0026_capture_volume_suggestions"
down_revision = "0025_capture_reconstruction"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Additive only: every new column is nullable, so existing rows stay valid.
    op.add_column("listing_capture", sa.Column("volume_suggestions", sa.JSON(), nullable=True))
    # Batch mode keeps the unique constraint portable to SQLite.
    with op.batch_alter_table("furniture_review") as batch:
        batch.add_column(sa.Column("capture_id", sa.String(length=64), nullable=True))
        batch.add_column(sa.Column("object_id", sa.String(length=64), nullable=True))
        batch.create_unique_constraint(
            "uq_furniture_review_volume", ["capture_id", "object_id"]
        )


def downgrade() -> None:
    with op.batch_alter_table("furniture_review") as batch:
        batch.drop_constraint("uq_furniture_review_volume", type_="unique")
        batch.drop_column("object_id")
        batch.drop_column("capture_id")
    op.drop_column("listing_capture", "volume_suggestions")
