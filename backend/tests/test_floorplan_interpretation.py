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
from app.modules.floorplan_interpretation import service as floorplan_service
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


def test_system_prompt_documents_semantic_wall_fragment_contract() -> None:
    prompt = " ".join(SYSTEM_PROMPT.split()).lower()

    assert "contour points represent semantic architectural walls" in prompt
    assert "room boundary segments" in prompt
    assert "doors and windows are openings in walls" in prompt
    assert "must not create additional semantic walls" in prompt
    assert "collinear or nearly-collinear" in prompt
    assert "separated by an opening or drawing gap" in prompt
    assert "one semantic wall when architecturally continuous" in prompt
    assert "furniture, dimensions, text, labels" in prompt
    assert "door swing arcs" in prompt
    assert "window detail strokes" in prompt
    assert "selected room perimeter" in prompt
    assert "rather than all visible linework" in prompt


def test_system_prompt_documents_first_attempt_semantic_topology_contract() -> None:
    prompt = " ".join(SYSTEM_PROMPT.split()).lower()

    assert "dominant room" in prompt
    assert "semantic perimeter" in prompt
    assert "one contour vertex per real architectural corner" in prompt
    assert "closed by implication" in prompt
    assert "do not repeat the first contour point" in prompt
    assert "simple, non-degenerate, non-self-intersecting" in prompt


def test_system_prompt_excludes_drawing_noise_from_first_attempt_contours() -> None:
    prompt = " ".join(SYSTEM_PROMPT.split()).lower()

    assert "do not create contour vertices or walls" in prompt
    assert "door swing arcs" in prompt
    assert "window detail strokes" in prompt
    assert "wall thickness bands" in prompt
    assert "furniture" in prompt
    assert "text" in prompt
    assert "dimension lines" in prompt
    assert "construction lines" in prompt
    assert "auxiliary lines" in prompt


def test_system_prompt_protects_irregular_geometry_without_target_wall_count() -> None:
    prompt = " ".join(SYSTEM_PROMPT.split()).lower()

    assert "l-shaped" in prompt
    assert "concave" in prompt
    assert "angled" in prompt
    assert "pentagonal" in prompt
    assert "irregular geometry" in prompt
    assert "do not force a rectangle" in prompt
    assert "do not add or remove architectural walls" in prompt
    assert "target wall count" in prompt


def test_system_prompt_prioritizes_topology_before_opening_and_dimension_evidence() -> None:
    prompt = " ".join(SYSTEM_PROMPT.split()).lower()

    assert "establish semantic topology before interpreting openings or dimensions" in prompt


def test_system_prompt_documents_opening_geometry_contract() -> None:
    prompt = " ".join(SYSTEM_PROMPT.split()).lower()

    assert "position" in prompt
    assert "normalizedwidth" in prompt
    assert "normalized center" in prompt
    assert "associated wall" in prompt
    assert "fraction of the associated wall" in prompt
    assert "position is in [0,1]" in prompt
    assert "normalizedwidth is in (0,1]" in prompt
    assert "only when visually defensible" in prompt
    assert "return null rather than guessing" in prompt
    assert "never fabricate opening position or width" in prompt


def test_system_prompt_unambiguously_defines_opening_center_geometry() -> None:
    prompt = " ".join(SYSTEM_PROMPT.split()).lower()

    assert "position is the normalized center" in prompt
    assert "from contour[edgeindex] toward contour[(edgeindex + 1) % wallcount]" in prompt
    assert "position=0 is its start, position=0.5 is its midpoint, and position=1 is its end" in prompt
    assert "never the opening start, opening end, nearest jamb" in prompt
    assert "physical opening span along that semantic wall divided by the semantic wall length" in prompt
    assert "if the exact center is not defensible, return position=null" in prompt
    assert "if the width is not defensible, return normalizedwidth=null" in prompt
    assert "never fabricate precise opening geometry" in prompt


def test_system_prompt_requires_exhaustive_semantic_wall_opening_inspection() -> None:
    prompt = " ".join(SYSTEM_PROMPT.split()).lower()

    assert "after establishing semantic topology" in prompt
    assert "inspect every semantic perimeter wall for openings" in prompt
    assert "report every visually supported door or window" in prompt


def test_system_prompt_classifies_doors_and_windows_from_independent_evidence() -> None:
    prompt = " ".join(SYSTEM_PROMPT.split()).lower()

    assert "classify each opening from its own visible architectural evidence" in prompt
    assert "do not classify every wall gap as a door" in prompt
    assert "window-specific visual evidence" in prompt
    assert "remain window" in prompt
    assert "nearby dimension label" in prompt


def test_system_prompt_preserves_separate_physical_openings_as_separate_proposals() -> None:
    prompt = " ".join(SYSTEM_PROMPT.split()).lower()

    assert "one physical opening per opening proposal" in prompt
    assert "do not merge separate physical openings" in prompt


def test_system_prompt_prioritizes_opening_scan_after_topology_before_dimensions() -> None:
    prompt = " ".join(SYSTEM_PROMPT.split()).lower()

    topology_index = prompt.index("after establishing semantic topology")
    opening_scan_index = prompt.index("inspect every semantic perimeter wall for openings")
    dimensions_index = prompt.index("report dimensions")

    assert topology_index < opening_scan_index < dimensions_index
    assert "opening edgeindex only when wall association is visually defensible" in prompt


def test_system_prompt_preserves_unknown_openings_and_rejects_opening_noise() -> None:
    prompt = " ".join(SYSTEM_PROMPT.split()).lower()

    assert "report every visually supported door or window" in prompt
    assert 'if an opening is visible but its type is genuinely ambiguous, use type="unknown"' in prompt
    assert (
        "do not create openings from furniture, annotations, dimension lines, wall thickness, door swing arcs alone"
        in prompt
    )


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
    room = cast(dict[str, Any], cast(list[dict[str, Any]], document["rooms"])[0])
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


def test_provider_wall_index_alias_preserves_incomplete_openings(
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.INFO, logger="roomforge.floorplan_interpretation")
    document = _pentagon()
    document["status"] = "success"
    room = cast(list[dict[str, Any]], document["rooms"])[0]
    room["openings"] = [
        {
            "wallIndex": 0,
            "type": "window",
            "position": 0.5,
            "normalizedWidth": None,
            "status": "proposed",
        },
        {
            "wallIndex": 1,
            "type": "window",
            "position": 0.5,
            "normalizedWidth": None,
            "status": "proposed",
        },
        {
            "wallIndex": 3,
            "type": "door",
            "position": 0.5,
            "normalizedWidth": None,
            "status": "proposed",
        },
    ]

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda request: _provider_response(document))
        ) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key", model="model", timeout_seconds=2, client=client
            ).interpret(image=b"image", content_type="image/png")

    result = asyncio.run(run())
    assert len(result.rooms) == 1
    room = result.rooms[0]
    assert room.wall_count == 5
    assert len(room.openings) == 3
    assert [opening.type for opening in room.openings] == ["window", "window", "door"]
    assert [opening.edge_index for opening in room.openings] == [0, 1, 3]
    assert [opening.position for opening in room.openings] == [0.5, 0.5, 0.5]
    assert all(opening.normalized_width is None for opening in room.openings)
    assert "opening_wall_index_alias_normalized" in caplog.text


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


def test_oversegmented_room_with_dimension_is_still_downgraded_to_needs_review(
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.INFO, logger="roomforge.floorplan_interpretation")
    document = _many_wall_room(wall_count=23, with_dimension=True)

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda request: _provider_response(document))
        ) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key", model="model", timeout_seconds=2, client=client
            ).interpret(image=b"image", content_type="image/png")

    result = asyncio.run(run())
    assert result.status == "needs_review"
    assert len(result.rooms) == 1
    assert result.rooms[0].wall_count == 23
    assert len(result.rooms[0].dimensions) == 1
    complete_openings = [
        opening
        for opening in result.rooms[0].openings
        if opening.position is not None and opening.normalized_width is not None
    ]
    assert complete_openings == []
    assert "low_quality_oversegmentation" in caplog.text


def test_oversegmented_room_with_sparse_dimensions_is_downgraded_to_needs_review(
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.INFO, logger="roomforge.floorplan_interpretation")
    document = _many_wall_room(wall_count=22, with_dimension=True)
    room = cast(list[dict[str, Any]], document["rooms"])[0]
    room["dimensions"] = [
        {
            "edgeIndex": 2,
            "literalText": "2.0 m",
            "value": 2.0,
            "unit": "m",
            "status": "proposed",
            "provenance": "ai_detected",
        },
        {
            "edgeIndex": 3,
            "literalText": "1.8 m",
            "value": 1.8,
            "unit": "m",
            "status": "proposed",
            "provenance": "ai_detected",
        },
        {
            "edgeIndex": 7,
            "literalText": "3.1 m",
            "value": 3.1,
            "unit": "m",
            "status": "proposed",
            "provenance": "ai_detected",
        },
    ]

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda request: _provider_response(document))
        ) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key", model="model", timeout_seconds=2, client=client
            ).interpret(image=b"image", content_type="image/png")

    result = asyncio.run(run())
    assert result.status == "needs_review"
    assert len(result.rooms) == 1
    assert result.rooms[0].wall_count == 22
    assert len(result.rooms[0].contour) == 22
    assert len(result.rooms[0].dimensions) == 3
    complete_openings = [
        opening
        for opening in result.rooms[0].openings
        if opening.position is not None and opening.normalized_width is not None
    ]
    assert complete_openings == []
    assert (
        "La propuesta automática presenta sobresegmentación y requiere corrección humana." in result.warnings
    )
    assert (
        "Reintentar la interpretación o corregir la geometría manualmente." in result.information_still_needed
    )
    assert "low_quality_oversegmentation" in caplog.text


def test_many_wall_irregular_room_is_not_rejected_by_wall_count_alone() -> None:
    document = _many_wall_room(wall_count=21, with_dimension=True)
    room = cast(list[dict[str, Any]], document["rooms"])[0]
    room["openings"] = [
        {
            "edgeIndex": 0,
            "type": "window",
            "position": 0.35,
            "normalizedWidth": 0.18,
            "status": "proposed",
        },
        {
            "edgeIndex": 5,
            "type": "door",
            "position": 0.50,
            "normalizedWidth": 0.16,
            "status": "proposed",
        },
        {
            "edgeIndex": 11,
            "type": "window",
            "position": 0.65,
            "normalizedWidth": 0.20,
            "status": "proposed",
        },
    ]

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
    complete_openings = [
        opening
        for opening in result.rooms[0].openings
        if opening.position is not None and opening.normalized_width is not None
    ]
    assert len(complete_openings) >= 3


def _dense_turn_room(*, corroborated: bool) -> dict[str, object]:
    """A scale-neutral, valid decagon with material turns but no micro-noise."""
    wall_count = 10
    contour = [
        {
            "x": 0.5 + 0.36 * math.cos(2 * math.pi * index / wall_count),
            "y": 0.5 + 0.36 * math.sin(2 * math.pi * index / wall_count),
        }
        for index in range(wall_count)
    ]
    dimensions: list[dict[str, object]] = [
        {
            "edgeIndex": 0,
            "literalText": "2.4 m",
            "value": 2.4,
            "unit": "m",
            "status": "proposed",
            "provenance": "ai_detected",
        }
    ]
    openings: list[dict[str, object]] = [
        {
            "edgeIndex": 1,
            "type": "window",
            "position": 0.5,
            "normalizedWidth": 0.2,
            "status": "proposed",
        }
    ]
    if corroborated:
        dimensions.extend(
            [
                {
                    "edgeIndex": 3,
                    "literalText": "1.8 m",
                    "value": 1.8,
                    "unit": "m",
                    "status": "proposed",
                    "provenance": "ai_detected",
                },
                {
                    "edgeIndex": 6,
                    "literalText": "2.1 m",
                    "value": 2.1,
                    "unit": "m",
                    "status": "proposed",
                    "provenance": "ai_detected",
                },
            ]
        )
    return {
        "status": "success",
        "confidence": 0.88,
        "rooms": [
            {
                "id": "dense-turn-room",
                "label": "Irregular room",
                "contour": contour,
                "wallCount": wall_count,
                "dimensions": dimensions,
                "openings": openings,
                "confidence": 0.88,
            }
        ],
        "provenance": "ai_proposal",
    }


def test_dense_uncorroborated_structural_transitions_are_downgraded_non_destructively(
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.INFO, logger="roomforge.floorplan_interpretation")
    document = _dense_turn_room(corroborated=False)
    source_room = cast(dict[str, Any], cast(list[dict[str, Any]], document["rooms"])[0])
    source_contour = cast(list[dict[str, float]], source_room["contour"])
    source_dimensions = cast(list[dict[str, Any]], source_room["dimensions"])
    source_openings = cast(list[dict[str, Any]], source_room["openings"])

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda request: _provider_response(document))
        ) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key", model="model", timeout_seconds=2, client=client
            ).interpret(image=b"image", content_type="image/png")

    result = asyncio.run(run())
    room = result.rooms[0]
    assert result.status == "needs_review"
    assert [point.model_dump() for point in room.contour] == source_contour
    assert [dimension.model_dump(by_alias=True) for dimension in room.dimensions] == source_dimensions
    assert [opening.edge_index for opening in room.openings] == [source_openings[0]["edgeIndex"]]
    assert [opening.type for opening in room.openings] == [source_openings[0]["type"]]
    assert [opening.position for opening in room.openings] == [source_openings[0]["position"]]
    assert [opening.normalized_width for opening in room.openings] == [source_openings[0]["normalizedWidth"]]
    assert room.label == source_room["label"]
    assert room.confidence == source_room["confidence"]
    assert (
        "La topología de la habitación contiene transiciones estructurales inusualmente densas y debe revisarse."
        in result.warnings
    )
    assert (
        "Confirmar si las transiciones del contorno representan muros arquitectónicos reales."
        in result.information_still_needed
    )
    assert "low_quality_structural_complexity" in caplog.text
    assert "semantic_contour_simplified" not in caplog.text


def test_dense_irregular_room_with_multiple_independent_dimensions_remains_success() -> None:
    document = _dense_turn_room(corroborated=True)

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda request: _provider_response(document))
        ) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key", model="model", timeout_seconds=2, client=client
            ).interpret(image=b"image", content_type="image/png")

    result = asyncio.run(run())
    assert result.status == "success"
    assert result.rooms[0].wall_count == 10
    assert len(result.rooms[0].dimensions) == 3


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


def _live_e_duplicate_closure_document() -> dict[str, Any]:
    document = _l_room_with_list_contour()
    room = cast(dict[str, Any], document["rooms"][0])
    room["contour"] = [
        {"x": 0.15, "y": 0.15},
        {"x": 0.49, "y": 0.15},
        {"x": 0.49, "y": 0.75},
        {"x": 0.65, "y": 0.75},
        {"x": 0.65, "y": 0.77},
        {"x": 0.75, "y": 0.77},
        {"x": 0.75, "y": 0.15},
        {"x": 0.15, "y": 0.15},
    ]
    room["wallCount"] = 8
    room["dimensions"] = []
    room["openings"] = []
    return document


def _live_e_topology_failure_document() -> dict[str, object]:
    document = _pentagon()
    rooms = cast(list[dict[str, Any]], document["rooms"])
    room = rooms[0]
    room["contour"] = [
        [0.15, 0.15],
        [0.49, 0.15],
        [0.49, 0.75],
        [0.65, 0.75],
        [0.65, 0.77],
        [0.75, 0.77],
        [0.75, 0.15],
        [0.15, 0.15],
    ]
    room["wallCount"] = 7
    room["dimensions"] = []
    room["openings"] = []
    return document


def _topology_rescue_document() -> dict[str, object]:
    document = _pentagon()
    document["status"] = "success"
    rooms = cast(list[dict[str, Any]], document["rooms"])
    room = rooms[0]
    room["contour"] = [
        {"x": 0.15, "y": 0.15},
        {"x": 0.75, "y": 0.15},
        {"x": 0.75, "y": 0.75},
        {"x": 0.15, "y": 0.75},
    ]
    room["wallCount"] = 4
    room["dimensions"] = []
    room["openings"] = []
    return document


def _topology_rescue_transport(
    prompts: list[str], payloads: list[dict[str, Any]]
) -> tuple[httpx.MockTransport, list[int]]:
    outcomes = [
        _provider_response(_live_e_topology_failure_document()),
        _provider_response(_topology_rescue_document()),
    ]
    calls: list[int] = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(len(calls) + 1)
        payload = cast(dict[str, Any], json.loads(request.content))
        payloads.append(payload)
        prompts.append(cast(str, payload["messages"][0]["content"][0]["text"]))
        return outcomes[len(calls) - 1]

    return httpx.MockTransport(handler), calls


def _live_e_staircase_contour() -> list[dict[str, float]]:
    return [
        {"x": 0.14, "y": 0.15},
        {"x": 0.50, "y": 0.15},
        {"x": 0.50, "y": 0.16},
        {"x": 0.75, "y": 0.16},
        {"x": 0.75, "y": 0.75},
        {"x": 0.65, "y": 0.75},
        {"x": 0.65, "y": 0.77},
        {"x": 0.49, "y": 0.77},
        {"x": 0.49, "y": 0.75},
        {"x": 0.14, "y": 0.75},
        {"x": 0.14, "y": 0.15},
    ]


def _live_e_shallow_notch_contour() -> list[dict[str, float]]:
    return [
        {"x": 0.15, "y": 0.15},
        {"x": 0.75, "y": 0.15},
        {"x": 0.75, "y": 0.75},
        {"x": 0.65, "y": 0.75},
        {"x": 0.65, "y": 0.70},
        {"x": 0.50, "y": 0.70},
        {"x": 0.50, "y": 0.75},
        {"x": 0.15, "y": 0.75},
    ]


def _noisy_orthogonal_l_contour() -> list[dict[str, float]]:
    return [
        {"x": 0.15, "y": 0.86},
        {"x": 0.15, "y": 0.30},
        {"x": 0.14, "y": 0.28},
        {"x": 0.15, "y": 0.26},
        {"x": 0.15, "y": 0.24},
        {"x": 0.14, "y": 0.22},
        {"x": 0.15, "y": 0.20},
        {"x": 0.15, "y": 0.18},
        {"x": 0.14, "y": 0.16},
        {"x": 0.15, "y": 0.14},
        {"x": 0.15, "y": 0.12},
        {"x": 0.14, "y": 0.10},
        {"x": 0.15, "y": 0.08},
        {"x": 0.15, "y": 0.06},
        {"x": 0.14, "y": 0.04},
        {"x": 0.15, "y": 0.02},
        {"x": 0.15, "y": 0.00},
        {"x": 0.30, "y": 0.00},
        {"x": 0.30, "y": 0.02},
        {"x": 0.32, "y": 0.02},
        {"x": 0.32, "y": 0.00},
        {"x": 0.50, "y": 0.00},
        {"x": 0.50, "y": 0.02},
        {"x": 0.52, "y": 0.02},
        {"x": 0.52, "y": 0.00},
        {"x": 0.70, "y": 0.00},
        {"x": 0.70, "y": 0.02},
        {"x": 0.72, "y": 0.02},
        {"x": 0.72, "y": 0.00},
        {"x": 0.85, "y": 0.00},
        {"x": 0.85, "y": 0.55},
        {"x": 0.83, "y": 0.55},
        {"x": 0.83, "y": 0.53},
        {"x": 0.81, "y": 0.53},
        {"x": 0.81, "y": 0.55},
        {"x": 0.55, "y": 0.55},
        {"x": 0.55, "y": 0.57},
        {"x": 0.53, "y": 0.57},
        {"x": 0.53, "y": 0.55},
        {"x": 0.50, "y": 0.55},
        {"x": 0.50, "y": 0.86},
    ]


def _transform_contour(
    contour: list[dict[str, float]], *, scale: float, offset_x: float, offset_y: float
) -> list[dict[str, float]]:
    return [{"x": point["x"] * scale + offset_x, "y": point["y"] * scale + offset_y} for point in contour]


def _point_to_contour_distance(point: dict[str, float], contour: list[dict[str, float]]) -> float:
    def distance_to_segment(start: dict[str, float], end: dict[str, float]) -> float:
        delta_x = end["x"] - start["x"]
        delta_y = end["y"] - start["y"]
        length_squared = delta_x * delta_x + delta_y * delta_y
        projection = (
            (point["x"] - start["x"]) * delta_x + (point["y"] - start["y"]) * delta_y
        ) / length_squared
        projection = min(1.0, max(0.0, projection))
        nearest_x = start["x"] + projection * delta_x
        nearest_y = start["y"] + projection * delta_y
        return math.hypot(point["x"] - nearest_x, point["y"] - nearest_y)

    return min(
        distance_to_segment(contour[index], contour[(index + 1) % len(contour)])
        for index in range(len(contour))
    )


def _live_e_shallow_notch_document() -> dict[str, object]:
    document = _pentagon()
    rooms = cast(list[dict[str, Any]], document["rooms"])
    room = rooms[0]
    room["contour"] = _live_e_shallow_notch_contour()
    room["wallCount"] = 8
    room["dimensions"] = [
        {
            "edgeIndex": 0,
            "literalText": "3.50 m",
            "value": 3.50,
            "unit": "m",
            "status": "proposed",
        },
        {
            "edgeIndex": 5,
            "literalText": "0.90 m",
            "value": 0.90,
            "unit": "m",
            "status": "proposed",
        },
    ]
    room["openings"] = [
        {
            "edgeIndex": 1,
            "type": "window",
            "position": 0.40,
            "normalizedWidth": 0.20,
            "status": "proposed",
        },
        {
            "edgeIndex": 6,
            "type": "door",
            "position": 0.50,
            "normalizedWidth": 0.22,
            "status": "proposed",
        },
    ]
    return document


def _live_e_simplification_document() -> dict[str, object]:
    document = _pentagon()
    rooms = cast(list[dict[str, Any]], document["rooms"])
    room = rooms[0]
    contour = _live_e_staircase_contour()
    room["contour"] = [[point["x"], point["y"]] for point in contour]
    room["wallCount"] = 10
    room["dimensions"] = [
        {
            "literalText": "3.50",
            "value": 3.50,
            "unit": "m",
            "status": "proposed",
            "edgeIndex": 9,
        },
        {
            "literalText": "3.50",
            "value": 3.50,
            "unit": "m",
            "status": "proposed",
            "edgeIndex": 3,
        },
        {
            "literalText": "1.50",
            "value": 1.50,
            "unit": "m",
            "status": "proposed",
            "edgeIndex": 0,
        },
        {
            "literalText": "0.90",
            "value": 0.90,
            "unit": "m",
            "status": "proposed",
            "edgeIndex": 7,
        },
    ]
    room["openings"] = [
        {
            "type": "door",
            "wallIndex": 0,
            "position": 0.43,
            "normalizedWidth": 0.26,
            "status": "proposed",
        },
        {
            "type": "door",
            "wallIndex": 7,
            "position": 0.50,
            "normalizedWidth": 0.26,
            "status": "proposed",
        },
    ]
    return document


def test_semantic_contour_preserves_unverified_live_case_e_micro_fragments() -> None:
    contour = _live_e_staircase_contour()
    simplified, edge_mapping = floorplan_service._simplify_semantic_contour(contour)

    # Only the duplicated closing vertex has an unambiguous justification for
    # removal. A shallow stair may be a real wall: never force a rectangle.
    assert simplified == contour[:-1]
    assert len(simplified) == 10
    assert simplified[0] != simplified[-1]
    assert edge_mapping == list(range(10))
    semantic_room = {**_room(), "contour": simplified, "wallCount": 10, "dimensions": [], "openings": []}
    validated = FloorplanInterpretation.model_validate({**_pentagon(), "rooms": [semantic_room]})
    assert validated.rooms[0].wall_count == 10

def test_semantic_contour_preserves_unconfirmed_shallow_notch() -> None:
    contour = _live_e_shallow_notch_contour()
    simplified, edge_mapping = floorplan_service._simplify_semantic_contour(contour)

    # Without corroborating image evidence, eliminating this recess changes
    # physical topology; it must remain a proposal for manual confirmation.
    assert simplified == contour
    assert {point["y"] for point in simplified} == {0.15, 0.70, 0.75}
    assert edge_mapping == list(range(8))
    semantic_room = {**_room(), "contour": simplified, "wallCount": 8, "dimensions": [], "openings": []}
    validated = FloorplanInterpretation.model_validate({**_pentagon(), "rooms": [semantic_room]})
    assert validated.rooms[0].wall_count == 8

def test_normalization_preserves_shallow_notch_and_evidence_associations() -> None:
    document = _live_e_shallow_notch_document()
    normalized, stats = floorplan_service._normalize_groq_response(document)
    normalized_room = cast(dict[str, Any], cast(dict[str, Any], normalized)["rooms"][0])

    assert normalized_room["wallCount"] == 8
    assert normalized_room["contour"] == _live_e_shallow_notch_contour()
    assert "semantic_contour_simplified" not in stats.actions
    assert [item["edgeIndex"] for item in normalized_room["dimensions"]] == [0, 5]
    assert [item["edgeIndex"] for item in normalized_room["openings"]] == [1, 6]
    assert all(item["status"] == "proposed" for item in normalized_room["dimensions"])
    assert FloorplanInterpretation.model_validate(normalized).rooms[0].wall_count == 8


def test_simplify_semantic_contour_preserves_deep_architectural_alcove() -> None:
    alcove = [
        {"x": 0.10, "y": 0.10},
        {"x": 0.90, "y": 0.10},
        {"x": 0.90, "y": 0.90},
        {"x": 0.70, "y": 0.90},
        {"x": 0.70, "y": 0.65},
        {"x": 0.40, "y": 0.65},
        {"x": 0.40, "y": 0.90},
        {"x": 0.10, "y": 0.90},
    ]

    simplified, edge_mapping = floorplan_service._simplify_semantic_contour(alcove)

    assert simplified == alcove
    assert len(simplified) == 8
    assert {point["y"] for point in simplified} == {0.10, 0.65, 0.90}
    assert edge_mapping == list(range(8))


def test_semantic_contour_keeps_noisy_orthogonal_l_shape_without_inventing_walls() -> None:
    contour = _noisy_orthogonal_l_contour()
    simplified, edge_mapping = floorplan_service._simplify_semantic_contour(contour)

    # A deterministic non-destructive fallback is preferable to deleting a
    # series of visually ambiguous small recesses without image corroboration.
    assert simplified == contour
    for index in (0, 16, 32, 33, 39, 40):
        assert contour[index] in simplified
    assert edge_mapping == list(range(len(contour)))
    semantic_room = {
        **_room(), "contour": simplified, "wallCount": len(simplified), "dimensions": [], "openings": []
    }
    assert FloorplanInterpretation.model_validate(
        {**_pentagon(), "rooms": [semantic_room]}
    ).rooms[0].wall_count == len(contour)


@pytest.mark.parametrize(
    ("scale", "offset_x", "offset_y"),
    [(1.0, 0.0, 0.0), (0.70, 0.10, 0.08)],
)
def test_simplification_does_not_replace_supported_right_angle_with_diagonal_chord(
    scale: float, offset_x: float, offset_y: float
) -> None:
    contour = _transform_contour(
        _noisy_orthogonal_l_contour(),
        scale=scale,
        offset_x=offset_x,
        offset_y=offset_y,
    )

    simplified, edge_mapping = floorplan_service._simplify_semantic_contour(contour)

    macro_corner = contour[16]
    assert macro_corner in simplified
    assert all(_point_to_contour_distance(point, simplified) <= 0.03 * scale for point in contour)
    assert all(isinstance(edge, int) and 0 <= edge < len(simplified) for edge in edge_mapping)


def test_simplify_semantic_contour_preserves_real_pentagon_corners() -> None:
    contour = cast(list[dict[str, float]], _room()["contour"])
    original_contour = [dict(point) for point in contour]

    simplified, edge_mapping = floorplan_service._simplify_semantic_contour(  # type: ignore[attr-defined]
        contour
    )

    assert simplified == original_contour
    assert len(simplified) == 5
    assert edge_mapping == [0, 1, 2, 3, 4]


def test_simplify_semantic_contour_returns_deterministic_provider_edge_mapping() -> None:
    contour = _live_e_staircase_contour()

    simplified, edge_mapping = floorplan_service._simplify_semantic_contour(  # type: ignore[attr-defined]
        contour
    )
    repeated_simplified, repeated_mapping = floorplan_service._simplify_semantic_contour(  # type: ignore[attr-defined]
        contour
    )

    assert repeated_simplified == simplified
    assert repeated_mapping == edge_mapping
    assert len(edge_mapping) == len(contour) - 1

    assert all(isinstance(edge, int) and 0 <= edge < len(simplified) for edge in edge_mapping)
    assert set(edge_mapping) == set(range(len(simplified)))
    # An ambiguous shallow jog does not justify merging provider walls.
    assert edge_mapping == list(range(len(simplified)))


def test_normalization_simplifies_live_case_e_and_derives_semantic_wall_count() -> None:
    normalized, stats = floorplan_service._normalize_groq_response(_live_e_simplification_document())
    normalized_room = cast(dict[str, Any], cast(dict[str, Any], normalized)["rooms"][0])

    assert normalized_room["contour"] == _live_e_staircase_contour()[:-1]
    assert normalized_room["wallCount"] == 10
    assert normalized_room["contour"][0] != normalized_room["contour"][-1]
    assert all(
        0 <= item["edgeIndex"] < 10 for item in [*normalized_room["dimensions"], *normalized_room["openings"]]
    )
    validated = FloorplanInterpretation.model_validate(normalized)
    assert validated.rooms[0].wall_count == 10
    # The only unambiguous simplification is the duplicated closure.
    assert "semantic_contour_simplified" in stats.actions


def test_normalization_remaps_live_case_e_evidence_to_simplified_edges() -> None:
    document = _live_e_simplification_document()
    source_room = cast(dict[str, Any], cast(list[dict[str, Any]], document["rooms"])[0])
    _, edge_mapping = floorplan_service._simplify_semantic_contour(_live_e_staircase_contour())

    normalized, _ = floorplan_service._normalize_groq_response(document)
    normalized_room = cast(dict[str, Any], cast(dict[str, Any], normalized)["rooms"][0])

    for source, remapped in zip(source_room["dimensions"], normalized_room["dimensions"], strict=True):
        source_dimension = cast(dict[str, Any], source)
        normalized_dimension = cast(dict[str, Any], remapped)
        assert normalized_dimension["edgeIndex"] == edge_mapping[source_dimension["edgeIndex"]]
        assert normalized_dimension["literalText"] == source_dimension["literalText"]
        assert normalized_dimension["value"] == source_dimension["value"]
        assert normalized_dimension["unit"] == source_dimension["unit"]
        assert normalized_dimension["status"] == source_dimension["status"]

    for source, remapped in zip(source_room["openings"], normalized_room["openings"], strict=True):
        source_opening = cast(dict[str, Any], source)
        normalized_opening = cast(dict[str, Any], remapped)
        assert normalized_opening["edgeIndex"] == edge_mapping[source_opening["wallIndex"]]
        assert "wallIndex" not in normalized_opening
        assert normalized_opening["type"] == source_opening["type"]
        assert 0 <= normalized_opening["position"] <= 1
        assert 0 < normalized_opening["normalizedWidth"] <= 1
        assert normalized_opening["status"] == source_opening["status"]


def test_normalization_preserves_real_pentagon_geometry_and_edge_associations() -> None:
    document = _pentagon()
    source_room = cast(dict[str, Any], cast(list[dict[str, Any]], document["rooms"])[0])

    normalized, stats = floorplan_service._normalize_groq_response(document)
    normalized_room = cast(dict[str, Any], cast(dict[str, Any], normalized)["rooms"][0])

    assert normalized_room["contour"] == source_room["contour"]
    assert normalized_room["wallCount"] == 5
    assert [item["edgeIndex"] for item in normalized_room["dimensions"]] == [
        item["edgeIndex"] for item in source_room["dimensions"]
    ]
    assert [item["edgeIndex"] for item in normalized_room["openings"]] == [
        item["edgeIndex"] for item in source_room["openings"]
    ]
    assert "semantic_contour_simplified" not in stats.actions


def test_invalid_geometry_gets_one_sanitized_corrective_attempt() -> None:
    invalid = _invalid_contour_document()
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
    corrective_prompt = " ".join(prompts[1].split()).lower()
    assert len(result.rooms) == 1
    assert calls == [1, 2]
    assert prompts[1] != prompts[0]
    assert "your previous room contour was rejected" in corrective_prompt
    assert "original image" in corrective_prompt
    assert "dominant room" in corrective_prompt
    assert "semantic perimeter" in corrective_prompt
    assert "do not repeat the first point" in corrective_prompt
    assert "do not force a rectangle" in corrective_prompt
    assert json.dumps(invalid) not in prompts[1]


def test_duplicate_closing_vertex_and_collinear_overlap_get_invalid_contour_retry(
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.INFO, logger="roomforge.floorplan_interpretation")
    invalid = _live_e_duplicate_closure_document()
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
    corrective_prompt = " ".join(prompts[1].split()).lower()
    assert len(result.rooms) == 1
    assert result.rooms[0].wall_count == 6
    assert calls == [1, 2]
    assert "reason=invalid_contour" in caplog.text
    assert prompts[1] != prompts[0]
    assert "your previous room contour was rejected" in corrective_prompt
    assert "original image" in corrective_prompt
    assert "dominant room" in corrective_prompt
    assert "semantic perimeter" in corrective_prompt
    assert "do not repeat the first point" in corrective_prompt
    assert json.dumps(invalid) not in prompts[1]


def test_invalid_contour_corrective_attempt_uses_topology_rescue_prompt() -> None:
    prompts: list[str] = []
    payloads: list[dict[str, Any]] = []
    transport, calls = _topology_rescue_transport(prompts, payloads)

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(transport=transport) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key", model="model", timeout_seconds=2, client=client
            ).interpret(image=b"original-image", content_type="image/png")

    result = asyncio.run(run())
    corrective_prompt = " ".join(prompts[1].split()).lower()

    assert result.rooms[0].wall_count == 4
    assert calls == [1, 2]
    assert "original image" in corrective_prompt
    assert "dominant room" in corrective_prompt
    assert "semantic perimeter" in corrective_prompt
    assert "one vertex per real architectural wall" in corrective_prompt
    assert "closed by implication" in corrective_prompt
    assert "non-self-intersecting" in corrective_prompt
    assert "do not repeat the first point" in corrective_prompt
    assert "door swing arcs" in corrective_prompt
    assert "window strokes" in corrective_prompt
    assert "wall thickness bands" in corrective_prompt
    assert "furniture, text, dimensions" in corrective_prompt
    assert "construction lines" in corrective_prompt
    assert "preserve genuine irregular" in corrective_prompt
    assert "do not force a rectangle" in corrective_prompt
    assert "do not invent missing walls" in corrective_prompt
    assert "target count" in corrective_prompt


def test_invalid_contour_topology_rescue_uses_reduced_response_budget() -> None:
    prompts: list[str] = []
    payloads: list[dict[str, Any]] = []
    transport, calls = _topology_rescue_transport(prompts, payloads)

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(transport=transport) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key", model="model", timeout_seconds=2, client=client
            ).interpret(image=b"original-image", content_type="image/png")

    asyncio.run(run())

    assert calls == [1, 2]
    assert payloads[1]["max_tokens"] < payloads[0]["max_tokens"]


def test_dimensionless_topology_rescue_succeeds_with_two_semantic_attempts() -> None:
    prompts: list[str] = []
    payloads: list[dict[str, Any]] = []
    transport, calls = _topology_rescue_transport(prompts, payloads)

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(transport=transport) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key", model="model", timeout_seconds=2, client=client
            ).interpret(image=b"original-image", content_type="image/png")

    result = asyncio.run(run())

    assert calls == [1, 2]
    assert len(result.rooms) == 1
    assert result.rooms[0].wall_count == 4
    assert result.rooms[0].dimensions == []


def test_corrective_attempt_retries_short_rate_limit_without_consuming_semantic_attempt() -> None:
    delays: list[float] = []

    async def fake_sleep(delay: float) -> None:
        delays.append(delay)

    invalid = _live_e_duplicate_closure_document()
    prompts: list[str] = []
    transport, calls = _sequential_transport(
        [
            _provider_response(invalid),
            httpx.Response(429, headers={"Retry-After": "2"}),
            _provider_response(_l_room_with_list_contour()),
        ],
        prompts,
    )

    async def run() -> FloorplanInterpretation:
        async with httpx.AsyncClient(transport=transport) as client:
            return await GroqFloorplanInterpreter(
                api_key="test-key",
                model="model",
                timeout_seconds=3,
                client=client,
                sleep=fake_sleep,
            ).interpret(image=b"original-image", content_type="image/png")

    result = asyncio.run(run())
    corrective_prompt = " ".join(prompts[1].split()).lower()
    assert result.rooms[0].wall_count == 6
    assert calls == [1, 2, 3]
    assert delays == [2.0]
    assert "your previous room contour was rejected" in corrective_prompt
    assert "original image" in corrective_prompt
    assert "dominant room" in corrective_prompt
    assert "semantic perimeter" in corrective_prompt
    assert "do not repeat the first point" in corrective_prompt
    assert prompts[1] == prompts[2]


def test_corrective_rate_limit_repeats_only_once_then_propagates() -> None:
    delays: list[float] = []

    async def fake_sleep(delay: float) -> None:
        delays.append(delay)

    prompts: list[str] = []
    transport, calls = _sequential_transport(
        [
            _provider_response(_live_e_duplicate_closure_document()),
            httpx.Response(429, headers={"Retry-After": "1"}),
            httpx.Response(429, headers={"Retry-After": "1"}),
        ],
        prompts,
    )

    async def run() -> None:
        async with httpx.AsyncClient(transport=transport) as client:
            with pytest.raises(ProviderUnavailable) as raised:
                await GroqFloorplanInterpreter(
                    api_key="test-key", model="model", timeout_seconds=3,
                    client=client, sleep=fake_sleep,
                ).interpret(image=b"image", content_type="image/png")
            assert raised.value.reason == "rate_limited"

    asyncio.run(run())
    assert calls == [1, 2, 3]
    assert delays == [1.0]
    assert prompts[1] == prompts[2]


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


@pytest.mark.parametrize("association", [None, pytest.param("missing", id="missing")])
def test_unassociated_opening_evidence_survives_normalization(association: object) -> None:
    opening: dict[str, object] = {"type": "window", "status": "proposed"}
    if association != "missing":
        opening["edgeIndex"] = association
    normalized, stats = floorplan_service._normalize_groq_response(
        {**_pentagon(), "rooms": [{**_room(), "openings": [opening]}]}
    )
    room = cast(dict[str, Any], cast(list[object], cast(dict[str, Any], normalized)["rooms"])[0])
    preserved = cast(list[dict[str, Any]], room["openings"])
    assert preserved == [{**opening, "edgeIndex": None}]
    assert stats.actions == ["opening_edge_unassociated"]
    assert stats.dropped_openings == 0


def test_null_wall_index_alias_survives_as_unassociated_opening() -> None:
    normalized, stats = floorplan_service._normalize_groq_response(
        {**_pentagon(), "rooms": [{**_room(), "openings": [{"wallIndex": None, "type": "door"}]}]}
    )
    room = cast(dict[str, Any], cast(list[object], cast(dict[str, Any], normalized)["rooms"])[0])
    assert room["openings"] == [{"type": "door", "edgeIndex": None}]
    assert stats.actions == ["opening_edge_unassociated"]


@pytest.mark.parametrize("edge", [True, "1", 1.5, -1, 99])
def test_invalid_non_null_opening_edge_is_still_dropped(edge: object) -> None:
    normalized, stats = floorplan_service._normalize_groq_response(
        {**_pentagon(), "rooms": [{**_room(), "openings": [{"edgeIndex": edge, "type": "door"}]}]}
    )
    room = cast(dict[str, Any], cast(list[object], cast(dict[str, Any], normalized)["rooms"])[0])
    assert room["openings"] == []
    assert stats.actions == ["opening_dropped_invalid_edge"]


def test_room_candidate_accepts_unassociated_opening_but_rejects_invalid_concrete_edge() -> None:
    accepted = FloorplanInterpretation.model_validate(
        {**_pentagon(), "rooms": [{**_room(), "openings": [{"edgeIndex": None, "type": "unknown"}]}]}
    )
    assert accepted.rooms[0].openings[0].edge_index is None
    with pytest.raises(ValidationError):
        FloorplanInterpretation.model_validate(
            {**_pentagon(), "rooms": [{**_room(), "openings": [{"edgeIndex": 99, "type": "unknown"}]}]}
        )


@pytest.mark.parametrize(
    ("provider_edge", "semantic_edge", "expected_position", "expected_width"),
    [
        (
            ({"x": 0.0, "y": 0.0}, {"x": 0.4, "y": 0.0}),
            (({"x": 0.0, "y": 0.0}, {"x": 1.0, "y": 0.0}),),
            0.2,
            0.2,
        ),
        (
            ({"x": 0.6, "y": 0.0}, {"x": 1.0, "y": 0.0}),
            (({"x": 0.0, "y": 0.0}, {"x": 1.0, "y": 0.0}),),
            0.8,
            0.2,
        ),
        (
            ({"x": 0.4, "y": 0.0}, {"x": 0.0, "y": 0.0}),
            (({"x": 0.0, "y": 0.0}, {"x": 1.0, "y": 0.0}),),
            0.2,
            0.2,
        ),
    ],
)
def test_opening_geometry_is_remapped_to_semantic_edge(
    provider_edge: tuple[dict[str, float], dict[str, float]],
    semantic_edge: tuple[tuple[dict[str, float], dict[str, float]], ...],
    expected_position: float,
    expected_width: float,
) -> None:
    opening: dict[str, Any] = {"position": 0.5, "normalizedWidth": 0.5}
    stats = floorplan_service._NormalizationStats()
    provider = [*provider_edge, {"x": 0.4, "y": 0.4}]
    semantic = [*semantic_edge[0], {"x": 1.0, "y": 1.0}, {"x": 0.0, "y": 1.0}]
    floorplan_service._transform_opening_geometry_to_semantic_edge(
        opening,
        provider_contour=provider,
        provider_edge_index=0,
        semantic_contour=semantic,
        semantic_edge_index=0,
        stats=stats,
    )
    assert opening["position"] == pytest.approx(expected_position)
    assert opening["normalizedWidth"] == pytest.approx(expected_width)


def test_opening_geometry_uses_directed_semantic_edge_coordinates() -> None:
    provider_contour = [
        {"x": 0.0, "y": 0.0},
        {"x": 1.0, "y": 0.0},
        {"x": 1.0, "y": 1.0},
        {"x": 0.0, "y": 1.0},
    ]
    forward_opening: dict[str, Any] = {"position": 0.2, "normalizedWidth": 0.1}
    reversed_opening: dict[str, Any] = {"position": 0.2, "normalizedWidth": 0.1}
    stats = floorplan_service._NormalizationStats()

    floorplan_service._transform_opening_geometry_to_semantic_edge(
        forward_opening,
        provider_contour=provider_contour,
        provider_edge_index=0,
        semantic_contour=provider_contour,
        semantic_edge_index=0,
        stats=stats,
    )
    floorplan_service._transform_opening_geometry_to_semantic_edge(
        reversed_opening,
        provider_contour=provider_contour,
        provider_edge_index=0,
        semantic_contour=[
            {"x": 1.0, "y": 0.0},
            {"x": 0.0, "y": 0.0},
            {"x": 0.0, "y": 1.0},
            {"x": 1.0, "y": 1.0},
        ],
        semantic_edge_index=0,
        stats=stats,
    )

    assert forward_opening["position"] == pytest.approx(0.2)
    assert reversed_opening["position"] == pytest.approx(0.8)
    assert forward_opening["normalizedWidth"] == pytest.approx(0.1)
    assert reversed_opening["normalizedWidth"] == pytest.approx(0.1)


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
