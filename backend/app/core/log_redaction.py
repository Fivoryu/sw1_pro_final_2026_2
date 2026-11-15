"""Keeps the customer's position out of the server access log (F14.5, S4).

The zone search sends the customer's position as the ``latitude`` and
``longitude`` query parameters, and uvicorn's access log prints the full
request target. The filter replaces those two values before any handler
formats the record; every other parameter is left as it was.
"""

from __future__ import annotations

import logging
import re

REDACTED = "[redacted]"

ACCESS_LOGGER_NAME = "uvicorn.access"

_COORDINATE = re.compile(r"(?i)([?&](?:latitude|longitude)=)[^&\s#]*")


def redact_location(text: str) -> str:
    """Return ``text`` with the values of the coordinate parameters replaced."""
    return _COORDINATE.sub(lambda match: f"{match.group(1)}{REDACTED}", text)


class LocationRedactionFilter(logging.Filter):
    """Redacts coordinate parameters in a log record's message and arguments."""

    def filter(self, record: logging.LogRecord) -> bool:
        if isinstance(record.msg, str):
            record.msg = redact_location(record.msg)
        if isinstance(record.args, tuple):
            record.args = tuple(
                redact_location(arg) if isinstance(arg, str) else arg for arg in record.args
            )
        return True


def install_location_redaction() -> None:
    """Attach the filter to the access logger once; calling it again is a no-op."""
    logger = logging.getLogger(ACCESS_LOGGER_NAME)
    if not any(isinstance(existing, LocationRedactionFilter) for existing in logger.filters):
        logger.addFilter(LocationRedactionFilter())
