from __future__ import annotations

from collections.abc import Iterable
import importlib.util
import ipaddress
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator
from unittest.mock import patch

import pytest
from alembic import command
from alembic.config import Config
from alembic.operations import Operations
from alembic.runtime.migration import MigrationContext
from sqlalchemy import (
    Column,
    Engine,
    MetaData,
    String,
    Table,
    create_engine,
    inspect,
    insert,
    text,
)
from sqlalchemy.engine import Connection, URL, make_url
from sqlalchemy.engine.reflection import Inspector
from sqlalchemy.exc import IntegrityError
from sqlalchemy.schema import CheckConstraint, UniqueConstraint

from app.db.base import Base
from app.modules.identity import models as identity_models  # noqa: F401

_BACKEND_ROOT = Path(__file__).resolve().parents[1]
_R6_DATABASE_PREFIX = "roomforge_r6_"
_R6_ENGINE_INFO_KEY = "roomforge.r6.isolated_engine"


@dataclass(frozen=True)
class R6Database:
    engine: Engine
    started_blank: bool


def _validated_r6_url() -> URL:
    raw_url = os.environ.get("ROOMFORGE_R6_DATABASE_URL")
    if not raw_url:
        pytest.skip("ROOMFORGE_R6_DATABASE_URL is unset")

    try:
        url = make_url(raw_url)
    except Exception:
        pytest.fail("ROOMFORGE_R6_DATABASE_URL is not a valid SQLAlchemy URL")

    host = url.host
    try:
        is_loopback = host is not None and ipaddress.ip_address(host).is_loopback
    except ValueError:
        is_loopback = host == "localhost"
    if url.drivername != "postgresql+psycopg" or not is_loopback or url.port is None:
        pytest.fail("R6 tests require postgresql+psycopg on an explicit loopback host and port")
    if not url.database or not url.database.startswith(_R6_DATABASE_PREFIX):
        pytest.fail(f"R6 tests require a fresh database named with prefix {_R6_DATABASE_PREFIX!r}")
    return url



def _upgrade_fresh_database(url: URL) -> R6Database:
    engine = create_engine(url, pool_pre_ping=True)
    try:
        table_names = set(inspect(engine).get_table_names())
        if table_names:
            pytest.fail("R6 migration tests require a fresh, completely blank database")
        connection_url = url.render_as_string(hide_password=False)
        config = Config(str(_BACKEND_ROOT / "alembic.ini"))
        config.set_main_option("script_location", str(_BACKEND_ROOT / "alembic"))
        config.set_main_option("sqlalchemy.url", connection_url.replace("%", "%%"))
        # env.py honors DATABASE_URL, so bind it only to this validated disposable URL.
        with patch.dict(os.environ, {"DATABASE_URL": connection_url}):
            command.upgrade(config, "head")
        return R6Database(engine=engine, started_blank=True)
    except BaseException:
        engine.dispose()
        raise


@pytest.fixture(scope="session")
def r6_database() -> Iterator[R6Database]:
    database = _upgrade_fresh_database(_validated_r6_url())
    Base.metadata.info[_R6_ENGINE_INFO_KEY] = database.engine
    try:
        yield database
    finally:
        Base.metadata.info.pop(_R6_ENGINE_INFO_KEY, None)
        database.engine.dispose()


def _normalize_sql(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = value.lower().replace('"', "")
    normalized = re.sub(r"\b[a-z_][a-z0-9_]*\.", "", normalized)
    normalized = re.sub(r"::\s*(?:character varying|varchar|text)(?:\(\d+\))?", "", normalized)
    normalized = re.sub(
        r"=\s*any\s*\(\s*array\s*\[(.*?)\]\s*(?:\[\])?\s*\)",
        r"in (\1)",
        normalized,
    )
    normalized = normalized.replace("(", " ").replace(")", " ")
    return " ".join(normalized.split())


def _expected_default(column: Column[object], engine: Engine) -> str | None:
    server_default = getattr(column, "server_default")
    if server_default is None:
        return None
    compiled = server_default.arg.compile(
        dialect=engine.dialect, compile_kwargs={"literal_binds": True}
    )
    return _normalize_sql(str(compiled))


def _required_names(names: Iterable[str | None], context: str) -> tuple[str, ...]:
    resolved_names = tuple(names)
    if any(name is None for name in resolved_names):
        raise AssertionError(f"{context} must use named columns")
    return tuple(name for name in resolved_names if name is not None)


def _metadata_unique_keys(table: Table, engine: Engine) -> set[tuple[tuple[str, ...], str | None]]:
    keys: set[tuple[tuple[str, ...], str | None]] = set()
    for constraint in getattr(table, "constraints"):
        if isinstance(constraint, UniqueConstraint):
            keys.add(
                (
                    _required_names(
                        (column.name for column in constraint.columns),
                        f"metadata unique constraint on {table.name}",
                    ),
                    None,
                )
            )
    for index in getattr(table, "indexes"):
        if not index.unique:
            continue
        where = index.dialect_options["postgresql"].get("where")
        compiled_where = (
            str(where.compile(dialect=engine.dialect, compile_kwargs={"literal_binds": True}))
            if where is not None
            else None
        )
        keys.add(
            (
                _required_names(
                    (expression.name for expression in index.expressions),
                    f"metadata index {index.name!r}",
                ),
                _normalize_sql(compiled_where),
            )
        )
    return keys


def _database_unique_keys(inspector: Inspector, table_name: str) -> set[tuple[tuple[str, ...], str | None]]:
    keys: set[tuple[tuple[str, ...], str | None]] = set()
    for constraint in inspector.get_unique_constraints(table_name):
        column_names = constraint.get("column_names")
        if column_names:
            keys.add((_required_names(column_names, f"unique constraint on {table_name}"), None))
    for index in inspector.get_indexes(table_name):
        if not index.get("unique") or index.get("duplicates_constraint"):
            continue
        dialect_options = index.get("dialect_options", {})
        where = dialect_options.get("postgresql_where", index.get("where"))
        column_names = index.get("column_names")
        if column_names is None:
            raise AssertionError(f"database index on {table_name} must use named columns")
        keys.add(
            (
                _required_names(column_names, f"database index {index.get('name')!r}"),
                _normalize_sql(where),
            )
        )
    return keys


def _metadata_indexes(table: Table, engine: Engine) -> set[tuple[str, tuple[str, ...], bool, str | None]]:
    indexes: set[tuple[str, tuple[str, ...], bool, str | None]] = set()
    for index in getattr(table, "indexes"):
        where = index.dialect_options["postgresql"].get("where")
        compiled_where = (
            str(where.compile(dialect=engine.dialect, compile_kwargs={"literal_binds": True}))
            if where is not None
            else None
        )
        if index.name is None:
            raise AssertionError("metadata indexes must be named")
        indexes.add(
            (
                index.name,
                _required_names(
                    (expression.name for expression in index.expressions),
                    f"metadata index {index.name!r}",
                ),
                index.unique,
                _normalize_sql(compiled_where),
            )
        )
    return indexes


def _database_indexes(inspector: Inspector, table_name: str) -> set[tuple[str, tuple[str, ...], bool, str | None]]:
    indexes: set[tuple[str, tuple[str, ...], bool, str | None]] = set()
    for index in inspector.get_indexes(table_name):
        if index.get("duplicates_constraint"):
            continue
        dialect_options = index.get("dialect_options", {})
        where = dialect_options.get("postgresql_where", index.get("where"))
        name = index.get("name")
        column_names = index.get("column_names")
        if name is None or column_names is None:
            raise AssertionError(f"database indexes on {table_name} must use named columns")
        indexes.add(
            (
                name,
                _required_names(column_names, f"database index {name!r}"),
                bool(index["unique"]),
                _normalize_sql(where),
            )
        )
    return indexes


def _metadata_checks(table: Table) -> dict[str, str]:
    checks: dict[str, str] = {}
    for constraint in table.constraints:
        if not isinstance(constraint, CheckConstraint):
            continue
        if not isinstance(constraint.name, str):
            raise AssertionError("metadata check constraints must be named")
        checks[constraint.name] = _normalize_sql(str(constraint.sqltext)) or ""
    return checks


def _create_pre_agency_schema(connection: Connection) -> None:
    metadata = MetaData()
    role_tenant_check = (
        "(role = 'platform_admin' AND tenant_id IS NULL) "
        "OR (role IN ('agency_admin', 'agent') AND tenant_id IS NOT NULL)"
    )
    account = Table(
        "staff_account",
        metadata,
        Column("id", String(36), primary_key=True),
        Column("role", String(32), nullable=False),
        Column("tenant_id", String(36), nullable=True),
        CheckConstraint(
            "role IN ('platform_admin', 'agency_admin', 'agent')",
            name="ck_staff_account_role",
        ),
        CheckConstraint(role_tenant_check, name="ck_staff_account_role_tenant"),
    )
    invitation = Table(
        "staff_invitation",
        metadata,
        Column("id", String(36), primary_key=True),
        Column("role", String(32), nullable=False),
        Column("tenant_id", String(36), nullable=True),
        Column("status", String(16), nullable=False),
        CheckConstraint(
            "role IN ('platform_admin', 'agency_admin', 'agent')",
            name="ck_staff_invitation_role",
        ),
        CheckConstraint(role_tenant_check, name="ck_staff_invitation_role_tenant"),
    )
    metadata.create_all(connection)
    connection.execute(
        insert(account),
        [
            {"id": "account-admin", "role": "platform_admin", "tenant_id": None},
            {"id": "account-shared", "role": "agency_admin", "tenant_id": "agency-shared"},
            {"id": "account-only", "role": "agent", "tenant_id": "agency-account-only"},
        ],
    )
    connection.execute(
        insert(invitation),
        [
            {
                "id": "invitation-admin",
                "role": "platform_admin",
                "tenant_id": None,
                "status": "pending",
            },
            {
                "id": "invitation-shared",
                "role": "agency_admin",
                "tenant_id": "agency-shared",
                "status": "accepted",
            },
            {
                "id": "invitation-only",
                "role": "agent",
                "tenant_id": "agency-invitation-only",
                "status": "revoked",
            },
        ],
    )


def _apply_agency_registry_migration(connection: Connection) -> None:
    migration_path = _BACKEND_ROOT / "alembic" / "versions" / "0003_agency_registry.py"
    assert migration_path.is_file(), "agency registry migration 0003 is missing"
    spec = importlib.util.spec_from_file_location(
        "agency_registry_migration", migration_path
    )
    assert spec is not None and spec.loader is not None
    migration = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration)
    migration.op = Operations(MigrationContext.configure(connection))
    migration.upgrade()


@pytest.fixture
def upgraded_agency_connection() -> Iterator[Connection]:
    engine = create_engine("sqlite+pysqlite:///:memory:")
    try:
        with engine.connect() as connection:
            connection.exec_driver_sql("PRAGMA foreign_keys = ON")
            connection.commit()
            with connection.begin():
                _create_pre_agency_schema(connection)
                _apply_agency_registry_migration(connection)
                yield connection
    finally:
        engine.dispose()


def test_agency_migration_backfills_all_distinct_tenant_ids_before_foreign_keys(
    upgraded_agency_connection: Connection,
) -> None:
    connection = upgraded_agency_connection

    agency_ids = set(connection.execute(text("SELECT id FROM agency")).scalars())
    assert agency_ids == {
        "agency-shared",
        "agency-account-only",
        "agency-invitation-only",
    }

    for table_name in ("staff_account", "staff_invitation"):
        foreign_keys = inspect(connection).get_foreign_keys(table_name)
        assert any(
            foreign_key["constrained_columns"] == ["tenant_id"]
            and foreign_key["referred_table"] == "agency"
            and foreign_key["referred_columns"] == ["id"]
            for foreign_key in foreign_keys
        ), f"{table_name}.tenant_id must reference agency.id"


def test_agency_migration_preserves_role_tenant_rules_and_enforces_references(
    upgraded_agency_connection: Connection,
) -> None:
    connection = upgraded_agency_connection
    inspector = inspect(connection)
    account = Table("staff_account", MetaData(), autoload_with=connection)
    invitation = Table("staff_invitation", MetaData(), autoload_with=connection)

    for table_name in ("staff_account", "staff_invitation"):
        checks = {
            constraint["name"]
            for constraint in inspector.get_check_constraints(table_name)
        }
        assert f"ck_{table_name}_role_tenant" in checks

    connection.execute(
        insert(account),
        {"id": "valid-admin", "role": "platform_admin", "tenant_id": None},
    )
    connection.execute(
        insert(invitation),
        {
            "id": "valid-admin-invitation",
            "role": "platform_admin",
            "tenant_id": None,
            "status": "pending",
        },
    )

    invalid_rows = (
        (
            account,
            {
                "id": "admin-with-tenant",
                "role": "platform_admin",
                "tenant_id": "agency-shared",
            },
        ),
        (
            account,
            {"id": "agency-without-tenant", "role": "agent", "tenant_id": None},
        ),
        (
            account,
            {
                "id": "unknown-agency",
                "role": "agent",
                "tenant_id": "agency-missing",
            },
        ),
        (
            invitation,
            {
                "id": "admin-invitation-with-tenant",
                "role": "platform_admin",
                "tenant_id": "agency-shared",
                "status": "pending",
            },
        ),
        (
            invitation,
            {
                "id": "agency-invitation-without-tenant",
                "role": "agency_admin",
                "tenant_id": None,
                "status": "pending",
            },
        ),
        (
            invitation,
            {
                "id": "unknown-agency-invitation",
                "role": "agent",
                "tenant_id": "agency-missing",
                "status": "pending",
            },
        ),
    )
    for table, values in invalid_rows:
        with pytest.raises(IntegrityError):
            connection.execute(insert(table), values)


def test_blank_database_upgrade_matches_identity_metadata(r6_database: R6Database) -> None:
    assert r6_database.started_blank, "schema verification must begin from a blank R6 database"
    engine = r6_database.engine
    inspector = inspect(engine)
    actual_tables = set(inspector.get_table_names()) - {"alembic_version"}
    expected_tables = set(Base.metadata.tables)
    differences: list[str] = []

    if actual_tables != expected_tables:
        differences.append(
            f"tables: expected {sorted(expected_tables)}, got {sorted(actual_tables)}"
        )

    for table_name in sorted(expected_tables & actual_tables):
        metadata_table = Base.metadata.tables[table_name]
        actual_columns = {column["name"]: column for column in inspector.get_columns(table_name)}
        expected_columns = set(metadata_table.columns.keys())
        if set(actual_columns) != expected_columns:
            differences.append(
                f"{table_name} columns: expected {sorted(expected_columns)}, got {sorted(actual_columns)}"
            )
        for column_name in sorted(expected_columns & set(actual_columns)):
            metadata_column = metadata_table.columns[column_name]
            actual_column = actual_columns[column_name]
            expected_type = metadata_column.type.compile(dialect=engine.dialect).lower()
            actual_type = actual_column["type"].compile(dialect=engine.dialect).lower()
            if expected_type != actual_type:
                differences.append(
                    f"{table_name}.{column_name} type: expected {expected_type}, got {actual_type}"
                )
            if metadata_column.nullable != actual_column["nullable"]:
                differences.append(
                    f"{table_name}.{column_name} nullable: expected {metadata_column.nullable}, "
                    f"got {actual_column['nullable']}"
                )
            expected_default = _expected_default(metadata_column, engine)
            actual_default = _normalize_sql(actual_column["default"])
            if expected_default != actual_default:
                differences.append(
                    f"{table_name}.{column_name} server default: expected {expected_default!r}, "
                    f"got {actual_default!r}"
                )

        expected_pk = tuple(column.name for column in metadata_table.primary_key.columns)
        actual_pk = tuple((inspector.get_pk_constraint(table_name).get("constrained_columns") or []))
        if actual_pk != expected_pk:
            differences.append(f"{table_name} primary key: expected {expected_pk}, got {actual_pk}")

        expected_fks = {
            (
                foreign_key.parent.name,
                foreign_key.target_fullname,
                (foreign_key.ondelete or "").upper() or None,
            )
            for foreign_key in metadata_table.foreign_keys
        }
        actual_fks = {
            (
                column_name,
                f"{foreign_key['referred_table']}.{referred_column}",
                (foreign_key.get("options", {}).get("ondelete") or "").upper() or None,
            )
            for foreign_key in inspector.get_foreign_keys(table_name)
            for column_name, referred_column in zip(
                foreign_key["constrained_columns"], foreign_key["referred_columns"], strict=True
            )
        }
        if actual_fks != expected_fks:
            differences.append(f"{table_name} foreign keys: expected {expected_fks}, got {actual_fks}")

        expected_unique = _metadata_unique_keys(metadata_table, engine)
        actual_unique = _database_unique_keys(inspector, table_name)
        if actual_unique != expected_unique:
            differences.append(
                f"{table_name} unique keys: expected {expected_unique}, got {actual_unique}"
            )

        expected_indexes = _metadata_indexes(metadata_table, engine)
        actual_indexes = _database_indexes(inspector, table_name)
        if actual_indexes != expected_indexes:
            differences.append(
                f"{table_name} indexes: expected {expected_indexes}, got {actual_indexes}"
            )

        expected_checks = _metadata_checks(metadata_table)
        actual_checks = {
            constraint["name"]: _normalize_sql(constraint["sqltext"]) or ""
            for constraint in inspector.get_check_constraints(table_name)
        }
        if actual_checks != expected_checks:
            differences.append(
                f"{table_name} check constraints: expected {expected_checks}, got {actual_checks}"
            )

    assert not differences, "migrated schema differs from identity metadata:\n- " + "\n- ".join(
        differences
    )
