"""Create customer reservations with per-listing active locks.

Revision ID: 0010_reservations
Revises: 0009_agency_wallets_listing_deposit
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0010_reservations"
down_revision = "0009_agency_wallets_listing_deposit"
branch_labels = None
depends_on = None


_ACTIVE_RESERVATION_PREDICATE = "status IN ('pending', 'accepted')"


def upgrade() -> None:
    op.create_table(
        "reservation",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column(
            "listing_id",
            sa.String(length=36),
            sa.ForeignKey("listing.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column(
            "quote_id",
            sa.String(length=36),
            sa.ForeignKey("quote_snapshot.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column(
            "customer_id",
            sa.String(length=36),
            sa.ForeignKey("customer_account.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column(
            "customer_wallet_id",
            sa.String(length=36),
            sa.ForeignKey("customer_wallet.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column(
            "agency_wallet_id",
            sa.String(length=36),
            sa.ForeignKey("agency_wallet.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("customer_wallet_address", sa.String(length=42), nullable=False),
        sa.Column("agency_wallet_address", sa.String(length=42), nullable=False),
        sa.Column("offer_version", sa.Integer(), nullable=False),
        sa.Column("operation", sa.String(length=8), nullable=False),
        sa.Column("quote_lines", sa.JSON(), nullable=False),
        sa.Column("one_time_total", sa.Numeric(precision=18, scale=2), nullable=False),
        sa.Column("monthly_total", sa.Numeric(precision=18, scale=2), nullable=False),
        sa.Column("deposit_amount_cop", sa.Numeric(precision=18, scale=2), nullable=True),
        sa.Column("api_created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("decision_deadline_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("deposit_confirmed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("idempotency_key", sa.String(length=128), nullable=False),
        sa.Column("request_fingerprint", sa.String(length=64), nullable=False),
        sa.CheckConstraint(
            "status IN ('pending', 'accepted', 'rejected', 'cancelled', 'expired')",
            name="ck_reservation_status",
        ),
        sa.CheckConstraint("offer_version >= 1", name="ck_reservation_offer_version_positive"),
        sa.CheckConstraint(
            "decision_deadline_at > api_created_at",
            name="ck_reservation_deadline_after_creation",
        ),
        sa.CheckConstraint(
            "deposit_amount_cop IS NULL OR deposit_amount_cop > 0",
            name="ck_reservation_deposit_amount_cop_positive",
        ),
        sa.CheckConstraint(
            "deposit_amount_cop IS NULL OR deposit_amount_cop = round(deposit_amount_cop, 2)",
            name="ck_reservation_deposit_amount_cop_scale",
        ),
        sa.CheckConstraint(
            "one_time_total >= 0", name="ck_reservation_one_time_total_nonnegative"
        ),
        sa.CheckConstraint("monthly_total >= 0", name="ck_reservation_monthly_total_nonnegative"),
        sa.CheckConstraint(
            "length(trim(idempotency_key)) > 0",
            name="ck_reservation_idempotency_key_nonblank",
        ),
        sa.CheckConstraint(
            "length(request_fingerprint) = 64",
            name="ck_reservation_fingerprint_sha256",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "customer_id",
            "idempotency_key",
            name="uq_reservation_customer_idempotency_key",
        ),
    )
    op.create_index(
        "uq_reservation_active_listing",
        "reservation",
        ["listing_id"],
        unique=True,
        sqlite_where=sa.text(_ACTIVE_RESERVATION_PREDICATE),
        postgresql_where=sa.text(_ACTIVE_RESERVATION_PREDICATE),
    )
    op.create_index(
        "ix_reservation_customer_created_at",
        "reservation",
        ["customer_id", "api_created_at", "id"],
    )


def downgrade() -> None:
    op.drop_index("ix_reservation_customer_created_at", table_name="reservation")
    op.drop_index("uq_reservation_active_listing", table_name="reservation")
    op.drop_table("reservation")
