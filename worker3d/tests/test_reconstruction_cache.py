"""A-01: invalid derived caches must not trap retained capture jobs."""

from __future__ import annotations

import hashlib
import json
import os
import threading
import time
from pathlib import Path

import pytest
from test_reconstruction_hardening import worker
from test_reconstruction_worker import FakeHttpClient, FakeQueue, FakeResponse


def cached_worker(tmp_path: Path, **kwargs):
    http, queue = FakeHttpClient(**kwargs), FakeQueue()
    http.claim._body["package_sha256"] = hashlib.sha256(http.package).hexdigest()
    consumer = worker(http, queue, result_cache=tmp_path)
    return consumer, http, queue, consumer._cache_path(http.claim._body)


@pytest.mark.parametrize("content", [
    b"{unreadable", b"\xff", b"[]", b"null", b"{}",
    b'{"payload": []}', b'{"sceneDraft": [], "warnings": []}',
    b'{"sceneDraft": {"version": "2.0"}, "warnings": "invalid"}',
    b'{"expires_at": null, "payload": {}}',
    b'{"expires_at": NaN, "payload": {}}',
    b'{"expires_at": ' + b'9' * 400 + b', "payload": {}}',
    b'[' * 1100 + b']' * 1100,
])
def test_corrupt_cache_reconstructs_verified_source(tmp_path: Path, content: bytes) -> None:
    consumer, http, queue, path = cached_worker(tmp_path)
    source = tmp_path / "source.zip"
    source.write_bytes(http.package)
    path.write_bytes(content)

    assert consumer.run_once()

    assert len(http.downloads) == 1
    assert http.posts[-1][0].endswith("/complete")
    body = http.posts[-1][2]
    assert body is not None and body["sceneDraft"]["version"] == "2.0"
    assert len(queue.deleted) == 1 and not path.exists()
    assert source.read_bytes() == http.package


def test_unreadable_cache_is_discarded(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    consumer, http, queue, path = cached_worker(tmp_path)
    path.write_text("private", encoding="utf-8")
    original = Path.read_text

    def read(current: Path, *args, **kwargs):
        if current == path:
            raise PermissionError("private cache details")
        return original(current, *args, **kwargs)

    monkeypatch.setattr(Path, "read_text", read)
    assert consumer.run_once()
    assert http.downloads and len(queue.deleted) == 1 and not path.exists()


def test_corrupt_cache_with_unavailable_source_reports_retryable_failure(tmp_path: Path) -> None:
    consumer, http, queue, path = cached_worker(tmp_path, download_status=503)
    path.write_text("{bad", encoding="utf-8")
    assert consumer.run_once()
    assert http.posts[-1][0].endswith("/fail")
    body = http.posts[-1][2]
    assert body is not None and body["retryable"] is True
    assert len(queue.deleted) == 1 and not path.exists()


def test_cache_corrupted_after_sweep_still_recovers(tmp_path: Path) -> None:
    consumer, http, queue, path = cached_worker(tmp_path)
    assert consumer._sweep_cache() == 0
    path.write_text("{bad", encoding="utf-8")
    consumer._execute_claimed("http://api/job", queue.deliveries[0], http.claim._body,
                              "claim-token-one", threading.Event())
    assert http.downloads and http.posts[-1][0].endswith("/complete")
    assert len(queue.deleted) == 1 and not path.exists()


def test_cache_cleanup_failure_reports_recoverable_error_without_private_details(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    consumer, http, queue, path = cached_worker(tmp_path)
    path.write_text("{bad", encoding="utf-8")
    original = Path.unlink

    def unlink(current: Path, *args, **kwargs):
        if current == path:
            raise PermissionError("private filesystem details")
        return original(current, *args, **kwargs)

    monkeypatch.setattr(Path, "unlink", unlink)
    assert consumer.run_once()
    body = http.posts[-1][2]
    assert http.posts[-1][0].endswith("/fail")
    assert body is not None and body["retryable"] is True
    assert "private" not in body["reason"]
    assert len(queue.deleted) == 1 and not http.downloads


def test_corrupt_cache_does_not_bypass_source_checksum(tmp_path: Path) -> None:
    consumer, http, queue, _ = cached_worker(tmp_path)
    http.claim._body["package_sha256"] = "0" * 64
    path = consumer._cache_path(http.claim._body)
    path.write_text("{bad", encoding="utf-8")
    assert consumer.run_once()
    body = http.posts[-1][2]
    assert http.posts[-1][0].endswith("/fail")
    assert body is not None and body["retryable"] is False
    assert len(queue.deleted) == 1 and not path.exists()


@pytest.mark.parametrize("legacy", [False, True])
def test_valid_cache_replays_exact_payload_without_source(tmp_path: Path, legacy: bool) -> None:
    consumer, http, queue, path = cached_worker(tmp_path, download_status=503)
    payload = {"sceneDraft": {"version": "2.0"}, "warnings": ["retain provenance"]}
    saved = payload if legacy else {"expires_at": time.time() + 60, "payload": payload}
    path.write_text(json.dumps(saved), encoding="utf-8")
    assert consumer.run_once()
    assert not http.downloads and http.posts[-1][2] == payload
    assert len(queue.deleted) == 1 and not path.exists()


@pytest.mark.parametrize("status", [422, 503, 409])
def test_only_definitively_incompatible_cache_is_rebuilt(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, status: int,
) -> None:
    consumer, http, queue, path = cached_worker(tmp_path)
    payload = {"sceneDraft": {"version": "2.0"}, "warnings": []}
    encoded = json.dumps({"expires_at": time.time() + 60, "payload": payload})
    path.write_text(encoded, encoding="utf-8")
    original = http.post

    def post(url, *, headers, json=None):
        if url.endswith("/complete") and not http.downloads:
            return FakeResponse(status_code=status)
        return original(url, headers=headers, json=json)

    monkeypatch.setattr(http, "post", post)
    if status == 422:
        assert consumer.run_once()
        assert http.downloads and len(queue.deleted) == 1 and not path.exists()
    else:
        with pytest.raises(RuntimeError):
            consumer.run_once()
        assert not http.downloads and not queue.deleted
        assert path.read_text(encoding="utf-8") == encoded


@pytest.mark.parametrize("expired_by", ["mtime", "envelope"])
def test_expired_cache_never_replays(tmp_path: Path, expired_by: str) -> None:
    consumer, http, queue, path = cached_worker(tmp_path)
    payload = {"sceneDraft": {"version": "2.0"}, "warnings": ["expired"]}
    path.write_text(json.dumps({"expires_at": time.time() + (-1 if expired_by == "envelope" else 60),
                                "payload": payload}), encoding="utf-8")
    if expired_by == "mtime":
        old = time.time() - 31 * 24 * 3600
        os.utime(path, (old, old))
    assert consumer.run_once()
    assert http.downloads and http.posts[-1][2] != payload
    assert len(queue.deleted) == 1 and not path.exists()
