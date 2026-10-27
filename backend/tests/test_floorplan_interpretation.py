from __future__ import annotations

import asyncio
import json
import logging
import math
import re
from typing import Any, cast

import httpx
import pytest
from pydantic import ValidationError

from app.core.config import Settings
from app.modules.floorplan_interpretation.schemas import FloorplanInterpretation
from app.modules.floorplan_interpretation.service import (
    LOGGER,
    SYSTEM_PROMPT,
    GroqFloorplanInterpreter,
    InvalidProviderResponse,
    ProviderUnavailable,
)


def test_floorplan_logger_emits_info_without_changing_global_logging() -> None:
    root = logging.getLogger()
    root_level = root.level
    root_handlers = tuple(root.handlers)

    assert LOGGER.name == "roomforge.floorplan_interpretation"
    assert LOGGER.isEnabledFor(logging.INFO)
    assert LOGGER.isEnabledFor(logging.WARNING)
    assert LOGGER.isEnabledFor(logging.ERROR)
    assert LOGGER.level == logging.INFO
    assert LOGGER.propagate
    assert LOGGER.handlers == []
    assert root.level == root_level
    assert tuple(root.handlers) == root_handlers


def test_floorplan_provider_default_timeout_is_30_seconds() -> None:
    settings = Settings(
        database_url="postgresql://local",
        jwt_secret="x" * 32,
        totp_encryption_key="local-key",
        web_origin="http://127.0.0.1:5173",
    )
    assert settings.groq_floorplan_timeout_seconds == 30


def _provider_response(document: dict[str, object], status: int = 200) -> httpx.Response:
    return httpx.Response(
        status,
        json={"choices": [{"message": {"content": json.dumps(document)}}]},
    )


def _sequential_transport(
    outcomes: list[httpx.Response | Exception],
    prompts: list[str] | None = None,
) -> tuple[httpx.MockTransport, list[int]]:
    calls: list[int] = []

    def handler(request: httpx.Request) -> httpx.Response:
        index = len(calls)
        calls.append(index + 1)
        if prompts is not None:
            body = json.loads(request.content)
            prompts.append(body["messages"][0]["content"][0]["text"])
        outcome = outcomes[index]
        if isinstance(outcome, Exception):
            raise outcome
        return outcome

    return httpx.MockTransport(handler), calls


def _room() -> dict[str, object]:
    return {
        "id": "candidate-c",
        "contour": [
            {"x": 0.1, "y": 0.1},
            {"x": 0.7, "y": 0.1},
            {"x": 0.9, "y": 0.5},
            {"x": 0.65, "y": 0.9},
            {"x": 0.1, "y": 0.8},
        ],
        "wallCount": 5,
        "openings": [
            {"edgeIndex": 0, "type": "window", "position": 0.3, "status": "proposed"},
            {"edgeIndex": 0, "type": "window", "position": 0.7, "status": "proposed"},
            {"edgeIndex": 3, "type": "door", "position": 0.5, "status": "proposed"},
        ],
        "dimensions": [
            {
                "edgeIndex": 2,
                "literalText": "419",
                "value": 419,
                "unit": "unknown",
                "provenance": "ai_detected",
                "status": "unresolved",
            }
        ],
    }


def _pentagon() -> dict[str, object]:
    return {
        "status": "partial",
        "confidence": 0.9,
        "rooms": [_room()],
        "ambiguities": ["La lectura 419 debe verificarse contra el plano."],
        "informationStillNeeded": ["Confirmar las cinco medidas."],
        "provenance": "ai_proposal",
    }


def _with_dimension(dimension: dict[str, object]) -> dict[str, object]:
    return {**_pentagon(), "rooms": [{**_room(), "dimensions": [dimension]}]}


def test_system_prompt_documents_dimension_status_contract() -> None:
    prompt = " ".join(SYSTEM_PROMPT.split()).lower()

    assert "proposed | unresolved | conflict" in prompt
    assert "literaltext exactly as read" in prompt
    assert "visible metric unit m/cm/mm" in prompt
    assert "bare numbers use unit unknown and unresolved" in prompt
    assert "proximity alone is insufficient" in prompt
    assert "never fabricate geometry, text, units, dimensions" in prompt
    assert "roomforge performs deterministic validation and metric solving" in prompt


def test_system_prompt_documents_semantic_room_interpretation_rules() -> None:
    prompt = " ".join(SYSTEM_PROMPT.split()).lower()

    assert "one roomcandidate per defensible room" in prompt
    assert "internal partitions separate rooms" in prompt
    assert "must not become one mega-room contour" in prompt
    assert "one continuous room-perimeter segment" in prompt
    assert "doors, windows, gaps, wall thickness" in prompt
    assert "do not split or create walls" in prompt
    assert "double wall bands are one wall" in prompt
    assert "preserve l-shaped, concave, angled, pentagonal" in prompt
    assert "never force rectangles or orthogonality" in prompt
    assert "hand sketches may yield partial or needs_review" in prompt
    assert "geometry recognition must not depend on the plan language" in prompt
    assert "return json only" in prompt


def _l_room_with_list_contour() -> dict[str, Any]:
    return {
        "status": "success",
        "rooms": [
            {
                "id": "room_1",
                "label": "L-shaped room",
                "contour": [
                    [0.06, 0.06],
                    [0.94, 0.06],
                    [0.94, 0.38],
                    [0.52, 0.38],
                    [0.52, 0.69],
                    [0.06, 0.69],
                ],
                "wallCount": 6,
                "openings": [],
                "dimensions": [
                    {
                        "edgeIndex": 0,
                        "literalText": "7 m",
                        "value": 7.0,
                        "unit": "m",
                        "status": "proposed",
                        "provenance": "ai_detected",
                    }
                ],
                "confidence": 0.95,
            }
        ],
        "provenance": "ai_proposal",
    }


def test_groq_normalizes_list_contour_to_canonical_points() -> None:
    async def run() -> FloorplanInterpretation:
        transport = httpx.MockTransport(lambda request: _provider_response(_l_room_with_list_contour()))
        async with httpx.AsyncClient(transport=transport) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key", model="model", timeout_seconds=2, client=client
            ).interpret(image=b"image", content_type="image/png")

    result = asyncio.run(run())
    assert [point.model_dump() for point in result.rooms[0].contour] == [
        {"x": 0.06, "y": 0.06},
        {"x": 0.94, "y": 0.06},
        {"x": 0.94, "y": 0.38},
        {"x": 0.52, "y": 0.38},
        {"x": 0.52, "y": 0.69},
        {"x": 0.06, "y": 0.69},
    ]


@pytest.mark.parametrize(
    "point",
    [
        "[0.06, 0.06]",
        '{"x": 0.06, "y": 0.06}',
    ],
    ids=["json-string-array", "json-string-object"],
)
def test_groq_normalizes_strict_json_string_points(point: str) -> None:
    document = _l_room_with_list_contour()
    room = cast(dict[str, Any], document["rooms"][0])
    cast(list[object], room["contour"])[0] = point

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda request: _provider_response(document))
        ) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key", model="model", timeout_seconds=2, client=client
            ).interpret(image=b"image", content_type="image/png")

    first = asyncio.run(run()).rooms[0].contour[0]
    assert (first.x, first.y) == (0.06, 0.06)


def test_groq_normalizes_strict_json_string_contour() -> None:
    document = _l_room_with_list_contour()
    room = cast(dict[str, Any], document["rooms"][0])
    room["contour"] = json.dumps(room["contour"])

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda request: _provider_response(document))
        ) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key", model="model", timeout_seconds=2, client=client
            ).interpret(image=b"image", content_type="image/png")

    assert asyncio.run(run()).rooms[0].wall_count == 6


@pytest.mark.parametrize(
    "bad_point",
    [[0.1], [0.1, 0.2, 0.3], ["0.1", 0.2], [float("nan"), 0.2], [float("inf"), 0.2]],
    ids=["short", "long", "nonnumeric", "nan", "infinity"],
)
def test_groq_rejects_malformed_contour_arrays(bad_point: list[object]) -> None:
    document = _l_room_with_list_contour()
    room = cast(dict[str, Any], document["rooms"][0])
    cast(list[object], room["contour"])[0] = bad_point

    async def run() -> None:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda request: _provider_response(document))
        ) as client:
            with pytest.raises(InvalidProviderResponse):
                await GroqFloorplanInterpreter(
                    api_key="test-key", model="model", timeout_seconds=2, client=client
                ).interpret(image=b"image", content_type="image/png")

    asyncio.run(run())


@pytest.mark.parametrize(
    "bad_point",
    ["[0.25]", "[0.25, 0.80, 0.90]", "0.25,0.80", "point near upper-left"],
)
def test_groq_rejects_malformed_or_prose_string_points(bad_point: str) -> None:
    document = _l_room_with_list_contour()
    room = cast(dict[str, Any], document["rooms"][0])
    cast(list[object], room["contour"])[0] = bad_point

    async def run() -> None:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda request: _provider_response(document))
        ) as client:
            with pytest.raises(InvalidProviderResponse):
                await GroqFloorplanInterpreter(
                    api_key="test-key", model="model", timeout_seconds=2, client=client
                ).interpret(image=b"image", content_type="image/png")

    asyncio.run(run())


def test_missing_literal_text_is_rejected_without_fabrication() -> None:
    dimension = {
        "edgeIndex": 0,
        "value": 7.0,
        "unit": "m",
        "status": "proposed",
        "provenance": "ai_detected",
    }
    with pytest.raises(ValidationError):
        FloorplanInterpretation.model_validate(_with_dimension(dimension))


def test_complete_proposed_dimension_is_accepted_as_review_evidence() -> None:
    dimension = {
        "edgeIndex": 0,
        "literalText": "7 m",
        "value": 7.0,
        "unit": "m",
        "status": "proposed",
        "provenance": "ai_detected",
    }
    parsed = FloorplanInterpretation.model_validate(_with_dimension(dimension)).rooms[0].dimensions[0]
    assert parsed.literal_text == "7 m"
    assert parsed.edge_index == 0
    assert parsed.status == "proposed"


def test_valid_first_attempt_makes_exactly_one_provider_request() -> None:
    transport, calls = _sequential_transport([_provider_response(_l_room_with_list_contour())])

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(transport=transport) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key", model="model", timeout_seconds=2, client=client
            ).interpret(image=b"image", content_type="image/png")

    assert len(asyncio.run(run()).rooms) == 1
    assert calls == [1]


def test_invalid_dimension_edge_is_downgraded_without_retry(
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.INFO, logger="roomforge.floorplan_interpretation")
    document = _l_room_with_list_contour()
    dimension = cast(dict[str, Any], document["rooms"][0])["dimensions"][0]
    cast(dict[str, Any], dimension)["edgeIndex"] = 8
    transport, calls = _sequential_transport([_provider_response(document)])

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(transport=transport) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key", model="model", timeout_seconds=2, client=client
            ).interpret(image=b"image", content_type="image/png")

    result = asyncio.run(run())
    preserved = result.rooms[0].dimensions[0]
    assert calls == [1]
    assert preserved.literal_text == "7 m"
    assert preserved.value == 7.0
    assert preserved.edge_index is None
    assert preserved.status == "unresolved"
    assert "normalizedDimensions=1" in caplog.text
    assert "droppedDimensions=0" in caplog.text
    assert "droppedOpenings=0" in caplog.text
    assert "dimension_edge_downgraded" in caplog.text
    assert "point_array_normalized" in caplog.text


def test_wall_count_is_derived_from_valid_contour_without_retry() -> None:
    document = _l_room_with_list_contour()
    cast(dict[str, Any], document["rooms"][0])["wallCount"] = 7
    transport, calls = _sequential_transport([_provider_response(document)])

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(transport=transport) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key", model="model", timeout_seconds=2, client=client
            ).interpret(image=b"image", content_type="image/png")

    result = asyncio.run(run())
    assert result.rooms[0].wall_count == 6
    assert calls == [1]


def test_invalid_opening_edge_is_omitted_without_retry() -> None:
    document = _l_room_with_list_contour()
    cast(dict[str, Any], document["rooms"][0])["openings"] = [
        {"edgeIndex": 9, "type": "door", "status": "proposed"}
    ]
    transport, calls = _sequential_transport([_provider_response(document)])

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(transport=transport) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key", model="model", timeout_seconds=2, client=client
            ).interpret(image=b"image", content_type="image/png")

    result = asyncio.run(run())
    assert result.rooms[0].openings == []
    assert calls == [1]


def _many_wall_room(*, wall_count: int, with_dimension: bool) -> dict[str, object]:
    contour = [
        {
            "x": 0.5 + 0.4 * math.cos(2 * math.pi * index / wall_count),
            "y": 0.5 + 0.4 * math.sin(2 * math.pi * index / wall_count),
        }
        for index in range(wall_count)
    ]
    dimensions: list[dict[str, object]] = []
    if with_dimension:
        dimensions.append(
            {
                "edgeIndex": 0,
                "literalText": "2.0 m",
                "value": 2.0,
                "unit": "m",
                "status": "proposed",
                "provenance": "ai_detected",
            }
        )
    return {
        "status": "success",
        "confidence": 0.9,
        "rooms": [
            {
                "id": "complex-room",
                "contour": contour,
                "wallCount": wall_count,
                "dimensions": dimensions,
                "openings": [
                    {"edgeIndex": index, "type": "unknown", "status": "proposed"} for index in range(9)
                ],
                "confidence": 0.9,
            }
        ],
        "provenance": "ai_proposal",
    }


def test_extreme_oversegmentation_is_downgraded_to_needs_review(
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.INFO, logger="roomforge.floorplan_interpretation")
    document = _many_wall_room(wall_count=31, with_dimension=False)

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda request: _provider_response(document))
        ) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key", model="model", timeout_seconds=2, client=client
            ).interpret(image=b"image", content_type="image/png")

    result = asyncio.run(run())
    assert result.status == "needs_review"
    assert result.rooms[0].wall_count == 31
    assert "low_quality_oversegmentation" in caplog.text


def test_many_wall_irregular_room_is_not_rejected_by_wall_count_alone() -> None:
    document = _many_wall_room(wall_count=21, with_dimension=True)

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda request: _provider_response(document))
        ) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key", model="model", timeout_seconds=2, client=client
            ).interpret(image=b"image", content_type="image/png")

    result = asyncio.run(run())
    assert result.status == "success"
    assert result.rooms[0].wall_count == 21


def test_multi_room_candidates_and_semantic_opening_are_preserved() -> None:
    first = _room()
    first["id"] = "room-a"
    first["contour"] = [
        {"x": 0.05, "y": 0.05},
        {"x": 0.45, "y": 0.05},
        {"x": 0.45, "y": 0.45},
        {"x": 0.05, "y": 0.45},
    ]
    first["wallCount"] = 4
    first["openings"] = [
        {
            "edgeIndex": 0,
            "type": "door",
            "position": 0.5,
            "normalizedWidth": 0.2,
            "status": "proposed",
        }
    ]
    first["dimensions"] = []
    second = {**first, "id": "room-b", "label": "Hall"}
    document = {
        "status": "success",
        "rooms": [first, second],
        "provenance": "ai_proposal",
    }

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda request: _provider_response(document))
        ) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key", model="model", timeout_seconds=2, client=client
            ).interpret(image=b"image", content_type="image/png")

    result = asyncio.run(run())
    assert [room.id for room in result.rooms] == ["room-a", "room-b"]
    assert result.rooms[0].wall_count == 4
    assert len(result.rooms[0].openings) == 1


def _invalid_contour_document() -> dict[str, Any]:
    document = _l_room_with_list_contour()
    room = cast(dict[str, Any], document["rooms"][0])
    room["contour"] = [[0.1, 0.1], [0.9, 0.9], [0.9, 0.1], [0.1, 0.9]]
    room["wallCount"] = 4
    return document


def test_invalid_geometry_gets_one_sanitized_corrective_attempt() -> None:
    invalid = _invalid_contour_document()
    instruction_fragment = "simple, non-degenerate, non-self-intersecting"
    prompts: list[str] = []
    transport, calls = _sequential_transport(
        [_provider_response(invalid), _provider_response(_l_room_with_list_contour())], prompts
    )

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(transport=transport) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key", model="model", timeout_seconds=2, client=client
            ).interpret(image=b"original-image", content_type="image/png")

    result = asyncio.run(run())
    assert len(result.rooms) == 1
    assert calls == [1, 2]
    assert instruction_fragment not in prompts[0]
    assert instruction_fragment in prompts[1]
    assert json.dumps(invalid) not in prompts[1]


def test_retryable_unavailable_then_valid_retries_once() -> None:
    transport, calls = _sequential_transport(
        [httpx.Response(503), _provider_response(_l_room_with_list_contour())]
    )

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(transport=transport) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key", model="model", timeout_seconds=2, client=client
            ).interpret(image=b"image", content_type="image/png")

    assert asyncio.run(run()).rooms[0].wall_count == 6
    assert calls == [1, 2]


def test_rate_limit_honors_retry_after_once_then_succeeds() -> None:
    delays: list[float] = []

    async def fake_sleep(delay: float) -> None:
        delays.append(delay)

    transport, calls = _sequential_transport(
        [
            httpx.Response(429, headers={"Retry-After": "1.5"}),
            _provider_response(_l_room_with_list_contour()),
        ]
    )

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(transport=transport) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key",
                model="model",
                timeout_seconds=2,
                client=client,
                sleep=fake_sleep,
            ).interpret(image=b"image", content_type="image/png")

    assert asyncio.run(run()).rooms[0].wall_count == 6
    assert calls == [1, 2]
    assert delays == [1.5]


def test_rate_limit_without_retry_after_uses_bounded_fallback_before_final_retry() -> None:
    delays: list[float] = []

    async def fake_sleep(delay: float) -> None:
        delays.append(delay)

    transport, calls = _sequential_transport(
        [httpx.Response(429), _provider_response(_l_room_with_list_contour())]
    )

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(transport=transport) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key",
                model="model",
                timeout_seconds=2,
                client=client,
                sleep=fake_sleep,
            ).interpret(image=b"image", content_type="image/png")

    assert asyncio.run(run()).rooms[0].wall_count == 6
    assert calls == [1, 2]
    assert delays == [1.75]


def test_second_attempt_rate_limit_stops_at_two_requests_without_third() -> None:
    delays: list[float] = []

    async def fake_sleep(delay: float) -> None:
        delays.append(delay)

    transport, calls = _sequential_transport([httpx.Response(429), httpx.Response(429)])

    async def run() -> None:
        async with httpx.AsyncClient(transport=transport) as client:
            with pytest.raises(ProviderUnavailable) as raised:
                await GroqFloorplanInterpreter(
                    api_key="test-key",
                    model="model",
                    timeout_seconds=2,
                    client=client,
                    sleep=fake_sleep,
                ).interpret(image=b"image", content_type="image/png")
            assert raised.value.reason == "rate_limited"

    asyncio.run(run())
    assert calls == [1, 2]
    assert delays == [1.75]


@pytest.mark.parametrize("retry_after", ["4", "3600"])
def test_excessive_retry_after_fails_fast_without_retry(retry_after: str) -> None:
    delays: list[float] = []

    async def fake_sleep(delay: float) -> None:
        delays.append(delay)

    transport, calls = _sequential_transport([httpx.Response(429, headers={"Retry-After": retry_after})])

    async def run() -> None:
        async with httpx.AsyncClient(transport=transport) as client:
            with pytest.raises(ProviderUnavailable) as raised:
                await GroqFloorplanInterpreter(
                    api_key="test-key",
                    model="model",
                    timeout_seconds=2,
                    client=client,
                    sleep=fake_sleep,
                ).interpret(image=b"image", content_type="image/png")
            assert raised.value.reason == "rate_limited"
            assert not raised.value.retryable

    asyncio.run(run())
    assert calls == [1]
    assert delays == []


@pytest.mark.parametrize(
    ("failure", "reason"),
    [
        (httpx.Response(503), "provider_5xx"),
        (httpx.ReadTimeout("timed out"), "timeout"),
        (httpx.NetworkError("network failed"), "network_failure"),
    ],
)
def test_transient_failure_then_valid_uses_at_most_two_calls(
    failure: httpx.Response | Exception, reason: str, caplog: pytest.LogCaptureFixture
) -> None:
    delays: list[float] = []

    async def fake_sleep(delay: float) -> None:
        delays.append(delay)

    transport, calls = _sequential_transport([failure, _provider_response(_l_room_with_list_contour())])

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(transport=transport) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key",
                model="model",
                timeout_seconds=2,
                client=client,
                sleep=fake_sleep,
            ).interpret(image=b"image", content_type="image/png")

    assert asyncio.run(run()).rooms[0].wall_count == 6
    assert calls == [1, 2]
    assert delays == [0.1]
    assert f"reason={reason}" in caplog.text


@pytest.mark.parametrize("status", [401, 403])
def test_nonretryable_unavailable_does_not_retry(status: int) -> None:
    transport, calls = _sequential_transport([httpx.Response(status)])

    async def run() -> None:
        async with httpx.AsyncClient(transport=transport) as client:
            with pytest.raises(ProviderUnavailable) as raised:
                await GroqFloorplanInterpreter(
                    api_key="test-key", model="model", timeout_seconds=2, client=client
                ).interpret(image=b"image", content_type="image/png")
            assert not raised.value.retryable
            assert raised.value.reason == "nonretryable_provider_error"
            assert raised.value.provider_status == status

    asyncio.run(run())
    assert calls == [1]


def test_two_invalid_responses_exhaust_exactly_two_attempts() -> None:
    transport, calls = _sequential_transport(
        [_provider_response(_invalid_contour_document()), _provider_response(_invalid_contour_document())]
    )

    async def run() -> None:
        async with httpx.AsyncClient(transport=transport) as client:
            with pytest.raises(InvalidProviderResponse) as raised:
                await GroqFloorplanInterpreter(
                    api_key="test-key", model="model", timeout_seconds=2, client=client
                ).interpret(image=b"image", content_type="image/png")
            assert raised.value.reason == "invalid_contour"

    asyncio.run(run())
    assert calls == [1, 2]


def test_two_retryable_failures_exhaust_exactly_two_attempts() -> None:
    transport, calls = _sequential_transport([httpx.Response(503), httpx.Response(429)])

    async def run() -> None:
        async with httpx.AsyncClient(transport=transport) as client:
            with pytest.raises(ProviderUnavailable) as raised:
                await GroqFloorplanInterpreter(
                    api_key="test-key", model="model", timeout_seconds=2, client=client
                ).interpret(image=b"image", content_type="image/png")
            assert raised.value.retryable

    asyncio.run(run())
    assert calls == [1, 2]


def test_missing_literal_text_is_dropped_without_fabrication_or_retry() -> None:
    invalid = _l_room_with_list_contour()
    room = cast(dict[str, Any], invalid["rooms"][0])
    room["dimensions"] = [
        {"edgeIndex": 0, "value": 7.0, "unit": "m", "status": "proposed", "provenance": "ai_detected"}
    ]
    prompts: list[str] = []
    transport, calls = _sequential_transport([_provider_response(invalid)], prompts)

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(transport=transport) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key", model="model", timeout_seconds=2, client=client
            ).interpret(image=b"image", content_type="image/png")

    result = asyncio.run(run())
    assert result.rooms[0].dimensions == []
    assert calls == [1]
    assert "7 m" not in json.dumps(result.model_dump(by_alias=True))


def test_valid_groq_json_maps_semantic_pentagon_without_confirming_measurement() -> None:
    async def run() -> FloorplanInterpretation:
        transport = httpx.MockTransport(lambda request: _provider_response(_pentagon()))
        async with httpx.AsyncClient(transport=transport) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key", model="qwen/qwen3.8-27b", timeout_seconds=2, client=client
            ).interpret(image=b"image", content_type="image/png")

    result = asyncio.run(run())
    room = result.rooms[0]
    assert room.wall_count == 5
    assert [opening.type for opening in room.openings] == ["window", "window", "door"]
    assert room.dimensions[0].literal_text == "419"
    assert room.dimensions[0].status == "unresolved"
    assert room.dimensions[0].provenance == "ai_detected"


@pytest.mark.parametrize(
    "dimension",
    [
        {"literalText": "4.10 m", "value": 4.10, "unit": "m"},
        {"literalText": "4.10 m", "value": 4.10, "unit": "m", "status": None},
        {"literalText": "4.10 m", "value": 4.10, "unit": "m", "status": "guessed"},
        {"literalText": "4.10 m", "value": 4.10, "unit": "m", "status": 7},
    ],
    ids=["missing", "null", "unknown", "wrong-type"],
)
def test_dimension_status_is_mandatory_and_known(dimension: dict[str, object]) -> None:
    with pytest.raises(ValidationError):
        FloorplanInterpretation.model_validate(_with_dimension(dimension))


@pytest.mark.parametrize(
    "dimension",
    [
        {"literalText": "4.10 m", "value": 4.10, "unit": "m", "status": "proposed"},
        {"literalText": "410 cm", "value": 410, "unit": "cm", "status": "proposed"},
        {"literalText": "4100 mm", "value": 4100, "unit": "mm", "status": "proposed"},
        {"literalText": "419", "value": 419, "unit": "unknown", "status": "unresolved"},
        {
            "edgeIndex": 2,
            "literalText": "4.10 m",
            "value": 4.10,
            "unit": "m",
            "status": "conflict",
        },
        {
            "edgeIndex": 2,
            "literalText": "419",
            "value": 419,
            "unit": "unknown",
            "status": "conflict",
        },
    ],
    ids=["proposed-m", "proposed-cm", "proposed-mm", "unresolved", "conflict-metric", "conflict-unknown"],
)
def test_valid_dimension_status_contract(dimension: dict[str, object]) -> None:
    result = FloorplanInterpretation.model_validate(_with_dimension(dimension))
    parsed = result.rooms[0].dimensions[0]

    assert parsed.status == dimension["status"]
    assert parsed.value == dimension["value"]
    assert parsed.unit == dimension["unit"]
    assert parsed.edge_index == dimension.get("edgeIndex")


@pytest.mark.parametrize(
    "dimension",
    [
        {"literalText": "419", "value": 419, "unit": "unknown", "status": "proposed"},
        {"literalText": "4.10 m", "value": None, "unit": "m", "status": "proposed"},
        {"literalText": "0 m", "value": 0, "unit": "m", "status": "proposed"},
        {"literalText": "-1 m", "value": -1, "unit": "m", "status": "proposed"},
    ],
    ids=["unknown-unit", "missing-value", "zero", "negative"],
)
def test_proposed_dimension_requires_metric_meaning(dimension: dict[str, object]) -> None:
    with pytest.raises(ValidationError):
        FloorplanInterpretation.model_validate(_with_dimension(dimension))


@pytest.mark.parametrize("status", ["proposed", "unresolved", "conflict"])
@pytest.mark.parametrize("value", [float("nan"), float("inf"), float("-inf")])
def test_non_finite_dimension_evidence_is_rejected_for_every_status(status: str, value: float) -> None:
    dimension = {"literalText": "4.10 m", "value": value, "unit": "m", "status": status}
    with pytest.raises(ValidationError):
        FloorplanInterpretation.model_validate(_with_dimension(dimension))


@pytest.mark.parametrize(
    "document",
    [
        {**_pentagon(), "rooms": [{**_room(), "contour": [{"x": 2, "y": 0}]}]},
        {**_pentagon(), "confidence": 1.2},
    ],
)
def test_invalid_provider_geometry_is_rejected(document: dict[str, object]) -> None:
    async def run() -> None:
        transport = httpx.MockTransport(lambda request: _provider_response(document))
        async with httpx.AsyncClient(transport=transport) as client:
            with pytest.raises(InvalidProviderResponse):
                await GroqFloorplanInterpreter(
                    api_key="test-key", model="model", timeout_seconds=2, client=client
                ).interpret(image=b"image", content_type="image/png")

    asyncio.run(run())


@pytest.mark.parametrize(
    ("room_patch", "reason"),
    [
        ({"wallCount": 6}, "wall_count_mismatch"),
        ({"openings": [{"edgeIndex": 8, "type": "door"}]}, "invalid_opening_edge"),
        (
            {
                "dimensions": [
                    {
                        "edgeIndex": 8,
                        "literalText": "4.10 m",
                        "value": 4.1,
                        "unit": "m",
                        "status": "proposed",
                    }
                ]
            },
            "invalid_dimension_edge",
        ),
        (
            {
                "contour": [
                    {"x": 0.1, "y": 0.1},
                    {"x": 0.9, "y": 0.9},
                    {"x": 0.9, "y": 0.1},
                    {"x": 0.1, "y": 0.9},
                ],
                "wallCount": 4,
            },
            "invalid_contour",
        ),
    ],
)
def test_room_business_validation_has_stable_reason_codes(room_patch: dict[str, object], reason: str) -> None:
    document = _pentagon()
    document["rooms"] = [{**_room(), **room_patch}]
    with pytest.raises(ValidationError) as raised:
        FloorplanInterpretation.model_validate(document)
    assert raised.value.errors(include_url=False)[0]["type"] == reason


@pytest.mark.parametrize(
    "document",
    [
        {**_pentagon(), "confidence": float("nan")},
        {**_pentagon(), "confidence": -0.1},
        {
            **_pentagon(),
            "rooms": [
                {
                    **_room(),
                    "confidence": 1.01,
                }
            ],
        },
        {
            **_pentagon(),
            "rooms": [
                {
                    **_room(),
                    "openings": [{"edgeIndex": 0, "position": float("inf")}],
                }
            ],
        },
        {
            **_pentagon(),
            "rooms": [
                {
                    **_room(),
                    "openings": [{"edgeIndex": 0, "normalizedWidth": 1.5}],
                }
            ],
        },
        {
            **_pentagon(),
            "rooms": [
                {
                    **_room(),
                    "openings": [{"edgeIndex": 0, "confidence": -0.5}],
                }
            ],
        },
    ],
)
def test_non_finite_or_out_of_range_provider_numbers_are_rejected(
    document: dict[str, object],
) -> None:
    with pytest.raises(ValidationError):
        FloorplanInterpretation.model_validate(document)


def test_provider_numeric_boundaries_are_accepted() -> None:
    result = FloorplanInterpretation.model_validate(
        {
            **_pentagon(),
            "confidence": 1.0,
            "rooms": [
                {
                    **_room(),
                    "confidence": 0.0,
                    "openings": [
                        {"edgeIndex": 0, "position": 0.0, "normalizedWidth": 1.0, "confidence": 1.0}
                    ],
                }
            ],
        }
    )
    opening = result.rooms[0].openings[0]
    assert opening.position == 0.0
    assert opening.normalized_width == 1.0
    assert opening.confidence == 1.0


def test_malformed_json_is_safe_failure() -> None:
    async def run() -> None:
        response = httpx.Response(200, json={"choices": [{"message": {"content": "not-json"}}]})
        async with httpx.AsyncClient(transport=httpx.MockTransport(lambda request: response)) as client:
            with pytest.raises(InvalidProviderResponse):
                await GroqFloorplanInterpreter(
                    api_key="test-key", model="model", timeout_seconds=2, client=client
                ).interpret(image=b"image", content_type="image/png")

    asyncio.run(run())


def test_success_logs_bounded_raw_and_normalized_diagnostics_without_sensitive_input(
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.INFO, logger="roomforge.floorplan_interpretation")
    document = _pentagon()
    room = cast(dict[str, Any], cast(list[object], document["rooms"])[0])
    room["label"] = (
        "Authorization: Bearer echoed-token data:image/png;base64,cHJpdmF0ZS1pbWFnZQ== secret-api-key"
    )

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda request: _provider_response(document))
        ) as client:
            return await GroqFloorplanInterpreter(
                api_key="secret-api-key", model="model", timeout_seconds=2, client=client
            ).interpret(image=b"private-image", content_type="image/png")

    result = asyncio.run(run())
    assert result == FloorplanInterpretation.model_validate(document)
    log = caplog.text
    assert "[RoomForge][FloorplanProviderRaw]" in log
    assert "providerOutcome=VALID_MODEL_RESPONSE" in log
    assert '"wallCount":5' in log
    assert '"dimensions":' in log
    assert '"openings":' in log
    assert "[RoomForge][FloorplanNormalized]" in log
    assert "roomWalls=[5]" in log
    assert "roomDimensions=[1]" in log
    assert "roomOpenings=[3]" in log
    diagnostic_ids = set(re.findall(r"floorplanDiag=(fp-[0-9a-f]{8})", log))
    assert len(diagnostic_ids) == 1
    assert "floorplanDiag" not in result.model_dump(mode="json")
    assert "secret-api-key" not in log
    assert "echoed-token" not in log
    assert "private-image" not in log
    assert "cHJpdmF0ZS1pbWFnZQ" not in log


def test_malformed_provider_json_logs_only_a_bounded_sanitized_preview(
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.INFO, logger="roomforge.floorplan_interpretation")
    malformed = "not-json " * 1000
    transport, calls = _sequential_transport(
        [
            httpx.Response(200, json={"choices": [{"message": {"content": malformed}}]}),
            httpx.Response(200, json={"choices": [{"message": {"content": malformed}}]}),
        ]
    )

    async def run() -> None:
        async with httpx.AsyncClient(transport=transport) as client:
            with pytest.raises(InvalidProviderResponse):
                await GroqFloorplanInterpreter(
                    api_key="test-key", model="model", timeout_seconds=2, client=client
                ).interpret(image=b"image", content_type="image/png")

    asyncio.run(run())
    preview_messages = [
        record.getMessage() for record in caplog.records if "rawJsonValid=false" in record.getMessage()
    ]
    assert len(preview_messages) == 2
    assert len(calls) == 2
    for message in preview_messages:
        preview = message.split("preview=", maxsplit=1)[1]
        assert len(preview) <= 4000


def test_contract_failure_logs_raw_shape_without_provider_payload(
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.INFO, logger="roomforge.floorplan_interpretation")
    document = _pentagon()
    room = cast(dict[str, Any], cast(list[object], document["rooms"])[0])
    room["contour"] = [[0.1], [0.7, 0.1], [0.9, 0.5], [0.65, 0.9], [0.1, 0.8]]
    transport, calls = _sequential_transport([_provider_response(document), _provider_response(document)])

    async def run() -> None:
        async with httpx.AsyncClient(transport=transport) as client:
            with pytest.raises(InvalidProviderResponse):
                await GroqFloorplanInterpreter(
                    api_key="test-key", model="model", timeout_seconds=2, client=client
                ).interpret(image=b"image", content_type="image/png")

    asyncio.run(run())
    log = caplog.text
    assert len(calls) == 2
    assert "[RoomForge][FloorplanContractFailure]" in log
    assert "path=rooms.0.contour.0" in log
    assert "category=model_type" in log
    assert "rawJsonValid=true" in log
    assert "rooms=1" in log
    assert "offendingType=array" in log


def test_provider_failures_are_distinct_from_model_low_confidence(
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.INFO, logger="roomforge.floorplan_interpretation")

    async def run_low_confidence() -> None:
        document: dict[str, object] = {
            "status": "low_confidence",
            "confidence": 0.2,
            "rooms": [],
            "provenance": "ai_proposal",
        }
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda request: _provider_response(document))
        ) as client:
            await GroqFloorplanInterpreter(
                api_key="test-key", model="model", timeout_seconds=2, client=client
            ).interpret(image=b"image", content_type="image/png")

    async def run_failure(outcome: httpx.Response | Exception) -> None:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(
                lambda request: (_ for _ in ()).throw(outcome) if isinstance(outcome, Exception) else outcome
            )
        ) as client:
            with pytest.raises(ProviderUnavailable):
                await GroqFloorplanInterpreter(
                    api_key="test-key", model="model", timeout_seconds=2, client=client
                ).interpret(image=b"image", content_type="image/png")

    asyncio.run(run_low_confidence())
    asyncio.run(run_failure(httpx.Response(429)))
    asyncio.run(run_failure(httpx.ReadTimeout("timed out")))
    log = caplog.text
    assert "providerOutcome=MODEL_LOW_CONFIDENCE" in log
    assert "providerOutcome=PROVIDER_RATE_LIMITED" in log
    assert "providerOutcome=PROVIDER_TIMEOUT" in log


def test_invalid_response_log_contains_only_safe_validation_metadata(
    caplog: pytest.LogCaptureFixture,
) -> None:
    document = _invalid_contour_document()

    async def run() -> None:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda request: _provider_response(document))
        ) as client:
            with pytest.raises(InvalidProviderResponse):
                await GroqFloorplanInterpreter(
                    api_key="secret-that-must-not-appear",
                    model="model",
                    timeout_seconds=2,
                    client=client,
                ).interpret(image=b"private-image", content_type="image/png")

    asyncio.run(run())
    log = caplog.text
    assert "result=invalid_provider_response" in log
    assert "attempt=1" in log
    assert "attempt=2" in log
    assert "attempts=2" in log
    assert "reason=invalid_contour" in log
    assert "path=rooms.0" in log
    assert "category=invalid_contour" in log
    assert "secret-that-must-not-appear" not in log
    assert "private-image" not in log
    assert "Authorization" not in log
    assert "cHJpdmF0ZS1pbWFnZQ" not in log


@pytest.mark.parametrize("status", [429, 503])
def test_rate_limit_and_service_failure_are_retryable(status: int) -> None:
    async def run() -> None:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda request: httpx.Response(status))
        ) as client:
            with pytest.raises(ProviderUnavailable) as raised:
                await GroqFloorplanInterpreter(
                    api_key="test-key", model="model", timeout_seconds=2, client=client
                ).interpret(image=b"image", content_type="image/png")
            assert raised.value.retryable

    asyncio.run(run())


def test_missing_key_is_controlled_and_not_retryable() -> None:
    with pytest.raises(ProviderUnavailable) as raised:
        asyncio.run(
            GroqFloorplanInterpreter(api_key=None, model="model", timeout_seconds=2).interpret(
                image=b"image", content_type="image/png"
            )
        )
    assert not raised.value.retryable


def test_unknown_unit_remains_unknown() -> None:
    result = FloorplanInterpretation.model_validate(_pentagon())
    assert result.rooms[0].dimensions[0].unit == "unknown"
