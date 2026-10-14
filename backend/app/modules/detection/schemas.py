"""Payload shapes for detection jobs (F08.4).

The `result` column holds this shape. It carries suggestions, never commercial
inventory: the confirmed inventory belongs to F08.5 and its contract with F05
is not frozen yet.
"""

from __future__ import annotations

from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field

MAX_DETECTIONS = 100


class DetectionSuggestion(BaseModel):
    """One suggested object: a class, a score and a box in image pixels."""

    model_config = ConfigDict(extra="forbid")

    label: Annotated[str, Field(min_length=1, max_length=64)]
    score: Annotated[float, Field(ge=0.0, le=1.0)]
    box: Annotated[list[float], Field(min_length=4, max_length=4)]


class DetectionResultPayload(BaseModel):
    """What the worker reports back for one image."""

    model_config = ConfigDict(extra="forbid")

    model_id: Annotated[str, Field(min_length=1, max_length=64)]
    detections: Annotated[list[DetectionSuggestion], Field(max_length=MAX_DETECTIONS)]


class DetectionJobFailure(BaseModel):
    """Why a worker could not finish a job."""

    model_config = ConfigDict(extra="forbid")

    reason: Annotated[str, Field(min_length=1, max_length=255)]
