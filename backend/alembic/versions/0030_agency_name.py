"""Add the customer-facing display name to agencies.

Revision ID: 0030_agency_name
Revises: 0029_listing_coordinate_indexes
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0030_agency_name"
down_revision: Union[str, Sequence[str], None] = "0029_listing_coordinate_indexes"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("agency", sa.Column("name", sa.String(length=120), nullable=True))
    # Existing agencies have no name yet; their id is the best available label.
    op.execute("UPDATE agency SET name = id WHERE name IS NULL")
    op.alter_column("agency", "name", existing_type=sa.String(length=120), nullable=False)


def downgrade() -> None:
    op.drop_column("agency", "name")
