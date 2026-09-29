"""Persist immutable quote snapshots and shared rate-limit events.

Revision ID: 0008_quote_snapshots
Revises: 0007_catalog_offers
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0008_quote_snapshots"
down_revision = "0007_catalog_offers"
branch_labels = None
depends_on = None


def _install_snapshot_immutability() -> None:
    dialect_name = op.get_bind().dialect.name
    if dialect_name == "sqlite":
        op.execute(
            """
            CREATE TRIGGER trg_quote_snapshot_immutable_update
            BEFORE UPDATE ON quote_snapshot
            BEGIN
                SELECT RAISE(ABORT, 'quote snapshots are immutable');
            END
            """
        )
        op.execute(
            """
            CREATE TRIGGER trg_quote_snapshot_immutable_delete
            BEFORE DELETE ON quote_snapshot
            BEGIN
                SELECT RAISE(ABORT, 'quote snapshots are immutable');
            END
            """
        )
    elif dialect_name == "postgresql":
        op.execute(
            """
            CREATE FUNCTION roomforge_reject_quote_snapshot_mutation() RETURNS trigger
            LANGUAGE plpgsql AS $$
            BEGIN
                RAISE EXCEPTION 'quote snapshots are immutable'
                    USING ERRCODE = 'check_violation';
            END;
            $$
            """
        )
        op.execute(
            """
            CREATE TRIGGER trg_quote_snapshot_immutable_update
            BEFORE UPDATE OR DELETE ON quote_snapshot
            FOR EACH ROW EXECUTE FUNCTION roomforge_reject_quote_snapshot_mutation()
            """
        )
    else:
        raise RuntimeError(
            f"Quote snapshot immutability is unsupported for database dialect {dialect_name!r}"
        )


def _drop_snapshot_immutability() -> None:
    dialect_name = op.get_bind().dialect.name
    if dialect_name == "sqlite":
        op.execute("DROP TRIGGER IF EXISTS trg_quote_snapshot_immutable_delete")
        op.execute("DROP TRIGGER IF EXISTS trg_quote_snapshot_immutable_update")
    elif dialect_name == "postgresql":
        op.execute("DROP TRIGGER IF EXISTS trg_quote_snapshot_immutable_update ON quote_snapshot")
        op.execute("DROP FUNCTION IF EXISTS roomforge_reject_quote_snapshot_mutation()")
    else:
        raise RuntimeError(
            f"Quote snapshot immutability is unsupported for database dialect {dialect_name!r}"
        )


def upgrade() -> None:
    op.create_table(
        "quote_snapshot",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("listing_id", sa.String(length=36), nullable=False),
        sa.Column("offer_version", sa.Integer(), nullable=False),
        sa.Column("operation", sa.String(length=8), nullable=False),
        sa.Column("lines", sa.JSON(), nullable=False),
        sa.Column("one_time_total", sa.Numeric(precision=18, scale=2), nullable=False),
        sa.Column("monthly_total", sa.Numeric(precision=18, scale=2), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("offer_version >= 1", name="ck_quote_snapshot_offer_version_positive"),
        sa.CheckConstraint("operation IN ('sale', 'rent')", name="ck_quote_snapshot_operation"),
        sa.CheckConstraint("one_time_total >= 0", name="ck_quote_snapshot_one_time_nonnegative"),
        sa.CheckConstraint("monthly_total >= 0", name="ck_quote_snapshot_monthly_nonnegative"),
        sa.CheckConstraint("expires_at > created_at", name="ck_quote_snapshot_expiry_after_creation"),
    )
    op.create_index(
        "ix_quote_snapshot_listing_version",
        "quote_snapshot",
        ["listing_id", "offer_version"],
    )
    op.create_table(
        "quote_rate_limit_event",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("client_key", sa.String(length=64), nullable=False),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index(
        "ix_quote_rate_limit_client_time",
        "quote_rate_limit_event",
        ["client_key", "occurred_at"],
    )
    op.create_index(
        "ix_quote_rate_limit_occurred_at",
        "quote_rate_limit_event",
        ["occurred_at"],
    )
    _install_snapshot_immutability()


def downgrade() -> None:
    _drop_snapshot_immutability()
    op.drop_index("ix_quote_rate_limit_occurred_at", table_name="quote_rate_limit_event")
    op.drop_index("ix_quote_rate_limit_client_time", table_name="quote_rate_limit_event")
    op.drop_table("quote_rate_limit_event")
    op.drop_index("ix_quote_snapshot_listing_version", table_name="quote_snapshot")
    op.drop_table("quote_snapshot")
