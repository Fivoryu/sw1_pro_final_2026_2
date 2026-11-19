"""Persist capture checksums and manifest identity, keeping historical captures intact."""
from alembic import op
import sqlalchemy as sa

revision = "0036_capture_integrity"
down_revision = "0035_merge_f07_heads"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("listing_capture", sa.Column("package_sha256", sa.String(64), nullable=True))
    op.add_column("listing_capture", sa.Column("package_manifest", sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column("listing_capture", "package_manifest")
    op.drop_column("listing_capture", "package_sha256")
