"""Add the active worker claim token for detection-job fencing.

Revision ID: 0020_detection_job_claim_token
Revises: 0019_detection_jobs
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0020_detection_job_claim_token"
down_revision = "0019_detection_jobs"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "detection_job",
        sa.Column("claim_token", sa.String(length=64), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("detection_job", "claim_token")
