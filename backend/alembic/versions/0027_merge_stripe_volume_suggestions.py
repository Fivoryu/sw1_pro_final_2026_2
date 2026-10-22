"""Merge Stripe payments and capture volume-suggestion migration heads.

Revision ID: 0027_merge_f09_heads
Revises: 0019_stripe_card_payments, 0026_capture_volume_suggestions
"""

from __future__ import annotations

from typing import Sequence, Union

from alembic import op


revision: str = "0027_merge_f09_heads"
down_revision: Union[str, Sequence[str], None] = (
    "0019_stripe_card_payments",
    "0026_capture_volume_suggestions",
)
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
