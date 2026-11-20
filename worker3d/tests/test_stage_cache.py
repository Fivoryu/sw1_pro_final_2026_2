"""F07 stage cache (S3): expensive stage results are reused, and a bad cache file is never trusted."""

from __future__ import annotations

import pickle
import sys
from dataclasses import dataclass
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import stage_cache


@dataclass(frozen=True)
class Payload:
    value: int


class Counter:
    def __init__(self, result: object) -> None:
        self.result = result
        self.calls = 0

    def __call__(self) -> object:
        self.calls += 1
        return self.result


def test_a_second_fetch_with_the_same_key_does_not_compute_again(tmp_path: Path) -> None:
    cache = stage_cache.StageCache(tmp_path)
    compute = Counter([1, 2, 3])

    first = cache.fetch("sfm", "key", compute)
    second = cache.fetch("sfm", "key", compute)

    assert first == second == [1, 2, 3]
    assert compute.calls == 1


def test_another_key_or_stage_computes_again(tmp_path: Path) -> None:
    cache = stage_cache.StageCache(tmp_path)
    compute = Counter("x")

    cache.fetch("sfm", "key", compute)
    cache.fetch("sfm", "other", compute)
    cache.fetch("raw", "key", compute)

    assert compute.calls == 3


def test_the_cache_survives_a_new_instance_over_the_same_directory(tmp_path: Path) -> None:
    stage_cache.StageCache(tmp_path).fetch("sfm", "key", Counter("kept"))
    compute = Counter("recomputed")

    assert stage_cache.StageCache(tmp_path).fetch("sfm", "key", compute) == "kept"
    assert compute.calls == 0


def test_a_result_that_fails_the_keep_check_is_not_stored(tmp_path: Path) -> None:
    cache = stage_cache.StageCache(tmp_path)
    compute = Counter([])

    cache.fetch("sfm", "key", compute, keep=bool)
    cache.fetch("sfm", "key", compute, keep=bool)

    assert compute.calls == 2


def test_a_corrupt_cache_file_is_recomputed_and_replaced(tmp_path: Path) -> None:
    cache = stage_cache.StageCache(tmp_path)
    cache.fetch("sfm", "key", Counter("good"))
    (stored,) = tmp_path.glob("sfm-*.pkl")
    stored.write_bytes(b"\x80not a pickle")
    compute = Counter("fresh")

    assert cache.fetch("sfm", "key", compute) == "fresh"
    assert cache.fetch("sfm", "key", compute) == "fresh"
    assert compute.calls == 1


def test_a_pickle_that_names_a_class_outside_the_allowed_ones_is_ignored(tmp_path: Path) -> None:
    marker = tmp_path / "executed"

    class Boom:
        def __reduce__(self):
            return (marker.write_text, ("pwned",))

    cache = stage_cache.StageCache(tmp_path / "cache")
    cache.fetch("sfm", "key", Counter("seed"))
    (stored,) = (tmp_path / "cache").glob("sfm-*.pkl")
    stored.write_bytes(pickle.dumps(Boom()))
    compute = Counter("fresh")

    assert cache.fetch("sfm", "key", compute) == "fresh"
    assert not marker.exists()


def test_an_allowed_dataclass_round_trips(tmp_path: Path) -> None:
    cache = stage_cache.StageCache(tmp_path, allowed=[Payload])
    cache.fetch("sfm", "key", Counter([Payload(7)]))

    assert cache.fetch("sfm", "key", Counter("never")) == [Payload(7)]


def test_a_dataclass_that_was_not_allowed_is_not_loaded(tmp_path: Path) -> None:
    stage_cache.StageCache(tmp_path).fetch("sfm", "key", Counter([Payload(7)]))
    compute = Counter("fresh")

    assert stage_cache.StageCache(tmp_path).fetch("sfm", "key", compute) == "fresh"


def test_an_unwritable_directory_still_returns_the_computed_value(tmp_path: Path) -> None:
    blocker = tmp_path / "file"
    blocker.write_text("not a directory")

    assert stage_cache.StageCache(blocker / "inside").fetch("sfm", "key", Counter("ok")) == "ok"


def test_the_fingerprint_changes_when_a_file_changes_and_not_otherwise(tmp_path: Path) -> None:
    first, second = tmp_path / "a.bin", tmp_path / "b.bin"
    first.write_bytes(b"one")
    second.write_bytes(b"two")
    before = stage_cache.fingerprint([first, second])

    assert stage_cache.fingerprint([first, second]) == before
    second.write_bytes(b"changed")
    assert stage_cache.fingerprint([first, second]) != before


@pytest.mark.parametrize("name", ["sfm", "raw-openings"])
def test_stage_names_become_file_prefixes(tmp_path: Path, name: str) -> None:
    stage_cache.StageCache(tmp_path).fetch(name, "key", Counter(1))

    assert list(tmp_path.glob(f"{name}-*.pkl"))
