from __future__ import annotations

import re
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator


_EMAIL_PATTERN = re.compile(r"[^@\s]+@[^@\s]+\.[^@\s]+")


class AgencyCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str = Field(min_length=1, max_length=36)

    @field_validator("id")
    @classmethod
    def validate_id(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("Agency ID must not be blank")
        return value


class AgencyListItem(BaseModel):
    id: str


class AgencyPagination(BaseModel):
    limit: int = Field(ge=1, le=100)
    offset: int = Field(ge=0)
    total: int = Field(ge=0)


class AgencyListResponse(BaseModel):
    agencies: list[AgencyListItem]
    pagination: AgencyPagination


class AgencyAdminInvitationCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    email: str = Field(min_length=3, max_length=320)

    @field_validator("email")
    @classmethod
    def normalize_and_validate_email(cls, value: str) -> str:
        normalized = value.strip().lower()
        if not _EMAIL_PATTERN.fullmatch(normalized):
            raise ValueError("A valid email address is required")
        return normalized


class AgencyWalletChallengeCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    address: str = Field(pattern=r"^0x[a-fA-F0-9]{40}$")

    @field_validator("address")
    @classmethod
    def canonicalize_address(cls, value: str) -> str:
        return value.lower()


class AgencyWalletChallengeResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    challenge_id: str
    message: str
    expires_at: datetime


class AgencyWalletLinkRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    challenge_id: str = Field(min_length=1, max_length=36)
    signature: str = Field(min_length=1, max_length=512)


class AgencyWalletResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    agency_id: str
    address: str
    linked_at: datetime


class AgentInvitationCreate(AgencyAdminInvitationCreate):
    pass


class AgentListItem(BaseModel):
    id: str
    email: str
    active: bool


class AgentListResponse(BaseModel):
    agents: list[AgentListItem]
    pagination: AgencyPagination
