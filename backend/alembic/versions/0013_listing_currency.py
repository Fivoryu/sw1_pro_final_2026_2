"""Add per-listing currency and currency-neutral deposit names.

Revision ID: 0013_listing_currency
Revises: 0012_listing_transitions
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0013_listing_currency"
down_revision = "0012_listing_transitions"
branch_labels = None
depends_on = None

_SUPPORTED_CURRENCY_CHECK = "currency IN ('BOB', 'USD', 'USDT')"


def _drop_listing_triggers() -> None:
    if op.get_bind().dialect.name == "sqlite":
        for trigger_name in (
            "trg_listing_deposit_amount_scale_update_guard",
            "trg_listing_deposit_amount_scale_insert_guard",
            "trg_listing_deposit_amount_update_guard",
            "trg_listing_deposit_amount_insert_guard",
            "trg_listing_offer_version_advance",
            "trg_listing_offer_version_guard",
            "trg_listing_offer_id_immutable",
            "trg_listing_offer_insert_guard",
        ):
            op.execute(f"DROP TRIGGER IF EXISTS {trigger_name}")


def _install_sqlite_listing_currency_triggers() -> None:
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
          AND NEW.deposit_amount IS OLD.deposit_amount
          AND NEW.currency IS OLD.currency
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
          OR NEW.deposit_amount IS NOT OLD.deposit_amount
          OR NEW.currency IS NOT OLD.currency
        BEGIN
            INSERT OR IGNORE INTO listing_offer_version_guard (listing_id) VALUES (NEW.id);
            UPDATE listing SET offer_version = OLD.offer_version + 1 WHERE id = NEW.id;
            DELETE FROM listing_offer_version_guard WHERE listing_id = NEW.id;
        END
        """
    )
    op.execute(
        """
        CREATE TRIGGER trg_listing_deposit_amount_insert_guard
        BEFORE INSERT ON listing
        WHEN NEW.deposit_amount IS NOT NULL AND NEW.deposit_amount <= 0
        BEGIN
            SELECT RAISE(ABORT, 'listing deposit amount must be positive');
        END
        """
    )
    op.execute(
        """
        CREATE TRIGGER trg_listing_deposit_amount_update_guard
        BEFORE UPDATE OF deposit_amount ON listing
        WHEN NEW.deposit_amount IS NOT NULL AND NEW.deposit_amount <= 0
        BEGIN
            SELECT RAISE(ABORT, 'listing deposit amount must be positive');
        END
        """
    )
    op.execute(
        """
        CREATE TRIGGER trg_listing_deposit_amount_scale_insert_guard
        BEFORE INSERT ON listing
        WHEN NEW.deposit_amount IS NOT NULL
          AND NEW.deposit_amount != ROUND(NEW.deposit_amount, 2)
        BEGIN
            SELECT RAISE(ABORT, 'listing deposit amount must have at most two decimals');
        END
        """
    )
    op.execute(
        """
        CREATE TRIGGER trg_listing_deposit_amount_scale_update_guard
        BEFORE UPDATE OF deposit_amount ON listing
        WHEN NEW.deposit_amount IS NOT NULL
          AND NEW.deposit_amount != ROUND(NEW.deposit_amount, 2)
        BEGIN
            SELECT RAISE(ABORT, 'listing deposit amount must have at most two decimals');
        END
        """
    )


def _install_postgresql_listing_currency_function() -> None:
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
               OR NEW.deposit_amount IS DISTINCT FROM OLD.deposit_amount
               OR NEW.currency IS DISTINCT FROM OLD.currency THEN
                NEW.offer_version := OLD.offer_version + 1;
            ELSIF NEW.offer_version IS DISTINCT FROM OLD.offer_version THEN
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


def _install_listing_currency_triggers() -> None:
    dialect_name = op.get_bind().dialect.name
    if dialect_name == "sqlite":
        _drop_listing_triggers()
        _install_sqlite_listing_currency_triggers()
    elif dialect_name == "postgresql":
        _install_postgresql_listing_currency_function()
    else:
        raise RuntimeError(
            "Listing currency enforcement is unsupported for database dialect "
            f"{dialect_name!r}"
        )


def _install_legacy_listing_triggers() -> None:
    dialect_name = op.get_bind().dialect.name
    if dialect_name == "sqlite":
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
        for trigger_name, timing, condition in (
            (
                "trg_listing_deposit_amount_insert_guard",
                "INSERT",
                "NEW.deposit_amount_cop IS NOT NULL AND NEW.deposit_amount_cop <= 0",
            ),
            (
                "trg_listing_deposit_amount_update_guard",
                "UPDATE OF deposit_amount_cop",
                "NEW.deposit_amount_cop IS NOT NULL AND NEW.deposit_amount_cop <= 0",
            ),
            (
                "trg_listing_deposit_amount_scale_insert_guard",
                "INSERT",
                "NEW.deposit_amount_cop IS NOT NULL AND "
                "NEW.deposit_amount_cop != ROUND(NEW.deposit_amount_cop, 2)",
            ),
            (
                "trg_listing_deposit_amount_scale_update_guard",
                "UPDATE OF deposit_amount_cop",
                "NEW.deposit_amount_cop IS NOT NULL AND "
                "NEW.deposit_amount_cop != ROUND(NEW.deposit_amount_cop, 2)",
            ),
        ):
            message = (
                "listing deposit amount must have at most two decimals"
                if "scale" in trigger_name
                else "listing deposit amount must be positive"
            )
            op.execute(
                f"CREATE TRIGGER {trigger_name} BEFORE {timing} ON listing "
                f"WHEN {condition} BEGIN SELECT RAISE(ABORT, '{message}'); END"
            )
    elif dialect_name == "postgresql":
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
    else:
        raise RuntimeError(
            "Listing trigger restoration is unsupported for database dialect "
            f"{dialect_name!r}"
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


def _detach_sqlite_inbound_tables(table_name: str) -> list[tuple[str, str, str, list[str]]]:
    bind = op.get_bind()
    if bind.dialect.name != "sqlite":
        return []

    inspector = sa.inspect(bind)
    preparer = bind.dialect.identifier_preparer
    table_names = inspector.get_table_names()
    foreign_keys = {
        name: inspector.get_foreign_keys(name) for name in table_names if name != table_name
    }
    drop_order: list[str] = []
    visited: set[str] = set()

    def visit(parent_name: str) -> None:
        for child_name, references in foreign_keys.items():
            if child_name not in visited and any(
                foreign_key.get("referred_table") == parent_name for foreign_key in references
            ):
                visit(child_name)
                visited.add(child_name)
                drop_order.append(child_name)

    visit(table_name)
    detached: list[tuple[str, str, str, list[str]]] = []
    for child_name in drop_order:
        table_sql = bind.execute(
            sa.text(
                "SELECT sql FROM sqlite_master "
                "WHERE type = 'table' AND name = :table_name"
            ),
            {"table_name": child_name},
        ).scalar_one()
        object_sql = bind.execute(
            sa.text(
                "SELECT sql FROM sqlite_master "
                "WHERE tbl_name = :table_name AND type IN ('index', 'trigger') "
                "AND sql IS NOT NULL ORDER BY type, name"
            ),
            {"table_name": child_name},
        ).scalars().all()
        backup_name = f"roomforge_currency_backup_{child_name}"
        quoted_child = preparer.quote(child_name)
        quoted_backup = preparer.quote(backup_name)
        bind.exec_driver_sql(
            f"CREATE TABLE {quoted_backup} AS SELECT * FROM {quoted_child}"
        )
        bind.exec_driver_sql(f"DROP TABLE {quoted_child}")
        detached.append((child_name, backup_name, table_sql, list(object_sql)))
    return detached


def _restore_sqlite_inbound_tables(
    detached: list[tuple[str, str, str, list[str]]],
) -> None:
    bind = op.get_bind()
    preparer = bind.dialect.identifier_preparer
    for table_name, backup_name, table_sql, object_sql in reversed(detached):
        quoted_table = preparer.quote(table_name)
        quoted_backup = preparer.quote(backup_name)
        bind.exec_driver_sql(table_sql)
        bind.exec_driver_sql(f"INSERT INTO {quoted_table} SELECT * FROM {quoted_backup}")
        bind.exec_driver_sql(f"DROP TABLE {quoted_backup}")
        for statement in object_sql:
            bind.exec_driver_sql(statement)


def _rewrite_snapshot_line_currencies(old_currency: str, new_currency: str) -> None:
    bind = op.get_bind()
    for table_name, column_name in (
        ("quote_snapshot", "lines"),
        ("reservation", "quote_lines"),
    ):
        table = sa.table(
            table_name,
            sa.column("id", sa.String(length=36)),
            sa.column(column_name, sa.JSON()),
        )
        rows = bind.execute(sa.select(table.c.id, table.c[column_name])).all()
        for row_id, lines in rows:
            if not isinstance(lines, list):
                continue
            rewritten: list[object] = []
            changed = False
            for line in lines:
                if isinstance(line, dict) and line.get("currency") == old_currency:
                    rewritten.append({**line, "currency": new_currency})
                    changed = True
                else:
                    rewritten.append(line)
            if changed:
                bind.execute(
                    sa.update(table)
                    .where(table.c.id == row_id)
                    .values({column_name: rewritten})
                )


def _assert_downgrade_is_lossless() -> None:
    bind = op.get_bind()
    for table_name in ("listing", "quote_snapshot"):
        currencies = bind.execute(
            sa.text(f"SELECT DISTINCT currency FROM {table_name}")
        ).scalars()
        if any(currency != "BOB" for currency in currencies):
            raise RuntimeError(
                "Cannot downgrade currency data other than BOB to the legacy COP schema."
            )

    reservations = sa.table(
        "reservation",
        sa.column("id", sa.String(length=36)),
        sa.column("quote_lines", sa.JSON()),
    )
    for lines, in bind.execute(sa.select(reservations.c.quote_lines)):
        if isinstance(lines, list) and any(
            isinstance(line, dict)
            and line.get("currency") not in {None, "BOB"}
            for line in lines
        ):
            raise RuntimeError(
                "Cannot downgrade reservation snapshots outside the legacy COP currency."
            )


def upgrade() -> None:
    dialect_name = op.get_bind().dialect.name
    if dialect_name not in {"sqlite", "postgresql"}:
        raise RuntimeError(f"Unsupported currency migration dialect {dialect_name!r}")
    detached_listing_tables = _detach_sqlite_inbound_tables("listing")
    _drop_listing_triggers()
    with op.batch_alter_table("listing") as batch_op:
        batch_op.drop_constraint("ck_listing_deposit_amount_cop_positive", type_="check")
        batch_op.drop_constraint("ck_listing_deposit_amount_cop_scale", type_="check")
        batch_op.alter_column(
            "deposit_amount_cop",
            new_column_name="deposit_amount",
            existing_type=sa.Numeric(precision=18, scale=2),
        )
        batch_op.add_column(
            sa.Column(
                "currency",
                sa.String(length=4),
                nullable=False,
                server_default=sa.text("'BOB'"),
            )
        )
        batch_op.create_check_constraint("ck_listing_currency_supported", _SUPPORTED_CURRENCY_CHECK)
        batch_op.create_check_constraint(
            "ck_listing_deposit_amount_positive",
            "deposit_amount IS NULL OR deposit_amount > 0",
        )
        batch_op.create_check_constraint(
            "ck_listing_deposit_amount_scale",
            "deposit_amount IS NULL OR deposit_amount = round(deposit_amount, 2)",
        )
    _restore_sqlite_inbound_tables(detached_listing_tables)

    op.add_column(
        "quote_snapshot",
        sa.Column(
            "currency",
            sa.String(length=4),
            nullable=False,
            server_default=sa.text("'BOB'"),
        ),
    )
    _drop_snapshot_immutability()
    # Existing COP development amounts are relabeled 1:1 as BOB; no FX conversion is applied.
    _rewrite_snapshot_line_currencies("COP", "BOB")

    detached_tables = _detach_sqlite_inbound_tables("reservation")
    with op.batch_alter_table("reservation") as batch_op:
        batch_op.drop_constraint("ck_reservation_deposit_amount_cop_positive", type_="check")
        batch_op.drop_constraint("ck_reservation_deposit_amount_cop_scale", type_="check")
        batch_op.alter_column(
            "deposit_amount_cop",
            new_column_name="deposit_amount",
            existing_type=sa.Numeric(precision=18, scale=2),
        )
        batch_op.create_check_constraint(
            "ck_reservation_deposit_amount_positive",
            "deposit_amount IS NULL OR deposit_amount > 0",
        )
        batch_op.create_check_constraint(
            "ck_reservation_deposit_amount_scale",
            "deposit_amount IS NULL OR deposit_amount = round(deposit_amount, 2)",
        )
    _restore_sqlite_inbound_tables(detached_tables)

    _install_listing_currency_triggers()
    _install_snapshot_immutability()


def downgrade() -> None:
    dialect_name = op.get_bind().dialect.name
    if dialect_name not in {"sqlite", "postgresql"}:
        raise RuntimeError(f"Unsupported currency migration dialect {dialect_name!r}")
    _assert_downgrade_is_lossless()

    _drop_listing_triggers()
    _drop_snapshot_immutability()
    _rewrite_snapshot_line_currencies("BOB", "COP")

    detached_tables = _detach_sqlite_inbound_tables("reservation")
    with op.batch_alter_table("reservation") as batch_op:
        batch_op.drop_constraint("ck_reservation_deposit_amount_positive", type_="check")
        batch_op.drop_constraint("ck_reservation_deposit_amount_scale", type_="check")
        batch_op.alter_column(
            "deposit_amount",
            new_column_name="deposit_amount_cop",
            existing_type=sa.Numeric(precision=18, scale=2),
        )
        batch_op.create_check_constraint(
            "ck_reservation_deposit_amount_cop_positive",
            "deposit_amount_cop IS NULL OR deposit_amount_cop > 0",
        )
        batch_op.create_check_constraint(
            "ck_reservation_deposit_amount_cop_scale",
            "deposit_amount_cop IS NULL OR deposit_amount_cop = round(deposit_amount_cop, 2)",
        )
    _restore_sqlite_inbound_tables(detached_tables)

    op.drop_column("quote_snapshot", "currency")
    detached_listing_tables = _detach_sqlite_inbound_tables("listing")
    with op.batch_alter_table("listing") as batch_op:
        batch_op.drop_constraint("ck_listing_currency_supported", type_="check")
        batch_op.drop_constraint("ck_listing_deposit_amount_positive", type_="check")
        batch_op.drop_constraint("ck_listing_deposit_amount_scale", type_="check")
        batch_op.drop_column("currency")
        batch_op.alter_column(
            "deposit_amount",
            new_column_name="deposit_amount_cop",
            existing_type=sa.Numeric(precision=18, scale=2),
        )
        batch_op.create_check_constraint(
            "ck_listing_deposit_amount_cop_positive",
            "deposit_amount_cop IS NULL OR deposit_amount_cop > 0",
        )
        batch_op.create_check_constraint(
            "ck_listing_deposit_amount_cop_scale",
            "deposit_amount_cop IS NULL OR deposit_amount_cop = round(deposit_amount_cop, 2)",
        )
    _restore_sqlite_inbound_tables(detached_listing_tables)

    _install_legacy_listing_triggers()
    _install_snapshot_immutability()
