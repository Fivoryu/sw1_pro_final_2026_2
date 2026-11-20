"""Merge the furniture-inclusion and listing-review migration heads.

Revision ID: 0035_merge_f07_heads
Revises: 0028_extra_inclusion, 0034_listing_reviews
"""

from __future__ import annotations

from typing import Sequence, Union


revision: str = "0035_merge_f07_heads"
down_revision: Union[str, Sequence[str], None] = (
    "0028_extra_inclusion",
    "0034_listing_reviews",
)
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
