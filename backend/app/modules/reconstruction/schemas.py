"""Payload shapes for the capture package flow (F07.7); wire names follow the contract."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Any

from pydantic import BaseModel, ConfigDict, Field

MAX_PACKAGE_BYTES = 150 * 1024 * 1024
MAX_WARNINGS = 200


class CaptureRegistration(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    capture_id: Annotated[str, Field(alias="captureId", pattern=r"^[A-Za-z0-9_-]{1,64}$")]
    size_bytes: Annotated[int, Field(alias="sizeBytes", ge=1, le=MAX_PACKAGE_BYTES)]


class CaptureRegistered(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    capture_id: str = Field(alias="captureId")
    status: str
    upload_url: str | None = Field(default=None, alias="uploadUrl")
    expires_at: datetime | None = Field(default=None, alias="expiresAt")


class CaptureStatusOnly(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    capture_id: str = Field(alias="captureId")
    status: str


class CaptureResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    capture_id: str = Field(alias="captureId")
    status: str
    scene_draft: dict[str, Any] | None = Field(default=None, alias="sceneDraft")
    warnings: list[str] = Field(default_factory=list)
    failure_reason: str | None = Field(default=None, alias="failureReason")


class CaptureList(BaseModel):
    captures: list[CaptureResponse]


class VolumeSuggestion(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    object_id: Annotated[str, Field(alias="objectId", min_length=1, max_length=64)]
    label: Annotated[str, Field(min_length=1, max_length=64)]
    score: Annotated[float, Field(ge=0, le=1, allow_inf_nan=False)]
    keyframe: Annotated[int, Field(ge=1)]
    box: Annotated[
        list[Annotated[float, Field(allow_inf_nan=False)]], Field(min_length=4, max_length=4)
    ]


class VolumeSuggestions(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    model_id: Annotated[str, Field(alias="modelId", min_length=1, max_length=64)]
    items: list[VolumeSuggestion] = Field(max_length=100)


class ReconstructionResult(BaseModel):
    """What the worker reports for its active claim; the route validates ``sceneDraft``."""

    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    scene_draft: Any = Field(alias="sceneDraft")
    warnings: list[Annotated[str, Field(max_length=500)]] = Field(
        default_factory=list, max_length=MAX_WARNINGS
    )
    volume_suggestions: VolumeSuggestions | None = Field(default=None, alias="volumeSuggestions")


class ReconstructionFailure(BaseModel):
    model_config = ConfigDict(extra="forbid")

    reason: Annotated[str, Field(min_length=1, max_length=255)]
    retryable: bool


class ReconstructionClaimResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    job_id: str
    status: str
    claim_token: str | None = None
    download_url: str | None = None
