"""Add detection jobs for pre-trained furniture detection.

Revision ID: 0019_detection_jobs
Revises: 0018_listing_photos

No foreign keys on purpose: the retention policy for results is undecided and
deleting a listing photo must keep working. See
`app/modules/detection/models.py`.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0019_detection_jobs"
down_revision = "0018_listing_photos"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "detection_job",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("agency_id", sa.String(length=36), nullable=False),
        sa.Column("listing_id", sa.String(length=36), nullable=False),
        sa.Column("photo_id", sa.String(length=36), nullable=False),
        sa.Column("object_key", sa.String(length=255), nullable=False),
        sa.Column("model_id", sa.String(length=64), nullable=False),
        sa.Column("dedupe_key", sa.String(length=160), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("lease_expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("result", sa.JSON(), nullable=True),
        sa.Column("failure_reason", sa.String(length=255), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "status IN ('pending', 'running', 'completed', 'failed')",
            name="ck_detection_job_status",
        ),
        sa.CheckConstraint("attempts >= 0", name="ck_detection_job_attempts"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("dedupe_key", name="uq_detection_job_dedupe_key"),
    )
    op.create_index(
        "ix_detection_job_status_lease_expires_at",
        "detection_job",
        ["status", "lease_expires_at"],
    )
    op.create_index("ix_detection_job_listing_id", "detection_job", ["listing_id"])


def downgrade() -> None:
    op.drop_index("ix_detection_job_listing_id", table_name="detection_job")
    op.drop_index("ix_detection_job_status_lease_expires_at", table_name="detection_job")
    op.drop_table("detection_job")
