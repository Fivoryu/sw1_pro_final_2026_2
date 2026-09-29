"""Add customer wallet links and one-time verification challenges.

Revision ID: 0006_customer_wallet
Revises: 0005_customer_identity
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0006_customer_wallet"
down_revision = "0005_customer_identity"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "customer_wallet",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column(
            "customer_id",
            sa.String(length=36),
            sa.ForeignKey("customer_account.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("address", sa.String(length=42), nullable=False),
        sa.Column("linked_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "address = lower(address)", name="ck_customer_wallet_address_canonical"
        ),
        sa.UniqueConstraint("customer_id", name="uq_customer_wallet_customer_id"),
        sa.UniqueConstraint("address", name="uq_customer_wallet_address"),
    )

    op.create_table(
        "customer_wallet_challenge",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column(
            "customer_id",
            sa.String(length=36),
            sa.ForeignKey("customer_account.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("address", sa.String(length=42), nullable=False),
        sa.Column("purpose", sa.String(length=64), nullable=False),
        sa.Column("nonce", sa.String(length=64), nullable=False),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("issued_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("consumed_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "purpose = 'link-customer-wallet'", name="ck_customer_wallet_challenge_purpose"
        ),
        sa.UniqueConstraint("nonce", name="uq_customer_wallet_challenge_nonce"),
    )
    op.create_index(
        "ix_customer_wallet_challenge_customer_id",
        "customer_wallet_challenge",
        ["customer_id"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_customer_wallet_challenge_customer_id", table_name="customer_wallet_challenge"
    )
    op.drop_table("customer_wallet_challenge")
    op.drop_table("customer_wallet")
