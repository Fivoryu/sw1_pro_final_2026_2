from __future__ import annotations

import base64
import asyncio
import json
import logging
import math
import re
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from time import monotonic
from typing import Any, Protocol, TypeGuard, cast
from uuid import uuid4

import httpx
from pydantic import ValidationError

from app.modules.floorplan_interpretation.schemas import (
    FloorplanInterpretation,
    Point,
    _has_zero_length_edge,
    _self_intersects,
    _signed_area,
)


SYSTEM_PROMPT = """Return one concise JSON object describing architectural room candidates in the image.
First identify closed architectural spaces. Return one RoomCandidate per defensible room; internal partitions separate
rooms and must not become one mega-room contour. A semantic wall is one continuous room-perimeter segment ending only at
a material direction or topology change. Doors, windows, gaps, wall thickness, furniture, labels, hatching, and
dimension/extension lines do not split or create walls. Double wall bands are one wall.
First identify the dominant room or enclosure and recover its semantic perimeter. Establish semantic topology before
interpreting openings or dimensions. Use one contour vertex per real architectural corner or wall transition, in
consistent order. The contour is closed by implication: do not repeat the first contour point as the final point, and
it must be simple, non-degenerate, non-self-intersecting. Do not create contour vertices or walls from door swing arcs,
window detail strokes, wall thickness bands, furniture, text, dimension lines, construction lines, auxiliary lines, or
similar drawing noise. Do not infer room walls from nearby dimension labels.
Contour points represent semantic architectural walls and room boundary segments for the selected room perimeter, rather
than all visible linework. Doors and windows are openings in walls and must not create additional semantic walls; report
them in openings, not as contour edges. Collinear or nearly-collinear boundary fragments separated by an opening or
drawing gap, including a door, window, or wall-detail interruption, are one semantic wall when architecturally
continuous and visually supported. Do not create contour walls from furniture, dimensions, text, labels, door swing arcs,
window detail strokes, decorative lines, auxiliary/construction lines, or similar non-boundary graphical artifacts.
Internal details or unrelated partitions belong in the contour only when they define the selected room boundary.
Preserve L-shaped, concave, angled, pentagonal, and other irregular geometry; never force rectangles or orthogonality.
Do not force a rectangle. Do not add or remove architectural walls merely to satisfy a target wall count.
Hand sketches may yield partial or needs_review candidates when closed topology is defensible. Otherwise return
low_confidence with no rooms. Geometry recognition must not depend on the plan language.
After establishing semantic topology, inspect every semantic perimeter wall for openings and report every visually
supported door or window. Classify each opening from its own visible architectural evidence: do not classify every wall
gap as a door. A window must remain window when window-specific visual evidence supports it, and a door must remain door
when door-specific visual evidence supports it; do not use a nearby dimension label to decide opening type. If an opening
is visible but its type is genuinely ambiguous, use type="unknown". One physical opening per opening proposal:
do not merge separate physical openings and do not duplicate a single physical opening. Do not create openings from
furniture, annotations, dimension lines, wall thickness, door swing arcs alone, construction/auxiliary lines, decorative
noise, or window-detail strokes alone; arcs and window detail can support classification only when a real wall opening is
visible. After topology, assign opening edgeIndex only when wall association is visually defensible; never assign it by
nearest distance when architectural association is uncertain. If an opening is visually supported but its semantic wall association is not defensible, preserve the opening and use edgeIndex=null. For each opening, position is the normalized center along
the associated wall, directed from contour[edgeIndex] toward contour[(edgeIndex + 1) % wallCount]: position=0 is its start,
position=0.5 is its midpoint, and position=1 is its end. Position is never the opening start, opening end, nearest jamb,
or a dimension-chain offset. normalizedWidth is the physical opening span along that semantic wall divided by the semantic
wall length: a fraction of the associated wall length, not an endpoint or a room-relative width. Report position and normalizedWidth only when visually
defensible from the image. If the exact center is not defensible, return position=null. If the width is not defensible,
return normalizedWidth=null. Otherwise return null rather than guessing. position is in [0,1] and normalizedWidth is in (0,1]. Never fabricate opening position or width. Never fabricate precise opening geometry or substitute typical/default door or window dimensions. Report dimensions only as visible
evidence: every item requires literalText exactly as read and status proposed | unresolved | conflict. proposed
requires a finite positive value and visible metric unit m/cm/mm. Bare numbers use unit unknown and unresolved. Assign
edgeIndex only when dimension orientation, line/endpoints, and wall alignment support it; proximity alone is insufficient.
Coordinates are normalized [0,1]. wallCount equals contour length and every edgeIndex is in range or null. Opening status
is proposed; types are door/window/unknown. All output remains a proposal for human review with provenance ai_proposal /
ai_detected. Never fabricate geometry, text, units, dimensions, openings, scale, area, or confidence.
Do not calculate, solve geometry, derive missing measurements, build shared-wall entities, or model furniture. RoomForge
performs deterministic validation and metric solving. Use status success, partial, needs_review, low_confidence, or
invalid_input and include rooms, ambiguities, warnings, informationStillNeeded, and supported confidence.
Return JSON only. Do not output reasoning, markdown, or prose."""

_MAX_RETRY_AFTER_SECONDS = 3.0
_FALLBACK_RETRY_DELAY_SECONDS = 0.1
_RATE_LIMIT_FALLBACK_DELAY_SECONDS = 1.75
_MAX_DIAGNOSTIC_PREVIEW_CHARS = 4000
_DEFAULT_RESPONSE_MAX_TOKENS = 900
_TOPOLOGY_RESCUE_MAX_TOKENS = 550
_OPENING_EDGE_PROJECTION_TOLERANCE = 0.02

# Dimensionless topology-review tolerances. These do not define architectural
# wall sizes: they identify a dense sequence of material turns that is unusual
# without independent evidence corroborating every inferred transition.
_STRUCTURAL_SUSPICION_MIN_MEANINGFUL_TURNS = 7
_STRUCTURAL_SUSPICION_MIN_TURN_ANGLE_DEGREES = 25.0
_STRUCTURAL_SUSPICION_MAX_RELATIVE_COMPACT_EDGE = 0.30
_STRUCTURAL_SUSPICION_MIN_COMPACT_EDGE_FRACTION = 0.75
_STRUCTURAL_SUSPICION_MIN_TURN_DENSITY = 3.0

LOGGER = logging.getLogger("roomforge.floorplan_interpretation")
# Uvicorn supplies the runtime handlers. Keep this namespace independently
# observable without increasing the root or third-party logger verbosity.
LOGGER.setLevel(logging.INFO)


class FloorplanInterpreter(Protocol):
    async def interpret(self, *, image: bytes, content_type: str) -> FloorplanInterpretation: ...


class ProviderUnavailable(RuntimeError):
    def __init__(
        self,
        *,
        retryable: bool = True,
        reason: str = "network_failure",
        provider_status: int | None = None,
        retry_after_seconds: float | None = None,
    ) -> None:
        self.retryable = retryable
        self.reason = reason
        self.provider_status = provider_status
        self.retry_after_seconds = retry_after_seconds
        super().__init__(reason)


class InvalidProviderResponse(RuntimeError):
    def __init__(self, summary: str = "invalid_response", *, reason: str = "contract_failure") -> None:
        self.summary = summary
        self.reason = reason
        super().__init__(summary)


@dataclass
class _NormalizationStats:
    normalized_dimensions: int = 0
    dropped_dimensions: int = 0
    dropped_openings: int = 0
    actions: list[str] = field(default_factory=list)

    def record(self, action: str) -> None:
        if action not in self.actions:
            self.actions.append(action)


def _safe_type(value: object) -> str:
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, (int, float)):
        return "number"
    if isinstance(value, str):
        return "string"
    return "other"


def _sanitize_diagnostic_text(text: str, *, secrets: tuple[str, ...] = ()) -> str:
    sanitized = text
    for secret in secrets:
        if secret:
            sanitized = sanitized.replace(secret, "[redacted-secret]")
    sanitized = re.sub(r"(?i)authorization\s*[:=]\s*(?:bearer\s+)?\S+", "Authorization=[redacted]", sanitized)
    sanitized = re.sub(r"(?i)bearer\s+[A-Za-z0-9._~+/=-]+", "Bearer [redacted]", sanitized)
    sanitized = re.sub(r"data:[^,\s\"]+,[A-Za-z0-9+/=]+", "[redacted-data-url]", sanitized)
    sanitized = re.sub(r"[A-Za-z0-9+/]{256,}={0,2}", "[redacted-long-token]", sanitized)
    return sanitized[:_MAX_DIAGNOSTIC_PREVIEW_CHARS]


def _provider_semantic_summary(raw: object) -> object:
    if not isinstance(raw, dict):
        return {"topLevelType": _safe_type(raw)}
    summary: dict[str, Any] = {key: raw[key] for key in ("status", "confidence") if key in raw}
    rooms = raw.get("rooms")
    if not isinstance(rooms, list):
        summary["roomsType"] = _safe_type(rooms)
        return summary
    summarized_rooms: list[object] = []
    for room in rooms:
        if not isinstance(room, dict):
            summarized_rooms.append({"type": _safe_type(room)})
            continue
        summarized_rooms.append(
            {
                key: room[key]
                for key in (
                    "label",
                    "confidence",
                    "wallCount",
                    "contour",
                    "dimensions",
                    "openings",
                )
                if key in room
            }
        )
    summary["rooms"] = summarized_rooms
    return summary


def _raw_validation_context(raw: object, error: ValidationError) -> tuple[int | None, str]:
    rooms = raw.get("rooms") if isinstance(raw, dict) else None
    room_count = len(rooms) if isinstance(rooms, list) else None
    first = error.errors(include_url=False, include_input=False)[0]
    value = raw
    for part in first.get("loc", ()):
        if isinstance(part, int) and isinstance(value, list) and 0 <= part < len(value):
            value = value[part]
        elif isinstance(part, str) and isinstance(value, dict) and part in value:
            value = value[part]
        else:
            break
    return room_count, _safe_type(value)


def _is_finite_number(value: object) -> TypeGuard[int | float]:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def _has_structurally_valid_contour(contour: list[object]) -> bool:
    if len(contour) < 3:
        return False
    for point in contour:
        if not isinstance(point, dict):
            return False
        x = point.get("x")
        y = point.get("y")
        if not (_is_finite_number(x) and _is_finite_number(y)):
            return False
        if not (0 <= x <= 1 and 0 <= y <= 1):
            return False
    return True


def _strict_json_container(value: object, expected_type: type[list[Any]] | type[dict[str, Any]]) -> object:
    if not isinstance(value, str):
        return value
    try:
        decoded = json.loads(value)
    except json.JSONDecodeError:
        return value
    return decoded if isinstance(decoded, expected_type) else value


def _normalize_contour_point(point: object, stats: _NormalizationStats) -> object:
    decoded = _strict_json_container(point, list)
    if decoded is point:
        decoded = _strict_json_container(point, dict)
    if decoded is not point:
        stats.record("string_point_decoded")
    if isinstance(decoded, list) and len(decoded) == 2 and all(_is_finite_number(value) for value in decoded):
        stats.record("point_array_normalized")
        return {"x": decoded[0], "y": decoded[1]}
    return decoded


_SEMANTIC_CONTOUR_CLOSURE_EPSILON = 1e-9
_SEMANTIC_EDGE_MIN_ORIENTATION_COSINE = math.cos(math.radians(12))
_SEMANTIC_EDGE_MIN_ORIGINAL_OVERLAP = 0.8
_SEMANTIC_EDGE_MAX_RELATIVE_PROJECTION_DISTANCE = 0.016


def _simplify_semantic_contour(
    contour: list[dict[str, float]],
) -> tuple[list[dict[str, float]], list[int | None]]:
    """Remove only exactly redundant collinear vertices from a valid contour.

    The returned mapping associates a provider edge only when orientation,
    projection distance and segment overlap establish one defensible semantic
    correspondence. ``None`` deliberately preserves uncertainty.
    """
    points = [_semantic_contour_point(point) for point in contour]
    if len(points) >= 2 and _semantic_points_equal(points[0], points[-1]):
        points.pop()
    if len(points) < 3:
        raise ValueError("Semantic contour requires at least three points")

    canonical_points = list(points)
    working = [(point, index) for index, point in enumerate(points)]
    # Short walls, corners, recesses and notches are architectural evidence.
    # Their size alone is never sufficient justification for deleting them.
    simplified, _ = _remove_redundant_collinear_vertices(working)
    if not _semantic_polygon_is_valid(simplified):
        return _semantic_contour_dicts(canonical_points), list(range(len(canonical_points)))

    semantic_points = [point for point, _ in simplified]
    mapping = [
        _nearest_semantic_edge_index(
            start=canonical_points[index],
            end=canonical_points[(index + 1) % len(canonical_points)],
            semantic_points=semantic_points,
        )
        for index in range(len(canonical_points))
    ]
    # A simplified contour is usable only when every original edge retains one
    # unambiguous semantic wall. Otherwise preserve the original geometry and
    # its identity mapping instead of guessing.
    if any(edge_index is None for edge_index in mapping):
        return _semantic_contour_dicts(canonical_points), list(range(len(canonical_points)))
    return _semantic_contour_dicts(semantic_points), mapping


def _semantic_contour_point(point: dict[str, float]) -> tuple[float, float]:
    x = point.get("x")
    y = point.get("y")
    if not (_is_finite_number(x) and _is_finite_number(y) and 0 <= x <= 1 and 0 <= y <= 1):
        raise ValueError("Semantic contour points must be finite and normalized")
    return float(x), float(y)


def _semantic_points_equal(first: tuple[float, float], second: tuple[float, float]) -> bool:
    return math.hypot(first[0] - second[0], first[1] - second[1]) <= _SEMANTIC_CONTOUR_CLOSURE_EPSILON


def _semantic_contour_dicts(points: list[tuple[float, float]]) -> list[dict[str, float]]:
    return [{"x": x, "y": y} for x, y in points]


def _remove_redundant_collinear_vertices(
    working: list[tuple[tuple[float, float], int]],
) -> tuple[list[tuple[tuple[float, float], int]], set[int]]:
    simplified = list(working)
    removed_indexes: set[int] = set()
    while len(simplified) > 3:
        removal: int | None = None
        for index in range(len(simplified)):
            previous = simplified[(index - 1) % len(simplified)][0]
            current = simplified[index][0]
            following = simplified[(index + 1) % len(simplified)][0]
            if not _semantic_point_is_between(previous, current, following):
                continue
            candidate = [item for item_index, item in enumerate(simplified) if item_index != index]
            if _semantic_polygon_is_valid(candidate):
                removal = index
                break
        if removal is None:
            break
        removed_indexes.add(simplified[removal][1])
        simplified = [item for index, item in enumerate(simplified) if index != removal]
    return simplified, removed_indexes


def _semantic_point_is_between(
    previous: tuple[float, float], current: tuple[float, float], following: tuple[float, float]
) -> bool:
    cross = (current[0] - previous[0]) * (following[1] - previous[1]) - (current[1] - previous[1]) * (
        following[0] - previous[0]
    )
    # Only an exactly collinear intermediate point is redundant. A tolerance
    # here could erase a genuine shallow corner or recess.
    if cross != 0.0:
        return False
    return (
        min(previous[0], following[0]) <= current[0] <= max(previous[0], following[0])
        and min(previous[1], following[1]) <= current[1] <= max(previous[1], following[1])
    )


def _semantic_polygon_is_valid(working: list[tuple[tuple[float, float], int]]) -> bool:
    points = [Point(x=point[0], y=point[1]) for point, _ in working]
    return (
        len(points) >= 3
        and not _has_zero_length_edge(points)
        and abs(_signed_area(points)) >= 1e-6
        and not _self_intersects(points)
    )


def _nearest_semantic_edge_index(
    *,
    start: tuple[float, float],
    end: tuple[float, float],
    semantic_points: list[tuple[float, float]],
) -> int | None:
    original_x = end[0] - start[0]
    original_y = end[1] - start[1]
    original_length = math.hypot(original_x, original_y)
    if original_length <= _SEMANTIC_CONTOUR_CLOSURE_EPSILON:
        return None
    all_points = [start, end, *semantic_points]
    diagonal = math.hypot(
        max(point[0] for point in all_points) - min(point[0] for point in all_points),
        max(point[1] for point in all_points) - min(point[1] for point in all_points),
    )
    if diagonal <= _SEMANTIC_CONTOUR_CLOSURE_EPSILON:
        return None
    max_distance = diagonal * _SEMANTIC_EDGE_MAX_RELATIVE_PROJECTION_DISTANCE
    matches: list[tuple[float, float, float, int]] = []
    for index, semantic_start in enumerate(semantic_points):
        semantic_end = semantic_points[(index + 1) % len(semantic_points)]
        semantic_x = semantic_end[0] - semantic_start[0]
        semantic_y = semantic_end[1] - semantic_start[1]
        semantic_length = math.hypot(semantic_x, semantic_y)
        if semantic_length <= _SEMANTIC_CONTOUR_CLOSURE_EPSILON:
            continue
        orientation = abs(
            (original_x * semantic_x + original_y * semantic_y)
            / (original_length * semantic_length)
        )
        if orientation < _SEMANTIC_EDGE_MIN_ORIENTATION_COSINE:
            continue
        unit_x, unit_y = semantic_x / semantic_length, semantic_y / semantic_length
        start_projection = (
            (start[0] - semantic_start[0]) * unit_x
            + (start[1] - semantic_start[1]) * unit_y
        )
        end_projection = (
            (end[0] - semantic_start[0]) * unit_x
            + (end[1] - semantic_start[1]) * unit_y
        )
        overlap = max(
            0.0,
            min(max(start_projection, end_projection), semantic_length)
            - max(min(start_projection, end_projection), 0.0),
        )
        overlap_ratio = overlap / original_length
        if overlap_ratio < _SEMANTIC_EDGE_MIN_ORIGINAL_OVERLAP:
            continue
        start_distance = abs(
            semantic_x * (start[1] - semantic_start[1])
            - semantic_y * (start[0] - semantic_start[0])
        ) / semantic_length
        end_distance = abs(
            semantic_x * (end[1] - semantic_start[1])
            - semantic_y * (end[0] - semantic_start[0])
        ) / semantic_length
        projection_distance = max(start_distance, end_distance)
        if projection_distance > max_distance:
            continue
        matches.append((projection_distance, 1 - overlap_ratio, 1 - orientation, index))
    # More than one defensible match is still ambiguous; proximity must never
    # decide which logical wall receives physical evidence.
    return matches[0][3] if len(matches) == 1 else None


def _normalize_dimensions(
    dimensions: object,
    *,
    wall_count: int,
    stats: _NormalizationStats,
    edge_mapping: list[int | None] | None = None,
) -> object:
    if not isinstance(dimensions, list):
        return dimensions
    normalized: list[dict[str, Any]] = []
    for dimension in dimensions:
        if not isinstance(dimension, dict):
            stats.dropped_dimensions += 1
            stats.record("dimension_dropped_invalid_contract")
            continue
        literal_text = dimension.get("literalText")
        if not isinstance(literal_text, str) or not literal_text.strip():
            stats.dropped_dimensions += 1
            stats.record("dimension_dropped_missing_literal")
            continue
        candidate: dict[str, Any] = dict(dimension)
        status = candidate.get("status")
        if status not in {"proposed", "unresolved", "conflict"}:
            stats.dropped_dimensions += 1
            stats.record("dimension_dropped_invalid_contract")
            continue
        value = candidate.get("value")
        if value is not None and not _is_finite_number(value):
            stats.dropped_dimensions += 1
            stats.record("dimension_dropped_invalid_contract")
            continue
        if status == "proposed" and (value is None or value <= 0):
            stats.dropped_dimensions += 1
            stats.record("dimension_dropped_invalid_contract")
            continue
        unit = candidate.get("unit", "unknown")
        if not isinstance(unit, str) or not unit.strip() or len(unit) > 32:
            stats.dropped_dimensions += 1
            stats.record("dimension_dropped_invalid_contract")
            continue
        candidate["unit"] = unit
        changed = False
        if "edgeIndex" in candidate:
            provider_edge_index = candidate.get("edgeIndex")
            candidate["edgeIndex"] = _remap_provider_edge(provider_edge_index, edge_mapping)
            if (
                edge_mapping is not None
                and isinstance(provider_edge_index, int)
                and not isinstance(provider_edge_index, bool)
                and 0 <= provider_edge_index < len(edge_mapping)
                and candidate["edgeIndex"] is None
            ):
                changed = True
                stats.record("dimension_edge_mapping_unresolved")
        edge_index = candidate.get("edgeIndex")
        if edge_index is not None and (
            not isinstance(edge_index, int)
            or isinstance(edge_index, bool)
            or edge_index < 0
            or edge_index >= wall_count
        ):
            candidate["edgeIndex"] = None
            changed = True
            stats.record("dimension_edge_downgraded")
        if candidate["status"] == "proposed" and (
            candidate.get("edgeIndex") is None
            or candidate.get("unit") not in {"m", "cm", "mm"}
            or changed
        ):
            candidate["status"] = "unresolved"
            changed = True
            if candidate.get("edgeIndex") is None:
                stats.record("dimension_edge_unassociated")
            if candidate.get("unit") not in {"m", "cm", "mm"}:
                stats.record("unknown_unit_unresolved")
        if changed:
            stats.normalized_dimensions += 1
        normalized.append(candidate)
    return normalized


def _normalize_openings(
    openings: object,
    *,
    wall_count: int,
    stats: _NormalizationStats,
    edge_mapping: list[int | None] | None = None,
    provider_contour: list[dict[str, float]] | None = None,
    semantic_contour: list[dict[str, float]] | None = None,
) -> object:
    if not isinstance(openings, list):
        return openings
    normalized: list[dict[str, Any]] = []
    for opening in openings:
        if not isinstance(opening, dict):
            stats.dropped_openings += 1
            stats.record("opening_dropped_invalid_contract")
            continue
        has_canonical_edge_index = "edgeIndex" in opening
        edge_index = opening.get("edgeIndex")
        uses_wall_index_alias = not has_canonical_edge_index and "wallIndex" in opening
        if uses_wall_index_alias:
            edge_index = opening.get("wallIndex")
        provider_edge_index = edge_index
        edge_index = _remap_provider_edge(edge_index, edge_mapping)
        unassociated_edge = edge_index is None
        invalid_edge = not unassociated_edge and (
            not isinstance(edge_index, int)
            or isinstance(edge_index, bool)
            or edge_index < 0
            or edge_index >= wall_count
        )
        invalid_contract = (
            opening.get("type", "unknown")
            not in {
                "door",
                "window",
                "unknown",
            }
            or opening.get("status", "proposed") != "proposed"
        )
        if invalid_edge or invalid_contract:
            stats.dropped_openings += 1
            stats.record(
                "opening_dropped_invalid_edge" if invalid_edge else "opening_dropped_invalid_contract"
            )
            continue
        candidate: dict[str, Any] = dict(opening)
        candidate.pop("wallIndex", None)
        candidate["edgeIndex"] = edge_index
        if unassociated_edge:
            # Positional geometry has meaning only in the coordinate system of
            # a defensibly associated wall.
            had_positional_geometry = "position" in candidate or "normalizedWidth" in candidate
            candidate.pop("position", None)
            candidate.pop("normalizedWidth", None)
            if had_positional_geometry:
                stats.record("opening_geometry_unresolved_after_edge_mapping")
        if unassociated_edge:
            stats.record("opening_edge_unassociated")
        if uses_wall_index_alias and edge_index is not None:
            stats.record("opening_wall_index_alias_normalized")
        if (
            isinstance(provider_edge_index, int)
            and not isinstance(provider_edge_index, bool)
            and isinstance(edge_index, int)
            and provider_contour is not None
            and semantic_contour is not None
        ):
            _transform_opening_geometry_to_semantic_edge(
                candidate,
                provider_contour=provider_contour,
                provider_edge_index=provider_edge_index,
                semantic_contour=semantic_contour,
                semantic_edge_index=edge_index,
                stats=stats,
            )
        for key, lower, lower_inclusive in (
            ("position", 0.0, True),
            ("normalizedWidth", 0.0, False),
            ("confidence", 0.0, True),
        ):
            value = candidate.get(key)
            if value is None:
                continue
            valid = _is_finite_number(value) and value <= 1
            valid = valid and (value >= lower if lower_inclusive else value > lower)
            if not valid:
                candidate.pop(key, None)
                stats.record("opening_invalid_field_dropped")
        normalized.append(candidate)
    return normalized


def _transform_opening_geometry_to_semantic_edge(
    opening: dict[str, Any],
    *,
    provider_contour: list[dict[str, float]],
    provider_edge_index: int,
    semantic_contour: list[dict[str, float]],
    semantic_edge_index: int,
    stats: _NormalizationStats,
) -> None:
    """Express provider-edge opening evidence in the mapped semantic-edge coordinates."""
    if provider_edge_index >= len(provider_contour) or semantic_edge_index >= len(semantic_contour):
        return
    p0 = _semantic_contour_point(provider_contour[provider_edge_index])
    p1 = _semantic_contour_point(provider_contour[(provider_edge_index + 1) % len(provider_contour)])
    s0 = _semantic_contour_point(semantic_contour[semantic_edge_index])
    s1 = _semantic_contour_point(semantic_contour[(semantic_edge_index + 1) % len(semantic_contour)])
    if _semantic_points_equal(p0, s0) and _semantic_points_equal(p1, s1):
        return
    pdx, pdy = p1[0] - p0[0], p1[1] - p0[1]
    sdx, sdy = s1[0] - s0[0], s1[1] - s0[1]
    provider_length = math.hypot(pdx, pdy)
    semantic_squared = sdx * sdx + sdy * sdy
    semantic_length = math.sqrt(semantic_squared)
    diagonal = math.hypot(
        max(p["x"] for p in semantic_contour) - min(p["x"] for p in semantic_contour),
        max(p["y"] for p in semantic_contour) - min(p["y"] for p in semantic_contour),
    )
    if provider_length <= 0 or semantic_length <= 0 or diagonal <= 0:
        return
    position = opening.get("position")
    if not _is_finite_number(position):
        return
    qx, qy = p0[0] + float(position) * pdx, p0[1] + float(position) * pdy
    semantic_position = ((qx - s0[0]) * sdx + (qy - s0[1]) * sdy) / semantic_squared
    px, py = s0[0] + semantic_position * sdx, s0[1] + semantic_position * sdy
    if (
        -_OPENING_EDGE_PROJECTION_TOLERANCE <= semantic_position <= 1 + _OPENING_EDGE_PROJECTION_TOLERANCE
        and math.hypot(qx - px, qy - py) <= _OPENING_EDGE_PROJECTION_TOLERANCE * diagonal
    ):
        opening["position"] = semantic_position
        width = opening.get("normalizedWidth")
        if _is_finite_number(width):
            opening["normalizedWidth"] = float(width) * provider_length / semantic_length
        stats.record("opening_geometry_remapped_to_semantic_edge")
    else:
        opening.pop("position", None)
        opening.pop("normalizedWidth", None)
        stats.record("opening_geometry_unresolved_after_edge_mapping")


def _remap_provider_edge(edge_index: object, edge_mapping: list[int | None] | None) -> object:
    if (
        edge_mapping is not None
        and isinstance(edge_index, int)
        and not isinstance(edge_index, bool)
        and 0 <= edge_index < len(edge_mapping)
    ):
        return edge_mapping[edge_index]
    return edge_index


def _append_warning(container: dict[str, Any], warning: str) -> None:
    warnings = container.get("warnings")
    if not isinstance(warnings, list):
        warnings = []
    if warning not in warnings:
        warnings.append(warning)
    container["warnings"] = warnings


def _normalize_groq_response(raw: object) -> tuple[object, _NormalizationStats]:
    """Remove unsafe provider certainty without repairing or inventing evidence."""
    stats = _NormalizationStats()
    if not isinstance(raw, dict):
        return raw, stats
    normalized: dict[str, Any] = dict(raw)
    rooms = raw.get("rooms")
    if not isinstance(rooms, list):
        return normalized, stats
    normalized_rooms: list[object] = []
    for room in rooms:
        if not isinstance(room, dict):
            normalized_rooms.append(room)
            continue
        normalized_room: dict[str, Any] = dict(room)
        contour = _strict_json_container(room.get("contour"), list)
        if contour is not room.get("contour"):
            stats.record("string_contour_decoded")
        if isinstance(contour, list):
            normalized_contour = [_normalize_contour_point(point, stats) for point in contour]
            if _has_structurally_valid_contour(normalized_contour):
                simplified_contour, edge_mapping = _simplify_semantic_contour(
                    cast(list[dict[str, float]], normalized_contour)
                )
                if simplified_contour != normalized_contour:
                    stats.record("semantic_contour_simplified")
                normalized_room["contour"] = simplified_contour
                wall_count = len(simplified_contour)
                if room.get("wallCount") != wall_count:
                    stats.record("derived_wall_count")
                normalized_room["wallCount"] = wall_count
                normalized_room["dimensions"] = _normalize_dimensions(
                    room.get("dimensions", []),
                    wall_count=wall_count,
                    stats=stats,
                    edge_mapping=edge_mapping,
                )
                normalized_room["openings"] = _normalize_openings(
                    room.get("openings", []),
                    wall_count=wall_count,
                    stats=stats,
                    edge_mapping=edge_mapping,
                    provider_contour=cast(list[dict[str, float]], normalized_contour),
                    semantic_contour=simplified_contour,
                )
            else:
                normalized_room["contour"] = normalized_contour
        normalized_rooms.append(normalized_room)
    normalized["rooms"] = normalized_rooms
    if stats.dropped_dimensions:
        _append_warning(
            normalized,
            "Some dimension evidence was omitted because it could not be safely validated.",
        )
    if stats.dropped_openings:
        _append_warning(
            normalized,
            "Some opening evidence was omitted because its wall association was invalid.",
        )
    return normalized, stats


def _apply_quality_gate(
    result: FloorplanInterpretation, stats: _NormalizationStats
) -> FloorplanInterpretation:
    """Downgrade only combined, obvious unusability signals; never reinterpret geometry."""
    quality_reason: str | None = None
    for room in result.rooms:
        openings_without_geometry = sum(
            opening.position is None or opening.normalized_width is None for opening in room.openings
        )
        mostly_unusable_openings = bool(room.openings) and (
            openings_without_geometry / len(room.openings) >= 0.75
        )
        weak_dimension_evidence = len(room.dimensions) <= 3
        insufficient_corroboration = weak_dimension_evidence and (
            not room.openings or mostly_unusable_openings
        )
        if room.wall_count >= 20 and insufficient_corroboration:
            quality_reason = "oversegmentation"
            break
        if _has_suspicious_structural_complexity(room):
            quality_reason = "structural_complexity"
            break
    if quality_reason is None or result.status not in {"success", "partial"}:
        return result
    if quality_reason == "oversegmentation":
        stats.record("low_quality_oversegmentation")
        warning = "La propuesta automática presenta sobresegmentación y requiere corrección humana."
        needed = "Reintentar la interpretación o corregir la geometría manualmente."
    else:
        stats.record("low_quality_structural_complexity")
        warning = (
            "La topología de la habitación contiene transiciones estructurales "
            "inusualmente densas y debe revisarse."
        )
        needed = "Confirmar si las transiciones del contorno representan muros arquitectónicos reales."
    return result.model_copy(
        update={
            "status": "needs_review",
            "warnings": [*result.warnings, *([] if warning in result.warnings else [warning])],
            "information_still_needed": [
                *result.information_still_needed,
                *([] if needed in result.information_still_needed else [needed]),
            ],
        }
    )


def _has_suspicious_structural_complexity(room: Any) -> bool:
    """Identify review-worthy dense topology without changing a room candidate.

    A candidate is suspicious only when several scale-independent geometry
    signals agree and dimensions/openings do not independently corroborate its
    dense set of inferred wall transitions. This intentionally does not decide
    which walls are real, so it cannot fabricate a replacement contour.
    """
    points = [(point.x, point.y) for point in room.contour]
    if len(points) < _STRUCTURAL_SUSPICION_MIN_MEANINGFUL_TURNS:
        return False

    bounds_width = max(point[0] for point in points) - min(point[0] for point in points)
    bounds_height = max(point[1] for point in points) - min(point[1] for point in points)
    bounds_diagonal = math.hypot(bounds_width, bounds_height)
    if bounds_diagonal <= _SEMANTIC_CONTOUR_CLOSURE_EPSILON:
        return False

    edge_lengths = [
        math.dist(points[index], points[(index + 1) % len(points)]) for index in range(len(points))
    ]
    perimeter = sum(edge_lengths)
    if perimeter <= _SEMANTIC_CONTOUR_CLOSURE_EPSILON:
        return False

    meaningful_turns = sum(
        _structural_turn_angle_degrees(
            points[(index - 1) % len(points)], points[index], points[(index + 1) % len(points)]
        )
        >= _STRUCTURAL_SUSPICION_MIN_TURN_ANGLE_DEGREES
        for index in range(len(points))
    )
    compact_edge_fraction = sum(
        edge_length / bounds_diagonal <= _STRUCTURAL_SUSPICION_MAX_RELATIVE_COMPACT_EDGE
        for edge_length in edge_lengths
    ) / len(edge_lengths)
    turn_density = meaningful_turns * bounds_diagonal / perimeter

    dimension_edges = {
        dimension.edge_index for dimension in room.dimensions if dimension.edge_index is not None
    }
    complete_opening_edges = {
        opening.edge_index
        for opening in room.openings
        if opening.edge_index is not None
        and opening.position is not None
        and opening.normalized_width is not None
    }
    strong_corroboration = len(dimension_edges) >= 3 or (
        len(dimension_edges) >= 1 and len(complete_opening_edges) >= 3
    )
    return (
        meaningful_turns >= _STRUCTURAL_SUSPICION_MIN_MEANINGFUL_TURNS
        and compact_edge_fraction >= _STRUCTURAL_SUSPICION_MIN_COMPACT_EDGE_FRACTION
        and turn_density >= _STRUCTURAL_SUSPICION_MIN_TURN_DENSITY
        and not strong_corroboration
    )


def _structural_turn_angle_degrees(
    previous: tuple[float, float], current: tuple[float, float], following: tuple[float, float]
) -> float:
    incoming = current[0] - previous[0], current[1] - previous[1]
    outgoing = following[0] - current[0], following[1] - current[1]
    incoming_length = math.hypot(*incoming)
    outgoing_length = math.hypot(*outgoing)
    if (
        incoming_length <= _SEMANTIC_CONTOUR_CLOSURE_EPSILON
        or outgoing_length <= _SEMANTIC_CONTOUR_CLOSURE_EPSILON
    ):
        return 0.0
    cosine = (incoming[0] * outgoing[0] + incoming[1] * outgoing[1]) / (incoming_length * outgoing_length)
    return math.degrees(math.acos(max(-1.0, min(1.0, cosine))))


def _validation_details(error: ValidationError) -> tuple[str, str]:
    first = error.errors(include_url=False, include_input=False)[0]
    path = ".".join(str(part) for part in first.get("loc", ())) or "root"
    category = str(first.get("type", "validation_error"))
    known_reasons = {
        "wall_count_mismatch",
        "invalid_opening_edge",
        "invalid_dimension_edge",
        "invalid_contour",
    }
    reason = category if category in known_reasons else "contract_failure"
    return reason, f"path={path} category={category}"


_CORRECTIVE_INSTRUCTIONS = {
    "wall_count_mismatch": (
        "Your previous proposal had a wallCount that did not match the semantic contour. "
        "Re-evaluate the original image and return one contour vertex per semantic wall. "
        "Do not invent or remove architectural walls merely to satisfy the count."
    ),
    "invalid_contour": (
        "Your previous room contour was rejected as geometrically invalid. Re-read the original image "
        "and focus on the dominant room's semantic perimeter. Return one vertex per real "
        "architectural wall transition or corner, in consistent order. Return a simple, non-degenerate, "
        "non-self-intersecting contour closed by implication; do not repeat the first point as the last "
        "point. Ignore door swing arcs, window strokes and window detail strokes, wall thickness bands, "
        "furniture, text, dimensions, and construction lines as contour edges. Preserve genuine irregular, "
        "L-shaped, concave, angled, and pentagonal geometry; do not force a rectangle. Do not invent "
        "missing walls or remove real architectural walls to reach a target count."
    ),
    "invalid_opening_edge": (
        "Your previous proposal referenced an opening outside the room's valid wall indexes. "
        "Re-evaluate the opening-to-wall association from the original image. Omit an uncertain "
        "opening association instead of guessing an edge."
    ),
    "invalid_dimension_edge": (
        "Your previous proposal referenced a dimension outside the room's valid wall indexes. "
        "Re-evaluate the dimension-to-wall association. Use edgeIndex only when the association "
        "is reliable; otherwise leave it absent/null."
    ),
    "contract_failure": (
        "Your previous proposal did not satisfy the required JSON/domain contract. Re-evaluate "
        "the original floor plan and return a new proposal. Do not invent missing evidence."
    ),
}


class GroqFloorplanInterpreter:
    def __init__(
        self,
        *,
        api_key: str | None,
        model: str,
        timeout_seconds: int,
        client: httpx.AsyncClient | None = None,
        sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
    ) -> None:
        self._api_key = api_key
        self._model = model
        self._timeout = timeout_seconds
        self._client = client
        self._sleep = sleep

    async def interpret(self, *, image: bytes, content_type: str) -> FloorplanInterpretation:
        started = monotonic()
        diagnostic_id = f"fp-{uuid4().hex[:8]}"
        if not self._api_key:
            LOGGER.warning(
                "[RoomForge][FloorplanInterpretation] floorplanDiag=%s provider=groq "
                "attempt=1 result=provider_unavailable reason=configuration_missing "
                "providerStatus=None retryAfterMs=None rooms=0 elapsedMs=%d",
                diagnostic_id,
                round((monotonic() - started) * 1000),
            )
            raise ProviderUnavailable(retryable=False, reason="configuration_missing")
        owned = self._client is None
        client = self._client or httpx.AsyncClient(timeout=self._timeout)
        corrective_instruction: str | None = None
        response_max_tokens = _DEFAULT_RESPONSE_MAX_TOKENS
        try:
            for attempt in (1, 2):
                try:
                    remaining = self._timeout - (monotonic() - started)
                    if remaining <= 0:
                        raise ProviderUnavailable(reason="timeout")
                    try:
                        result, stats = await asyncio.wait_for(
                            self._attempt(
                                client=client,
                                image=image,
                                content_type=content_type,
                                corrective_instruction=corrective_instruction,
                                max_tokens=response_max_tokens,
                                attempt=attempt,
                                diagnostic_id=diagnostic_id,
                            ),
                            timeout=remaining,
                        )
                    except TimeoutError:
                        raise ProviderUnavailable(reason="timeout") from None
                except ProviderUnavailable as exc:
                    provider_outcome = {
                        "timeout": "PROVIDER_TIMEOUT",
                        "rate_limited": "PROVIDER_RATE_LIMITED",
                        "network_failure": "PROVIDER_NETWORK_FAILURE",
                        "provider_5xx": "PROVIDER_5XX",
                    }.get(exc.reason)
                    if exc.provider_status in {401, 403}:
                        provider_outcome = "PROVIDER_AUTH_FAILURE"
                    provider_outcome = provider_outcome or "PROVIDER_UNAVAILABLE"
                    LOGGER.warning(
                        "[RoomForge][FloorplanInterpretation] floorplanDiag=%s provider=groq "
                        "attempt=%d result=provider_unavailable reason=%s providerStatus=%s "
                        "providerOutcome=%s retryAfterMs=%s rooms=0 elapsedMs=%d",
                        diagnostic_id,
                        attempt,
                        exc.reason,
                        exc.provider_status,
                        provider_outcome,
                        (
                            round(exc.retry_after_seconds * 1000)
                            if exc.retry_after_seconds is not None
                            else None
                        ),
                        round((monotonic() - started) * 1000),
                    )
                    if attempt == 1 and exc.retryable:
                        delay = (
                            exc.retry_after_seconds
                            if exc.reason == "rate_limited" and exc.retry_after_seconds is not None
                            else (
                                _RATE_LIMIT_FALLBACK_DELAY_SECONDS
                                if exc.reason == "rate_limited"
                                else _FALLBACK_RETRY_DELAY_SECONDS
                            )
                        )
                        remaining = self._timeout - (monotonic() - started)
                        if delay >= remaining:
                            raise ProviderUnavailable(reason="timeout") from None
                        await self._sleep(delay)
                        continue
                    if (
                        attempt == 2
                        and corrective_instruction is not None
                        and exc.reason == "rate_limited"
                        and exc.retryable
                    ):
                        # A short transport-level rate limit on the corrective
                        # semantic attempt must not consume a third semantic
                        # attempt. Permit at most one repeat with the SAME prompt.
                        delay = (
                            exc.retry_after_seconds
                            if exc.retry_after_seconds is not None
                            else _RATE_LIMIT_FALLBACK_DELAY_SECONDS
                        )
                        remaining = self._timeout - (monotonic() - started)
                        if delay >= remaining:
                            raise ProviderUnavailable(reason="timeout") from None
                        await self._sleep(delay)
                        remaining = self._timeout - (monotonic() - started)
                        if remaining <= 0:
                            raise ProviderUnavailable(reason="timeout") from None
                        try:
                            result, stats = await asyncio.wait_for(
                                self._attempt(
                                    client=client,
                                    image=image,
                                    content_type=content_type,
                                    corrective_instruction=corrective_instruction,
                                    max_tokens=response_max_tokens,
                                    attempt=attempt,
                                    diagnostic_id=diagnostic_id,
                                ),
                                timeout=remaining,
                            )
                        except TimeoutError:
                            raise ProviderUnavailable(reason="timeout") from None
                        # A second rate limit (or any other error) propagates;
                        # never retry indefinitely or modify the proposal.
                    else:
                        if attempt == 2:
                            LOGGER.warning(
                                "[RoomForge][FloorplanInterpretation] floorplanDiag=%s provider=groq "
                                "attempts=2 result=provider_unavailable",
                                diagnostic_id,
                            )
                        raise
                except InvalidProviderResponse as exc:
                    LOGGER.warning(
                        "[RoomForge][FloorplanInterpretation] floorplanDiag=%s provider=groq attempt=%d "
                        "result=invalid_provider_response providerOutcome=CONTRACT_FAILURE "
                        "reason=%s elapsedMs=%d %s",
                        diagnostic_id,
                        attempt,
                        exc.reason,
                        round((monotonic() - started) * 1000),
                        exc.summary,
                    )
                    if attempt == 1:
                        corrective_instruction = _CORRECTIVE_INSTRUCTIONS[exc.reason]
                        response_max_tokens = (
                            _TOPOLOGY_RESCUE_MAX_TOKENS
                            if exc.reason == "invalid_contour"
                            else _DEFAULT_RESPONSE_MAX_TOKENS
                        )
                        continue
                    LOGGER.warning(
                        "[RoomForge][FloorplanInterpretation] floorplanDiag=%s provider=groq "
                        "attempts=2 result=invalid_provider_response reason=%s",
                        diagnostic_id,
                        exc.reason,
                    )
                    raise
                LOGGER.info(
                    "[RoomForge][FloorplanInterpretation] floorplanDiag=%s provider=groq "
                    "attempt=%d result=success rooms=%d normalizedDimensions=%d "
                    "droppedDimensions=%d droppedOpenings=%d elapsedMs=%d",
                    diagnostic_id,
                    attempt,
                    len(result.rooms),
                    stats.normalized_dimensions,
                    stats.dropped_dimensions,
                    stats.dropped_openings,
                    round((monotonic() - started) * 1000),
                )
                return result
        finally:
            if owned:
                await client.aclose()
        raise RuntimeError("Unreachable floor-plan interpreter state")

    async def _attempt(
        self,
        *,
        client: httpx.AsyncClient,
        image: bytes,
        content_type: str,
        corrective_instruction: str | None,
        max_tokens: int,
        attempt: int,
        diagnostic_id: str,
    ) -> tuple[FloorplanInterpretation, _NormalizationStats]:
        prompt = SYSTEM_PROMPT
        if corrective_instruction is not None:
            prompt = f"{prompt}\n\nCORRECTIVE RETRY:\n{corrective_instruction}"
        payload = {
            "model": self._model,
            "temperature": 0,
            "max_tokens": max_tokens,
            "response_format": {"type": "json_object"},
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:{content_type};base64,{base64.b64encode(image).decode('ascii')}"
                            },
                        },
                    ],
                }
            ],
        }
        try:
            response = await client.post(
                "https://api.groq.com/openai/v1/chat/completions",
                headers={"Authorization": f"Bearer {self._api_key}"},
                json=payload,
            )
            if response.status_code == 429:
                retry_after_header = response.headers.get("Retry-After")
                retry_after = _parse_retry_after(retry_after_header)
                excessive_retry_after = _retry_after_is_excessive(retry_after_header)
                raise ProviderUnavailable(
                    retryable=not excessive_retry_after,
                    reason="rate_limited",
                    provider_status=429,
                    retry_after_seconds=retry_after,
                )
            if response.status_code >= 500:
                raise ProviderUnavailable(reason="provider_5xx", provider_status=response.status_code)
            if response.status_code >= 400:
                raise ProviderUnavailable(
                    retryable=False,
                    reason="nonretryable_provider_error",
                    provider_status=response.status_code,
                )
            try:
                content = response.json()["choices"][0]["message"]["content"]
                if not isinstance(content, str):
                    raise TypeError
                raw = json.loads(content)
                LOGGER.info(
                    "[RoomForge][FloorplanProviderRaw] floorplanDiag=%s attempt=%d provider=groq "
                    "httpStatus=%d contentType=json contentChars=%d",
                    diagnostic_id,
                    attempt,
                    response.status_code,
                    len(content),
                )
                raw_summary = _sanitize_diagnostic_text(
                    json.dumps(_provider_semantic_summary(raw), ensure_ascii=True, separators=(",", ":")),
                    secrets=(self._api_key or "",),
                )
                LOGGER.info(
                    "[RoomForge][FloorplanProviderRaw] floorplanDiag=%s attempt=%d "
                    "providerOutcome=VALID_MODEL_RESPONSE rawSummary=%s",
                    diagnostic_id,
                    attempt,
                    raw_summary,
                )
                normalized, stats = _normalize_groq_response(raw)
                result = FloorplanInterpretation.model_validate(normalized)
                result = _apply_quality_gate(result, stats)
            except ValidationError as exc:
                reason, summary = _validation_details(exc)
                room_count, offending_type = _raw_validation_context(raw, exc)
                LOGGER.warning(
                    "[RoomForge][FloorplanContractFailure] floorplanDiag=%s attempt=%d %s "
                    "rawJsonValid=true rooms=%s offendingType=%s",
                    diagnostic_id,
                    attempt,
                    summary,
                    room_count,
                    offending_type,
                )
                raise InvalidProviderResponse(summary, reason=reason) from None
            except json.JSONDecodeError:
                LOGGER.warning(
                    "[RoomForge][FloorplanProviderRaw] floorplanDiag=%s attempt=%d provider=groq "
                    "httpStatus=%d contentType=text providerOutcome=CONTRACT_FAILURE "
                    "rawJsonValid=false contentChars=%d "
                    "preview=%s",
                    diagnostic_id,
                    attempt,
                    response.status_code,
                    len(content),
                    _sanitize_diagnostic_text(content, secrets=(self._api_key or "",)),
                )
                raise InvalidProviderResponse(
                    "path=response category=malformed_json", reason="contract_failure"
                ) from None
            except (KeyError, TypeError, ValueError):
                raise InvalidProviderResponse(
                    "path=response category=malformed_json", reason="contract_failure"
                ) from None
            LOGGER.info(
                "[RoomForge][FloorplanNormalized] floorplanDiag=%s attempt=%d result=%s rooms=%d "
                "roomWalls=%s roomDimensions=%s roomOpenings=%s normalizationActions=%s "
                "providerOutcome=%s",
                diagnostic_id,
                attempt,
                result.status,
                len(result.rooms),
                [room.wall_count for room in result.rooms],
                [len(room.dimensions) for room in result.rooms],
                [len(room.openings) for room in result.rooms],
                stats.actions,
                "MODEL_LOW_CONFIDENCE" if result.status == "low_confidence" else "VALID_MODEL_RESPONSE",
            )
            return result, stats
        except httpx.TimeoutException:
            raise ProviderUnavailable(reason="timeout") from None
        except httpx.NetworkError:
            raise ProviderUnavailable(reason="network_failure") from None


def _parse_retry_after(value: str | None) -> float | None:
    if value is None:
        return None
    try:
        seconds = float(value)
    except ValueError:
        return None
    if not math.isfinite(seconds) or not 0 <= seconds <= _MAX_RETRY_AFTER_SECONDS:
        return None
    return seconds


def _retry_after_is_excessive(value: str | None) -> bool:
    if value is None:
        return False
    try:
        seconds = float(value)
    except ValueError:
        return False
    return math.isfinite(seconds) and seconds > _MAX_RETRY_AFTER_SECONDS
