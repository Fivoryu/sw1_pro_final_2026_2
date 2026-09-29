from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, model_validator


ErrorCode = Literal[
    "validation_error",
    "unauthorized",
    "forbidden",
    "not_found",
    "conflict",
    "dependency_unavailable",
    "internal_error",
]


class ErrorResponse(BaseModel):
    detail: str
    code: ErrorCode

    @model_validator(mode="after")
    def redact_dependency_error_detail(self) -> ErrorResponse:
        if self.code == "dependency_unavailable":
            self.detail = "A required dependency is unavailable"
        return self


ERROR_RESPONSES = {
    "default": {"model": ErrorResponse},
    422: {"model": ErrorResponse},
}


def error_code_for_status(status_code: int) -> ErrorCode:
    if status_code in (400, 422):
        return "validation_error"
    if status_code == 401:
        return "unauthorized"
    if status_code == 403:
        return "forbidden"
    if status_code == 404:
        return "not_found"
    if status_code == 409:
        return "conflict"
    if status_code in (502, 503, 504):
        return "dependency_unavailable"
    return "internal_error"
