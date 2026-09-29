"""Persist validated local escrow transaction evidence.

Revision ID: 0011_reservation_chain_transactions
Revises: 0010_reservations
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0011_reservation_chain_transactions"
down_revision = "0010_reservations"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "reservation_chain_transaction",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column(
            "reservation_id",
            sa.String(length=36),
            sa.ForeignKey("reservation.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("chain_id", sa.Integer(), nullable=False),
        sa.Column("tx_hash", sa.String(length=66), nullable=False),
        sa.Column("action", sa.String(length=16), nullable=False),
        sa.Column("event_name", sa.String(length=32), nullable=False),
        sa.Column("event_signature", sa.String(length=128), nullable=False),
        sa.Column("event_topic", sa.String(length=66), nullable=False),
        sa.Column("log_index", sa.Integer(), nullable=False),
        sa.Column("block_number", sa.Integer(), nullable=False),
        sa.Column("block_hash", sa.String(length=66), nullable=False),
        sa.Column("block_timestamp", sa.BigInteger(), nullable=False),
        sa.Column("transaction_index", sa.Integer(), nullable=True),
        sa.Column("amount", sa.BigInteger(), nullable=False),
        sa.Column("nonce", sa.BigInteger(), nullable=False),
        sa.Column("escrow_address", sa.String(length=42), nullable=False),
        sa.Column("participant", sa.String(length=42), nullable=False),
        sa.Column("actor", sa.String(length=42), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "chain_id",
            "tx_hash",
            name="uq_reservation_chain_transaction_chain_tx_hash",
        ),
    )
    op.create_index(
        "ix_reservation_chain_transaction_reservation",
        "reservation_chain_transaction",
        ["reservation_id", "block_number"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_reservation_chain_transaction_reservation",
        table_name="reservation_chain_transaction",
    )
    op.drop_table("reservation_chain_transaction")
