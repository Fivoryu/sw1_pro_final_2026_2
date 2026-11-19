# ruff: noqa: E402  -- tests import the standalone worker after configuring sys.path.
"""Furniture suggestions for schema 2 (video) packages, F07 T6.

A synthetic furniture cluster is added to the synthetic room of ``test_reconstruct_video`` and a
fake detector returns the pixel box where that cluster projects. No real detector, ffmpeg or
pycolmap is involved.
"""

from __future__ import annotations

import io
import json
import sys
import zipfile
from pathlib import Path
from typing import Any

import pytest

WORKER3D_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(WORKER3D_DIR))
sys.path.insert(0, str(WORKER3D_DIR / "tests"))

import reconstruct
import reconstruct_video as rv
import reconstruction_worker
import test_reconstruct_video as T
from test_reconstruction_worker import FakeHttpClient, FakeQueue

# Furniture in metric room coordinates: x 1.5..2.2, z 1.0..1.6, y 0.1..0.8.
CUBE = (1.5, 1.0, 2.2, 1.6)
CUBE_Y = (0.1, 0.8)
SCALE, SHIFT = 0.4, (3.0, -2.0, 5.0)


def _to_sfm(point: tuple[float, float, float]) -> tuple[float, float, float]:
    rotated = T._mv(T.ROT, point)
    return (
        SCALE * rotated[0] + SHIFT[0],
        SCALE * rotated[1] + SHIFT[1],
        SCALE * rotated[2] + SHIFT[2],
    )


def furnished_model() -> rv.SparseModel:
    model = T.make_model((0.0, 0.0, 4.0, 3.0), scale=SCALE, shift=SHIFT)
    frames = tuple(p.frame_index for p in model.poses)
    extra = []
    for i in range(8):
        for j in range(7):
            for k in range(8):
                world = (CUBE[0] + 0.1 * i, CUBE_Y[0] + 0.1 * k, CUBE[1] + 0.1 * j)
                extra.append(rv.SparsePoint(_to_sfm(world), frames))
    return rv.SparseModel(model.poses, [*model.points, *extra], model.intrinsics)


def cube_box(model: rv.SparseModel, frame: int) -> list[float] | None:
    pose = next(p for p in model.poses if p.frame_index == frame)
    us, vs = [], []
    for x in (CUBE[0], CUBE[2]):
        for y in CUBE_Y:
            for z in (CUBE[1], CUBE[3]):
                p = _to_sfm((x, y, z))
                cam = T._mv(T._t(pose.rotation), tuple(a - b for a, b in zip(p, pose.center, strict=True)))
                if cam[2] <= 0:
                    return None
                us.append(T.FOCAL * cam[0] / cam[2] + T.WIDTH / 2)
                vs.append(T.FOCAL * cam[1] / cam[2] + T.HEIGHT / 2)
    return [round(min(us), 2), round(min(vs), 2), round(max(us), 2), round(max(vs), 2)]


class FakeDetector:
    def __init__(self, boxes: dict[int, list[float] | None], label: str = "sofa", score: float = 0.9) -> None:
        self.boxes, self.label, self.score = boxes, label, score
        self.calls: list[int] = []

    def __call__(self, images: Any, threshold: float) -> tuple[list[dict[str, Any]], list[str]]:
        records = []
        for path in images:
            frame = int(Path(path).stem)
            self.calls.append(frame)
            box = self.boxes.get(frame)
            detections = [{"label": self.label, "score": self.score, "box": box}] if box else []
            records.append({"image": Path(path).name, "detections": detections})
        return records, []


def _factory(detector: Any) -> Any:
    return lambda: (detector, "fake-model", 0.5)


def package_for(tmp_path: Path, model: rv.SparseModel, *, reference: bool = True) -> Path:
    manifest = T.v2_manifest(**({"reference": T.floor_reference(model)} if reference else {}))
    return T.write_v2(tmp_path / "p", manifest, sensors=T.gravity_lines([model]))


def run_detect(package: Path, model: rv.SparseModel, factory: Any) -> Any:
    return rv.reconstruct_video(
        package,
        extractor=T.FakeExtractor(),
        estimator=T.FakeEstimator([model]),
        detector_factory=factory,
    )


def visible_boxes(model: rv.SparseModel) -> dict[int, list[float] | None]:
    return {p.frame_index: cube_box(model, p.frame_index) for p in model.poses}


def test_a_detection_becomes_a_volume_with_the_pending_suggestion(tmp_path: Path) -> None:
    model = furnished_model()
    detector = FakeDetector(visible_boxes(model))

    result = run_detect(package_for(tmp_path, model), model, _factory(detector))

    [obj] = [o for o in result.scene_draft["objects"] if o["type"] == "occupancy"]
    assert obj["id"] == "box-1" and obj["source"] == "sfm_estimated"
    # The plan frame of an SfM model has an arbitrary yaw, so only frame-independent facts are pinned.
    corners = [(w["start"]["x"], w["start"]["z"]) for w in result.scene_draft["walls"]]
    assert reconstruct._point_in_polygon((obj["position"]["x"], obj["position"]["z"]), corners)
    assert 0.4 <= obj["dimensions"]["width"] <= 1.2
    assert 0.4 <= obj["dimensions"]["depth"] <= 1.2
    assert obj["dimensions"]["height"] == pytest.approx(0.8, abs=0.2)
    suggestions = result.volume_suggestions  # type: ignore[attr-defined]
    assert suggestions["modelId"] == "fake-model"
    [item] = suggestions["items"]
    assert set(item) == {"objectId", "label", "score", "keyframe", "box"}
    assert (item["objectId"], item["label"], item["score"]) == ("box-1", "sofa", 0.9)
    assert item["keyframe"] >= 1
    assert item["box"] == detector.boxes[item["keyframe"] - 1]
    assert result.volume_views == []


def test_the_same_furniture_seen_in_several_frames_is_one_volume(tmp_path: Path) -> None:
    model = furnished_model()
    detector = FakeDetector(visible_boxes(model))

    result = run_detect(package_for(tmp_path, model), model, _factory(detector))

    assert len(detector.calls) >= 2  # several sampled frames saw it
    assert len(result.scene_draft["objects"]) == 1
    assert len(result.volume_suggestions["items"]) == 1  # type: ignore[attr-defined]


def test_the_suggestion_passes_the_scene_and_suggestion_rules_of_the_api(tmp_path: Path) -> None:
    model = furnished_model()
    result = run_detect(
        package_for(tmp_path, model), model, _factory(FakeDetector(visible_boxes(model)))
    )

    ids = {o["id"] for o in result.scene_draft["objects"] if o["type"] == "occupancy"}
    items = result.volume_suggestions["items"]  # type: ignore[attr-defined]
    assert len(items) <= reconstruction_worker.MAX_SUGGESTIONS
    assert {i["objectId"] for i in items} <= ids and len({i["objectId"] for i in items}) == len(items)
    assert all(0 <= i["score"] <= 1 and 1 <= len(i["label"]) <= 64 for i in items)


def test_a_detection_with_no_sparse_points_behind_it_warns_and_makes_no_volume(tmp_path: Path) -> None:
    model = furnished_model()
    empty = {p.frame_index: [2.0, 2.0, 6.0, 6.0] for p in model.poses}  # corner of the image

    result = run_detect(package_for(tmp_path, model), model, _factory(FakeDetector(empty)))

    assert result.scene_draft["objects"] == []
    assert result.volume_suggestions is None  # type: ignore[attr-defined]
    assert "Sin profundidad: no se generaron volúmenes" in result.warnings


def test_a_detector_that_finds_nothing_adds_no_volumes_and_no_depth_warning(tmp_path: Path) -> None:
    model = furnished_model()

    result = run_detect(package_for(tmp_path, model), model, _factory(FakeDetector({})))

    assert result.scene_draft["objects"] == []
    assert result.volume_suggestions is None  # type: ignore[attr-defined]
    assert "Sin profundidad: no se generaron volúmenes" not in result.warnings


def test_an_unavailable_detector_degrades_to_a_warning(tmp_path: Path) -> None:
    model = furnished_model()

    def missing() -> Any:
        raise ImportError("no torch")

    result = run_detect(package_for(tmp_path, model), model, missing)

    assert result.volume_suggestions is None  # type: ignore[attr-defined]
    assert reconstruction_worker.WARNING_DETECTOR_UNAVAILABLE in result.warnings
    assert len(result.scene_draft["rooms"]) == 1


def test_a_failing_detector_never_crashes_the_reconstruction(tmp_path: Path) -> None:
    model = furnished_model()

    def boom(images: Any, threshold: float) -> Any:
        raise RuntimeError("secret path /x/y")

    result = run_detect(package_for(tmp_path, model), model, _factory(boom))

    assert result.volume_suggestions is None  # type: ignore[attr-defined]
    assert reconstruction_worker.WARNING_LABELING_FAILED in result.warnings
    assert not any("secret" in w for w in result.warnings)
    assert len(result.scene_draft["rooms"]) == 1


def test_detection_is_off_without_a_factory_and_changes_nothing(tmp_path: Path) -> None:
    model = furnished_model()
    package = package_for(tmp_path, model)

    plain = rv.reconstruct_video(
        package, extractor=T.FakeExtractor(), estimator=T.FakeEstimator([model])
    )

    assert plain.scene_draft["objects"] == []
    assert getattr(plain, "volume_suggestions", None) is None
    assert not any("Sin profundidad" in w or "Class suggestions" in w for w in plain.warnings)


def test_only_a_bounded_number_of_frames_goes_to_the_detector(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    model = furnished_model()
    detector = FakeDetector(visible_boxes(model))
    monkeypatch.setattr(rv, "DETECTION_MAX_FRAMES", 1)

    run_detect(package_for(tmp_path, model), model, _factory(detector))

    assert len(detector.calls) == 1


# --- worker wiring ----------------------------------------------------------------------------


def _zip(package: Path) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as handle:
        for name in ("manifest.json", "video.mp4", "frames.jsonl", "sensors.jsonl"):
            handle.write(package / name, name)
    return buffer.getvalue()


def test_the_worker_posts_the_video_suggestions_without_calling_the_depth_labeler(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    model = furnished_model()
    package = package_for(tmp_path, model)
    detector = FakeDetector(visible_boxes(model))
    monkeypatch.setattr(rv, "default_adapters", lambda: (T.FakeExtractor(), T.FakeEstimator([model])))
    monkeypatch.setattr(rv, "default_detector", _factory(detector))
    http, queue = FakeHttpClient(package=_zip(package)), FakeQueue()
    called: list[Any] = []

    def labeler(*args: Any) -> None:
        called.append(args)

    worker = reconstruction_worker.ReconstructionJobWorker(
        api_base_url="http://api:8000",
        service_token="service-token",
        queue=queue,
        http_client=http,
        labeler=labeler,
    )
    assert worker.run_once() is True

    _, _, body = http.posts[1]
    assert body is not None
    assert set(body) == {"sceneDraft", "warnings", "volumeSuggestions"}
    assert body["volumeSuggestions"]["items"][0]["objectId"] == "box-1"
    assert called == []


def test_the_default_reconstructor_keeps_schema_1_on_the_untouched_path(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    seen: list[Path] = []
    original = reconstruct.reconstruct

    def spy(package_dir: Path) -> reconstruct.ReconstructionResult:
        seen.append(package_dir)
        return original(package_dir)

    monkeypatch.setattr(reconstruct, "reconstruct", spy)
    monkeypatch.setattr(rv, "default_detector", lambda: pytest.fail("schema 1 must not load the video detector"))
    from test_reconstruct_synthetic import room_package, write_package

    package = write_package(tmp_path / "v1", room_package())

    result = reconstruction_worker.reconstruct_package(package)

    assert seen == [package]
    assert not hasattr(result, "volume_suggestions")
    assert json.loads((package / "manifest.json").read_text(encoding="utf-8"))["schemaVersion"] == 1


def test_schema_1_results_still_use_the_depth_labeler(tmp_path: Path) -> None:
    suggestions = {"modelId": "m", "items": []}
    http, queue = FakeHttpClient(), FakeQueue()
    seen: list[Any] = []

    def labeler(package_dir: Path, views: list[dict[str, Any]]) -> dict[str, Any]:
        seen.append(views)
        return suggestions

    def reconstructor(_: Path) -> reconstruct.ReconstructionResult:
        return reconstruct.ReconstructionResult(
            scene_draft={"version": "2.0"}, warnings=[], volume_views=[{"objectId": "box-1"}]
        )

    worker = reconstruction_worker.ReconstructionJobWorker(
        api_base_url="http://api:8000", service_token="service-token", queue=queue, http_client=http,
        reconstructor=reconstructor, labeler=labeler,
    )
    assert worker.run_once() is True

    assert seen == [[{"objectId": "box-1"}]]
    assert http.posts[1][2]["volumeSuggestions"] == suggestions  # type: ignore[index]


def test_the_video_warnings_match_the_schema_1_texts() -> None:
    assert rv.WARNING_DETECTOR_UNAVAILABLE == reconstruction_worker.WARNING_DETECTOR_UNAVAILABLE
    assert rv.WARNING_LABELING_FAILED == reconstruction_worker.WARNING_LABELING_FAILED
