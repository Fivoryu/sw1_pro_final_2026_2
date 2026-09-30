from __future__ import annotations

import re
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator


_EMAIL_PATTERN = re.compile(r"[^@\s]+@[^@\s]+\.[^@\s]+")
_ETHEREUM_ADDRESS_PATTERN = re.compile(r"0x[a-fA-F0-9]{40}")


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


class CustomerTokenPairResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: Literal["Bearer"]
    access_expires_in: Literal[900]


class CustomerIdentityResponse(BaseModel):
    id: str
    email: str


class CustomerWalletChallengeRequest(BaseModel):
    address: str = Field(pattern=r"^0x[a-fA-F0-9]{40}$")

    @field_validator("address")
    @classmethod
    def validate_and_canonicalize_address(cls, value: str) -> str:
        if _ETHEREUM_ADDRESS_PATTERN.fullmatch(value) is None:
            raise ValueError("Invalid wallet address")
        return value.lower()


class CustomerWalletChallengeResponse(BaseModel):
    challenge_id: str
    message: str
    expires_at: datetime


class CustomerWalletVerificationRequest(BaseModel):
    challenge_id: str = Field(min_length=1)
    signature: str


class CustomerWalletResponse(BaseModel):
    id: str
    address: str
    linked_at: datetime
