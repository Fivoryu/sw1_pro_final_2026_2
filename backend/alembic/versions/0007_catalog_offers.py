"""Create public catalog listings and versioned offer data.

Revision ID: 0007_catalog_offers
Revises: 0006_customer_wallet
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0007_catalog_offers"
down_revision = "0006_customer_wallet"
branch_labels = None
depends_on = None


def _install_sqlite_offer_version_triggers() -> None:
    op.execute(
        """
        CREATE TABLE listing_offer_version_guard (
            listing_id VARCHAR(36) NOT NULL PRIMARY KEY
        )
        """
    )
    op.execute(
        """
        CREATE TRIGGER trg_listing_offer_insert_guard
        BEFORE INSERT ON listing
        WHEN NEW.offer_version IS NOT 1
          OR EXISTS (SELECT 1 FROM listing WHERE id = NEW.id)
        BEGIN
            SELECT RAISE(ABORT, 'listing insert must start at offer_version 1 and cannot replace');
        END
        """
    )
    op.execute(
        """
        CREATE TRIGGER trg_listing_offer_id_immutable
        BEFORE UPDATE OF id ON listing
        WHEN NEW.id IS NOT OLD.id
        BEGIN
            SELECT RAISE(ABORT, 'listing id is immutable');
        END
        """
    )
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
    op.execute(
        """
        CREATE TRIGGER trg_listing_extra_insert_guard
        BEFORE INSERT ON listing_extra
        WHEN EXISTS (SELECT 1 FROM listing_extra WHERE id = NEW.id)
        BEGIN
            SELECT RAISE(ABORT, 'listing_extra replacement inserts are unsupported');
        END
        """
    )
    op.execute(
        """
        CREATE TRIGGER trg_listing_extra_insert_offer_version
        AFTER INSERT ON listing_extra
        BEGIN
            INSERT OR IGNORE INTO listing_offer_version_guard (listing_id)
                VALUES (NEW.listing_id);
            UPDATE listing SET offer_version = offer_version + 1 WHERE id = NEW.listing_id;
            DELETE FROM listing_offer_version_guard WHERE listing_id = NEW.listing_id;
        END
        """
    )
    op.execute(
        """
        CREATE TRIGGER trg_listing_extra_update_offer_version
        AFTER UPDATE ON listing_extra
        WHEN OLD.id IS NOT NEW.id
          OR OLD.listing_id IS NOT NEW.listing_id
          OR OLD.name IS NOT NEW.name
          OR OLD.price IS NOT NEW.price
        BEGIN
            INSERT OR IGNORE INTO listing_offer_version_guard (listing_id)
                VALUES (OLD.listing_id);
            INSERT OR IGNORE INTO listing_offer_version_guard (listing_id)
                VALUES (NEW.listing_id);
            UPDATE listing SET offer_version = offer_version + 1 WHERE id = OLD.listing_id;
            UPDATE listing SET offer_version = offer_version + 1
                WHERE id = NEW.listing_id AND NEW.listing_id IS NOT OLD.listing_id;
            DELETE FROM listing_offer_version_guard WHERE listing_id = OLD.listing_id;
            DELETE FROM listing_offer_version_guard WHERE listing_id = NEW.listing_id;
        END
        """
    )
    op.execute(
        """
        CREATE TRIGGER trg_listing_extra_delete_offer_version
        AFTER DELETE ON listing_extra
        BEGIN
            INSERT OR IGNORE INTO listing_offer_version_guard (listing_id)
                VALUES (OLD.listing_id);
            UPDATE listing SET offer_version = offer_version + 1 WHERE id = OLD.listing_id;
            DELETE FROM listing_offer_version_guard WHERE listing_id = OLD.listing_id;
        END
        """
    )


def _install_postgresql_offer_version_triggers() -> None:
    op.execute(
        """
        CREATE FUNCTION roomforge_guard_listing_offer_version() RETURNS trigger
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
    op.execute(
        """
        CREATE FUNCTION roomforge_bump_listing_offer_from_extra() RETURNS trigger
        LANGUAGE plpgsql AS $$
        BEGIN
            IF TG_OP = 'INSERT' THEN
                UPDATE listing SET offer_version = offer_version + 1
                    WHERE id = NEW.listing_id;
                RETURN NEW;
            ELSIF TG_OP = 'DELETE' THEN
                UPDATE listing SET offer_version = offer_version + 1
                    WHERE id = OLD.listing_id;
                RETURN OLD;
            END IF;

            UPDATE listing SET offer_version = offer_version + 1
                WHERE id = OLD.listing_id;
            IF NEW.listing_id IS DISTINCT FROM OLD.listing_id THEN
                UPDATE listing SET offer_version = offer_version + 1
                    WHERE id = NEW.listing_id;
            END IF;
            RETURN NEW;
        END;
        $$
        """
    )
    op.execute(
        """
        CREATE FUNCTION roomforge_bump_offers_before_extra_truncate() RETURNS trigger
        LANGUAGE plpgsql AS $$
        BEGIN
            UPDATE listing SET offer_version = offer_version + 1
                WHERE id IN (SELECT DISTINCT listing_id FROM listing_extra);
            RETURN NULL;
        END;
        $$
        """
    )
    op.execute(
        """
        CREATE TRIGGER trg_listing_offer_version_guard
        BEFORE INSERT OR UPDATE ON listing
        FOR EACH ROW EXECUTE FUNCTION roomforge_guard_listing_offer_version()
        """
    )
    op.execute(
        """
        CREATE TRIGGER trg_listing_extra_offer_insert
        AFTER INSERT ON listing_extra
        FOR EACH ROW EXECUTE FUNCTION roomforge_bump_listing_offer_from_extra()
        """
    )
    op.execute(
        """
        CREATE TRIGGER trg_listing_extra_offer_update
        AFTER UPDATE ON listing_extra
        FOR EACH ROW
        WHEN (OLD.id IS DISTINCT FROM NEW.id
              OR OLD.listing_id IS DISTINCT FROM NEW.listing_id
              OR OLD.name IS DISTINCT FROM NEW.name
              OR OLD.price IS DISTINCT FROM NEW.price)
        EXECUTE FUNCTION roomforge_bump_listing_offer_from_extra()
        """
    )
    op.execute(
        """
        CREATE TRIGGER trg_listing_extra_offer_delete
        AFTER DELETE ON listing_extra
        FOR EACH ROW EXECUTE FUNCTION roomforge_bump_listing_offer_from_extra()
        """
    )
    op.execute(
        """
        CREATE TRIGGER trg_listing_extra_offer_truncate
        BEFORE TRUNCATE ON listing_extra
        FOR EACH STATEMENT EXECUTE FUNCTION roomforge_bump_offers_before_extra_truncate()
        """
    )


def _install_offer_version_triggers() -> None:
    dialect_name = op.get_bind().dialect.name
    if dialect_name == "sqlite":
        _install_sqlite_offer_version_triggers()
    elif dialect_name == "postgresql":
        _install_postgresql_offer_version_triggers()
    else:
        raise RuntimeError(
            f"Offer-version enforcement is unsupported for database dialect {dialect_name!r}"
        )


def _drop_offer_version_triggers() -> None:
    dialect_name = op.get_bind().dialect.name
    if dialect_name == "sqlite":
        for trigger_name in (
            "trg_listing_extra_delete_offer_version",
            "trg_listing_extra_update_offer_version",
            "trg_listing_extra_insert_offer_version",
            "trg_listing_extra_insert_guard",
            "trg_listing_offer_version_advance",
            "trg_listing_offer_version_guard",
            "trg_listing_offer_id_immutable",
            "trg_listing_offer_insert_guard",
        ):
            op.execute(f"DROP TRIGGER IF EXISTS {trigger_name}")
        op.execute("DROP TABLE listing_offer_version_guard")
    elif dialect_name == "postgresql":
        for trigger_name, table_name in (
            ("trg_listing_extra_offer_truncate", "listing_extra"),
            ("trg_listing_extra_offer_delete", "listing_extra"),
            ("trg_listing_extra_offer_update", "listing_extra"),
            ("trg_listing_extra_offer_insert", "listing_extra"),
            ("trg_listing_offer_version_guard", "listing"),
        ):
            op.execute(f"DROP TRIGGER IF EXISTS {trigger_name} ON {table_name}")
        op.execute("DROP FUNCTION IF EXISTS roomforge_bump_offers_before_extra_truncate()")
        op.execute("DROP FUNCTION IF EXISTS roomforge_bump_listing_offer_from_extra()")
        op.execute("DROP FUNCTION IF EXISTS roomforge_guard_listing_offer_version()")
    else:
        raise RuntimeError(
            f"Offer-version enforcement is unsupported for database dialect {dialect_name!r}"
        )


def upgrade() -> None:
    op.create_table(
        "listing",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column(
            "agency_id",
            sa.String(length=36),
            sa.ForeignKey("agency.id"),
            nullable=False,
        ),
        sa.Column(
            "approval_status",
            sa.String(length=16),
            nullable=False,
            server_default="draft",
        ),
        sa.Column(
            "is_published",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
        sa.Column("operation", sa.String(length=8), nullable=False),
        sa.Column("base_price", sa.Numeric(precision=18, scale=2), nullable=False),
        sa.Column("offer_version", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("city", sa.String(length=120), nullable=False),
        sa.Column("city_key", sa.String(length=360), nullable=False),
        sa.Column("zone", sa.String(length=120), nullable=False),
        sa.Column("zone_key", sa.String(length=360), nullable=False),
        sa.Column("bedrooms", sa.Integer(), nullable=False),
        sa.Column("bathrooms", sa.Integer(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("exact_address", sa.Text(), nullable=True),
        sa.Column("photos", sa.JSON(), nullable=True),
        sa.CheckConstraint(
            "approval_status IN ('draft', 'pending', 'approved', 'rejected')",
            name="ck_listing_approval_status",
        ),
        sa.CheckConstraint("operation IN ('sale', 'rent')", name="ck_listing_operation"),
        sa.CheckConstraint("base_price >= 0", name="ck_listing_base_price_nonnegative"),
        sa.CheckConstraint("offer_version >= 1", name="ck_listing_offer_version_positive"),
        sa.CheckConstraint("bedrooms >= 0", name="ck_listing_bedrooms_nonnegative"),
        sa.CheckConstraint("bathrooms >= 0", name="ck_listing_bathrooms_nonnegative"),
    )
    op.create_index(
        "ix_listing_public_created_at_id",
        "listing",
        ["approval_status", "is_published", "created_at", "id"],
    )
    op.create_index("ix_listing_city_key", "listing", ["city_key"])
    op.create_index("ix_listing_zone_key", "listing", ["zone_key"])

    op.create_table(
        "listing_extra",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column(
            "listing_id",
            sa.String(length=36),
            sa.ForeignKey("listing.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("price", sa.Numeric(precision=18, scale=2), nullable=False),
        sa.CheckConstraint("price >= 0", name="ck_listing_extra_price_nonnegative"),
        sa.CheckConstraint("length(trim(name)) > 0", name="ck_listing_extra_name_nonblank"),
    )
    op.create_index("ix_listing_extra_listing_id", "listing_extra", ["listing_id"])
    _install_offer_version_triggers()


def downgrade() -> None:
    _drop_offer_version_triggers()
    op.drop_index("ix_listing_extra_listing_id", table_name="listing_extra")
    op.drop_table("listing_extra")
    op.drop_index("ix_listing_zone_key", table_name="listing")
    op.drop_index("ix_listing_city_key", table_name="listing")
    op.drop_index("ix_listing_public_created_at_id", table_name="listing")
    op.drop_table("listing")
