from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType

from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.engine import Connection


_MIGRATION = Path(__file__).resolve().parents[1] / "alembic" / "versions" / "0028_extra_inclusion.py"


def _load_migration() -> ModuleType:
    spec = importlib.util.spec_from_file_location("extra_inclusion_migration", _MIGRATION)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _run(connection: Connection, module: ModuleType, step: str) -> None:
    with Operations.context(MigrationContext.configure(connection)):
        getattr(module, step)()


def _prepare_pre_inclusion_table(connection: Connection) -> None:
    connection.execute(
        text(
            "CREATE TABLE listing_extra "
            "(id TEXT PRIMARY KEY, listing_id TEXT NOT NULL, name TEXT NOT NULL, price NUMERIC NOT NULL)"
        )
    )
    connection.execute(
        text(
            "CREATE TRIGGER trg_listing_extra_probe AFTER INSERT ON listing_extra "
            "BEGIN SELECT 1; END"
        )
    )
    connection.execute(
        text("INSERT INTO listing_extra (id, listing_id, name, price) VALUES ('e1', 'l1', 'Sofa', 10)")
    )


def test_revision_chain_continues_the_single_head() -> None:
    module = _load_migration()

    assert module.revision == "0028_extra_inclusion"
    assert module.down_revision == "0027_merge_f09_heads"


def test_upgrade_keeps_existing_extras_optional_and_the_offer_version_triggers() -> None:
    module = _load_migration()
    engine = create_engine("sqlite://")
    with engine.begin() as connection:
        _prepare_pre_inclusion_table(connection)

        _run(connection, module, "upgrade")

        columns = {column["name"]: column for column in inspect(connection).get_columns("listing_extra")}
        assert "inclusion" in columns
        assert columns["inclusion"]["nullable"] is False
        assert connection.execute(text("SELECT inclusion FROM listing_extra WHERE id = 'e1'")).scalar_one() == "optional"
        # Batch mode would rebuild the table and silently drop this trigger.
        triggers = connection.execute(
            text("SELECT name FROM sqlite_master WHERE type = 'trigger'")
        ).scalars().all()
        assert "trg_listing_extra_probe" in triggers


def test_downgrade_removes_the_column() -> None:
    module = _load_migration()
    engine = create_engine("sqlite://")
    with engine.begin() as connection:
        _prepare_pre_inclusion_table(connection)
        _run(connection, module, "upgrade")

        _run(connection, module, "downgrade")

        columns = {column["name"] for column in inspect(connection).get_columns("listing_extra")}
        assert "inclusion" not in columns
