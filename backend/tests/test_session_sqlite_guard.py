"""Regression tests for the SQLite catalog guard installed on pooled connections.

The guard is a property of a DBAPI connection, not of a checkout. Installing it again on
a connection another thread is already using blocks the SQLite connection mutex against
that thread's statement: instead of failing, the process deadlocks and pytest hangs.
These tests fail fast, which is the whole point of having them.
"""

from __future__ import annotations

from typing import Any

from app.db.session import (
    _apply_sqlite_offer_version_authorizer,
    _authorize_sqlite_offer_version_guard,
)


class _RecordingConnection:
    """DBAPI connection stand-in that records every guard installation."""

    def __init__(self) -> None:
        self.installed: list[object] = []

    def set_authorizer(self, authorizer: object) -> None:
        self.installed.append(authorizer)


class _RecordingRecord:
    """Pooled connection record stand-in, whose ``info`` dict survives checkouts."""

    def __init__(self) -> None:
        self.info: dict[object, object] = {}


def test_sqlite_guard_is_installed_once_per_connection() -> None:
    connection: Any = _RecordingConnection()
    record: Any = _RecordingRecord()

    _apply_sqlite_offer_version_authorizer(connection, record)
    _apply_sqlite_offer_version_authorizer(connection, record)

    assert connection.installed == [_authorize_sqlite_offer_version_guard]


def test_sqlite_guard_reinstall_is_skipped_even_with_a_fresh_record() -> None:
    """A second connection gets its own guard, and checkouts of it do not repeat it."""
    first: Any = _RecordingConnection()
    second: Any = _RecordingConnection()
    record: Any = _RecordingRecord()

    _apply_sqlite_offer_version_authorizer(first, record)
    _apply_sqlite_offer_version_authorizer(first, record)
    _apply_sqlite_offer_version_authorizer(second, _RecordingRecord())

    assert first.installed == [_authorize_sqlite_offer_version_guard]
    assert second.installed == [_authorize_sqlite_offer_version_guard]
