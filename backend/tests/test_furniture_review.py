"""F08.5 rules through HTTP; fixture seeding is not acceptance evidence."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from uuid import uuid4

import pytest

from app.modules.catalog.models import ListingPhoto
from app.modules.catalog.photo_storage import InMemoryPhotoStorage
from app.modules.detection.models import DetectionJob
from app.modules.identity.models import Agency
from app.modules.identity.session import get_active_staff
from test_f04_publications import F04Context, f04_context as f04_context

BASE = "/api/v1/staff/agencies/agency-one/listings"
CONTENT = {
    "operation": "sale", "base_price": "100000.00", "currency": "BOB",
    "city": "La Paz", "zone": "Centro", "bedrooms": 2, "bathrooms": 1,
}
ITEM = {
    "name": "Silla revisada", "price": "20.50", "width_cm": 50,
    "height_cm": 90, "depth_cm": 60, "quantity": 2,
    "position": {"x": 1, "y": 0.45, "z": 1},
}


def seed_review(context: F04Context, agency_id: str = "agency-one") -> tuple[F04Context, str, list[str]]:
    context.app.dependency_overrides[get_active_staff] = lambda: {
        "id": "reviewer", "email": "reviewer@example.test",
        "role": "agency_admin", "tenant_id": agency_id,
    }
    context.app.state.photo_storage = InMemoryPhotoStorage()
    with context.session_factory.begin() as session:
        if session.get(Agency, agency_id) is None:
            session.add(Agency(id=agency_id))
    base = BASE.replace("agency-one", agency_id)
    created = context.client.post(base, json=CONTENT)
    assert created.status_code == 201, created.text
    path = f"{base}/{created.json()['listing_id']}"
    scene = json.loads((Path(__file__).parents[2] / "docs/api/f06-scene-fixture.json").read_text())
    saved = context.client.put(path + "/scene", json=scene)
    assert saved.status_code == 200, saved.text
    now = datetime.now(timezone.utc)
    jobs = [str(uuid4()), str(uuid4())]
    with context.session_factory.begin() as session:
        for job_id in jobs:
            photo_id = job_id
            key = f"agencies/{agency_id}/listings/{created.json()['listing_id']}/photos/{photo_id}"
            session.add(ListingPhoto(
                id=photo_id, agency_id=agency_id, listing_id=created.json()["listing_id"],
                object_key=key, status="confirmed", content_type="image/jpeg", size_bytes=100,
                created_at=now, expires_at=now, confirmed_at=now,
            ))
            session.add(DetectionJob(
                id=job_id, agency_id=agency_id, listing_id=created.json()["listing_id"],
                photo_id=photo_id, object_key=key, model_id="test-model",
                dedupe_key=f"{photo_id}:test-model", status="completed", attempts=0,
                result={"model_id": "test-model", "detections": [
                    {"label": "chair", "score": 0.91, "box": [1, 2, 50, 90]},
                ]}, created_at=now, finished_at=now,
            ))
    return context, path, jobs


@pytest.fixture
def review(f04_context: F04Context) -> tuple[F04Context, str, list[str]]:
    return seed_review(f04_context)


def view(context: F04Context, path: str) -> dict[str, Any]:
    response = context.client.get(path + "/furniture-review")
    assert response.status_code == 200, response.text
    return response.json()


def command(context: F04Context, path: str, **changes: Any) -> dict[str, Any]:
    body: dict[str, Any] = {
        "request_id": str(uuid4()), "action": "manual", "item": ITEM,
        "expected_offer_version": context.client.get(path).json()["offer_version"],
    }
    body.update(changes)
    return body


def test_read_never_promotes_detection_and_preserves_existing_job_and_scene_api(review: Any) -> None:
    context, path, jobs = review
    scene = context.client.get(path + "/scene").json()
    first = view(context, path)
    assert first["listing"]["extras"] == []
    assert [s["status"] for s in first["suggestions"]] == ["pending", "pending"]
    assert first["history"] == []
    assert view(context, path) == first
    assert context.client.get(path + "/scene").json() == scene
    assert {j["job_id"] for j in context.client.get(path + "/detections").json()["jobs"]} == set(jobs)
    unchanged = context.client.put(path + "/scene", json=scene)
    assert unchanged.status_code == 200 and unchanged.json() == scene


def test_confirmation_is_atomic_audited_and_quote_uses_human_price(review: Any) -> None:
    context, path, jobs = review
    body = command(context, path, action="confirmed", job_id=jobs[0], detection_index=0)
    response = context.client.post(path + "/furniture-review", json=body)
    assert response.status_code == 200, response.text
    data = response.json()
    extra = data["listing"]["extras"][0]
    assert extra["price"] == "20.50" and extra["quantity"] == 2
    assert extra["width_cm"] == 50 and extra["origin"] == "human-confirmed-ai"
    assert data["listing"]["approval_status"] == "draft"
    assert data["listing"]["is_published"] is False
    objects = context.client.get(path + "/scene").json()["objects"]
    added = next(item for item in objects if item["id"] == extra["extra_id"])
    assert added["dimensions"] == {"width": 0.5, "height": 0.9, "depth": 0.6}
    assert added["position"] == ITEM["position"]
    event = data["history"][0]
    assert event["actor_id"] == "reviewer" and event["created_at"]
    assert event["snapshot"]["label"] == "chair"
    assert event["extra_id"] == extra["extra_id"]
    replay = context.client.post(path + "/furniture-review", json=body)
    assert replay.status_code == 200 and replay.json() == data
    for action in ("submit", "approve", "publish"):
        moved = context.client.post(path + "/" + action)
        assert moved.status_code == 200, moved.text
    quote = context.client.post("/api/v1/quotes", json={
        "listing_id": data["listing"]["listing_id"],
        "offer_version": context.client.get(path).json()["offer_version"],
        "selected_extra_ids": [extra["extra_id"]],
    })
    assert quote.status_code == 201, quote.text
    assert quote.json()["one_time_total"] == {"amount": "100041.00", "currency": "BOB"}


def test_rejection_is_final_and_has_no_inventory_scene_or_offer_effect(review: Any) -> None:
    context, path, jobs = review
    before = view(context, path)
    scene = context.client.get(path + "/scene").json()
    body = command(context, path, action="rejected", job_id=jobs[0], detection_index=0, item=None)
    response = context.client.post(path + "/furniture-review", json=body)
    assert response.status_code == 200, response.text
    after = view(context, path)
    assert after["listing"] == before["listing"]
    assert context.client.get(path + "/scene").json() == scene
    assert next(s for s in after["suggestions"] if s["job_id"] == jobs[0])["status"] == "rejected"
    assert len(after["history"]) == 1
    attempted = command(context, path, action="confirmed", job_id=jobs[0], detection_index=0)
    conflict = context.client.post(path + "/furniture-review", json=attempted)
    assert conflict.status_code == 409
    assert view(context, path) == after


def test_manual_inventory_and_cross_photo_duplicate_link_do_not_double_count(review: Any) -> None:
    context, path, jobs = review
    manual = command(context, path)
    response = context.client.post(path + "/furniture-review", json=manual)
    assert response.status_code == 200, response.text
    extra = response.json()["listing"]["extras"][0]
    assert extra["origin"] == "manual"
    for job in jobs:
        body = command(context, path, action="confirmed", item=None,
                       job_id=job, detection_index=0, existing_extra_id=extra["extra_id"])
        linked = context.client.post(path + "/furniture-review", json=body)
        assert linked.status_code == 200, linked.text
    after = view(context, path)
    assert after["listing"]["extras"] == [extra]
    assert len(after["history"]) == 3
    assert len([o for o in context.client.get(path + "/scene").json()["objects"]
                if o["id"] == extra["extra_id"]]) == 1
    before = view(context, path)
    replay = context.client.post(path + "/furniture-review", json=manual)
    assert replay.status_code == 200 and replay.json() == before
    conflict = context.client.post(path + "/furniture-review", json={**manual, "item": {**ITEM, "price": "99.00"}})
    assert conflict.status_code == 409 and view(context, path) == before


@pytest.mark.parametrize("change", ["edit", "unpublish"])
def test_listing_edit_conflicts_and_unpublish_still_requires_explicit_confirmation(review: Any, change: str) -> None:
    context, path, jobs = review
    if change == "unpublish":
        for action in ("submit", "approve", "publish"):
            assert context.client.post(path + "/" + action).status_code == 200
    body = command(context, path, action="confirmed", job_id=jobs[0], detection_index=0)
    if change == "edit":
        assert context.client.put(path, json={**CONTENT, "base_price": "100001.00"}).status_code == 200
    else:
        assert context.client.post(path + "/unpublish").status_code == 200
    before = view(context, path)
    scene = context.client.get(path + "/scene").json()
    response = context.client.post(path + "/furniture-review", json=body)
    assert before["listing"]["extras"] == []
    assert all(s["status"] == "pending" for s in before["suggestions"])
    if change == "edit":
        assert response.status_code == 409, response.text
        assert view(context, path) == before
        assert context.client.get(path + "/scene").json() == scene
    else:
        # F05 deliberately does not version a non-commercial publication change.
        # Unpublishing alone never confirms; this explicit human POST does.
        assert response.status_code == 200, response.text
        assert len(response.json()["listing"]["extras"]) == 1
        assert response.json()["listing"]["is_published"] is False


def test_deleted_photo_expires_pending_without_losing_audited_rejection(review: Any) -> None:
    context, path, jobs = review
    rejected = command(context, path, action="rejected", item=None, job_id=jobs[0], detection_index=0)
    assert context.client.post(path + "/furniture-review", json=rejected).status_code == 200
    for photo_id in jobs:
        removed = context.client.delete(path + f"/photos/{photo_id}")
        assert removed.status_code == 204, removed.text
    before = view(context, path)
    statuses = {s["job_id"]: s["status"] for s in before["suggestions"]}
    assert statuses == {jobs[0]: "rejected", jobs[1]: "expired"}
    body = command(context, path, action="confirmed", job_id=jobs[1], detection_index=0)
    response = context.client.post(path + "/furniture-review", json=body)
    assert response.status_code == 409 and view(context, path) == before


@pytest.mark.parametrize("change", [
    {"width_cm": 0}, {"height_cm": True}, {"depth_cm": "50"},
    {"price": "20.555"}, {"position": {"x": "1", "y": 0, "z": 0}},
    {"origin": "fabricated"},
])
def test_invalid_human_fields_leave_everything_unchanged(review: Any, change: Any) -> None:
    context, path, _ = review
    before = view(context, path)
    scene = context.client.get(path + "/scene").json()
    body = command(context, path, item={**ITEM, **change})
    response = context.client.post(path + "/furniture-review", json=body)
    assert response.status_code == 422, response.text
    assert view(context, path) == before
    assert context.client.get(path + "/scene").json() == scene


@pytest.mark.parametrize("role,tenant", [("agent", "agency-other"), ("platform_admin", None)])
def test_new_routes_preserve_tenant_authorization(review: Any, role: str, tenant: str | None) -> None:
    context, path, _ = review
    before = view(context, path)
    body = command(context, path)
    context.app.dependency_overrides[get_active_staff] = lambda: {
        "id": "other", "email": "other@example.test", "role": role, "tenant_id": tenant,
    }
    assert context.client.get(path + "/furniture-review").status_code == 403
    assert context.client.post(path + "/furniture-review", json=body).status_code == 403
    context.app.dependency_overrides[get_active_staff] = lambda: {
        "id": "reviewer", "email": "reviewer@example.test", "role": "agency_admin", "tenant_id": "agency-one",
    }
    assert view(context, path) == before


def test_foreign_already_reviewed_detection_is_indistinguishable_from_missing(review: Any) -> None:
    context, path, jobs = review
    own_before = view(context, path)
    _, foreign_path, foreign_jobs = seed_review(context, "agency-two")
    confirmed = context.client.post(foreign_path + "/furniture-review", json=command(
        context, foreign_path, action="confirmed", job_id=foreign_jobs[0], detection_index=0,
    ))
    assert confirmed.status_code == 200, confirmed.text
    foreign_before = view(context, foreign_path)
    context.app.dependency_overrides[get_active_staff] = lambda: {
        "id": "reviewer", "email": "reviewer@example.test", "role": "agent", "tenant_id": "agency-one",
    }
    responses = [
        context.client.post(path + "/furniture-review", json=command(
            context, path, action="confirmed", job_id=identifier, detection_index=0,
        )) for identifier in (foreign_jobs[0], str(uuid4()))
    ]
    assert [(response.status_code, response.json()) for response in responses] == [
        (404, {"detail": "Detection not found", "code": "not_found"}),
        (404, {"detail": "Detection not found", "code": "not_found"}),
    ]
    assert view(context, path) == own_before
    context.app.dependency_overrides[get_active_staff] = lambda: {
        "id": "reviewer", "email": "reviewer@example.test", "role": "agent", "tenant_id": "agency-two",
    }
    assert view(context, foreign_path) == foreign_before


def test_missing_session_and_foreign_listing_do_not_expose_review_data(review: Any) -> None:
    context, path, _ = review
    before = view(context, path)
    body = command(context, path)
    missing = path.rsplit("/", 1)[0] + "/" + str(uuid4())
    assert context.client.get(missing + "/furniture-review").status_code == 404
    assert context.client.post(missing + "/furniture-review", json=body).status_code == 404
    context.app.dependency_overrides.pop(get_active_staff)
    assert context.client.get(path + "/furniture-review").status_code == 401
    assert context.client.post(path + "/furniture-review", json=body).status_code == 401
    context.app.dependency_overrides[get_active_staff] = lambda: {
        "id": "reviewer", "email": "reviewer@example.test", "role": "agent", "tenant_id": "agency-one",
    }
    assert view(context, path) == before


def test_foreign_identifiers_and_missing_scene_reject_without_partial_inventory(review: Any) -> None:
    context, path, jobs = review
    before = view(context, path)
    for changes in (
        {"action": "confirmed", "job_id": str(uuid4()), "detection_index": 0},
        {"action": "confirmed", "job_id": jobs[0], "detection_index": 0,
         "item": None, "existing_extra_id": str(uuid4())},
    ):
        rejected = context.client.post(path + "/furniture-review", json=command(context, path, **changes))
        assert rejected.status_code == 404, rejected.text
        assert view(context, path) == before
    created = context.client.post(BASE, json=CONTENT).json()
    empty_path = f"{BASE}/{created['listing_id']}"
    snapshot = view(context, empty_path)
    failed = context.client.post(empty_path + "/furniture-review", json=command(context, empty_path))
    assert failed.status_code == 409 and view(context, empty_path) == snapshot
    assert context.client.get(empty_path + "/scene").status_code == 404
