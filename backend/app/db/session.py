from __future__ import annotations

import sqlite3
from collections.abc import Iterator, Mapping
from typing import Any

from sqlalchemy import create_engine, event
from sqlalchemy.engine import Connection, Engine
from sqlalchemy.orm import Session, sessionmaker


_SQLITE_OFFER_VERSION_GUARD = "listing_offer_version_guard"
# Keep these names in sync with the SQLite triggers in 0007_catalog_offers.py.
_SQLITE_OFFER_VERSION_TRIGGER_SOURCES = frozenset(
    {
        "trg_listing_offer_insert_guard",
        "trg_listing_offer_id_immutable",
        "trg_listing_offer_version_guard",
        "trg_listing_offer_version_advance",
        "trg_listing_extra_insert_guard",
        "trg_listing_extra_insert_offer_version",
        "trg_listing_extra_update_offer_version",
        "trg_listing_extra_delete_offer_version",
    }
)
_SQLITE_OFFER_VERSION_TRIGGER_SOURCE_NAMES = frozenset(
    name.casefold() for name in _SQLITE_OFFER_VERSION_TRIGGER_SOURCES
)
_SQLITE_GUARDED_TABLES = frozenset(
    {_SQLITE_OFFER_VERSION_GUARD, "listing", "listing_extra"}
)
_SQLITE_GUARDED_TABLE_NAMES = frozenset(name.casefold() for name in _SQLITE_GUARDED_TABLES)
_SQLITE_GUARD_WRITE_ACTIONS = frozenset(
    {sqlite3.SQLITE_INSERT, sqlite3.SQLITE_UPDATE, sqlite3.SQLITE_DELETE}
)
_SQLITE_TRIGGER_DDL_ACTIONS = frozenset(
    {
        sqlite3.SQLITE_CREATE_TRIGGER,
        sqlite3.SQLITE_DROP_TRIGGER,
        sqlite3.SQLITE_CREATE_TEMP_TRIGGER,
        sqlite3.SQLITE_DROP_TEMP_TRIGGER,
    }
)
_SQLITE_TABLE_DDL_ACTIONS = frozenset(
    {
        sqlite3.SQLITE_CREATE_TABLE,
        sqlite3.SQLITE_CREATE_TEMP_TABLE,
        sqlite3.SQLITE_DROP_TABLE,
        sqlite3.SQLITE_DROP_TEMP_TABLE,
    }
)
_SQLITE_SYSTEM_SCHEMA_NAMES = frozenset(
    {"sqlite_master", "sqlite_schema", "sqlite_temp_master", "sqlite_temp_schema"}
)


def _authorize_sqlite_offer_version_guard(
    action: int,
    table_name: str | None,
    column_name: str | None,
    _database_name: str | None,
    source: str | None,
) -> int:
    if (
        table_name is not None
        and table_name.casefold() == _SQLITE_OFFER_VERSION_GUARD.casefold()
        and action in _SQLITE_GUARD_WRITE_ACTIONS
        and source not in _SQLITE_OFFER_VERSION_TRIGGER_SOURCES
    ):
        return sqlite3.SQLITE_DENY

    if (
        action in _SQLITE_TRIGGER_DDL_ACTIONS
        and table_name is not None
        and table_name.casefold() in _SQLITE_OFFER_VERSION_TRIGGER_SOURCE_NAMES
    ):
        return sqlite3.SQLITE_DENY

    if (
        action in _SQLITE_TABLE_DDL_ACTIONS
        and table_name is not None
        and table_name.casefold() in _SQLITE_GUARDED_TABLE_NAMES
    ):
        return sqlite3.SQLITE_DENY

    if (
        action == sqlite3.SQLITE_ALTER_TABLE
        and column_name is not None
        and column_name.casefold() in _SQLITE_GUARDED_TABLE_NAMES
    ):
        return sqlite3.SQLITE_DENY

    if (
        action in _SQLITE_GUARD_WRITE_ACTIONS
        and table_name is not None
        and table_name.casefold() in _SQLITE_SYSTEM_SCHEMA_NAMES
    ):
        return sqlite3.SQLITE_DENY

    if action == sqlite3.SQLITE_PRAGMA and table_name is not None:
        if table_name.casefold() == "writable_schema":
            return sqlite3.SQLITE_DENY

    return sqlite3.SQLITE_OK


def _apply_sqlite_offer_version_authorizer(
    dbapi_connection: sqlite3.Connection,
    _connection_record: object,
    _connection_proxy: object | None = None,
) -> None:
    dbapi_connection.set_authorizer(_authorize_sqlite_offer_version_guard)


def _install_sqlite_offer_version_authorizer(engine: Engine) -> None:
    if engine.dialect.name != "sqlite":
        return

    if not event.contains(engine, "connect", _apply_sqlite_offer_version_authorizer):
        event.listen(engine, "connect", _apply_sqlite_offer_version_authorizer)
    # Existing pooled connections also receive the guard before they are checked out.
    if not event.contains(engine, "checkout", _apply_sqlite_offer_version_authorizer):
        event.listen(engine, "checkout", _apply_sqlite_offer_version_authorizer)


def _protect_session_bind(bind: Any) -> None:
    if isinstance(bind, Engine):
        if bind.dialect.name == "sqlite":
            _install_sqlite_offer_version_authorizer(bind)
        return

    if isinstance(bind, Connection):
        if bind.dialect.name != "sqlite":
            return
        if bind.closed:
            raise RuntimeError("SQLite session factory Connection bind must be open")
        dbapi_connection = bind.connection.driver_connection
        if not isinstance(dbapi_connection, sqlite3.Connection):
            raise RuntimeError("SQLite session factory Connection bind is uninspectable")
        dbapi_connection.set_authorizer(_authorize_sqlite_offer_version_guard)
        return

    raise RuntimeError("Session factory has an unsupported session factory bind value")


def protect_session_factory(session_factory: sessionmaker[Session]) -> None:
    """Install the catalog authorizer on every SQLite factory bind."""
    factory_options = session_factory.kw
    if not isinstance(factory_options, Mapping):
        raise RuntimeError("Session factory options are uninspectable")

    default_bind = factory_options.get("bind")
    mapped_binds = factory_options.get("binds")
    if mapped_binds is None:
        mapped_bind_values: tuple[Any, ...] = ()
    elif isinstance(mapped_binds, Mapping):
        try:
            mapped_bind_values = tuple(mapped_binds.values())
        except Exception as error:
            raise RuntimeError("Session factory mapped binds are uninspectable") from error
    else:
        raise RuntimeError("Session factory mapped binds are uninspectable")

    binds = (() if default_bind is None else (default_bind,)) + mapped_bind_values
    if not binds:
        raise RuntimeError("Session factory must be bound to a SQLAlchemy database")
    for bind in binds:
        _protect_session_bind(bind)


def create_session_factory(
    database_url: str, *, engine_options: dict[str, Any] | None = None
) -> tuple[Engine, sessionmaker[Session]]:
    engine = create_engine(database_url, pool_pre_ping=True, **(engine_options or {}))
    factory = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
    protect_session_factory(factory)
    return engine, factory


def session_scope(factory: sessionmaker[Session]) -> Iterator[Session]:
    session = factory()
    try:
        yield session
    finally:
        session.close()
