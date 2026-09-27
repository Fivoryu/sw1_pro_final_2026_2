from __future__ import annotations

import re
from typing import Literal

from pydantic import BaseModel, Field, field_validator


_EMAIL_PATTERN = re.compile(r"[^@\s]+@[^@\s]+\.[^@\s]+")


class CustomerCredentials(BaseModel):
    email: str = Field(
        min_length=3,
        max_length=255,
        json_schema_extra={"format": "email"},
    )
    password: str = Field(min_length=8)

    @field_validator("email")
    @classmethod
    def validate_email_format(cls, value: str) -> str:
        trimmed = value.strip()
        if _EMAIL_PATTERN.fullmatch(trimmed) is None:
            raise ValueError("Invalid email address")
        return trimmed


class CustomerRegistration(CustomerCredentials):
    pass


class CustomerRefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=1)


class CustomerRegistrationResponse(BaseModel):
    id: str
    email: str


class CustomerErrorDetail(BaseModel):
    code: str
    fields: dict[str, str] | None = None


class CustomerErrorResponse(BaseModel):
    error: CustomerErrorDetail


class CustomerTokenPairResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: Literal["Bearer"]
    access_expires_in: Literal[900]


class CustomerIdentityResponse(BaseModel):
    id: str
    email: str
