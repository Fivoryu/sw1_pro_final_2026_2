"""HTTP contract tests for the F07.7 capture package flow (docs/api/f07-capture-package.md)."""

from __future__ import annotations

import base64
from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from typing import Any

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.db.base import Base
from app.main import create_app
from app.modules.catalog.models import Listing
from app.modules.catalog.photo_storage import InMemoryPhotoStorage, PhotoStorageUnavailableError
from app.modules.identity.models import Agency
from app.modules.identity.session import get_active_staff
from app.modules.reconstruction.job_queue import InMemoryReconstructionQueue
from app.modules.reconstruction.models import ListingCapture
from app.modules.reconstruction.service import (
    run_capture_retention_sweep,
    run_reconstruction_recovery_sweep,
)

_T0 = datetime(2026, 10, 21, 12, 0, tzinfo=UTC)
_TOKEN = "recon-worker-token"
_CAPTURE = "11111111-1111-4111-8111-111111111111"
_MAX_BYTES = 150 * 1024 * 1024
_CLAIM_HEADER = "X-Reconstruction-Claim-Token"


def _settings(**changes: object) -> Settings:
    values: dict[str, object] = {
        "database_url": "sqlite+pysqlite:///:memory:",
        "jwt_secret": "reconstruction-test-secret-that-is-long-enough",
        "totp_encryption_key": base64.urlsafe_b64encode(b"0" * 32).decode(),
        "web_origin": "http://localhost",
        "reconstruction_worker_token": _TOKEN,
    }
    values.update(changes)
    return Settings(**values)  # type: ignore[arg-type]


def _scene() -> dict[str, Any]:
    walls = [
        ("n", (0, 0), (4, 0)),
        ("e", (4, 0), (4, 3)),
        ("s", (4, 3), (0, 3)),
        ("w", (0, 3), (0, 0)),
    ]
    return {
        "version": "2.0",
        "unit": "meters",
        "walls": [
            {
                "id": f"wall-{name}",
                "start": {"x": a[0], "z": a[1]},
                "end": {"x": b[0], "z": b[1]},
                "height": 2.4,
                "thickness": 0.15,
            }
            for name, a, b in walls
        ],
        "openings": [],
        "rooms": [{"id": "room-1", "wallIds": [f"wall-{n}" for n, _, _ in walls]}],
        "objects": [
            {
                "id": "vol-1",
                "type": "placeholder",
                "position": {"x": 1, "y": 0, "z": 1},
                "dimensions": {"width": 0.5, "height": 0.5, "depth": 0.5},
                "color": "gray",
                "source": "depth",
                "confidence": 0.7,
            }
        ],
    }


def _utc(value: datetime | None) -> datetime | None:
    assert value is not None
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value


def _auth(token: str = _TOKEN) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


class Ctx:
    def __init__(self, **settings_changes: object) -> None:
        self.now = _T0
        self.engine = create_engine(
            "sqlite+pysqlite:///:memory:",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        self.session_factory: sessionmaker[Session] = sessionmaker(
            bind=self.engine, autoflush=False, expire_on_commit=False
        )
        Base.metadata.create_all(self.engine)
        self.storage = InMemoryPhotoStorage("https://storage.example.test")
        self.queue = InMemoryReconstructionQueue()
        self.app = create_app(
            settings=_settings(**settings_changes),
            session_factory=self.session_factory,
            clock=lambda: self.now,
            photo_storage=self.storage,
            reconstruction_queue=self.queue,
        )
        self.set_staff(tenant="agency-one")
        self.client = TestClient(self.app)
        for agency, listing in (("agency-one", "listing-one"), ("agency-two", "listing-two")):
            with self.session_factory.begin() as session:
                if session.get(Agency, agency) is None:
                    session.add(Agency(id=agency))
                    session.flush()
                session.add(
                    Listing(
                        id=listing,
                        agency_id=agency,
                        approval_status="draft",
                        is_published=False,
                        operation="sale",
                        base_price=Decimal("1000.00"),
                        offer_version=1,
                        city="Cordoba",
                        zone="Centro",
                        bedrooms=1,
                        bathrooms=1,
                    )
                )

    def set_staff(self, *, tenant: str, role: str = "agent") -> None:
        self.app.dependency_overrides[get_active_staff] = lambda: {
            "id": "actor",
            "email": "actor@example.test",
            "role": role,
            "tenant_id": tenant,
        }

    def close(self) -> None:
        self.client.close()
        self.engine.dispose()

    def base(self, agency: str = "agency-one", listing: str = "listing-one") -> str:
        return f"/api/v1/staff/agencies/{agency}/listings/{listing}/captures"

    def register(self, capture_id: str = _CAPTURE, size: int = 1000, **where: str) -> Any:
        return self.client.post(
            self.base(**where), json={"captureId": capture_id, "sizeBytes": size}
        )

    def row(self, capture_id: str = _CAPTURE) -> ListingCapture:
        with self.session_factory() as session:
            row = session.get(ListingCapture, capture_id)
            assert row is not None
            return row

    def queued(self) -> str:
        """Register, upload and complete; return the job id."""
        assert self.register().status_code == 201
        self.storage.objects[self.row().object_key] = b"zip-bytes"
        done = self.client.post(f"{self.base()}/{_CAPTURE}/complete")
        assert done.status_code == 202, done.text
        return self.row().job_id

    def claim(self, job_id: str) -> Any:
        return self.client.post(
            f"/api/v1/reconstruction/jobs/{job_id}/claim", headers=_auth()
        )

    def running(self) -> tuple[str, str]:
        job_id = self.queued()
        claimed = self.claim(job_id)
        assert claimed.status_code == 200, claimed.text
        return job_id, claimed.json()["claim_token"]

    def worker(self, job_id: str, action: str, token: str | None, body: dict[str, Any]) -> Any:
        headers = _auth()
        if token is not None:
            headers[_CLAIM_HEADER] = token
        return self.client.post(
            f"/api/v1/reconstruction/jobs/{job_id}/{action}", headers=headers, json=body
        )

    def status(self) -> dict[str, Any]:
        response = self.client.get(f"{self.base()}/{_CAPTURE}")
        assert response.status_code == 200, response.text
        return response.json()


@pytest.fixture
def ctx() -> Iterator[Ctx]:
    opened = Ctx()
    yield opened
    opened.close()


# --- staff: register -------------------------------------------------------------


def test_register_creates_capture_with_signed_upload_url(ctx: Ctx) -> None:
    response = ctx.register(size=2048)

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["captureId"] == _CAPTURE
    assert body["status"] == "awaiting_upload"
    assert "agencies/agency-one/listings/listing-one/captures/" in body["uploadUrl"]
    assert body["expiresAt"].startswith("2026-10-21T12:15:00")
    row = ctx.row()
    assert (row.status, row.size_bytes, row.agency_id, row.listing_id) == (
        "awaiting_upload",
        2048,
        "agency-one",
        "listing-one",
    )


def test_register_is_idempotent_by_capture_id(ctx: Ctx) -> None:
    first = ctx.register()
    again = ctx.register()

    assert first.status_code == 201 and again.status_code == 200, again.text
    assert again.json()["captureId"] == first.json()["captureId"]
    assert again.json()["status"] == "awaiting_upload"
    with ctx.session_factory() as session:
        assert session.query(ListingCapture).count() == 1


def test_register_rejects_package_over_150_mb_and_accepts_exactly_150_mb(ctx: Ctx) -> None:
    other = "22222222-2222-4222-8222-222222222222"
    too_big = ctx.register(size=_MAX_BYTES + 1)
    exact = ctx.register(capture_id=other, size=_MAX_BYTES)

    assert too_big.status_code == 422, too_big.text
    assert exact.status_code == 201, exact.text
    with ctx.session_factory() as session:
        assert [c.id for c in session.query(ListingCapture).all()] == [other]


def test_register_rejects_capture_id_already_used_by_another_listing(ctx: Ctx) -> None:
    assert ctx.register().status_code == 201
    ctx.set_staff(tenant="agency-two")

    clash = ctx.register(agency="agency-two", listing="listing-two")

    assert clash.status_code == 409, clash.text


# --- staff: complete / get / accept ----------------------------------------------


def test_complete_enqueues_once_and_is_idempotent(ctx: Ctx) -> None:
    ctx.register()
    url = f"{ctx.base()}/{_CAPTURE}/complete"

    first = ctx.client.post(url)
    again = ctx.client.post(url)

    assert first.status_code == 202 and again.status_code == 202, again.text
    assert first.json() == {"captureId": _CAPTURE, "status": "queued"}
    assert again.json() == {"captureId": _CAPTURE, "status": "queued"}
    assert [m.job_id for m in ctx.queue.published] == [ctx.row().job_id]
    assert _utc(ctx.row().uploaded_at) == _T0


def test_complete_with_unavailable_queue_keeps_capture_recoverable(ctx: Ctx) -> None:
    ctx.register()
    ctx.queue.fail_on_publish = True
    url = f"{ctx.base()}/{_CAPTURE}/complete"

    failed = ctx.client.post(url)
    ctx.queue.fail_on_publish = False
    retried = ctx.client.post(url)

    assert failed.status_code == 503, failed.text
    assert ctx.row().status == "queued"
    assert retried.status_code == 202, retried.text
    assert len(ctx.queue.published) == 1


def test_complete_unknown_capture_is_404(ctx: Ctx) -> None:
    response = ctx.client.post(f"{ctx.base()}/{_CAPTURE}/complete")

    assert response.status_code == 404, response.text


def test_get_reports_state_through_the_whole_lifecycle(ctx: Ctx) -> None:
    ctx.register()
    assert ctx.status()["status"] == "awaiting_upload"
    ctx.storage.objects[ctx.row().object_key] = b"zip-bytes"
    assert ctx.client.post(f"{ctx.base()}/{_CAPTURE}/complete").status_code == 202
    job_id = ctx.row().job_id
    assert ctx.status()["status"] == "queued"
    token = ctx.claim(job_id).json()["claim_token"]
    assert ctx.status()["status"] == "processing"
    done = ctx.worker(job_id, "complete", token, {"sceneDraft": _scene(), "warnings": ["w1"]})
    assert done.status_code == 200, done.text

    body = ctx.status()

    assert body["status"] == "completed"
    assert body["sceneDraft"]["version"] == "2.0"
    assert body["warnings"] == ["w1"]
    assert body["failureReason"] is None


def test_accept_only_from_completed_and_idempotent(ctx: Ctx) -> None:
    job_id = ctx.queued()
    url = f"{ctx.base()}/{_CAPTURE}/accept"
    early = ctx.client.post(url)
    token = ctx.claim(job_id).json()["claim_token"]
    ctx.worker(job_id, "complete", token, {"sceneDraft": _scene(), "warnings": []})

    first = ctx.client.post(url)
    again = ctx.client.post(url)

    assert early.status_code == 409, early.text
    assert first.status_code == 200 and again.status_code == 200, again.text
    assert first.json()["status"] == "accepted" == again.json()["status"]
    row = ctx.row()
    assert _utc(row.accepted_at) == _T0 and _utc(row.frames_delete_after) == _T0


def test_staff_routes_enforce_agency_isolation(ctx: Ctx) -> None:
    ctx.queued()
    ctx.set_staff(tenant="agency-two")
    cap = f"{ctx.base()}/{_CAPTURE}"

    foreign_agency = [
        ctx.client.post(ctx.base(), json={"captureId": "x", "sizeBytes": 1}),
        ctx.client.post(f"{cap}/complete"),
        ctx.client.get(cap),
        ctx.client.post(f"{cap}/accept"),
    ]
    other_listing = ctx.client.get(f"{ctx.base('agency-two', 'listing-one')}/{_CAPTURE}")
    unknown_listing = ctx.register(agency="agency-two", listing="listing-one")

    assert [r.status_code for r in foreign_agency] == [403, 403, 403, 403]
    assert other_listing.status_code == 404
    assert unknown_listing.status_code == 404
    assert ctx.row().status == "queued"


def test_list_returns_the_listing_captures_newest_first(ctx: Ctx) -> None:
    assert ctx.client.get(ctx.base()).json() == {"captures": []}
    assert ctx.register("capture-old").status_code == 201
    ctx.now = ctx.now + timedelta(minutes=5)
    assert ctx.register("capture-new").status_code == 201
    assert ctx.register("capture-elsewhere", listing="listing-two", agency="agency-two").status_code == 403

    listed = ctx.client.get(ctx.base())

    assert listed.status_code == 200
    assert [c["captureId"] for c in listed.json()["captures"]] == ["capture-new", "capture-old"]
    assert listed.json()["captures"][0] == ctx.client.get(f"{ctx.base()}/capture-new").json()


def test_list_enforces_agency_isolation(ctx: Ctx) -> None:
    ctx.queued()
    ctx.set_staff(tenant="agency-two")

    assert ctx.client.get(ctx.base()).status_code == 403
    assert ctx.client.get(ctx.base("agency-two", "listing-one")).status_code == 404


# --- worker ------------------------------------------------------------------------


def test_worker_fails_closed_without_configured_token() -> None:
    bare = Ctx(reconstruction_worker_token=None)
    try:
        response = bare.client.post("/api/v1/reconstruction/jobs/j/claim")
    finally:
        bare.close()

    assert response.status_code == 503, response.text


def test_worker_rejects_wrong_token_without_claiming(ctx: Ctx) -> None:
    job_id = ctx.queued()

    response = ctx.client.post(
        f"/api/v1/reconstruction/jobs/{job_id}/claim", headers=_auth("nope")
    )

    assert response.status_code == 401, response.text
    assert ctx.row().status == "queued"


def test_claim_leases_the_job_and_signs_the_download(ctx: Ctx) -> None:
    job_id = ctx.queued()

    first = ctx.claim(job_id)
    second = ctx.claim(job_id)

    assert first.status_code == 200, first.text
    body = first.json()
    assert body["job_id"] == job_id and body["status"] == "running"
    assert body["claim_token"]
    assert body["download_url"].startswith("https://storage.example.test/")
    assert second.status_code == 200 and second.json()["claim_token"] is None
    assert second.json()["status"] == "running"
    row = ctx.row()
    assert row.status == "processing" and row.lease_expires_at is not None
    assert row.lease_expires_at.replace(tzinfo=UTC) == _T0 + timedelta(seconds=300)


def test_claim_unknown_job_is_404(ctx: Ctx) -> None:
    assert ctx.claim("missing").status_code == 404


def test_complete_requires_the_current_claim_token_and_is_idempotent(ctx: Ctx) -> None:
    job_id, token = ctx.running()
    payload = {"sceneDraft": _scene(), "warnings": []}

    wrong = ctx.worker(job_id, "complete", "stale", payload)
    missing = ctx.worker(job_id, "complete", None, payload)
    ok = ctx.worker(job_id, "complete", token, payload)
    again = ctx.worker(job_id, "complete", token, payload)

    assert wrong.status_code == 409, wrong.text
    assert missing.status_code == 422, missing.text
    assert ok.status_code == 200 and again.status_code == 200
    assert ok.json()["status"] == "completed"
    assert ctx.row().scene_draft is not None and ctx.row().lease_expires_at is None


def test_complete_rejects_invalid_scene_draft_with_scene_invalid_shape(ctx: Ctx) -> None:
    job_id, token = ctx.running()
    bad = _scene()
    bad["openings"] = [
        {
            "id": "d1",
            "wallId": "missing",
            "position": 0.5,
            "width": 0.9,
            "height": 2.1,
            "type": "door",
        }
    ]
    unknown_field = _scene()
    unknown_field["bogus"] = 1

    integrity = ctx.worker(job_id, "complete", token, {"sceneDraft": bad, "warnings": []})
    strict = ctx.worker(job_id, "complete", token, {"sceneDraft": unknown_field, "warnings": []})

    for response in (integrity, strict):
        assert response.status_code == 422, response.text
        assert response.json()["code"] == "scene_invalid" and response.json()["detail"]
    assert "openings[0].wallId" in integrity.json()["detail"]
    assert ctx.row().status == "processing" and ctx.row().scene_draft is None


def test_fail_retryable_requeues_until_attempts_are_exhausted(ctx: Ctx) -> None:
    job_id, token = ctx.running()

    first = ctx.worker(job_id, "fail", token, {"reason": "oom", "retryable": True})

    assert first.status_code == 200 and first.json()["status"] == "queued"
    assert ctx.row().attempts == 1 and ctx.row().claim_token is None
    assert len(ctx.queue.published) == 2
    token = ctx.claim(job_id).json()["claim_token"]
    ctx.worker(job_id, "fail", token, {"reason": "oom", "retryable": True})
    token = ctx.claim(job_id).json()["claim_token"]
    last = ctx.worker(job_id, "fail", token, {"reason": "oom again", "retryable": True})
    assert last.json()["status"] == "failed"
    assert ctx.status()["failureReason"] == "oom again"
    assert len(ctx.queue.published) == 3


def test_fail_non_retryable_ends_failed_without_retry(ctx: Ctx) -> None:
    job_id, token = ctx.running()

    response = ctx.worker(job_id, "fail", token, {"reason": "invalid package", "retryable": False})
    stale = ctx.worker(job_id, "fail", "other", {"reason": "x", "retryable": True})

    assert response.status_code == 200 and response.json()["status"] == "failed"
    assert stale.status_code == 409
    assert len(ctx.queue.published) == 1
    body = ctx.status()
    assert body["status"] == "failed" and body["failureReason"] == "invalid package"


# --- recovery sweep ---------------------------------------------------------------


def test_lease_sweep_requeues_expired_claims_and_fences_the_old_token(ctx: Ctx) -> None:
    job_id, old_token = ctx.running()

    untouched = run_reconstruction_recovery_sweep(
        ctx.session_factory, ctx.queue, now=_T0 + timedelta(seconds=10), max_attempts=3
    )
    recovered = run_reconstruction_recovery_sweep(
        ctx.session_factory, ctx.queue, now=_T0 + timedelta(hours=1), max_attempts=3
    )

    assert untouched == 0 and recovered == 1
    assert ctx.row().status == "queued" and ctx.row().attempts == 1
    assert len(ctx.queue.published) == 2
    stale = ctx.worker(job_id, "complete", old_token, {"sceneDraft": _scene(), "warnings": []})
    assert stale.status_code == 409


def test_lease_sweep_fails_the_capture_when_attempts_run_out(ctx: Ctx) -> None:
    job_id = ctx.queued()
    for hour in range(1, 4):
        ctx.claim(job_id)
        run_reconstruction_recovery_sweep(
            ctx.session_factory, ctx.queue, now=_T0 + timedelta(hours=hour), max_attempts=3
        )

    assert ctx.row().status == "failed"
    assert "lease expired" in (ctx.row().failure_reason or "")


# --- retention sweep --------------------------------------------------------------


def test_retention_deletes_frames_after_accept_but_keeps_draft(ctx: Ctx) -> None:
    job_id, token = ctx.running()
    ctx.worker(job_id, "complete", token, {"sceneDraft": _scene(), "warnings": ["w"]})
    key = ctx.row().object_key
    before = run_capture_retention_sweep(ctx.session_factory, ctx.storage, now=_T0)
    assert before == 0 and key in ctx.storage.objects
    ctx.client.post(f"{ctx.base()}/{_CAPTURE}/accept")

    deleted = run_capture_retention_sweep(ctx.session_factory, ctx.storage, now=_T0)
    again = run_capture_retention_sweep(ctx.session_factory, ctx.storage, now=_T0)

    assert deleted == 1 and again == 0
    assert key not in ctx.storage.objects
    row = ctx.row()
    assert _utc(row.frames_deleted_at) == _T0 and row.scene_draft is not None
    body = ctx.status()
    assert body["status"] == "accepted" and body["sceneDraft"] is not None


def test_retention_deletes_unaccepted_frames_only_after_30_days(ctx: Ctx) -> None:
    ctx.queued()
    key = ctx.row().object_key

    early = run_capture_retention_sweep(
        ctx.session_factory, ctx.storage, now=_T0 + timedelta(days=29, hours=23)
    )
    assert early == 0 and key in ctx.storage.objects
    late = run_capture_retention_sweep(
        ctx.session_factory, ctx.storage, now=_T0 + timedelta(days=30, seconds=1)
    )

    assert late == 1 and key not in ctx.storage.objects
    assert ctx.row().frames_deleted_at is not None


def test_retention_keeps_the_record_for_retry_when_storage_deletion_fails(ctx: Ctx) -> None:
    ctx.queued()
    key = ctx.row().object_key

    class FailingStorage(InMemoryPhotoStorage):
        def delete(self, key: str) -> None:
            raise PhotoStorageUnavailableError

    due = _T0 + timedelta(days=31)
    failing = FailingStorage()
    failing.objects = ctx.storage.objects

    first = run_capture_retention_sweep(ctx.session_factory, failing, now=due)
    assert first == 0 and ctx.row().frames_deleted_at is None
    second = run_capture_retention_sweep(ctx.session_factory, ctx.storage, now=due)

    assert second == 1 and key not in ctx.storage.objects
