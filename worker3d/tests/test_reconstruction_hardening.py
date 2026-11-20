from __future__ import annotations

import hashlib
import json
import os
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import reconstruct
import reconstruction_worker as rw
from test_reconstruction_worker import FakeHttpClient, FakeQueue, FakeResponse


def worker(http, queue, **kwargs):
    return rw.ReconstructionJobWorker(api_base_url="http://api", service_token="service-token",
                                      http_client=http, queue=queue, **kwargs)


def test_download_checksum_and_manifest_identity_are_enforced() -> None:
    for extra in ({"package_sha256": "0" * 64}, {"capture_id": "wrong-capture"}, {"listing_id": "wrong-listing"}):
        http, queue = FakeHttpClient(), FakeQueue()
        http.claim._body.update(extra)
        worker(http, queue).run_once()
        assert http.posts[-1][0].endswith("/fail")
        assert http.posts[-1][2]["retryable"] is False
        assert not any(url.endswith("/complete") for url, _, _ in http.posts)


class HeartbeatHttp(FakeHttpClient):
    renewals = 0
    reject = False
    def post(self, url, *, headers, json=None):
        if url.endswith("/renew"):
            self.renewals += 1
            return FakeResponse(status_code=409 if self.reject else 200)
        return super().post(url, headers=headers, json=json)


def test_a_long_running_reconstruction_renews_ownership() -> None:
    http, queue = HeartbeatHttp(), FakeQueue()
    http.claim._body["lease_seconds"] = .15
    def slow(path):
        time.sleep(.18)
        return reconstruct.reconstruct(path)
    worker(http, queue, reconstructor=slow).run_once()
    assert http.renewals >= 2
    assert queue.deleted


def test_a_lost_lease_never_submits_the_result() -> None:
    http, queue = HeartbeatHttp(), FakeQueue()
    http.reject = True
    http.claim._body["lease_seconds"] = .15
    def slow(path):
        time.sleep(.12)
        return reconstruct.reconstruct(path)
    with pytest.raises(RuntimeError, match="ownership was lost"):
        worker(http, queue, reconstructor=slow).run_once()
    assert not queue.deleted
    assert not any(url.endswith("/complete") for url, _, _ in http.posts)


def test_ambiguous_completion_reuses_persisted_result_without_reconstructing(tmp_path: Path) -> None:
    class Unavailable(FakeHttpClient):
        def post(self, url, *, headers, json=None):
            if url.endswith("/complete"):
                return FakeResponse(status_code=503)
            return super().post(url, headers=headers, json=json)
    http, queue = Unavailable(), FakeQueue()
    http.claim._body["package_sha256"] = hashlib.sha256(http.package).hexdigest()
    calls = []
    def reconstruct_once(path):
        calls.append(path)
        return reconstruct.reconstruct(path)
    with pytest.raises(RuntimeError):
        worker(http, queue, result_cache=tmp_path, reconstructor=reconstruct_once).run_once()
    assert len(calls) == 1 and list(tmp_path.glob("*.json"))
    recovered = FakeHttpClient(claim=http.claim, package=http.package)
    worker(recovered, FakeQueue(), result_cache=tmp_path, reconstructor=reconstruct_once).run_once()
    assert len(calls) == 1 and recovered.downloads == []
    assert not list(tmp_path.glob("*.json"))


def test_consumer_bootstraps_its_local_queue_before_polling(monkeypatch: pytest.MonkeyPatch) -> None:
    boto3 = pytest.importorskip("boto3")
    httpx = pytest.importorskip("httpx")
    created = []
    class StopLoop(BaseException):
        pass
    class LocalSqs:
        def create_queue(self, **kwargs):
            created.append(kwargs["QueueName"])
    class ClientContext:
        def __enter__(self):
            return FakeHttpClient()
        def __exit__(self, *args):
            return False
    class Consumer:
        def __init__(self, **kwargs):
            assert created == ["bootstrap-test"]
        def run_once(self):
            raise StopLoop
    monkeypatch.setenv("SQS_ENDPOINT_URL", "http://floci:4566")
    monkeypatch.setenv("RECONSTRUCTION_WORKER_TOKEN", "test-token")
    monkeypatch.setenv("RECONSTRUCTION_QUEUE_NAME", "bootstrap-test")
    monkeypatch.setattr(boto3, "client", lambda *args, **kwargs: LocalSqs())
    monkeypatch.setattr(httpx, "Client", lambda **kwargs: ClientContext())
    monkeypatch.setattr(rw, "SqsMessageQueue", lambda **kwargs: FakeQueue())
    monkeypatch.setattr(rw, "ReconstructionJobWorker", Consumer)
    with pytest.raises(StopLoop):
        rw.main()


def test_cache_expires_private_results_and_legacy_temporary_files(tmp_path: Path) -> None:
    old = tmp_path / ("a" * 64 + ".json")
    payload = {"sceneDraft": {"version": "2.0"}, "warnings": []}
    old.write_text(json.dumps(payload))
    os.utime(old, (time.time() - 100, time.time() - 100))
    temporary = tmp_path / ("b" * 64 + ".claim-token.tmp")
    temporary.write_text("private partial result")
    os.utime(temporary, (time.time() - 100, time.time() - 100))
    current = tmp_path / ("c" * 64 + ".json")
    current.write_text(json.dumps({"expires_at": time.time() + 10, "payload": payload}))
    unrelated = tmp_path / "operator.txt"
    unrelated.write_text("keep")
    consumer = worker(FakeHttpClient(), FakeQueue(count=0), result_cache=tmp_path, cache_retention_seconds=60)
    assert not consumer.run_once()
    assert not old.exists() and not temporary.exists()
    assert current.exists() and unrelated.exists()


def test_cache_honors_server_retention_and_is_removed_for_terminal_job(tmp_path: Path) -> None:
    from datetime import UTC, datetime
    class Unavailable(FakeHttpClient):
        def post(self, url, *, headers, json=None):
            if url.endswith("/complete"):
                return FakeResponse(status_code=503)
            return super().post(url, headers=headers, json=json)
    http = Unavailable()
    http.claim._body["package_sha256"] = hashlib.sha256(http.package).hexdigest()
    deadline = time.time() + 100
    http.claim._body["cache_delete_after"] = datetime.fromtimestamp(deadline, UTC).isoformat()
    with pytest.raises(RuntimeError):
        worker(http, FakeQueue(), result_cache=tmp_path).run_once()
    path = next(tmp_path.glob("*.json"))
    saved = json.loads(path.read_text())
    # Compare to the actual wire deadline (ISO datetime has microsecond precision),
    # not the pre-serialization float whose sub-microsecond bits are not transmitted.
    assert saved["expires_at"] <= datetime.fromisoformat(http.claim._body["cache_delete_after"]).timestamp()
    assert "sceneDraft" in saved["payload"]
    http.claim._body.update(status="completed", download_url=None)
    terminal = FakeHttpClient(claim=http.claim)
    worker(terminal, FakeQueue(), result_cache=tmp_path).run_once()
    assert not path.exists() and not terminal.downloads


def test_cache_capacity_applies_backpressure_without_evicting_pending_result(tmp_path: Path) -> None:
    path = tmp_path / ("d" * 64 + ".json")
    path.write_text(json.dumps({"sceneDraft": {"version": "2.0"}, "warnings": []}))
    http, queue = FakeHttpClient(), FakeQueue()
    assert not worker(http, queue, result_cache=tmp_path, cache_max_bytes=1).run_once()
    assert path.exists() and not http.posts and len(queue.deliveries) == 1
