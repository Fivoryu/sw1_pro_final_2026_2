"""F07 schema 2 (video + sensors) through the capture API (docs/api/f07-capture-package.md).

The backend treats the ZIP as opaque: it enforces the ZIP size limit, enqueues the same
message for every schema, and applies the same retention. ``worker3d`` dispatches on the
``manifest.json`` ``schemaVersion``. These tests pin that a schema 2 package travels the
unchanged flow and that schema 1 behavior did not move.
"""

from __future__ import annotations

import io
import json
import zipfile
from collections.abc import Iterator
from datetime import timedelta

import pytest
from test_reconstruction import _CAPTURE, _MAX_BYTES, _T0, Ctx, _scene  # pyright: ignore[reportMissingImports]

from app.modules.reconstruction.service import run_capture_retention_sweep


@pytest.fixture
def ctx() -> Iterator[Ctx]:
    opened = Ctx()
    yield opened
    opened.close()


def _package(schema_version: int) -> bytes:
    manifest = {"schemaVersion": schema_version, "captureId": _CAPTURE, "listingId": "listing-one"}
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr("manifest.json", json.dumps(manifest))
        if schema_version == 2:
            archive.writestr("video.mp4", b"\x00" * 64)
            archive.writestr("frames.jsonl", '{"i":0,"t":1}\n')
            archive.writestr("sensors.jsonl", '{"t":1,"type":"gyro","x":0,"y":0,"z":0}\n')
    return buffer.getvalue()


def _upload_and_complete(ctx: Ctx, package: bytes) -> str:
    assert ctx.register(size=len(package)).status_code == 201
    ctx.storage.objects[ctx.row().object_key] = package
    assert ctx.client.post(f"{ctx.base()}/{_CAPTURE}/complete").status_code == 202
    return ctx.row().job_id


@pytest.mark.parametrize("schema_version", [1, 2])
def test_both_schemas_use_the_same_flow_and_queue_message(ctx: Ctx, schema_version: int) -> None:
    package = _package(schema_version)

    job_id = _upload_and_complete(ctx, package)
    claimed = ctx.claim(job_id)

    assert [(m.version, m.job_id, m.attempt) for m in ctx.queue.published] == [(1, job_id, 1)]
    assert claimed.status_code == 200 and claimed.json()["status"] == "running"
    assert ctx.storage.objects[ctx.row().object_key] == package


def test_schema_2_package_limit_is_measured_on_the_zip(ctx: Ctx) -> None:
    other = "22222222-2222-4222-8222-222222222222"

    assert ctx.register(capture_id=other, size=_MAX_BYTES).status_code == 201
    assert ctx.register(size=_MAX_BYTES + 1).status_code == 422


def test_schema_2_retention_runs_30_days_from_upload(ctx: Ctx) -> None:
    _upload_and_complete(ctx, _package(2))
    key = ctx.row().object_key

    early = run_capture_retention_sweep(
        ctx.session_factory, ctx.storage, now=_T0 + timedelta(days=29, hours=23)
    )
    late = run_capture_retention_sweep(
        ctx.session_factory, ctx.storage, now=_T0 + timedelta(days=30, seconds=1)
    )

    assert early == 0 and late == 1 and key not in ctx.storage.objects


def test_schema_2_package_is_deleted_on_accept_keeping_the_draft(ctx: Ctx) -> None:
    job_id = _upload_and_complete(ctx, _package(2))
    token = ctx.claim(job_id).json()["claim_token"]
    scene = _scene()
    scene["measurement"] = {"source": "sfm", "referenceConfirmed": True, "scale": "reference", "alignment": "connected", "clock": "realtime"}
    done = ctx.worker(job_id, "complete", token, {"sceneDraft": scene, "warnings": []})
    assert done.status_code == 200, done.text
    key = ctx.row().object_key
    saved = ctx.client.put(ctx.base().removesuffix("/captures") + "/scene", json={**scene, "captureId": _CAPTURE})
    assert saved.status_code == 200, saved.text
    assert ctx.client.post(f"{ctx.base()}/{_CAPTURE}/accept").status_code == 200

    deleted = run_capture_retention_sweep(ctx.session_factory, ctx.storage, now=_T0)

    assert deleted == 1 and key not in ctx.storage.objects
    assert ctx.row().scene_draft is not None
