"""Add capture packages and their reconstruction jobs (F07.7).

Revision ID: 0025_capture_reconstruction
Revises: 0024_listing_scene_revision
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0025_capture_reconstruction"
down_revision = "0024_listing_scene_revision"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Additive only. No foreign keys: the scene draft outlives the frames and a
    # capture must never block deleting a listing.
    op.create_table(
        "listing_capture",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("job_id", sa.String(length=36), nullable=False),
        sa.Column("agency_id", sa.String(length=36), nullable=False),
        sa.Column("listing_id", sa.String(length=36), nullable=False),
        sa.Column("object_key", sa.String(length=255), nullable=False),
        sa.Column("size_bytes", sa.BigInteger(), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("lease_expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("claim_token", sa.String(length=64), nullable=True),
        sa.Column("scene_draft", sa.JSON(), nullable=True),
        sa.Column("warnings", sa.JSON(), nullable=True),
        sa.Column("failure_reason", sa.String(length=255), nullable=True),
        sa.Column("created_by", sa.String(length=36), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("uploaded_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("enqueued_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("accepted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("frames_delete_after", sa.DateTime(timezone=True), nullable=False),
        sa.Column("frames_deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "status IN ('awaiting_upload', 'queued', 'processing', 'completed', "
            "'failed', 'accepted')",
            name="ck_listing_capture_status",
        ),
        sa.CheckConstraint("attempts >= 0", name="ck_listing_capture_attempts"),
        sa.CheckConstraint("size_bytes >= 0", name="ck_listing_capture_size"),
        sa.UniqueConstraint("job_id", name="uq_listing_capture_job_id"),
    )
    op.create_index(
        "ix_listing_capture_status_lease_expires_at",
        "listing_capture",
        ["status", "lease_expires_at"],
    )
    op.create_index("ix_listing_capture_listing_id", "listing_capture", ["listing_id"])
    op.create_index(
        "ix_listing_capture_frames_due",
        "listing_capture",
        ["frames_deleted_at", "frames_delete_after"],
    )


def downgrade() -> None:
    op.drop_index("ix_listing_capture_frames_due", table_name="listing_capture")
    op.drop_index("ix_listing_capture_listing_id", table_name="listing_capture")
    op.drop_index("ix_listing_capture_status_lease_expires_at", table_name="listing_capture")
    op.drop_table("listing_capture")
