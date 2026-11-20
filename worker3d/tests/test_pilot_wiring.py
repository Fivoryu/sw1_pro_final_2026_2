"""F07 pilot wiring (S11): the stage cache and door recognition are switched on by the environment.

Both are off unless asked: the default reconstructor calls the video pipeline exactly as before.
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import openings
import reconstruct
import reconstruct_video as rv
import reconstruction_worker as worker
import test_reconstruct_video as T


def test_without_environment_nothing_is_switched_on() -> None:
    assert worker.pilot_options({}) == {}
    assert worker.pilot_options({worker.OPENING_DETECTION_ENV: "", worker.STAGE_CACHE_ENV: "  "}) == {}


@pytest.mark.parametrize("off", ["off", "OFF", "0", "false", "no"])
def test_door_recognition_can_be_switched_off_explicitly(off: str) -> None:
    assert worker.pilot_options({worker.OPENING_DETECTION_ENV: off}) == {}


def test_a_cache_directory_gives_a_stage_cache_over_it(tmp_path: Path) -> None:
    options = worker.pilot_options({worker.STAGE_CACHE_ENV: str(tmp_path / "cache")})

    assert set(options) == {"stage_cache"}
    options["stage_cache"].fetch("probe", "key", lambda: 1)
    assert list((tmp_path / "cache").glob("probe-*.pkl"))


def test_door_recognition_builds_the_detector_lazily_and_shares_the_cache(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    built: list[dict[str, Any]] = []
    monkeypatch.setattr(openings, "build_detector", lambda model_key, **kw: built.append({"model": model_key, **kw}) or "detector")

    options = worker.pilot_options({worker.OPENING_DETECTION_ENV: "owlv2", worker.STAGE_CACHE_ENV: str(tmp_path)})

    assert built == []  # nothing is loaded until the pipeline asks for the detector
    assert options["opening_detector"]() == "detector"
    assert built == [{"model": "owlv2", "cache": options["stage_cache"]}]


def test_door_recognition_without_a_cache_builds_a_detector_without_one(monkeypatch: pytest.MonkeyPatch) -> None:
    built: list[dict[str, Any]] = []
    monkeypatch.setattr(openings, "build_detector", lambda model_key, **kw: built.append({"model": model_key, **kw}) or "d")

    worker.pilot_options({worker.OPENING_DETECTION_ENV: "owlv2"})["opening_detector"]()

    assert built == [{"model": "owlv2", "cache": None}]


@pytest.mark.parametrize("value", ["yolo-world", "grounding-dino", "true"])
def test_a_model_the_worker_cannot_run_is_a_configuration_error(value: str) -> None:
    with pytest.raises(ValueError, match="owlv2"):
        worker.pilot_options({worker.OPENING_DETECTION_ENV: value})


def test_the_detector_backend_refuses_a_model_it_has_no_backend_for() -> None:
    with pytest.raises(ValueError, match="no backend"):
        openings.build_detector("grounding-dino")


def test_a_missing_runtime_is_reported_by_the_pipeline_as_a_warning_and_the_scene_is_still_made(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    def unavailable(*args: Any, **kwargs: Any):
        raise reconstruct.ExternalToolMissing("no torch")

    monkeypatch.setattr(openings, "build_detector", unavailable)
    package, model = T.single_room(tmp_path / "p")
    options = worker.pilot_options({worker.OPENING_DETECTION_ENV: "owlv2"})

    result = rv.reconstruct_video(package, extractor=T.FakeExtractor(), estimator=T.FakeEstimator([model]), **options)

    assert result.scene_draft["walls"]
    assert any("puertas" in w.lower() for w in result.warnings)


def _spy_video(monkeypatch: pytest.MonkeyPatch, package: Path) -> list[dict[str, Any]]:
    calls: list[dict[str, Any]] = []
    monkeypatch.setattr(reconstruct, "_declared_schema_version", lambda directory: 2)
    monkeypatch.setattr(rv, "reconstruct_video", lambda directory, **kw: calls.append(kw) or "result")
    return calls


def test_the_default_reconstructor_passes_only_the_furniture_detector_when_nothing_is_set(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    for name in (worker.OPENING_DETECTION_ENV, worker.STAGE_CACHE_ENV):
        monkeypatch.delenv(name, raising=False)
    calls = _spy_video(monkeypatch, tmp_path)

    assert worker.reconstruct_package(tmp_path) == "result"

    assert set(calls[0]) == {"detector_factory"}


def test_the_default_reconstructor_passes_the_pilot_options_to_the_video_pipeline(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv(worker.OPENING_DETECTION_ENV, "owlv2")
    monkeypatch.setenv(worker.STAGE_CACHE_ENV, str(tmp_path / "cache"))
    calls = _spy_video(monkeypatch, tmp_path)

    worker.reconstruct_package(tmp_path)

    assert set(calls[0]) == {"detector_factory", "opening_detector", "stage_cache"}
