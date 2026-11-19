"""F07 stage cache in the video pipeline (S3): the sparse reconstruction is paid for once."""

from __future__ import annotations

from pathlib import Path

import pytest
import reconstruct_video as rv
import stage_cache
import test_reconstruct_video as T


class CountingEstimator(T.FakeEstimator):
    def __init__(self, models: list[rv.SparseModel]) -> None:
        super().__init__(models)
        self.calls = 0

    def estimate(self, frames: list[rv.ExtractedFrame], work_dir: Path) -> list[rv.SparseModel]:
        self.calls += 1
        return super().estimate(frames, work_dir)


def _cache(tmp_path: Path) -> stage_cache.StageCache:
    return rv.make_stage_cache(tmp_path / "cache")


def _run(package: Path, model: rv.SparseModel, cache, extractor=None, estimator=None, **options):
    extractor = extractor or T.FakeExtractor()
    estimator = estimator or CountingEstimator([model])
    result = rv.reconstruct_video(package, extractor=extractor, estimator=estimator, stage_cache=cache, **options)
    return result, extractor, estimator


def test_a_second_run_reuses_the_sparse_reconstruction_and_gives_the_same_scene(tmp_path: Path) -> None:
    package, model = T.single_room(tmp_path / "p")
    cache = _cache(tmp_path)

    first, _, first_estimator = _run(package, model, cache)
    second, second_extractor, second_estimator = _run(package, model, cache)

    assert first_estimator.calls == 1
    assert second_estimator.calls == 0
    assert second_extractor.calls == []  # nothing needs the frames, so ffmpeg is not run either
    assert second.scene_draft == first.scene_draft
    assert second.warnings == first.warnings


def test_without_a_cache_every_run_computes(tmp_path: Path) -> None:
    package, model = T.single_room(tmp_path / "p")

    _, _, first = _run(package, model, None)
    _, _, second = _run(package, model, None)

    assert first.calls == second.calls == 1


def test_a_different_video_does_not_reuse_the_entry(tmp_path: Path) -> None:
    package, model = T.single_room(tmp_path / "p")
    cache = _cache(tmp_path)
    _run(package, model, cache)
    (package / "video.mp4").write_bytes(b"another recording")

    _, _, estimator = _run(package, model, cache)

    assert estimator.calls == 1


def test_a_change_in_the_sensors_does_not_invalidate_the_sparse_reconstruction(tmp_path: Path) -> None:
    package, model = T.single_room(tmp_path / "p")
    cache = _cache(tmp_path)
    _run(package, model, cache)
    (package / "sensors.jsonl").write_text("", encoding="utf-8")

    _, _, estimator = _run(package, model, cache)

    assert estimator.calls == 0


def test_geometry_threshold_changes_reuse_sfm_but_sampling_budget_does_not(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    package, model = T.single_room(tmp_path / "p")
    cache = _cache(tmp_path)
    _run(package, model, cache)
    monkeypatch.setattr(rv, "GRAVITY_MAX_SKEW_NS", rv.GRAVITY_MAX_SKEW_NS // 2)
    _, _, reused = _run(package, model, cache)
    assert reused.calls == 0
    monkeypatch.setattr(rv, "MAX_SFM_FRAMES", rv.MAX_SFM_FRAMES + 1)
    _, _, refreshed = _run(package, model, cache)
    assert refreshed.calls == 1


def test_door_recognition_still_gets_its_frames_when_the_reconstruction_is_cached(tmp_path: Path) -> None:
    package, model = T.single_room(tmp_path / "p")
    cache = _cache(tmp_path)
    _run(package, model, cache)
    seen: list[Path] = []

    def factory():
        return lambda path: seen.append(path) or []

    _, extractor, estimator = _run(package, model, cache, opening_detector=factory)

    assert estimator.calls == 0
    assert len(extractor.calls) == 1 and seen


def test_a_failed_reconstruction_is_not_cached(tmp_path: Path) -> None:
    package, model = T.single_room(tmp_path / "p")
    cache = _cache(tmp_path)
    empty = rv.SparseModel(poses=[], points=[], intrinsics=model.intrinsics)
    with pytest.raises(rv.InvalidPackage):
        _run(package, empty, cache)

    _, _, estimator = _run(package, model, cache)

    assert estimator.calls == 1


def test_cache_keeps_native_reference_diagnostics(tmp_path: Path, caplog: pytest.LogCaptureFixture) -> None:
    import json
    import logging

    caplog.set_level(logging.INFO, logger=rv.__name__)
    package, model = T.single_room(tmp_path / "p")
    cache = _cache(tmp_path)
    first = CountingEstimator([model])
    first.diagnostics = {"verified_matches": 17, "verified_inliers": 250, "features_median": 64,
                         "stage_durations": {"matching": 1.25}}
    _run(package, model, cache, estimator=first)
    caplog.clear()
    _run(package, model, cache, estimator=CountingEstimator([model]))
    record = next(r.message for r in caplog.records if r.message.startswith("F07 reconstruction diagnostic:"))
    diagnostic = json.loads(record.split(": ", 1)[1])
    assert diagnostic["verified_matches"] == 17
    assert diagnostic["verified_inliers"] == 250
    assert diagnostic["native_stage_durations"] == {"matching": 1.25}
    assert diagnostic["sfm_cache_hit"] is True
    assert diagnostic["frames_extracted"] == 0
    assert diagnostic["output_acceptable"] is None


def test_cached_sfm_never_skips_timestamp_validation(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    class CheckedExtractor(T.FakeExtractor):
        checks = 0
        reject = False

        def validate_timestamps(self, video, frames):
            self.checks += 1
            if self.reject:
                raise rv.InvalidPackage("MP4 presentation timestamps do not agree")

    monkeypatch.setattr(rv, "FfmpegFrameExtractor", CheckedExtractor)
    package, model = T.single_room(tmp_path / "p")
    cache, extractor = _cache(tmp_path), CheckedExtractor()
    _run(package, model, cache, extractor=extractor)
    extractor.reject = True
    with pytest.raises(rv.InvalidPackage, match="presentation timestamps"):
        _run(package, model, cache, extractor=extractor)
    assert extractor.checks == 2
