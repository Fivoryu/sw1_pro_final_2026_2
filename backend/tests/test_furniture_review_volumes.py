"""F08 x F07.7: human review of class suggestions for reconstructed volumes, through HTTP."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any
from uuid import uuid4

import pytest

from app.modules.reconstruction.models import ListingCapture
from test_f04_publications import F04Context, f04_context as f04_context  # noqa: F401
from test_furniture_review import ITEM, command, seed_review, view

CAPTURE = "capture-volumes-1"
GEOMETRY = {
    "position": {"x": 2.0, "y": 0.5, "z": 2.5},
    "dimensions": {"width": 1.0, "height": 1.0, "depth": 0.8},
}


def _volume(object_id: str = "box-1") -> dict[str, Any]:
    return {
        "id": object_id, "type": "occupancy", "color": "#778899", "source": "depth",
        "confidence": 0.7, **GEOMETRY,
    }


def seed_capture(
    context: F04Context, path: str, *, status: str = "completed", agency_id: str = "agency-one",
    capture_id: str = CAPTURE, with_object: bool = True,
) -> None:
    now = datetime.now(timezone.utc)
    with context.session_factory.begin() as session:
        session.add(ListingCapture(
            id=capture_id, job_id=str(uuid4()), agency_id=agency_id, listing_id=path.rsplit("/", 1)[1],
            object_key="k", size_bytes=1, status=status, created_by="agent", created_at=now,
            frames_delete_after=now, scene_draft={
                "version": "2.0", "unit": "meters", "walls": [], "openings": [], "rooms": [],
                "objects": [_volume()] if with_object else [],
            },
            volume_suggestions={"modelId": "test-model", "items": [
                {"objectId": "box-1", "label": "sofa", "score": 0.82, "keyframe": 3, "box": [1, 2, 3, 4]},
            ]},
        ))


@pytest.fixture
def volumes(f04_context: F04Context) -> tuple[F04Context, str]:
    context, path, _ = seed_review(f04_context)
    seed_capture(context, path)
    return context, path


def post(context: F04Context, path: str, **changes: Any) -> Any:
    return context.client.post(path + "/furniture-review", json=command(context, path, **changes))


def test_view_lists_volume_suggestions_with_geometry_and_pending_status(volumes: Any) -> None:
    context, path = volumes
    listed = view(context, path)["volume_suggestions"]
    assert listed == [{
        "capture_id": CAPTURE, "object_id": "box-1", "model_id": "test-model", "label": "sofa",
        "score": 0.82, **GEOMETRY, "status": "pending", "extra_id": None,
    }]
    assert view(context, path) == view(context, path)


def test_view_marks_volume_expired_when_the_capture_is_not_current(f04_context: F04Context) -> None:
    context, path, _ = seed_review(f04_context)
    seed_capture(context, path, status="failed")
    assert [v["status"] for v in view(context, path)["volume_suggestions"]] == ["expired"]


def test_confirm_by_volume_appends_the_scene_object_with_the_draft_geometry(volumes: Any) -> None:
    context, path = volumes
    # The form geometry differs on purpose: the reviewed volume decides where the box goes.
    item = {**ITEM, "position": {"x": 9, "y": 0.45, "z": 9}}
    response = post(context, path, action="confirmed", capture_id=CAPTURE, object_id="box-1", item=item)
    assert response.status_code == 200, response.text
    data = response.json()
    extra = data["listing"]["extras"][0]
    assert extra["origin"] == "human-confirmed-ai"
    assert extra["visual_reference"] == f"capture:{CAPTURE}:box-1"
    placed = next(o for o in context.client.get(path + "/scene").json()["objects"] if o["id"] == extra["extra_id"])
    assert placed["position"] == GEOMETRY["position"]
    assert placed["dimensions"] == GEOMETRY["dimensions"]
    assert data["volume_suggestions"][0]["status"] == "confirmed"
    assert data["volume_suggestions"][0]["extra_id"] == extra["extra_id"]
    assert data["history"][0]["capture_id"] == CAPTURE and data["history"][0]["snapshot"]["label"] == "sofa"
    assert post_replay(context, path, data)


def post_replay(context: F04Context, path: str, data: dict[str, Any]) -> bool:
    # The decision is final: a different request id for the same volume conflicts.
    again = post(context, path, action="confirmed", capture_id=CAPTURE, object_id="box-1")
    return again.status_code == 409


def test_confirm_replaces_an_existing_scene_object_keeping_its_geometry(volumes: Any) -> None:
    context, path = volumes
    scene = context.client.get(path + "/scene").json()
    stored = {**_volume(), "position": {"x": 3.0, "y": 0.5, "z": 1.0}}
    scene["objects"].append(stored)
    assert context.client.put(path + "/scene", json=scene).status_code == 200
    item = {**ITEM, "position": {"x": 1, "y": 0.45, "z": 1}}
    response = post(context, path, action="confirmed", capture_id=CAPTURE, object_id="box-1", item=item)
    assert response.status_code == 200, response.text
    extra_id = response.json()["listing"]["extras"][0]["extra_id"]
    objects = {o["id"]: o for o in context.client.get(path + "/scene").json()["objects"]}
    assert "box-1" not in objects
    assert objects[extra_id]["position"] == stored["position"]


def test_reject_by_volume_only_records_the_decision(volumes: Any) -> None:
    context, path = volumes
    before = view(context, path)
    scene = context.client.get(path + "/scene").json()
    response = post(context, path, action="rejected", capture_id=CAPTURE, object_id="box-1", item=None)
    assert response.status_code == 200, response.text
    after = response.json()
    assert after["listing"] == before["listing"]
    assert context.client.get(path + "/scene").json() == scene
    assert after["volume_suggestions"][0]["status"] == "rejected"
    conflict = post(context, path, action="confirmed", capture_id=CAPTURE, object_id="box-1")
    assert conflict.status_code == 409


def test_both_references_or_a_partial_one_are_rejected(volumes: Any) -> None:
    context, path = volumes
    both = post(context, path, action="rejected", item=None, capture_id=CAPTURE, object_id="box-1",
                job_id=str(uuid4()), detection_index=0)
    partial = post(context, path, action="rejected", item=None, capture_id=CAPTURE)
    manual = post(context, path, capture_id=CAPTURE, object_id="box-1")
    assert [r.status_code for r in (both, partial, manual)] == [422, 422, 422]


def test_unavailable_capture_or_object_conflicts_and_changes_nothing(f04_context: F04Context) -> None:
    context, path, _ = seed_review(f04_context)
    seed_capture(context, path, status="failed")
    seed_capture(context, path, capture_id="capture-empty", with_object=False)
    before = view(context, path)
    for capture_id in (CAPTURE, "capture-empty"):
        response = post(context, path, action="confirmed", capture_id=capture_id, object_id="box-1")
        assert response.status_code == 409
        assert response.json()["detail"] == "The source capture is no longer available"
    assert view(context, path) == before


def test_foreign_capture_is_not_listed_and_cannot_be_reviewed(f04_context: F04Context) -> None:
    context, path, _ = seed_review(f04_context)
    seed_capture(context, path, agency_id="agency-two")
    assert view(context, path)["volume_suggestions"] == []
    response = post(context, path, action="rejected", capture_id=CAPTURE, object_id="box-1", item=None)
    assert response.status_code == 404
    assert view(context, path)["history"] == []
    missing = post(context, path, action="rejected", capture_id="nope", object_id="box-1", item=None)
    assert missing.status_code == 404
