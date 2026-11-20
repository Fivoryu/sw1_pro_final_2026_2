"""F07 integrity, lease fencing and metric boundary regressions."""
from __future__ import annotations

import hashlib
from datetime import timedelta

import pytest

from test_reconstruction import Ctx, _CAPTURE, _auth, _capture_zip, _scene
from app.modules.catalog.models import Listing, ListingScene


@pytest.fixture
def ctx():
    opened = Ctx()
    yield opened
    opened.close()


def test_missing_upload_never_queues(ctx: Ctx) -> None:
    ctx.register()
    response = ctx.client.post(f"{ctx.base()}/{_CAPTURE}/complete")
    assert response.status_code == 409
    assert ctx.row().status == "awaiting_upload" and not ctx.queue.published


@pytest.mark.parametrize("data", [b"not a zip", b"truncated"])
def test_invalid_zip_never_confirms_delivery(ctx: Ctx, data: bytes) -> None:
    ctx.register(size=len(data))
    ctx.storage.objects[ctx.row().object_key] = data
    response = ctx.client.post(f"{ctx.base()}/{_CAPTURE}/complete")
    assert response.status_code == 422
    assert ctx.row().status == "awaiting_upload"


def test_truncated_object_is_rejected(ctx: Ctx) -> None:
    ctx.register(size=1000)
    ctx.storage.objects[ctx.row().object_key] = _capture_zip()
    assert ctx.client.post(f"{ctx.base()}/{_CAPTURE}/complete").status_code == 409


def test_confirmed_snapshot_cannot_be_changed_with_old_put_url(ctx: Ctx) -> None:
    data = _capture_zip()
    ctx.register(size=len(data))
    staging = ctx.row().object_key
    ctx.storage.objects[staging] = data
    done = ctx.client.post(f"{ctx.base()}/{_CAPTURE}/complete")
    assert done.json()["uploadVerified"] is True
    snapshot = ctx.row().object_key
    assert snapshot != staging
    ctx.storage.objects[staging] = b"replacement"
    claim = ctx.claim(ctx.row().job_id).json()
    assert claim["package_sha256"] == hashlib.sha256(data).hexdigest()
    assert claim["capture_id"] == _CAPTURE and claim["listing_id"] == "listing-one"
    assert ctx.storage.objects[snapshot] == data


def test_manifest_of_another_listing_is_rejected(ctx: Ctx) -> None:
    data = _capture_zip(listing_id="listing-two")
    ctx.register(size=len(data))
    ctx.storage.objects[ctx.row().object_key] = data
    assert ctx.client.post(f"{ctx.base()}/{_CAPTURE}/complete").status_code == 422


def test_registration_does_not_silently_change_metadata(ctx: Ctx) -> None:
    assert ctx.register(size=1000).status_code == 201
    assert ctx.register(size=1001).status_code == 409


def test_expected_checksum_is_enforced(ctx: Ctx) -> None:
    data = _capture_zip()
    response = ctx.client.post(ctx.base(), json={"captureId": _CAPTURE, "sizeBytes": len(data), "sha256": "0" * 64})
    assert response.status_code == 201
    ctx.storage.objects[ctx.row().object_key] = data
    assert ctx.client.post(f"{ctx.base()}/{_CAPTURE}/complete").status_code == 409


@pytest.mark.parametrize("unit,scale,alignment,clock,confirmed", [
    ("arbitrary", "unscaled", "connected", "realtime", True),
    ("meters", "unscaled", "connected", "realtime", True),
    ("meters", "reference", "disconnected", "realtime", True),
    ("meters", "reference", "connected", "unknown", True),
    ("meters", "reference", "connected", "realtime", False),
])
def test_nonmetric_draft_can_be_kept_but_not_accepted_or_saved(
    ctx: Ctx, unit: str, scale: str, alignment: str, clock: str, confirmed: bool,
) -> None:
    job, token = ctx.running()
    scene = _scene()
    scene.update(unit=unit, measurement={"source": "sfm", "referenceConfirmed": confirmed, "scale": scale, "alignment": alignment, "clock": clock})
    assert ctx.worker(job, "complete", token, {"sceneDraft": scene}).status_code == 200
    assert ctx.row().status == "completed" and ctx.row().accepted_at is None
    assert ctx.status()["sceneDraft"]["measurement"]["clock"] == clock
    assert ctx.client.post(f"{ctx.base()}/{_CAPTURE}/accept").status_code == 409
    response = ctx.client.put(ctx.base().removesuffix("/captures") + "/scene", json=scene)
    assert response.status_code == 422
    with ctx.session_factory() as session:
        assert session.get(ListingScene, "listing-one") is None
    assert ctx.row().accepted_at is None


def test_heartbeat_extends_current_owner_and_fences_expired_token(ctx: Ctx) -> None:
    job, token = ctx.running()
    endpoint = f"/api/v1/reconstruction/jobs/{job}/renew"
    headers = {**_auth(), "X-Reconstruction-Claim-Token": token}
    ctx.now += timedelta(seconds=250)
    assert ctx.client.post(endpoint, headers=headers).status_code == 200
    ctx.now += timedelta(seconds=100)
    assert ctx.worker(job, "complete", token, {"sceneDraft": _scene()}).status_code == 200
    assert ctx.client.post(endpoint, headers=headers).status_code == 409


def test_geometry_and_reference_diagnostics_survive_draft_review_without_acceptance(ctx: Ctx) -> None:
    job, token = ctx.running()
    scene = _scene()
    scene.update(unit="arbitrary", measurement={"source": "sfm", "referenceConfirmed": True,
        "scale": "unscaled", "alignment": "disconnected", "clock": "unknown"})
    warnings = ["REFERENCE_FRAME_NOT_REGISTERED: La referencia no obtuvo pose.",
                "GEOMETRY_CAMERA_SUPPORT_MISSING: Revisá bases de paredes y esquinas."]
    assert ctx.worker(job, "complete", token, {"sceneDraft": scene, "warnings": warnings}).status_code == 200
    body = ctx.status()
    assert body["status"] == "completed" and body["warnings"] == warnings
    assert body["sceneDraft"]["measurement"] == scene["measurement"]
    assert ctx.client.post(f"{ctx.base()}/{_CAPTURE}/accept").status_code == 409
    assert ctx.row().accepted_at is None
    with ctx.session_factory() as session:
        assert session.get(ListingScene, "listing-one") is None


def test_historical_proportional_preview_never_claims_meters(ctx: Ctx) -> None:
    from app.modules.reconstruction.models import ListingCapture

    job, token = ctx.running()
    assert ctx.worker(job, "complete", token, {"sceneDraft": _scene()}).status_code == 200
    with ctx.session_factory.begin() as session:
        capture = session.get(ListingCapture, _CAPTURE)
        assert capture is not None
        capture.scene_draft = {**_scene(), "scale": {"mode": "proportional"}}
    assert ctx.status()["sceneDraft"]["unit"] == "arbitrary"
    historical = ctx.row().scene_draft
    assert historical is not None and historical["unit"] == "meters"  # Read did not rewrite historical evidence.
    assert ctx.client.post(f"{ctx.base()}/{_CAPTURE}/accept").status_code == 409


@pytest.mark.parametrize("unit,scale,alignment,clock,confirmed,expected", [
    ("arbitrary", "unscaled", "connected", "realtime", True, 409),
    ("meters", "unscaled", "connected", "realtime", True, 409),
    ("meters", "reference", "disconnected", "realtime", True, 409),
    ("meters", "reference", "connected", "unknown", True, 409),
    ("meters", "reference", "connected", "realtime", False, 409),
    ("meters", "reference", "connected", "realtime", True, 200),
])
def test_publication_independently_checks_historical_saved_measurement_evidence(
    ctx: Ctx, unit: str, scale: str, alignment: str, clock: str, confirmed: bool, expected: int,
) -> None:
    scene = _scene()
    scene.update(unit=unit, measurement={"source": "sfm", "scale": scale, "alignment": alignment,
        "clock": clock, "referenceConfirmed": confirmed})
    # Seed an already stored historical document only in the disposable fixture.
    # New invalid drafts are rejected before persistence by the preceding test.
    with ctx.session_factory.begin() as session:
        listing = session.get(Listing, "listing-one")
        assert listing is not None
        listing.approval_status = "approved"
        session.add(ListingScene(listing_id=listing.id, scene=scene, updated_at=ctx.now))
    ctx.set_staff(tenant="agency-one", role="agency_admin")
    response = ctx.client.post(ctx.base().removesuffix("/captures") + "/publish")
    assert response.status_code == expected, response.text
    with ctx.session_factory() as session:
        listing = session.get(Listing, "listing-one")
        assert listing is not None and listing.is_published is (expected == 200)


def test_expired_owner_cannot_renew_or_complete(ctx: Ctx) -> None:
    job, token = ctx.running()
    ctx.now += timedelta(seconds=301)
    assert ctx.worker(job, "renew", token, {}).status_code == 409
    assert ctx.worker(job, "complete", token, {"sceneDraft": _scene()}).status_code == 409
