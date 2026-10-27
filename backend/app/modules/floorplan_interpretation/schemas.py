from __future__ import annotations

import math
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator
from pydantic_core import PydanticCustomError


class Point(BaseModel):
    x: float
    y: float

    @model_validator(mode="after")
    def normalized(self) -> "Point":
        if (
            not math.isfinite(self.x)
            or not math.isfinite(self.y)
            or not (0 <= self.x <= 1 and 0 <= self.y <= 1)
        ):
            raise ValueError("Contour coordinates must be finite and normalized")
        return self


class DimensionProposal(BaseModel):
    edge_index: int | None = Field(default=None, alias="edgeIndex")
    literal_text: str = Field(alias="literalText", min_length=1)
    value: float | None = None
    unit: Literal["m", "cm", "mm", "unknown"] = "unknown"
    provenance: Literal["ai_detected"] = "ai_detected"
    status: Literal["proposed", "unresolved", "conflict"]
    model_config = ConfigDict(populate_by_name=True)

    @model_validator(mode="after")
    def coherent_metric_meaning(self) -> "DimensionProposal":
        if self.value is not None and not math.isfinite(self.value):
            raise ValueError("Dimension value must be finite")
        if self.status == "proposed":
            if self.value is None:
                raise ValueError("Proposed dimension requires a value")
            if self.value <= 0:
                raise ValueError("Proposed dimension value must be positive")
            if self.unit not in {"m", "cm", "mm"}:
                raise ValueError("Proposed dimension requires an explicit metric unit")
        return self


class OpeningProposal(BaseModel):
    edge_index: int = Field(alias="edgeIndex")
    type: Literal["door", "window", "unknown"] = "unknown"
    position: float | None = None
    normalized_width: float | None = Field(default=None, alias="normalizedWidth")
    confidence: float | None = None
    status: Literal["proposed"] = "proposed"
    model_config = ConfigDict(populate_by_name=True)

    @model_validator(mode="after")
    def numeric_ranges(self) -> "OpeningProposal":
        _unit_interval(self.position, "Opening position")
        _positive_unit_interval(self.normalized_width, "Opening normalizedWidth")
        _unit_interval(self.confidence, "Opening confidence")
        return self


class RoomCandidate(BaseModel):
    id: str
    label: str | None = None
    contour: list[Point]
    wall_count: int = Field(alias="wallCount")
    openings: list[OpeningProposal] = []
    dimensions: list[DimensionProposal] = []
    confidence: float | None = None
    warnings: list[str] = []
    model_config = ConfigDict(populate_by_name=True)

    @model_validator(mode="after")
    def coherent(self) -> "RoomCandidate":
        if self.wall_count != len(self.contour):
            raise PydanticCustomError("wall_count_mismatch", "wallCount must match a usable contour")
        if len(self.contour) < 3:
            raise PydanticCustomError("invalid_contour", "Contour must contain at least three vertices")
        if any(item.edge_index < 0 or item.edge_index >= self.wall_count for item in self.openings):
            raise PydanticCustomError("invalid_opening_edge", "Opening references an invalid wall")
        if any(
            item.edge_index is not None and not (0 <= item.edge_index < self.wall_count)
            for item in self.dimensions
        ):
            raise PydanticCustomError("invalid_dimension_edge", "Dimension references an invalid wall")
        if abs(_signed_area(self.contour)) < 1e-6 or _self_intersects(self.contour):
            raise PydanticCustomError("invalid_contour", "Contour is degenerate or self-intersecting")
        _unit_interval(self.confidence, "Room confidence")
        return self


class FloorplanInterpretation(BaseModel):
    status: Literal[
        "success", "partial", "needs_review", "low_confidence", "provider_unavailable", "invalid_input"
    ]
    confidence: float | None = None
    rooms: list[RoomCandidate] = []
    ambiguities: list[str] = []
    warnings: list[str] = []
    information_still_needed: list[str] = Field(default=[], alias="informationStillNeeded")
    provenance: Literal["ai_proposal"] = Field(default="ai_proposal")
    retryable: bool = False
    model_config = ConfigDict(populate_by_name=True)

    @model_validator(mode="after")
    def valid_confidence(self) -> "FloorplanInterpretation":
        _unit_interval(self.confidence, "Interpretation confidence")
        return self


def _unit_interval(value: float | None, name: str) -> None:
    if value is None:
        return
    if not math.isfinite(value) or not 0 <= value <= 1:
        raise ValueError(f"{name} must be finite and within 0..1")


def _positive_unit_interval(value: float | None, name: str) -> None:
    if value is None:
        return
    if not math.isfinite(value) or not 0 < value <= 1:
        raise ValueError(f"{name} must be finite and within (0,1]")


def _signed_area(points: list[Point]) -> float:
    return sum(a.x * b.y - b.x * a.y for a, b in zip(points, points[1:] + points[:1])) / 2


def _self_intersects(points: list[Point]) -> bool:
    def cross(a: Point, b: Point, c: Point) -> float:
        return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)

    size = len(points)
    for i in range(size):
        a, b = points[i], points[(i + 1) % size]
        for j in range(i + 1, size):
            if j in {i, (i + 1) % size} or (j + 1) % size in {i, (i + 1) % size}:
                continue
            c, d = points[j], points[(j + 1) % size]
            if cross(a, b, c) * cross(a, b, d) < 0 and cross(c, d, a) * cross(c, d, b) < 0:
                return True
    return False
