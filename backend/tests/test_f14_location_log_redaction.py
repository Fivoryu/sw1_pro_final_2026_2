from __future__ import annotations

import logging

import pytest

from app.core.log_redaction import (
    REDACTED,
    LocationRedactionFilter,
    install_location_redaction,
    redact_location,
)


@pytest.mark.parametrize(
    "raw,expected",
    [
        (
            "/api/v1/listings?latitude=-17.78&longitude=-63.18&radius_km=5",
            f"/api/v1/listings?latitude={REDACTED}&longitude={REDACTED}&radius_km=5",
        ),
        (
            "/api/v1/listings?city=Santa+Cruz&LONGITUDE=-63.18&Latitude=-17.78",
            f"/api/v1/listings?city=Santa+Cruz&LONGITUDE={REDACTED}&Latitude={REDACTED}",
        ),
        ("/api/v1/listings?radius_km=5&limit=20", "/api/v1/listings?radius_km=5&limit=20"),
        ("/api/v1/listings/abc", "/api/v1/listings/abc"),
        # A parameter that merely ends in the same letters is not a coordinate.
        ("/x?mylatitude=1&latitude_note=2", "/x?mylatitude=1&latitude_note=2"),
    ],
)
def test_redact_location(raw: str, expected: str) -> None:
    assert redact_location(raw) == expected


def test_access_log_never_contains_coordinates() -> None:
    records: list[str] = []

    class Capture(logging.Handler):
        def emit(self, record: logging.LogRecord) -> None:
            records.append(record.getMessage())

    logger = logging.getLogger("uvicorn.access")
    handler = Capture()
    logger.addHandler(handler)
    previous_level = logger.level
    logger.setLevel(logging.INFO)
    install_location_redaction()
    install_location_redaction()  # idempotent
    try:
        assert sum(isinstance(f, LocationRedactionFilter) for f in logger.filters) == 1
        logger.info(
            '%s - "%s %s HTTP/%s" %d',
            "127.0.0.1:5000",
            "GET",
            "/api/v1/listings?latitude=-17.78&longitude=-63.18&radius_km=5",
            "1.1",
            200,
        )
    finally:
        logger.removeHandler(handler)
        logger.setLevel(previous_level)
    assert len(records) == 1
    assert "-17.78" not in records[0]
    assert "-63.18" not in records[0]
    assert "radius_km=5" in records[0]
    assert records[0].endswith(" 200")
