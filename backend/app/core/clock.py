from __future__ import annotations

from datetime import UTC, datetime
from typing import Protocol


class ClockProtocol(Protocol):
    def now(self) -> datetime:
        """Return the current timezone-aware UTC time."""
        ...


class SystemClock:
    def now(self) -> datetime:
        return datetime.now(UTC)
