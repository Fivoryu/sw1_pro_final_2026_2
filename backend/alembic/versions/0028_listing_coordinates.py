"""Add optional listing coordinates.

Revision ID: 0028_listing_coordinates
Revises: 0027_merge_f09_heads
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0028_listing_coordinates"
down_revision: Union[str, Sequence[str], None] = "0027_merge_f09_heads"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("listing", sa.Column("latitude", sa.Double(), nullable=True))
    op.add_column("listing", sa.Column("longitude", sa.Double(), nullable=True))


def downgrade() -> None:
    op.drop_column("listing", "longitude")
    op.drop_column("listing", "latitude")
