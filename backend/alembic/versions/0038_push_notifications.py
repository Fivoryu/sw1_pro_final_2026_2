"""Add device tokens and the push marker on notifications (FCM).

Revision ID: 0038_push_notifications
Revises: 0037_customer_favorites
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0038_push_notifications"
down_revision: Union[str, Sequence[str], None] = "0037_customer_favorites"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "device_token",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("recipient_kind", sa.String(length=16), nullable=False),
        sa.Column("recipient_id", sa.String(length=36), nullable=False),
        sa.Column("token", sa.String(length=512), nullable=False),
        sa.Column("platform", sa.String(length=16), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "recipient_kind IN ('customer', 'staff')", name="ck_device_token_recipient_kind"
        ),
        sa.CheckConstraint("platform IN ('android', 'ios')", name="ck_device_token_platform"),
        sa.UniqueConstraint("token", name="uq_device_token_token"),
    )
    op.create_index(
        "ix_device_token_recipient", "device_token", ["recipient_kind", "recipient_id"]
    )
    op.add_column(
        "notification", sa.Column("pushed_at", sa.DateTime(timezone=True), nullable=True)
    )
    # History is never pushed: every notice that exists now counts as already delivered.
    op.execute("UPDATE notification SET pushed_at = created_at")


def downgrade() -> None:
    op.drop_column("notification", "pushed_at")
    op.drop_index("ix_device_token_recipient", table_name="device_token")
    op.drop_table("device_token")
