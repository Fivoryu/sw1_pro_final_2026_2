"""Add furniture details and quantity to listing extras.

Revision ID: 0016_listing_extra_details
Revises: 0015_quote_display_currency
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0016_listing_extra_details"
down_revision = "0015_quote_display_currency"
branch_labels = None
depends_on = None

_SQLITE_EXTRA_TRIGGERS = (
    "trg_listing_extra_delete_offer_version",
    "trg_listing_extra_update_offer_version",
    "trg_listing_extra_insert_offer_version",
    "trg_listing_extra_insert_guard",
)


def _drop_sqlite_extra_triggers() -> None:
    for trigger_name in _SQLITE_EXTRA_TRIGGERS:
        op.execute(f"DROP TRIGGER IF EXISTS {trigger_name}")


def _install_sqlite_extra_triggers(*, quantity_aware: bool) -> None:
    """Recreate the 0007 extra triggers; `quantity_aware` extends the update rule."""
    quantity_condition = "\n          OR OLD.quantity IS NOT NEW.quantity" if quantity_aware else ""
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
        f"""
        CREATE TRIGGER trg_listing_extra_update_offer_version
        AFTER UPDATE ON listing_extra
        WHEN OLD.id IS NOT NEW.id
          OR OLD.listing_id IS NOT NEW.listing_id
          OR OLD.name IS NOT NEW.name
          OR OLD.price IS NOT NEW.price{quantity_condition}
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


def _drop_postgresql_extra_triggers() -> None:
    for trigger_name in (
        "trg_listing_extra_offer_truncate",
        "trg_listing_extra_offer_delete",
        "trg_listing_extra_offer_update",
        "trg_listing_extra_offer_insert",
    ):
        op.execute(f"DROP TRIGGER IF EXISTS {trigger_name} ON listing_extra")


def _install_postgresql_extra_triggers(*, quantity_aware: bool) -> None:
    """Recreate the 0007 extra triggers; `quantity_aware` extends the update rule."""
    quantity_condition = (
        "\n              OR OLD.quantity IS DISTINCT FROM NEW.quantity" if quantity_aware else ""
    )
    op.execute(
        """
        CREATE TRIGGER trg_listing_extra_offer_insert
        AFTER INSERT ON listing_extra
        FOR EACH ROW EXECUTE FUNCTION roomforge_bump_listing_offer_from_extra()
        """
    )
    op.execute(
        f"""
        CREATE TRIGGER trg_listing_extra_offer_update
        AFTER UPDATE ON listing_extra
        FOR EACH ROW
        WHEN (OLD.id IS DISTINCT FROM NEW.id
              OR OLD.listing_id IS DISTINCT FROM NEW.listing_id
              OR OLD.name IS DISTINCT FROM NEW.name
              OR OLD.price IS DISTINCT FROM NEW.price{quantity_condition})
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


def _install_legacy_postgresql_extra_update_trigger() -> None:
    _install_postgresql_extra_triggers(quantity_aware=False)


def _install_legacy_sqlite_extra_update_trigger() -> None:
    _install_sqlite_extra_triggers(quantity_aware=False)


def upgrade() -> None:
    dialect_name = op.get_bind().dialect.name
    if dialect_name == "sqlite":
        _drop_sqlite_extra_triggers()
    elif dialect_name == "postgresql":
        _drop_postgresql_extra_triggers()
    else:
        raise RuntimeError(
            "Listing extra details are unsupported for database dialect "
            f"{dialect_name!r}"
        )

    with op.batch_alter_table("listing_extra") as batch_op:
        batch_op.add_column(sa.Column("category", sa.String(length=32), nullable=True))
        batch_op.add_column(sa.Column("room", sa.String(length=32), nullable=True))
        batch_op.add_column(sa.Column("width_cm", sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column("height_cm", sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column("depth_cm", sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column("origin", sa.String(length=120), nullable=True))
        batch_op.add_column(
            sa.Column("visual_reference", sa.String(length=255), nullable=True)
        )
        batch_op.add_column(
            sa.Column(
                "quantity",
                sa.Integer(),
                nullable=False,
                server_default=sa.text("1"),
            )
        )
        batch_op.create_check_constraint(
            "ck_listing_extra_quantity_positive", "quantity >= 1"
        )
        batch_op.create_check_constraint(
            "ck_listing_extra_dimensions_positive",
            "(width_cm IS NULL OR width_cm > 0) AND (height_cm IS NULL OR height_cm > 0) "
            "AND (depth_cm IS NULL OR depth_cm > 0)",
        )
        batch_op.create_check_constraint(
            "ck_listing_extra_optional_text_nonblank",
            "(category IS NULL OR length(trim(category)) > 0) "
            "AND (room IS NULL OR length(trim(room)) > 0) "
            "AND (origin IS NULL OR length(trim(origin)) > 0) "
            "AND (visual_reference IS NULL OR length(trim(visual_reference)) > 0)",
        )

    if dialect_name == "sqlite":
        _install_sqlite_extra_triggers(quantity_aware=True)
    else:
        _install_postgresql_extra_triggers(quantity_aware=True)


def downgrade() -> None:
    dialect_name = op.get_bind().dialect.name
    if dialect_name not in {"sqlite", "postgresql"}:
        raise RuntimeError(
            "Listing extra details are unsupported for database dialect "
            f"{dialect_name!r}"
        )

    if dialect_name == "sqlite":
        _drop_sqlite_extra_triggers()
    else:
        _drop_postgresql_extra_triggers()

    with op.batch_alter_table("listing_extra") as batch_op:
        batch_op.drop_constraint("ck_listing_extra_optional_text_nonblank", type_="check")
        batch_op.drop_constraint("ck_listing_extra_dimensions_positive", type_="check")
        batch_op.drop_constraint("ck_listing_extra_quantity_positive", type_="check")
        batch_op.drop_column("quantity")
        batch_op.drop_column("visual_reference")
        batch_op.drop_column("origin")
        batch_op.drop_column("depth_cm")
        batch_op.drop_column("height_cm")
        batch_op.drop_column("width_cm")
        batch_op.drop_column("room")
        batch_op.drop_column("category")

    if dialect_name == "sqlite":
        _install_legacy_sqlite_extra_update_trigger()
    else:
        _install_legacy_postgresql_extra_update_trigger()
