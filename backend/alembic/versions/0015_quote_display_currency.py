"""Freeze optional display-currency totals and their exchange rates in quotes.

Revision ID: 0015_quote_display_currency
Revises: 0014_exchange_rates
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0015_quote_display_currency"
down_revision = "0014_exchange_rates"
branch_labels = None
depends_on = None


_IMMUTABILITY_UPDATE_TRIGGER = "trg_quote_snapshot_immutable_update"
_IMMUTABILITY_DELETE_TRIGGER = "trg_quote_snapshot_immutable_delete"
_IMMUTABILITY_FUNCTION = "roomforge_reject_quote_snapshot_mutation"


def _drop_snapshot_immutability() -> None:
    dialect_name = op.get_bind().dialect.name
    if dialect_name == "sqlite":
        op.execute(f"DROP TRIGGER IF EXISTS {_IMMUTABILITY_DELETE_TRIGGER}")
        op.execute(f"DROP TRIGGER IF EXISTS {_IMMUTABILITY_UPDATE_TRIGGER}")
    elif dialect_name == "postgresql":
        op.execute(
            f"DROP TRIGGER IF EXISTS {_IMMUTABILITY_UPDATE_TRIGGER} ON quote_snapshot"
        )
        op.execute(f"DROP FUNCTION IF EXISTS {_IMMUTABILITY_FUNCTION}()")
    else:
        raise RuntimeError(
            "Quote snapshot migration is unsupported for database dialect "
            f"{dialect_name!r}"
        )


def _install_snapshot_immutability() -> None:
    dialect_name = op.get_bind().dialect.name
    if dialect_name == "sqlite":
        op.execute(
            f"""
            CREATE TRIGGER {_IMMUTABILITY_UPDATE_TRIGGER}
            BEFORE UPDATE ON quote_snapshot
            BEGIN
                SELECT RAISE(ABORT, 'quote snapshots are immutable');
            END
            """
        )
        op.execute(
            f"""
            CREATE TRIGGER {_IMMUTABILITY_DELETE_TRIGGER}
            BEFORE DELETE ON quote_snapshot
            BEGIN
                SELECT RAISE(ABORT, 'quote snapshots are immutable');
            END
            """
        )
    elif dialect_name == "postgresql":
        op.execute(
            f"""
            CREATE FUNCTION {_IMMUTABILITY_FUNCTION}() RETURNS trigger
            LANGUAGE plpgsql AS $$
            BEGIN
                RAISE EXCEPTION 'quote snapshots are immutable'
                    USING ERRCODE = 'check_violation';
            END;
            $$
            """
        )
        op.execute(
            f"""
            CREATE TRIGGER {_IMMUTABILITY_UPDATE_TRIGGER}
            BEFORE UPDATE OR DELETE ON quote_snapshot
            FOR EACH ROW EXECUTE FUNCTION {_IMMUTABILITY_FUNCTION}()
            """
        )
    else:
        raise RuntimeError(
            "Quote snapshot migration is unsupported for database dialect "
            f"{dialect_name!r}"
        )


def upgrade() -> None:
    _drop_snapshot_immutability()
    with op.batch_alter_table("quote_snapshot") as batch_op:
        batch_op.add_column(sa.Column("display_currency", sa.String(length=4), nullable=True))
        batch_op.add_column(
            sa.Column("display_one_time_total", sa.Numeric(precision=18, scale=2), nullable=True)
        )
        batch_op.add_column(
            sa.Column("display_monthly_total", sa.Numeric(precision=18, scale=2), nullable=True)
        )
        batch_op.add_column(
            sa.Column("base_units_per_usd", sa.Numeric(precision=18, scale=8), nullable=True)
        )
        batch_op.add_column(
            sa.Column("display_units_per_usd", sa.Numeric(precision=18, scale=8), nullable=True)
        )
        batch_op.create_check_constraint(
            "ck_quote_snapshot_display_fields_all_or_none",
            "(display_currency IS NULL AND display_one_time_total IS NULL "
            "AND display_monthly_total IS NULL AND base_units_per_usd IS NULL "
            "AND display_units_per_usd IS NULL) OR "
            "(display_currency IS NOT NULL AND display_one_time_total IS NOT NULL "
            "AND display_monthly_total IS NOT NULL AND base_units_per_usd IS NOT NULL "
            "AND display_units_per_usd IS NOT NULL)",
        )
    _install_snapshot_immutability()


def downgrade() -> None:
    _drop_snapshot_immutability()
    with op.batch_alter_table("quote_snapshot") as batch_op:
        batch_op.drop_constraint(
            "ck_quote_snapshot_display_fields_all_or_none", type_="check"
        )
        batch_op.drop_column("display_units_per_usd")
        batch_op.drop_column("base_units_per_usd")
        batch_op.drop_column("display_monthly_total")
        batch_op.drop_column("display_one_time_total")
        batch_op.drop_column("display_currency")
    _install_snapshot_immutability()
