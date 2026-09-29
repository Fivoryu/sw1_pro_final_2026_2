from __future__ import annotations

from unittest.mock import Mock

import pytest
import sqlalchemy
from sqlalchemy.pool import QueuePool

import app.db.session as database_session


def test_postgresql_engine_uses_bounded_connection_pool_and_statement_timeouts(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    original_create_engine = sqlalchemy.create_engine
    engine_options: dict[str, object] = {}

    def capture_engine_options(url: str, **kwargs: object):
        engine_options.update(kwargs)
        return original_create_engine(url, **kwargs)

    monkeypatch.setattr(database_session, "create_engine", capture_engine_options)

    engine, _ = database_session.create_session_factory(
        "postgresql+psycopg://roomforge:test@localhost/roomforge",
        connect_timeout_seconds=5,
        pool_timeout_seconds=5,
        statement_timeout_seconds=10,
    )
    try:
        assert isinstance(engine.pool, QueuePool)
        assert engine.pool._timeout == 5
        assert engine_options == {
            "pool_pre_ping": True,
            "pool_timeout": 5,
            "connect_args": {
                "connect_timeout": 5,
                "options": "-c statement_timeout=10000",
            },
        }
    finally:
        engine.dispose()


def test_non_psycopg_url_omits_connect_args(monkeypatch: pytest.MonkeyPatch) -> None:
    engine = Mock()
    create_engine = Mock(return_value=engine)
    monkeypatch.setattr(database_session, "create_engine", create_engine)
    # Building engine options is the subject here; the SQLite factory guard needs a real
    # bind and is covered by test_catalog.py::test_create_session_factory_protects_sqlite_guard_writes.
    monkeypatch.setattr(
        database_session, "protect_session_factory", lambda factory: None
    )
    database_session.create_session_factory("postgresql+pg8000://localhost/db")
    assert create_engine.call_args.kwargs == {"pool_pre_ping": True}


def test_non_postgresql_engine_does_not_receive_postgresql_connection_arguments(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    original_create_engine = sqlalchemy.create_engine
    engine_options: dict[str, object] = {}

    def capture_engine_options(url: str, **kwargs: object):
        engine_options.update(kwargs)
        return original_create_engine(url, **kwargs)

    monkeypatch.setattr(database_session, "create_engine", capture_engine_options)

    engine, _ = database_session.create_session_factory(
        "sqlite+pysqlite:///:memory:",
        connect_timeout_seconds=5,
        pool_timeout_seconds=5,
        statement_timeout_seconds=10,
    )
    try:
        assert engine.dialect.name == "sqlite"
        assert engine_options == {"pool_pre_ping": True}
    finally:
        engine.dispose()
