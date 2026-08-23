from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.core.config import Settings, get_settings
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


def create_app(settings: Settings | None = None) -> FastAPI:
    resolved_settings = settings or get_settings()
    app = FastAPI(title="RoomForge API")
    app.state.settings = resolved_settings

    @app.exception_handler(RequestValidationError)
    async def request_validation_exception_handler(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        del request
        return JSONResponse(status_code=422, content={"detail": _sanitize_validation_errors(exc)})

    app.include_router(identity_router, prefix="/api/v1")
    return app


app = create_app()
