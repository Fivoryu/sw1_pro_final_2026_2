"""Persist append-only human furniture reviews without rewriting detection jobs."""
from alembic import op
import sqlalchemy as sa

revision = "0023_furniture_review"
down_revision = "0022_listing_scene"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "furniture_review",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("agency_id", sa.String(36), nullable=False),
        sa.Column("listing_id", sa.String(36), nullable=False),
        sa.Column("job_id", sa.String(36), nullable=True),
        sa.Column("detection_index", sa.Integer(), nullable=True),
        sa.Column("action", sa.String(16), nullable=False),
        sa.Column("extra_id", sa.String(36), nullable=True),
        sa.Column("request_hash", sa.String(64), nullable=False),
        sa.Column("snapshot", sa.JSON(), nullable=False),
        sa.Column("actor_id", sa.String(36), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("action IN ('manual', 'confirmed', 'rejected')", name="ck_furniture_review_action"),
        sa.UniqueConstraint("job_id", "detection_index", name="uq_furniture_review_detection"),
    )
    op.create_index("ix_furniture_review_listing", "furniture_review", ["listing_id"])


def downgrade() -> None:
    op.drop_table("furniture_review")
