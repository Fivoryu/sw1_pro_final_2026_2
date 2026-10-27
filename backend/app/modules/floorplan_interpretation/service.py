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
from typing import Any, Protocol, TypeGuard
from uuid import uuid4

import httpx
from pydantic import ValidationError

from app.modules.floorplan_interpretation.schemas import FloorplanInterpretation


SYSTEM_PROMPT = """Return one concise JSON object describing architectural room candidates in the image.
First identify closed architectural spaces. Return one RoomCandidate per defensible room; internal partitions separate
rooms and must not become one mega-room contour. A semantic wall is one continuous room-perimeter segment ending only at
a material direction or topology change. Doors, windows, gaps, wall thickness, furniture, labels, hatching, and
dimension/extension lines do not split or create walls. Double wall bands are one wall.
Preserve L-shaped, concave, angled, pentagonal, and other irregular geometry; never force rectangles or orthogonality.
Hand sketches may yield partial or needs_review candidates when closed topology is defensible. Otherwise return
low_confidence with no rooms. Geometry recognition must not depend on the plan language.
After topology, report openings only when their wall association is reliable. Report dimensions only as visible evidence:
every item requires literalText exactly as read and status proposed | unresolved | conflict. proposed requires a finite
positive value and visible metric unit m/cm/mm. Bare numbers use unit unknown and unresolved. Assign edgeIndex only when
dimension orientation, line/endpoints, and wall alignment support it; proximity alone is insufficient.
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


def _normalize_dimensions(dimensions: object, *, wall_count: int, stats: _NormalizationStats) -> object:
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
        if candidate.get("unit") not in {"m", "cm", "mm", "unknown"}:
            stats.dropped_dimensions += 1
            stats.record("dimension_dropped_invalid_contract")
            continue
        changed = False
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
        if candidate["status"] == "proposed" and (candidate.get("unit") == "unknown" or changed):
            candidate["status"] = "unresolved"
            changed = True
            if candidate.get("unit") == "unknown":
                stats.record("unknown_unit_unresolved")
        if changed:
            stats.normalized_dimensions += 1
        normalized.append(candidate)
    return normalized


def _normalize_openings(openings: object, *, wall_count: int, stats: _NormalizationStats) -> object:
    if not isinstance(openings, list):
        return openings
    normalized: list[dict[str, Any]] = []
    for opening in openings:
        if not isinstance(opening, dict):
            stats.dropped_openings += 1
            stats.record("opening_dropped_invalid_contract")
            continue
        edge_index = opening.get("edgeIndex")
        invalid_edge = (
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
            normalized_room["contour"] = normalized_contour
            if _has_structurally_valid_contour(normalized_contour):
                wall_count = len(normalized_contour)
                if room.get("wallCount") != wall_count:
                    stats.record("derived_wall_count")
                normalized_room["wallCount"] = wall_count
                normalized_room["dimensions"] = _normalize_dimensions(
                    room.get("dimensions", []), wall_count=wall_count, stats=stats
                )
                normalized_room["openings"] = _normalize_openings(
                    room.get("openings", []), wall_count=wall_count, stats=stats
                )
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
    low_quality = False
    for room in result.rooms:
        openings_without_geometry = sum(
            opening.position is None or opening.normalized_width is None for opening in room.openings
        )
        mostly_unusable_openings = bool(room.openings) and (
            openings_without_geometry / len(room.openings) >= 0.75
        )
        no_useful_evidence = not room.dimensions and (not room.openings or mostly_unusable_openings)
        if room.wall_count >= 20 and no_useful_evidence:
            low_quality = True
            break
    if not low_quality or result.status not in {"success", "partial"}:
        return result
    stats.record("low_quality_oversegmentation")
    warning = "La propuesta automática presenta sobresegmentación y requiere corrección humana."
    needed = "Reintentar la interpretación o corregir la geometría manualmente."
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
        "Your previous room contour was rejected as geometrically invalid. Re-evaluate the room "
        "topology directly from the original image. Return a simple, non-degenerate, "
        "non-self-intersecting semantic wall contour. Do not invent geometry to force validity."
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
        try:
            for attempt in (1, 2):
                try:
                    result, stats = await self._attempt(
                        client=client,
                        image=image,
                        content_type=content_type,
                        corrective_instruction=corrective_instruction,
                        attempt=attempt,
                        diagnostic_id=diagnostic_id,
                    )
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
                        await self._sleep(delay)
                        continue
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
        attempt: int,
        diagnostic_id: str,
    ) -> tuple[FloorplanInterpretation, _NormalizationStats]:
        prompt = SYSTEM_PROMPT
        if corrective_instruction is not None:
            prompt = f"{prompt}\n\nCORRECTIVE RETRY:\n{corrective_instruction}"
        payload = {
            "model": self._model,
            "temperature": 0,
            "max_tokens": 900,
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
