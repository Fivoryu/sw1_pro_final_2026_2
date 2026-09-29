from __future__ import annotations

import socket
from urllib.parse import urlsplit

from fastapi import APIRouter, HTTPException, Request
from sqlalchemy import text
from sqlalchemy.orm import Session, sessionmaker

from app.core.errors import ERROR_RESPONSES, ErrorResponse

router = APIRouter(prefix="/health", tags=["health"])
_READINESS_RESPONSES = {**ERROR_RESPONSES, 503: {"model": ErrorResponse}}
_UNAVAILABLE = "A required dependency is unavailable"


def _unavailable() -> HTTPException:
    return HTTPException(status_code=503, detail=_UNAVAILABLE)


def _check_database(session_factory: sessionmaker[Session]) -> None:
    with session_factory() as session:
        session.execute(text("SELECT 1")).scalar_one()


def _check_floci(endpoint_url: str | None) -> None:
    try:
        endpoint = urlsplit(endpoint_url or "")
        hostname = endpoint.hostname
        port = endpoint.port
        if port is None:
            port = {"http": 80, "https": 443}.get(endpoint.scheme)
        if hostname is None or port is None or port == 0:
            raise ValueError("S3 endpoint URL is invalid")
        connection = socket.create_connection((hostname, port), timeout=2)
        connection.close()
    except Exception:
        raise _unavailable() from None


@router.get("/live")
def live() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/ready", responses=_READINESS_RESPONSES)
def ready(request: Request) -> dict[str, str]:
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    try:
        _check_database(session_factory)
    except Exception:
        raise _unavailable() from None

    _check_floci(request.app.state.settings.s3_endpoint_url)
    return {"status": "ok"}
