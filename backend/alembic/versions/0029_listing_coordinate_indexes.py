"""Index listing coordinates for geographic bounding-box searches.

Revision ID: 0029_listing_coordinate_indexes
Revises: 0028_listing_coordinates
"""

from __future__ import annotations

from typing import Sequence, Union

from alembic import op

revision: str = "0029_listing_coordinate_indexes"
down_revision: Union[str, Sequence[str], None] = "0028_listing_coordinates"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_index("ix_listing_latitude", "listing", ["latitude"])
    op.create_index("ix_listing_longitude", "listing", ["longitude"])


def downgrade() -> None:
    op.drop_index("ix_listing_longitude", table_name="listing")
    op.drop_index("ix_listing_latitude", table_name="listing")
