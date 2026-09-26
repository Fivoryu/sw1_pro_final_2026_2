from __future__ import annotations

from collections.abc import Callable
from datetime import datetime, timezone
from typing import Any

from cryptography.fernet import Fernet
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import Settings
from app.db.session import create_session_factory
from app.modules.agencies.router import router as agencies_router
from app.modules.identity.router import router as identity_router


def create_app(
    *,
    settings: Settings | None = None,
    session_factory: sessionmaker[Session] | None = None,
    email_sender: Any = None,
    clock: Callable[[], datetime] | None = None,
) -> FastAPI:
    resolved_settings = settings or Settings.from_env()
    resolved_settings.validate()
    Fernet(resolved_settings.totp_encryption_key.encode("ascii"))
    engine = None
    if session_factory is None:
        engine, session_factory = create_session_factory(resolved_settings.database_url)

    app = FastAPI(title="RoomForge Staff API", version="1.0.0")
    app.state.settings = resolved_settings
    app.state.session_factory = session_factory
    app.state.email_sender = email_sender
    app.state.clock = clock or (lambda: datetime.now(timezone.utc))
    app.state.engine = engine
    app.add_middleware(
        CORSMiddleware,
        allow_origins=[resolved_settings.web_origin.rstrip("/")],
        allow_credentials=True,
        allow_methods=["GET", "POST", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "X-CSRF-Token"],
    )
    app.include_router(identity_router)
    app.include_router(agencies_router)

    @app.exception_handler(RequestValidationError)
    async def safe_validation_error(request: Request, exc: RequestValidationError) -> JSONResponse:
        del request, exc
        return JSONResponse(status_code=422, content={"detail": "Request validation failed"})

    return app
