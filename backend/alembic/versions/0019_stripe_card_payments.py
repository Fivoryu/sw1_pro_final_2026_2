"""Add Stripe Connect accounts and card payment records.

Revision ID: 0019_stripe_card_payments
Revises: 0018_listing_photos
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "0019_stripe_card_payments"
down_revision = "0018_listing_photos"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Use a temporary server default to backfill existing wallet reservations,
    # then remove it so the database schema matches the ORM metadata.
    op.add_column(
        "reservation",
        sa.Column("payment_method", sa.String(length=8), nullable=False, server_default="wallet"),
    )
    with op.batch_alter_table("reservation") as batch:
        batch.alter_column("customer_wallet_id", existing_type=sa.String(length=36), nullable=True)
        batch.alter_column("agency_wallet_id", existing_type=sa.String(length=36), nullable=True)
        batch.alter_column("customer_wallet_address", existing_type=sa.String(length=42), nullable=True)
        batch.alter_column("agency_wallet_address", existing_type=sa.String(length=42), nullable=True)
        batch.create_check_constraint("ck_reservation_payment_method", "payment_method IN ('wallet', 'card')")
        batch.alter_column(
            "payment_method",
            existing_type=sa.String(length=8),
            existing_server_default="wallet",
            server_default=None,
        )

    op.create_table(
        "stripe_connect_account",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("agency_id", sa.String(length=36), nullable=False),
        sa.Column("stripe_account_id", sa.String(length=128), nullable=False),
        sa.Column("details_submitted", sa.Boolean(), nullable=False),
        sa.Column("charges_enabled", sa.Boolean(), nullable=False),
        sa.Column("payouts_enabled", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["agency_id"], ["agency.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("agency_id", name="uq_stripe_connect_account_agency"),
        sa.UniqueConstraint("stripe_account_id", name="uq_stripe_connect_account_id"),
    )
    op.create_table(
        "reservation_card_payment",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("reservation_id", sa.String(length=36), nullable=False),
        sa.Column("stripe_payment_intent_id", sa.String(length=128), nullable=False),
        sa.Column("latest_charge_id", sa.String(length=128), nullable=True),
        sa.Column("amount_minor", sa.Integer(), nullable=False),
        sa.Column("currency", sa.String(length=3), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("transfer_id", sa.String(length=128), nullable=True),
        sa.Column("refund_id", sa.String(length=128), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["reservation_id"], ["reservation.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("reservation_id", name="uq_reservation_card_payment_reservation"),
        sa.UniqueConstraint("stripe_payment_intent_id", name="uq_reservation_card_payment_intent"),
    )
    op.create_table(
        "stripe_webhook_event",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("stripe_event_id", sa.String(length=128), nullable=False),
        sa.Column("event_type", sa.String(length=128), nullable=False),
        sa.Column("processed_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("stripe_event_id", name="uq_stripe_webhook_event_id"),
    )


def downgrade() -> None:
    op.drop_table("stripe_webhook_event")
    op.drop_table("reservation_card_payment")
    op.drop_table("stripe_connect_account")
    with op.batch_alter_table("reservation") as batch:
        batch.drop_constraint("ck_reservation_payment_method", type_="check")
        batch.drop_column("payment_method")
        batch.alter_column("customer_wallet_id", existing_type=sa.String(length=36), nullable=False)
        batch.alter_column("agency_wallet_id", existing_type=sa.String(length=36), nullable=False)
        batch.alter_column("customer_wallet_address", existing_type=sa.String(length=42), nullable=False)
        batch.alter_column("agency_wallet_address", existing_type=sa.String(length=42), nullable=False)
