"""Payload shapes for detection jobs (F08.4).

The `result` column holds ``DetectionResultPayload``. It carries suggestions,
never commercial inventory: the confirmed inventory belongs to F08.5 and its
contract with F05 is not frozen yet.
"""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Any

from pydantic import BaseModel, ConfigDict, Field, field_validator

MAX_DETECTIONS = 100
SUGGESTION_BOX_SIZE = 4


class DetectionSuggestion(BaseModel):
    """One suggested object: a class, a score and a box in image pixels."""

    model_config = ConfigDict(extra="forbid")

    label: Annotated[str, Field(min_length=1, max_length=64)]
    score: Annotated[float, Field(ge=0.0, le=1.0)]
    box: Annotated[list[float], Field(min_length=SUGGESTION_BOX_SIZE, max_length=SUGGESTION_BOX_SIZE)]


def _validate_claim_token(value: Any) -> str:
    if not isinstance(value, str) or not 1 <= len(value) <= 64:
        raise ValueError("claim_token must be a string between 1 and 64 characters")
    return value


class DetectionResultPayload(BaseModel):
    """What the worker reports back for one image and active claim."""

    model_config = ConfigDict(extra="forbid")

    claim_token: Any = Field(
        json_schema_extra={"type": "string", "minLength": 1, "maxLength": 64}
    )
    _validate_claim_token = field_validator("claim_token")(_validate_claim_token)
    model_id: Annotated[str, Field(min_length=1, max_length=64)]
    detections: Annotated[list[DetectionSuggestion], Field(max_length=MAX_DETECTIONS)]


class DetectionJobFailure(BaseModel):
    """Why a worker could not finish its active claim."""

    model_config = ConfigDict(extra="forbid")

    claim_token: Any = Field(
        json_schema_extra={"type": "string", "minLength": 1, "maxLength": 64}
    )
    _validate_claim_token = field_validator("claim_token")(_validate_claim_token)
    reason: Annotated[str, Field(min_length=1, max_length=255)]


class DetectionWorkerClaimResponse(BaseModel):
    """Job state and, only for a successful claim, its authorized image URL."""

    model_config = ConfigDict(extra="forbid")

    job_id: str
    photo_id: str
    object_key: str
    model_id: str
    status: str
    attempts: int
    claim_token: str | None = None
    download_url: str | None = None


class DetectionJobResponse(BaseModel):
    """A job as the staff API reports it: state, attempts and result."""

    job_id: str
    photo_id: str
    model_id: str
    status: str
    attempts: int
    created_at: datetime
    started_at: datetime | None = None
    finished_at: datetime | None = None
    result: dict[str, Any] | None = None
    failure_reason: str | None = None


class DetectionJobList(BaseModel):
    jobs: list[DetectionJobResponse]
