"""Independent audit R02-R09: negative and recovery contract boundaries."""
from __future__ import annotations

import hashlib
import io
import json
import os
import time
import threading
import zipfile
from datetime import timedelta

import pytest

from test_reconstruction import Ctx, _CAPTURE, _capture_zip, _scene
from app.modules.reconstruction.models import ListingCapture
from app.modules.reconstruction.service import run_capture_retention_sweep, run_reconstruction_recovery_sweep


@pytest.fixture
def ctx():
    opened = Ctx()
    yield opened
    opened.close()


def test_purged_registration_cannot_be_reactivated(ctx: Ctx) -> None:
    ctx.register()
    ctx.now += timedelta(days=31)
    assert run_capture_retention_sweep(ctx.session_factory, ctx.storage, now=ctx.now) == 1
    assert ctx.register().status_code == 410
    ctx.storage.objects[ctx.row().object_key] = _capture_zip()
    assert ctx.client.post(f"{ctx.base()}/{_CAPTURE}/complete").status_code == 410


def test_publication_outage_does_not_consume_execution_attempts(ctx: Ctx) -> None:
    ctx.queued()
    for hour in range(1, 5):
        run_reconstruction_recovery_sweep(ctx.session_factory, None,
                                          now=ctx.now + timedelta(hours=hour), max_attempts=3)
    assert ctx.row().status == "queued"
    assert ctx.row().attempts == 0
    run_reconstruction_recovery_sweep(ctx.session_factory, ctx.queue,
                                      now=ctx.now + timedelta(hours=5), max_attempts=3)
    assert ctx.claim(ctx.row().job_id).status_code == 200


def test_repeated_queue_errors_remain_recoverable_without_attempts(ctx: Ctx) -> None:
    ctx.queued()
    ctx.queue.fail_on_publish = True
    for hour in range(1, 5):
        run_reconstruction_recovery_sweep(ctx.session_factory, ctx.queue,
                                          now=ctx.now + timedelta(hours=hour), max_attempts=3)
    assert ctx.row().attempts == 0 and ctx.row().status == "queued"
    ctx.queue.fail_on_publish = False
    run_reconstruction_recovery_sweep(ctx.session_factory, ctx.queue,
                                      now=ctx.now + timedelta(hours=5), max_attempts=3)
    assert ctx.claim(ctx.row().job_id).status_code == 200


def test_accept_requires_associated_persisted_scene(ctx: Ctx) -> None:
    job, token = ctx.running()
    assert ctx.worker(job, "complete", token, {"sceneDraft": _scene()}).status_code == 200
    assert ctx.client.post(f"{ctx.base()}/{_CAPTURE}/accept").status_code == 409
    assert ctx.row().accepted_at is None


def test_legacy_registration_can_acquire_checksum_without_identity_change(ctx: Ctx) -> None:
    data = _capture_zip()
    ctx.register()
    ctx.storage.objects[ctx.row().object_key] = data
    digest = hashlib.sha256(data).hexdigest()
    retry = ctx.client.post(ctx.base(), json={"captureId": _CAPTURE, "sizeBytes": len(data), "sha256": digest})
    assert retry.status_code == 200
    assert ctx.client.post(f"{ctx.base()}/{_CAPTURE}/complete").json()["uploadVerified"] is True
    assert ctx.row().package_sha256 == digest
    assert ctx.client.post(ctx.base(), json={"captureId": _CAPTURE, "sizeBytes": len(data), "sha256": "0" * 64}).status_code == 409


def test_legacy_completed_package_can_be_verified_without_requeue(ctx: Ctx) -> None:
    job, token = ctx.running()
    ctx.worker(job, "complete", token, {"sceneDraft": _scene()})
    with ctx.session_factory.begin() as session:
        row = session.get(ListingCapture, _CAPTURE)
        assert row is not None
        row.package_manifest = None
        row.package_sha256 = None
    assert ctx.client.post(f"{ctx.base()}/{_CAPTURE}/accept").status_code == 409
    assert ctx.client.put(ctx.base().removesuffix("/captures") + "/scene",
                          json={**_scene(), "captureId": _CAPTURE}).status_code == 422
    published = len(ctx.queue.published)
    response = ctx.client.post(f"{ctx.base()}/{_CAPTURE}/complete")
    assert response.status_code == 202
    assert response.json()["uploadVerified"] is True
    assert ctx.row().status == "completed"
    assert len(ctx.queue.published) == published
    assert ctx.client.put(ctx.base().removesuffix("/captures") + "/scene",
                          json={**_scene(), "captureId": _CAPTURE}).status_code == 200


def test_stripping_scale_metadata_cannot_launder_capture_geometry(ctx: Ctx) -> None:
    job, token = ctx.running()
    draft = _scene()
    draft.update(unit="arbitrary", measurement={"source": "sfm", "scale": "unscaled",
                  "alignment": "connected", "clock": "realtime", "referenceConfirmed": False})
    assert ctx.worker(job, "complete", token, {"sceneDraft": draft}).status_code == 200
    draft.pop("measurement")
    draft["unit"] = "meters"
    draft["walls"][0]["height"] = 2.5 # Human edits do not erase identity of captured walls.
    assert ctx.client.put(ctx.base().removesuffix("/captures") + "/scene", json=draft).status_code == 422


def test_associated_scene_allows_human_edits_but_not_provenance_removal(ctx: Ctx) -> None:
    job, token = ctx.running()
    draft = _scene()
    draft["measurement"] = {"source": "sfm", "scale": "reference", "alignment": "connected",
                            "clock": "realtime", "referenceConfirmed": True}
    ctx.worker(job, "complete", token, {"sceneDraft": draft})
    scene = {**draft, "captureId": _CAPTURE}
    scene["walls"][0]["height"] = 2.5
    url = ctx.base().removesuffix("/captures") + "/scene"
    first = ctx.client.put(url, json=scene)
    assert first.status_code == 200, first.text
    old_revision = first.headers["ETag"]
    second = ctx.client.put(url, json=scene, headers={"If-Match": old_revision})
    assert second.status_code == 200
    assert ctx.client.post(f"{ctx.base()}/{_CAPTURE}/accept", headers={"If-Match": old_revision}).status_code == 412
    without_evidence = {**scene}
    without_evidence.pop("measurement")
    assert ctx.client.put(url, json=without_evidence).status_code == 422
    without_evidence.pop("captureId")
    assert ctx.client.put(url, json=without_evidence).status_code == 422
    assert ctx.client.put(url, json=scene, headers={"If-Match": old_revision}).status_code == 412
    assert ctx.client.post(f"{ctx.base()}/{_CAPTURE}/accept", headers={"If-Match": second.headers["ETag"]}).status_code == 200


def test_missing_historical_object_is_recoverable_not_falsely_verified(ctx: Ctx) -> None:
    ctx.queued()
    with ctx.session_factory.begin() as session:
        row = session.get(ListingCapture, _CAPTURE)
        assert row is not None
        row.package_manifest = None
    ctx.storage.objects.clear()
    assert ctx.claim(ctx.row().job_id).status_code == 409
    assert ctx.row().attempts == 0
    assert ctx.client.post(f"{ctx.base()}/{_CAPTURE}/complete").status_code == 409
    assert ctx.row().package_manifest is None


def test_verified_delivery_receipt_survives_legal_retention_deletion(ctx: Ctx) -> None:
    job, token = ctx.running()
    ctx.worker(job, "complete", token, {"sceneDraft": _scene()})
    ctx.now += timedelta(days=31)
    run_capture_retention_sweep(ctx.session_factory, ctx.storage, now=ctx.now)
    assert ctx.register().status_code == 200 # Status/receipt only; never a new PUT URL.
    assert ctx.register().json()["uploadUrl"] is None
    assert ctx.client.post(ctx.base(), json={"captureId": _CAPTURE, "sizeBytes": ctx.row().size_bytes,
                                           "sha256": ctx.row().package_sha256}).status_code == 200
    ctx.app.state.photo_storage = None
    ctx.app.state.reconstruction_queue = None
    assert ctx.register().status_code == 200
    response = ctx.client.post(f"{ctx.base()}/{_CAPTURE}/complete")
    assert response.status_code == 202 and response.json()["uploadVerified"] is True
    assert ctx.row().status == "completed"
    assert not ctx.storage.objects


def test_verification_io_runs_without_database_transaction(ctx: Ctx, monkeypatch: pytest.MonkeyPatch) -> None:
    from sqlalchemy import event
    from sqlalchemy.orm import Session
    active: set[Session] = set()
    def begin(session, transaction, connection):
        active.add(session)
    def end(session, transaction):
        active.discard(session)
    event.listen(Session, "after_begin", begin)
    event.listen(Session, "after_transaction_end", end)
    try:
        ctx.register()
        ctx.storage.objects[ctx.row().object_key] = _capture_zip()
        original_read, original_write = ctx.storage.read, ctx.storage.write
        def read(*args, **kwargs):
            assert not active, "Storage read holds a DB transaction"
            return original_read(*args, **kwargs)
        def write(*args, **kwargs):
            assert not active, "Storage write holds a DB transaction"
            return original_write(*args, **kwargs)
        monkeypatch.setattr(ctx.storage, "read", read)
        monkeypatch.setattr(ctx.storage, "write", write)
        assert ctx.client.post(f"{ctx.base()}/{_CAPTURE}/complete").status_code == 202
    finally:
        event.remove(Session, "after_begin", begin)
        event.remove(Session, "after_transaction_end", end)


def test_competing_completion_cleans_only_its_own_snapshot(ctx: Ctx, monkeypatch: pytest.MonkeyPatch) -> None:
    ctx.register()
    ctx.storage.objects[ctx.row().object_key] = _capture_zip()
    original = ctx.storage.read
    raced = False
    def read(*args, **kwargs):
        nonlocal raced
        data = original(*args, **kwargs)
        if not raced:
            raced = True
            assert ctx.client.post(f"{ctx.base()}/{_CAPTURE}/complete").status_code == 202
        return data
    monkeypatch.setattr(ctx.storage, "read", read)
    assert ctx.client.post(f"{ctx.base()}/{_CAPTURE}/complete").status_code == 202
    verified = [key for key in ctx.storage.objects if "/verified-" in key]
    assert verified == [ctx.row().object_key]
    assert len(ctx.queue.published) == 1


def test_retention_wins_during_verification_and_candidate_is_removed(ctx: Ctx, monkeypatch: pytest.MonkeyPatch) -> None:
    ctx.register()
    ctx.storage.objects[ctx.row().object_key] = _capture_zip()
    original = ctx.storage.read
    raced = False
    def read(*args, **kwargs):
        nonlocal raced
        data = original(*args, **kwargs)
        if not raced:
            raced = True
            ctx.now += timedelta(days=31)
            run_capture_retention_sweep(ctx.session_factory, ctx.storage, now=ctx.now)
        return data
    monkeypatch.setattr(ctx.storage, "read", read)
    assert ctx.client.post(f"{ctx.base()}/{_CAPTURE}/complete").status_code == 410
    assert ctx.row().frames_deleted_at is not None
    assert not any("/verified-" in key for key in ctx.storage.objects)


def test_legacy_wrong_checksum_cannot_poison_registration(ctx: Ctx) -> None:
    ctx.register()
    ctx.storage.objects[ctx.row().object_key] = _capture_zip()
    assert ctx.client.post(ctx.base(), json={"captureId": _CAPTURE, "sizeBytes": ctx.row().size_bytes,
                                           "sha256": "0" * 64}).status_code == 409
    assert ctx.row().package_sha256 is None


def test_explicit_manual_replacement_requires_exact_revision_and_no_sfm_claims(ctx: Ctx) -> None:
    job, token = ctx.running()
    ctx.worker(job, "complete", token, {"sceneDraft": _scene()})
    url = ctx.base().removesuffix("/captures") + "/scene"
    saved = ctx.client.put(url, json={**_scene(), "captureId": _CAPTURE})
    assert saved.status_code == 200
    etag = saved.headers["ETag"]
    manual = _scene()
    assert ctx.client.put(url, json=manual, headers={"If-Match": etag}).status_code == 422
    intent = {"X-Scene-Intent": "manual-replacement"}
    assert ctx.client.put(url, json=manual, headers=intent).status_code == 412
    assert ctx.client.put(url, json=manual, headers={**intent, "If-Match": "*"}).status_code == 412
    manual["walls"][0]["heightSource"] = "estimated"
    assert ctx.client.put(url, json=manual, headers={**intent, "If-Match": etag}).status_code == 422
    manual["walls"][0]["heightSource"] = "manual"
    replaced = ctx.client.put(url, json=manual, headers={**intent, "If-Match": etag})
    assert replaced.status_code == 200, replaced.text
    assert replaced.json().get("captureId") is None
    assert ctx.row().scene_draft is not None
    assert ctx.client.post(f"{ctx.base()}/{_CAPTURE}/accept").status_code == 409
    assert ctx.client.put(url, json=manual, headers={**intent, "If-Match": etag}).status_code == 412


@pytest.mark.skipif(os.environ.get("ROOMFORGE_LARGE_ZIP_QA") != "1", reason="opt-in 149 MiB validation/I/O check")
def test_large_zip_competing_completion_retains_one_snapshot(ctx: Ctx, monkeypatch: pytest.MonkeyPatch) -> None:
    psutil = pytest.importorskip("psutil")
    from sqlalchemy import event
    from sqlalchemy.orm import Session
    active: set[Session] = set()
    def begin(session, transaction, connection):
        active.add(session)
    def end(session, transaction):
        active.discard(session)
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_STORED) as archive:
        archive.writestr("manifest.json", json.dumps({"schemaVersion": 1, "captureId": _CAPTURE,
                                                     "listingId": "listing-one"}))
        with archive.open("padding.bin", "w") as padding:
            for _ in range(149):
                padding.write(b"x" * (1024 * 1024))
    data = buffer.getvalue()
    assert len(data) < 150 * 1024 * 1024
    ctx.register(size=len(data))
    ctx.storage.objects[ctx.row().object_key] = data
    event.listen(Session, "after_begin", begin)
    event.listen(Session, "after_transaction_end", end)
    process = psutil.Process()
    peak = [process.memory_info().rss]
    stopped = threading.Event()
    def sample():
        while not stopped.wait(.02):
            peak[0] = max(peak[0], process.memory_info().rss)
    sampler = threading.Thread(target=sample, daemon=True)
    sampler.start()
    started, cpu = time.perf_counter(), time.process_time()
    original = ctx.storage.read
    raced = False
    def read(*args, **kwargs):
        nonlocal raced
        assert not active, "Large validation holds DB transaction"
        result = original(*args, **kwargs)
        if not raced:
            raced = True
            # Second HTTP client completes while the first request is in its
            # unlocked I/O phase. SQLite supplies no PostgreSQL row-lock evidence.
            assert ctx.client.post(f"{ctx.base()}/{_CAPTURE}/complete").status_code == 202
        return result
    monkeypatch.setattr(ctx.storage, "read", read)
    try:
        assert ctx.client.post(f"{ctx.base()}/{_CAPTURE}/complete").status_code == 202
        assert [key for key in ctx.storage.objects if "/verified-" in key] == [ctx.row().object_key]
    finally:
        stopped.set()
        sampler.join()
        event.remove(Session, "after_begin", begin)
        event.remove(Session, "after_transaction_end", end)
    print("R06_METRICS", json.dumps({"zip_bytes": len(data), "wall_seconds": time.perf_counter() - started,
                                      "cpu_seconds": time.process_time() - cpu, "peak_rss_bytes_sampled": peak[0],
                                      "clients": 2, "schedule": "interleaved HTTP", "database": "SQLite disposable"}))
