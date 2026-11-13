"""Create the notification table for in-app notices (F14.7).

Revision ID: 0033_notifications
Revises: 0032_agency_chat
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0033_notifications"
down_revision: Union[str, Sequence[str], None] = "0032_agency_chat"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "notification",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("recipient_kind", sa.String(length=16), nullable=False),
        sa.Column("recipient_id", sa.String(length=36), nullable=False),
        sa.Column("kind", sa.String(length=32), nullable=False),
        sa.Column("conversation_id", sa.String(length=36), nullable=True),
        sa.Column("reservation_id", sa.String(length=36), nullable=True),
        sa.Column("detail", sa.String(length=32), nullable=True),
        sa.Column("dedupe_key", sa.String(length=160), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("read_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "recipient_kind IN ('customer', 'staff')", name="ck_notification_recipient_kind"
        ),
        sa.ForeignKeyConstraint(["conversation_id"], ["chat_conversation.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["reservation_id"], ["reservation.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("dedupe_key"),
    )
    op.create_index(
        "ix_notification_recipient",
        "notification",
        ["recipient_kind", "recipient_id", "created_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_notification_recipient", table_name="notification")
    op.drop_table("notification")
