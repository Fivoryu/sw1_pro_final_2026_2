from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.core.config import Settings, get_settings
from app.core.tokens import PyJWTTokenService
from app.modules.identity.router import router as identity_router


def _sanitize_validation_errors(exc: RequestValidationError) -> list[dict[str, object]]:
    sanitized = []
    for error in exc.errors():
        location = [part for part in error.get("loc", ()) if part != "password"]
        sanitized.append(
            {
                "loc": location,
                "msg": error.get("msg", "Invalid request"),
                "type": error.get("type", "value_error"),
            }
        )
    return sanitized


def _register_routes(app: FastAPI) -> None:
    @app.exception_handler(RequestValidationError)
    async def request_validation_exception_handler(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        del request
        return JSONResponse(status_code=422, content={"detail": _sanitize_validation_errors(exc)})

    app.include_router(identity_router, prefix="/api/v1")


def create_app(settings: Settings | None = None) -> FastAPI:
    resolved_settings = settings or get_settings()
    token_service = PyJWTTokenService(resolved_settings)
    app = FastAPI(title="RoomForge API")
    app.state.settings = resolved_settings
    app.state.token_service = token_service
    if settings is not None:
        app.dependency_overrides[get_settings] = lambda: resolved_settings
    _register_routes(app)
    return app


def _create_default_app() -> FastAPI:
    app = FastAPI(title="RoomForge API")

    @app.on_event("startup")
    def validate_security_configuration() -> None:
        resolved_settings = get_settings()
        app.state.settings = resolved_settings
        app.state.token_service = PyJWTTokenService(resolved_settings)

    _register_routes(app)
    return app


app = _create_default_app()
