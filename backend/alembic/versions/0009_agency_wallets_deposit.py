"""Add agency wallet ownership and fixed listing deposits.

Revision ID: 0009_agency_wallets_deposit
Revises: 0008_quote_snapshots
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0009_agency_wallets_deposit"
down_revision = "0008_quote_snapshots"
branch_labels = None
depends_on = None


def _install_sqlite_listing_deposit_scale_guards() -> None:
    op.execute(
        """
        CREATE TRIGGER trg_listing_deposit_amount_scale_insert_guard
        BEFORE INSERT ON listing
        WHEN NEW.deposit_amount_cop IS NOT NULL
          AND NEW.deposit_amount_cop != ROUND(NEW.deposit_amount_cop, 2)
        BEGIN
            SELECT RAISE(ABORT, 'listing deposit amount must have at most two decimals');
        END
        """
    )
    op.execute(
        """
        CREATE TRIGGER trg_listing_deposit_amount_scale_update_guard
        BEFORE UPDATE OF deposit_amount_cop ON listing
        WHEN NEW.deposit_amount_cop IS NOT NULL
          AND NEW.deposit_amount_cop != ROUND(NEW.deposit_amount_cop, 2)
        BEGIN
            SELECT RAISE(ABORT, 'listing deposit amount must have at most two decimals');
        END
        """
    )


def _install_sqlite_listing_deposit_guards() -> None:
    op.execute(
        """
        CREATE TRIGGER trg_listing_deposit_amount_insert_guard
        BEFORE INSERT ON listing
        WHEN NEW.deposit_amount_cop IS NOT NULL AND NEW.deposit_amount_cop <= 0
        BEGIN
            SELECT RAISE(ABORT, 'listing deposit amount must be positive');
        END
        """
    )
    op.execute(
        """
        CREATE TRIGGER trg_listing_deposit_amount_update_guard
        BEFORE UPDATE OF deposit_amount_cop ON listing
        WHEN NEW.deposit_amount_cop IS NOT NULL AND NEW.deposit_amount_cop <= 0
        BEGIN
            SELECT RAISE(ABORT, 'listing deposit amount must be positive');
        END
        """
    )


def _install_sqlite_deposit_offer_version_triggers() -> None:
    # Reuse 0007's guarded trigger names so the existing SQLite authorizer keeps
    # permitting only trigger-owned writes to listing_offer_version_guard.
    op.execute("DROP TRIGGER IF EXISTS trg_listing_offer_version_guard")
    op.execute("DROP TRIGGER IF EXISTS trg_listing_offer_version_advance")
    op.execute(
        """
        CREATE TRIGGER trg_listing_offer_version_guard
        BEFORE UPDATE OF offer_version ON listing
        WHEN NEW.offer_version IS NOT OLD.offer_version
          AND NEW.base_price IS OLD.base_price
          AND NEW.operation IS OLD.operation
          AND NEW.deposit_amount_cop IS OLD.deposit_amount_cop
          AND NOT EXISTS (
              SELECT 1 FROM listing_offer_version_guard WHERE listing_id = OLD.id
          )
        BEGIN
            SELECT RAISE(ABORT, 'offer_version may only advance through offer changes');
        END
        """
    )
    op.execute(
        """
        CREATE TRIGGER trg_listing_offer_version_advance
        AFTER UPDATE ON listing
        WHEN NEW.base_price IS NOT OLD.base_price
          OR NEW.operation IS NOT OLD.operation
          OR NEW.deposit_amount_cop IS NOT OLD.deposit_amount_cop
        BEGIN
            INSERT OR IGNORE INTO listing_offer_version_guard (listing_id) VALUES (NEW.id);
            UPDATE listing SET offer_version = OLD.offer_version + 1 WHERE id = NEW.id;
            DELETE FROM listing_offer_version_guard WHERE listing_id = NEW.id;
        END
        """
    )


def _install_postgresql_deposit_offer_version_function() -> None:
    op.execute(
        """
        CREATE OR REPLACE FUNCTION roomforge_guard_listing_offer_version() RETURNS trigger
        LANGUAGE plpgsql AS $$
        BEGIN
            IF TG_OP = 'INSERT' THEN
                IF NEW.offer_version IS DISTINCT FROM 1 THEN
                    RAISE EXCEPTION 'new listings must start at offer_version 1'
                        USING ERRCODE = 'check_violation';
                END IF;
                RETURN NEW;
            END IF;

            IF NEW.id IS DISTINCT FROM OLD.id THEN
                RAISE EXCEPTION 'listing id is immutable'
                    USING ERRCODE = 'check_violation';
            END IF;

            IF NEW.base_price IS DISTINCT FROM OLD.base_price
               OR NEW.operation IS DISTINCT FROM OLD.operation
               OR NEW.deposit_amount_cop IS DISTINCT FROM OLD.deposit_amount_cop THEN
                NEW.offer_version := OLD.offer_version + 1;
            ELSIF NEW.offer_version IS DISTINCT FROM OLD.offer_version THEN
                -- An extra-row trigger nests this listing update at depth 2.
                IF pg_trigger_depth() < 2 THEN
                    RAISE EXCEPTION 'offer_version may only advance through offer changes'
                        USING ERRCODE = 'check_violation';
                END IF;
                NEW.offer_version := OLD.offer_version + 1;
            END IF;
            RETURN NEW;
        END;
        $$
        """
    )


def _install_listing_deposit_offer_version_triggers() -> None:
    dialect_name = op.get_bind().dialect.name
    if dialect_name == "sqlite":
        _install_sqlite_listing_deposit_guards()
        _install_sqlite_listing_deposit_scale_guards()
        _install_sqlite_deposit_offer_version_triggers()
    elif dialect_name == "postgresql":
        op.create_check_constraint(
            "ck_listing_deposit_amount_cop_positive",
            "listing",
            "deposit_amount_cop IS NULL OR deposit_amount_cop > 0",
        )
        op.create_check_constraint(
            "ck_listing_deposit_amount_cop_scale",
            "listing",
            "deposit_amount_cop IS NULL OR deposit_amount_cop = round(deposit_amount_cop, 2)",
        )
        _install_postgresql_deposit_offer_version_function()
    else:
        raise RuntimeError(
            "Listing deposit enforcement is unsupported for database dialect "
            f"{dialect_name!r}"
        )


def _restore_sqlite_offer_version_triggers() -> None:
    op.execute("DROP TRIGGER IF EXISTS trg_listing_offer_version_guard")
    op.execute("DROP TRIGGER IF EXISTS trg_listing_offer_version_advance")
    op.execute("DROP TRIGGER IF EXISTS trg_listing_deposit_amount_scale_update_guard")
    op.execute("DROP TRIGGER IF EXISTS trg_listing_deposit_amount_scale_insert_guard")
    op.execute("DROP TRIGGER IF EXISTS trg_listing_deposit_amount_update_guard")
    op.execute("DROP TRIGGER IF EXISTS trg_listing_deposit_amount_insert_guard")
    op.execute(
        """
        CREATE TRIGGER trg_listing_offer_version_guard
        BEFORE UPDATE OF offer_version ON listing
        WHEN NEW.offer_version IS NOT OLD.offer_version
          AND NEW.base_price IS OLD.base_price
          AND NEW.operation IS OLD.operation
          AND NOT EXISTS (
              SELECT 1 FROM listing_offer_version_guard WHERE listing_id = OLD.id
          )
        BEGIN
            SELECT RAISE(ABORT, 'offer_version may only advance through offer changes');
        END
        """
    )
    op.execute(
        """
        CREATE TRIGGER trg_listing_offer_version_advance
        AFTER UPDATE ON listing
        WHEN NEW.base_price IS NOT OLD.base_price OR NEW.operation IS NOT OLD.operation
        BEGIN
            INSERT OR IGNORE INTO listing_offer_version_guard (listing_id) VALUES (NEW.id);
            UPDATE listing SET offer_version = OLD.offer_version + 1 WHERE id = NEW.id;
            DELETE FROM listing_offer_version_guard WHERE listing_id = NEW.id;
        END
        """
    )


def _restore_postgresql_offer_version_function() -> None:
    op.execute(
        """
        CREATE OR REPLACE FUNCTION roomforge_guard_listing_offer_version() RETURNS trigger
        LANGUAGE plpgsql AS $$
        BEGIN
            IF TG_OP = 'INSERT' THEN
                IF NEW.offer_version IS DISTINCT FROM 1 THEN
                    RAISE EXCEPTION 'new listings must start at offer_version 1'
                        USING ERRCODE = 'check_violation';
                END IF;
                RETURN NEW;
            END IF;

            IF NEW.id IS DISTINCT FROM OLD.id THEN
                RAISE EXCEPTION 'listing id is immutable'
                    USING ERRCODE = 'check_violation';
            END IF;

            IF NEW.base_price IS DISTINCT FROM OLD.base_price
               OR NEW.operation IS DISTINCT FROM OLD.operation THEN
                NEW.offer_version := OLD.offer_version + 1;
            ELSIF NEW.offer_version IS DISTINCT FROM OLD.offer_version THEN
                -- An extra-row trigger nests this listing update at depth 2.
                IF pg_trigger_depth() < 2 THEN
                    RAISE EXCEPTION 'offer_version may only advance through offer changes'
                        USING ERRCODE = 'check_violation';
                END IF;
                NEW.offer_version := OLD.offer_version + 1;
            END IF;
            RETURN NEW;
        END;
        $$
        """
    )


def upgrade() -> None:
    op.add_column(
        "listing",
        sa.Column("deposit_amount_cop", sa.Numeric(precision=18, scale=2), nullable=True),
    )
    op.create_table(
        "agency_wallet",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column(
            "agency_id",
            sa.String(length=36),
            sa.ForeignKey("agency.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("address", sa.String(length=42), nullable=False),
        sa.Column("linked_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("address = lower(address)", name="ck_agency_wallet_address_canonical"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("agency_id", name="uq_agency_wallet_agency_id"),
        sa.UniqueConstraint("address", name="uq_agency_wallet_address"),
    )
    op.create_table(
        "agency_wallet_challenge",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column(
            "agency_id",
            sa.String(length=36),
            sa.ForeignKey("agency.id", ondelete="CASCADE"),
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
            "purpose = 'link-agency-wallet'", name="ck_agency_wallet_challenge_purpose"
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("nonce", name="uq_agency_wallet_challenge_nonce"),
    )
    op.create_index(
        "ix_agency_wallet_challenge_agency_id",
        "agency_wallet_challenge",
        ["agency_id"],
    )
    _install_listing_deposit_offer_version_triggers()


def downgrade() -> None:
    dialect_name = op.get_bind().dialect.name
    if dialect_name == "sqlite":
        _restore_sqlite_offer_version_triggers()
    elif dialect_name == "postgresql":
        _restore_postgresql_offer_version_function()
        op.drop_constraint(
            "ck_listing_deposit_amount_cop_scale", "listing", type_="check"
        )
        op.drop_constraint(
            "ck_listing_deposit_amount_cop_positive", "listing", type_="check"
        )
    else:
        raise RuntimeError(
            "Listing deposit enforcement is unsupported for database dialect "
            f"{dialect_name!r}"
        )

    op.drop_index(
        "ix_agency_wallet_challenge_agency_id", table_name="agency_wallet_challenge"
    )
    op.drop_table("agency_wallet_challenge")
    op.drop_table("agency_wallet")
    op.drop_column("listing", "deposit_amount_cop")
