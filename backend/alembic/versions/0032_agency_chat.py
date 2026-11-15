"""Create the agency chat tables: conversations, messages, reports and blocks.

Revision ID: 0032_agency_chat
Revises: 0031_listing_agent
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0032_agency_chat"
down_revision: Union[str, Sequence[str], None] = "0031_listing_agent"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "chat_conversation",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("listing_id", sa.String(length=36), nullable=False),
        sa.Column("agency_id", sa.String(length=36), nullable=False),
        sa.Column("customer_id", sa.String(length=36), nullable=False),
        sa.Column("agent_id", sa.String(length=36), nullable=True),
        sa.Column("needs_admin", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("awaiting_since", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_message_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["listing_id"], ["listing.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["agency_id"], ["agency.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["customer_id"], ["customer_account.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["agent_id"], ["staff_account.id"], ondelete="SET NULL"),
        sa.UniqueConstraint("listing_id", "customer_id", name="uq_chat_conversation_listing_customer"),
    )
    op.create_index("ix_chat_conversation_agency_id", "chat_conversation", ["agency_id"])
    op.create_index("ix_chat_conversation_agent_id", "chat_conversation", ["agent_id"])
    op.create_index("ix_chat_conversation_customer_id", "chat_conversation", ["customer_id"])

    op.create_table(
        "chat_message",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("conversation_id", sa.String(length=36), nullable=False),
        sa.Column("sender_role", sa.String(length=16), nullable=False),
        sa.Column("sender_staff_id", sa.String(length=36), nullable=True),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["conversation_id"], ["chat_conversation.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["sender_staff_id"], ["staff_account.id"], ondelete="SET NULL"),
        sa.CheckConstraint(
            "sender_role IN ('customer', 'agent', 'admin')", name="ck_chat_message_sender_role"
        ),
    )
    op.create_index(
        "ix_chat_message_conversation_id_id", "chat_message", ["conversation_id", "id"]
    )

    op.create_table(
        "chat_report",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("conversation_id", sa.String(length=36), nullable=False),
        sa.Column("reporter_role", sa.String(length=16), nullable=False),
        sa.Column("reporter_id", sa.String(length=36), nullable=False),
        sa.Column("reason", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["conversation_id"], ["chat_conversation.id"], ondelete="CASCADE"),
        sa.CheckConstraint(
            "reporter_role IN ('customer', 'agent', 'admin')", name="ck_chat_report_reporter_role"
        ),
    )
    op.create_index("ix_chat_report_conversation_id", "chat_report", ["conversation_id"])

    op.create_table(
        "chat_customer_block",
        sa.Column("agency_id", sa.String(length=36), nullable=False),
        sa.Column("customer_id", sa.String(length=36), nullable=False),
        sa.Column("blocked_by", sa.String(length=36), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["agency_id"], ["agency.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["customer_id"], ["customer_account.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["blocked_by"], ["staff_account.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("agency_id", "customer_id"),
    )


def downgrade() -> None:
    op.drop_table("chat_customer_block")
    op.drop_index("ix_chat_report_conversation_id", table_name="chat_report")
    op.drop_table("chat_report")
    op.drop_index("ix_chat_message_conversation_id_id", table_name="chat_message")
    op.drop_table("chat_message")
    op.drop_index("ix_chat_conversation_customer_id", table_name="chat_conversation")
    op.drop_index("ix_chat_conversation_agent_id", table_name="chat_conversation")
    op.drop_index("ix_chat_conversation_agency_id", table_name="chat_conversation")
    op.drop_table("chat_conversation")
