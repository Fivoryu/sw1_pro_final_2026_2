"""merge listing photo and detection revisions

Revision ID: 0021_merge_photos_detection
Revises: 0020_listing_photo_deletion, 0020_detection_job_claim_token
Create Date: 2026-10-15 06:22:11.793131
"""
from __future__ import annotations

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0021_merge_photos_detection'
down_revision: Union[str, None] = ('0020_listing_photo_deletion', '0020_detection_job_claim_token')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
