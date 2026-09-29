"""Create isolated customer account and session tables.

Revision ID: 0005_customer_identity
Revises: 0004_staff_invitation_pending_email_unique
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0005_customer_identity"
down_revision = "0004_staff_invitation_pending_email_unique"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "customer_account",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("email", sa.String(length=255), nullable=False),
        sa.Column("password_hash", sa.String(length=255), nullable=False),
    )
    op.create_index(
        "uq_customer_account_normalized_email",
        "customer_account",
        [sa.func.lower(sa.func.trim(sa.column("email")))],
        unique=True,
    )

    op.create_table(
        "customer_session",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column(
            "customer_id",
            sa.String(length=36),
            sa.ForeignKey("customer_account.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("refresh_token_hash", sa.String(length=64), nullable=False, unique=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column("last_activity_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_customer_session_customer_id", "customer_session", ["customer_id"])


def downgrade() -> None:
    op.drop_index("ix_customer_session_customer_id", table_name="customer_session")
    op.drop_table("customer_session")
    op.drop_index(
        "uq_customer_account_normalized_email",
        table_name="customer_account",
    )
    op.drop_table("customer_account")
