"""Schema 2 reconstruction (video + sensors -> scene v2 draft), F07 T5.

The heavy external steps (ffmpeg, pycolmap) are replaced by fakes that return a synthetic
rectangular room, so the geometry logic is exercised without any of them installed.
"""

from __future__ import annotations

import io
import json
import math
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
from test_reconstruct_synthetic import room_package, write_package

T0 = 1_000_000_000
STEP = 100_000_000  # 10 fps
WIDTH, HEIGHT, FOCAL = 1280, 720, 800.0
UP = (0.0, 1.0, 0.0)
# Rotation that turns the metric frame (y up) into an arbitrary SfM frame (z up).
ROT = ((1.0, 0.0, 0.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0))


# --- tiny vector helpers (test side) --------------------------------------------------------


def _mv(m: Any, v: Any) -> tuple[float, float, float]:
    return (
        sum(m[0][i] * v[i] for i in range(3)),
        sum(m[1][i] * v[i] for i in range(3)),
        sum(m[2][i] * v[i] for i in range(3)),
    )


def _mm(a: Any, b: Any) -> Any:
    return tuple(tuple(sum(a[r][k] * b[k][c] for k in range(3)) for c in range(3)) for r in range(3))


def _t(m: Any) -> Any:
    return tuple(tuple(m[c][r] for c in range(3)) for r in range(3))


def _cross(a: Any, b: Any) -> tuple[float, float, float]:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _unit(v: Any) -> tuple[float, float, float]:
    n = math.sqrt(sum(c * c for c in v))
    return (v[0] / n, v[1] / n, v[2] / n)


def _cols(c0: Any, c1: Any, c2: Any) -> Any:
    return tuple((c0[r], c1[r], c2[r]) for r in range(3))


# --- synthetic room + fake estimator --------------------------------------------------------


def _camera_rotation_w(forward: Any) -> Any:
    right = _unit(_cross(forward, UP))
    down = _cross(forward, right)
    return _cols(right, down, forward)  # world_from_camera, COLMAP axes (x right, y down, z fwd)


def _forward(yaw: float, pitch_deg: float) -> tuple[float, float, float]:
    p = math.radians(pitch_deg)
    return (math.cos(p) * math.sin(yaw), -math.sin(p), math.cos(p) * math.cos(yaw))


def make_model(
    rect: tuple[float, float, float, float],
    *,
    height: float = 2.5,
    scale: float = 0.4,
    shift: tuple[float, float, float] = (3.0, -2.0, 5.0),
    first_frame: int = 0,
    pitch_deg: float = 35.0,
    skip_walls: tuple[str, ...] = (),
    ceiling: bool = True,
) -> rv.SparseModel:
    x0, z0, x1, z1 = rect
    mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
    spots = [
        (x0 + 0.5, z0 + 0.5), (mx, z0 + 0.5), (x1 - 0.5, z0 + 0.5), (x1 - 0.5, mz),
        (x1 - 0.5, z1 - 0.5), (mx, z1 - 0.5), (x0 + 0.5, z1 - 0.5), (x0 + 0.5, mz),
    ]
    frames = list(range(first_frame, first_frame + len(spots)))
    poses = []
    for index, (px, pz) in zip(frames, spots, strict=True):
        yaw = math.atan2(mx - px, mz - pz)
        r_w = _camera_rotation_w(_forward(yaw, pitch_deg))
        centre = tuple(scale * c + s for c, s in zip(_mv(ROT, (px, 1.4, pz)), shift, strict=True))
        poses.append(rv.CameraPose(index, _mm(ROT, r_w), centre))

    world: list[tuple[float, float, float]] = []
    steps = [i * 0.25 for i in range(int(max(x1 - x0, z1 - z0) / 0.25) + 1)]
    levels = [0.5 + 0.25 * k for k in range(int((height - 1.0) / 0.25) + 1)]
    sides = {
        "n": ((x0, z0), (x1, z0)), "e": ((x1, z0), (x1, z1)),
        "s": ((x1, z1), (x0, z1)), "w": ((x0, z1), (x0, z0)),
    }
    for name, (a, b) in sides.items():
        if name in skip_walls:
            continue
        length = math.dist(a, b)
        for s in steps:
            if s > length + 1e-9:
                continue
            for y in levels:
                world.append((a[0] + (b[0] - a[0]) * s / length, y, a[1] + (b[1] - a[1]) * s / length))
    for sx in steps:
        for sz in steps:
            if x0 + sx <= x1 + 1e-9 and z0 + sz <= z1 + 1e-9:
                world.append((x0 + sx, 0.0, z0 + sz))
                if ceiling:
                    world.append((x0 + sx, height, z0 + sz))
    points = [
        rv.SparsePoint(
            tuple(scale * c + s for c, s in zip(_mv(ROT, p), shift, strict=True)), tuple(frames)
        )
        for p in world
    ]
    intrinsics = rv.Intrinsics(WIDTH, HEIGHT, FOCAL, FOCAL, WIDTH / 2, HEIGHT / 2)
    return rv.SparseModel(poses=poses, points=points, intrinsics=intrinsics)


def project(model: rv.SparseModel, frame: int, world_point: Any, scale: float, shift: Any) -> Any:
    """Normalised (x, y) of a metric world point seen from ``frame`` of ``model``."""
    pose = next(p for p in model.poses if p.frame_index == frame)
    point_s = tuple(scale * c + s for c, s in zip(_mv(ROT, world_point), shift, strict=True))
    x, y, z = _mv(_t(pose.rotation), tuple(a - b for a, b in zip(point_s, pose.center, strict=True)))
    assert z > 0
    u, v = FOCAL * x / z + WIDTH / 2, FOCAL * y / z + HEIGHT / 2
    assert 0 < u < WIDTH and 0 < v < HEIGHT, "the reference must be visible in the test frame"
    return {"x": u / WIDTH, "y": v / HEIGHT}


class FakeExtractor:
    def __init__(self) -> None:
        self.calls: list[list[int]] = []

    def extract(self, video: Path, indices: list[int], out_dir: Path) -> list[rv.ExtractedFrame]:
        self.calls.append(list(indices))
        return [rv.ExtractedFrame(i, out_dir / f"{i:06d}.jpg") for i in indices]


class FakeEstimator:
    def __init__(self, models: list[rv.SparseModel]) -> None:
        self.models = models

    def estimate(self, frames: list[rv.ExtractedFrame], work_dir: Path) -> list[rv.SparseModel]:
        return self.models


# --- synthetic v2 packages ------------------------------------------------------------------


def v2_manifest(**overrides: Any) -> dict[str, Any]:
    manifest: dict[str, Any] = {
        "schemaVersion": 2,
        "captureId": "capture-2",
        "listingId": "listing-1",
        "device": {"model": "test", "os": "android", "osVersion": "14"},
        "video": {
            "file": "video.mp4", "width": WIDTH, "height": HEIGHT, "fps": 10,
            "startedAtNs": T0, "sensorOrientation": 90, "framesFile": "frames.jsonl", "timestampSource": "realtime",
        },
        "sensors": {"file": "sensors.jsonl", "rateHz": 100},
        "rooms": [{"id": "room-1", "name": "Estar", "fromNs": T0, "toNs": T0 + 10 * STEP}],
    }
    manifest.update(overrides)
    return manifest


def frame_lines(count: int = 8) -> list[dict[str, int]]:
    return [{"i": i, "t": T0 + i * STEP} for i in range(count)]


def gravity_lines(
    models: list[rv.SparseModel],
    *,
    with_gravity: bool = True,
    orientation: int = 90,
    up_world: Any = None,
) -> list[dict[str, Any]]:
    matrix = rv.device_to_camera_matrix(orientation)
    up_s = _mv(ROT, UP) if up_world is None else up_world
    lines: list[dict[str, Any]] = []
    for model in models:
        for pose in model.poses:
            t = T0 + pose.frame_index * STEP
            lines.append({"t": t, "type": "gyro", "x": 0.0, "y": 0.0, "z": 0.0})
            if with_gravity:
                up_cam = _mv(_t(pose.rotation), up_s)
                g_dev = _mv(_t(matrix), up_cam)
                lines.append(
                    {"t": t + 1000, "type": "gravity", "x": 9.81 * g_dev[0], "y": 9.81 * g_dev[1],
                     "z": 9.81 * g_dev[2]}
                )
    return sorted(lines, key=lambda line: line["t"])


def write_v2(
    directory: Path,
    manifest: dict[str, Any] | None = None,
    frames: list[dict[str, Any]] | None = None,
    sensors: list[dict[str, Any]] | None = None,
) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "manifest.json").write_text(json.dumps(manifest or v2_manifest()), encoding="utf-8")
    (directory / "video.mp4").write_bytes(b"not a real video")
    (directory / "frames.jsonl").write_text(
        "\n".join(json.dumps(f) for f in (frame_lines() if frames is None else frames)), encoding="utf-8"
    )
    (directory / "sensors.jsonl").write_text(
        "\n".join(json.dumps(s) for s in (sensors or [])), encoding="utf-8"
    )
    return directory


def run(
    directory: Path, models: list[rv.SparseModel], extractor: FakeExtractor | None = None, **options: Any
) -> reconstruct.ReconstructionResult:
    return rv.reconstruct_video(
        directory, extractor=extractor or FakeExtractor(), estimator=FakeEstimator(models), **options
    )


def single_room(tmp_path: Path, *, reference: dict[str, Any] | None = None, **model_kwargs: Any) -> Any:
    model = make_model((0.0, 0.0, 4.0, 3.0), **model_kwargs)
    manifest = v2_manifest(**({"reference": reference} if reference else {}))
    package = write_v2(tmp_path / "p", manifest, sensors=gravity_lines([model]))
    return package, model


def wall_lengths(scene: dict[str, Any]) -> list[float]:
    return sorted(
        round(math.dist((w["start"]["x"], w["start"]["z"]), (w["end"]["x"], w["end"]["z"])), 2)
        for w in scene["walls"]
    )


def floor_reference(model: rv.SparseModel) -> dict[str, Any]:
    p1, p2 = (1.9, 0.0, 1.3), (2.4, 0.0, 1.9)
    shift = (3.0, -2.0, 5.0)
    return {
        "kind": "object", "label": "Alfombra", "lengthM": round(math.dist(p1, p2), 6),
        "surface": "floor", "frameNs": T0 + 0 * STEP,
        "p1": project(model, 0, p1, 0.4, shift), "p2": project(model, 0, p2, 0.4, shift),
    }


# --- S9 validation --------------------------------------------------------------------------


def test_a_valid_v2_package_passes_validation(tmp_path: Path) -> None:
    package = write_v2(tmp_path / "p")

    loaded = rv.load_package(package)

    assert loaded.manifest["captureId"] == "capture-2"
    assert [f.t for f in loaded.frames] == [T0 + i * STEP for i in range(8)]


def _reference(**overrides: Any) -> dict[str, Any]:
    base: dict[str, Any] = {
        "kind": "object", "label": "Puerta", "lengthM": 2.0, "surface": "wall", "frameNs": T0,
        "p1": {"x": 0.3, "y": 0.8}, "p2": {"x": 0.33, "y": 0.12},
    }
    base.update(overrides)
    return base


def _video(**overrides: Any) -> dict[str, Any]:
    video = v2_manifest()["video"]
    video.update(overrides)
    return video


_ROOM = {"id": "room-1", "name": "Estar", "fromNs": T0, "toNs": T0 + 10 * STEP}


@pytest.mark.parametrize(
    "mutation",
    [
        {"schemaVersion": 1},
        {"captureId": ""},
        {"listingId": 5},
        {"device": {"model": "x", "os": "android"}},
        {"video": _video(file="other.mp4")},
        {"video": _video(width=0)},
        {"video": _video(fps=0)},
        {"video": _video(startedAtNs=-1)},
        {"video": _video(framesFile="f.jsonl")},
        {"video": _video(timestampSource="monotonic")},
        {"video": _video(sensorOrientation=45)},
        {"video": _video(sensorOrientation="90")},
        {"video": {k: v for k, v in _video().items() if k != "sensorOrientation"}},
        {"sensors": {"file": "sensors.jsonl"}},
        {"sensors": {"file": "s.jsonl", "rateHz": 100}},
        {"rooms": []},
        {"rooms": [{"id": "r", "name": "A", "fromNs": T0 + 5, "toNs": T0 + 5}]},
        {"rooms": [_ROOM, {**_ROOM, "name": "Otro"}]},
        {"rooms": [_ROOM, {"id": "room-2", "name": "B", "fromNs": T0 + 5 * STEP, "toNs": T0 + 12 * STEP}]},
        {"reference": _reference(kind="tape")},
        {"reference": _reference(label="")},
        {"reference": _reference(lengthM=0)},
        {"reference": _reference(surface="ceiling")},
        {"reference": _reference(p1={"x": 1.2, "y": 0.5})},
        {"reference": _reference(p2={"x": 0.5, "y": -0.1})},
        {"reference": _reference(p2={"x": 0.3, "y": 0.8})},
        {"reference": _reference(frameNs=T0 + 99 * STEP)},
    ],
)
def test_each_schema_2_manifest_rule_is_enforced(tmp_path: Path, mutation: dict[str, Any]) -> None:
    package = write_v2(tmp_path / "p", v2_manifest(**mutation))

    with pytest.raises(reconstruct.InvalidPackage):
        rv.load_package(package)


@pytest.mark.parametrize(
    ("frames", "sensors"),
    [
        ([], []),
        ([{"i": 1, "t": T0}], []),
        ([{"i": 0, "t": T0 + 5}, {"i": 1, "t": T0 + 5}], []),
        ([{"i": 0, "t": "x"}], []),
        (frame_lines(), [{"t": T0 + 9, "type": "gravity", "x": 0, "y": 9.8, "z": 0},
                         {"t": T0 + 1, "type": "gravity", "x": 0, "y": 9.8, "z": 0}]),
        (frame_lines(), [{"t": T0, "type": "light", "x": 0, "y": 0, "z": 0}]),
        (frame_lines(), [{"t": T0, "type": "gravity", "x": "a", "y": 0, "z": 0}]),
    ],
)
def test_frames_and_sensors_files_are_validated(
    tmp_path: Path, frames: list[Any], sensors: list[Any]
) -> None:
    package = write_v2(tmp_path / "p", frames=frames, sensors=sensors)

    with pytest.raises(reconstruct.InvalidPackage):
        rv.load_package(package)


def test_missing_files_and_malformed_lines_are_invalid(tmp_path: Path) -> None:
    package = write_v2(tmp_path / "a")
    (package / "video.mp4").unlink()
    with pytest.raises(reconstruct.InvalidPackage, match="video.mp4"):
        rv.load_package(package)

    package = write_v2(tmp_path / "b")
    (package / "frames.jsonl").write_text("{not json}", encoding="utf-8")
    with pytest.raises(reconstruct.InvalidPackage, match="frames.jsonl"):
        rv.load_package(package)


def test_the_package_size_limit_is_enforced(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    package = write_v2(tmp_path / "p")
    monkeypatch.setattr(rv, "MAX_PACKAGE_BYTES", 10)

    with pytest.raises(reconstruct.InvalidPackage, match="too large"):
        rv.load_package(package)


def test_the_size_limit_is_the_documented_150_mib_and_within_the_zip_guard() -> None:
    assert rv.MAX_PACKAGE_BYTES == 150 * 1024 * 1024
    assert rv.MAX_PACKAGE_BYTES <= reconstruct.MAX_UNCOMPRESSED_BYTES


def test_the_device_to_camera_mapping_follows_the_sensor_orientation() -> None:
    for degrees in (0, 90, 180, 270):
        m = rv.device_to_camera_matrix(degrees)
        assert _mm(m, _t(m)) == ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
    # Portrait phone, stored frame turned 90: the device's "up" (+y) is the stored frame's -x.
    assert _mv(rv.device_to_camera_matrix(90), (0.0, 1.0, 0.0)) == (-1.0, 0.0, 0.0)
    # Unrotated frames: device +y (up) is the image's up, i.e. camera -y.
    assert _mv(rv.device_to_camera_matrix(0), (0.0, 1.0, 0.0)) == (0.0, -1.0, 0.0)
    assert rv.device_to_camera_matrix(90) != rv.device_to_camera_matrix(270)


@pytest.mark.parametrize("orientation", [0, 180, 270])
def test_the_pipeline_uses_the_manifest_sensor_orientation(tmp_path: Path, orientation: int) -> None:
    model = make_model((0.0, 0.0, 4.0, 3.0))
    manifest = v2_manifest(video=_video(sensorOrientation=orientation), reference=floor_reference(model))
    package = write_v2(tmp_path / "p", manifest, sensors=gravity_lines([model], orientation=orientation))

    result = run(package, [model])

    assert wall_lengths(result.scene_draft) == [3.15, 3.15, 4.15, 4.15]
    assert not any("gravedad" in w.lower() and "no coincide" in w for w in result.warnings)


# --- half-open room intervals -----------------------------------------------------------------


def test_room_intervals_are_half_open_and_adjacent_rooms_are_not_an_overlap() -> None:
    rooms = [
        {"id": "a", "name": "A", "fromNs": T0 - 5, "toNs": T0 + 4 * STEP},
        {"id": "b", "name": "B", "fromNs": T0 + 4 * STEP, "toNs": T0 + 7 * STEP + 1},
    ]
    rv.validate_manifest(v2_manifest(rooms=rooms))

    assert rv._room_index_at(rooms, T0) == 0  # the first room starts before the first frame
    assert rv._room_index_at(rooms, T0 + 4 * STEP) == 1  # a frame at toNs belongs to the next room
    assert rv._room_index_at(rooms, T0 + 7 * STEP) == 1  # last toNs = last frame + 1
    assert rv._room_index_at(rooms, T0 + 7 * STEP + 1) is None


def test_the_reference_frame_must_be_listed_in_frames_jsonl(tmp_path: Path) -> None:
    reference = _reference(frameNs=T0 + STEP // 2)  # inside a room, but between two frames
    package = write_v2(tmp_path / "p", v2_manifest(reference=reference))

    with pytest.raises(reconstruct.InvalidPackage, match="frames.jsonl"):
        rv.load_package(package)


def test_mag_samples_are_accepted_and_ignored(tmp_path: Path) -> None:
    model = make_model((0.0, 0.0, 4.0, 3.0))
    noisy = [*gravity_lines([model]), {"t": T0 + 5, "type": "mag", "x": 99.0, "y": -99.0, "z": 7.0}]
    noisy.sort(key=lambda s: s["t"])
    package = write_v2(tmp_path / "p", v2_manifest(reference=floor_reference(model)), sensors=noisy)

    result = run(package, [model])

    assert wall_lengths(result.scene_draft) == [3.15, 3.15, 4.15, 4.15]


# --- gravity vs geometry ------------------------------------------------------------------------


def test_plane_tilt_measures_the_angle_between_the_dominant_plane_and_up() -> None:
    flat = [(x * 0.1, 0.0, z * 0.1) for x in range(10) for z in range(10)]
    angle = math.radians(20)
    tilted = [(x, x * math.tan(angle), z) for x, _, z in flat]

    assert rv.plane_tilt_deg(flat, 0.01) == pytest.approx(0.0, abs=1e-6)
    assert rv.plane_tilt_deg(tilted, 0.01) == pytest.approx(20.0, abs=0.01)


def test_a_gravity_that_disagrees_with_the_floor_warns_but_does_not_fail(tmp_path: Path) -> None:
    model = make_model((0.0, 0.0, 4.0, 3.0))
    # Gravity 25 degrees off the true up, rotated about the SfM x axis.
    a = math.radians(25)
    wrong_up = (0.0, math.sin(a), math.cos(a))
    manifest = v2_manifest(reference=floor_reference(model))
    package = write_v2(tmp_path / "p", manifest, sensors=gravity_lines([model], up_world=wrong_up))

    result = run(package, [model])

    assert any("no coincide con el plano de piso o techo" in w for w in result.warnings)
    assert result.scene_draft["rooms"]


def test_consistent_gravity_does_not_warn(tmp_path: Path) -> None:
    package, model = single_room(tmp_path, reference=floor_reference(make_model((0.0, 0.0, 4.0, 3.0))))

    result = run(package, [model])

    assert not any("no coincide" in w for w in result.warnings)


# --- dispatch by schemaVersion --------------------------------------------------------------


def test_schema_1_packages_never_reach_the_video_path(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    def boom(*_: Any, **__: Any) -> None:
        raise AssertionError("schema 1 must not use the video pipeline")

    monkeypatch.setattr(rv, "reconstruct_video", boom)

    result = reconstruct.reconstruct(write_package(tmp_path / "p", room_package()))

    assert result.scene_draft["version"] == "2.0"
    assert len(result.scene_draft["rooms"]) == 1


def test_schema_1_zip_still_goes_through_reconstruct_path_and_the_cli(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    archive = tmp_path / "package.zip"
    with zipfile.ZipFile(archive, "w") as handle:
        handle.writestr("manifest.json", json.dumps(room_package()))

    result = reconstruct.reconstruct_path(archive)
    code = reconstruct.main([str(archive)])
    printed = json.loads(capsys.readouterr().out)

    assert code == 0
    assert printed["sceneDraft"] == result.scene_draft
    assert printed["warnings"] == result.warnings


@pytest.mark.parametrize("version", [3, 0, "2", 1.5])
def test_unknown_schema_versions_are_rejected_with_a_clear_error(tmp_path: Path, version: Any) -> None:
    package = write_package(tmp_path / "p", room_package(schemaVersion=version))

    with pytest.raises(reconstruct.InvalidPackage, match="unsupported schemaVersion"):
        reconstruct.reconstruct(package)


def test_schema_2_packages_dispatch_to_the_video_pipeline(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    package, model = single_room(tmp_path)
    monkeypatch.setattr(rv, "default_adapters", lambda: (FakeExtractor(), FakeEstimator([model])))

    result = reconstruct.reconstruct_path(package)

    assert len(result.scene_draft["rooms"]) == 1


# --- gravity --------------------------------------------------------------------------------


def test_gravity_gives_up_in_the_sfm_frame_synchronised_through_frames_jsonl() -> None:
    model = make_model((0.0, 0.0, 4.0, 3.0))
    times = {p.frame_index: T0 + p.frame_index * STEP for p in model.poses}
    sensors = [
        rv.SensorSample(s["t"], s["type"], s["x"], s["y"], s["z"]) for s in gravity_lines([model])
    ]

    up, source = rv.estimate_up(model.poses, times, sensors, rv.DEVICE_TO_CAMERA)

    assert source == "gravity"
    assert up == pytest.approx((0.0, 0.0, 1.0), abs=1e-9)


def test_without_gravity_samples_up_falls_back_to_the_cameras() -> None:
    model = make_model((0.0, 0.0, 4.0, 3.0), pitch_deg=0.0)
    times = {p.frame_index: T0 + p.frame_index * STEP for p in model.poses}

    up, source = rv.estimate_up(model.poses, times, [], rv.DEVICE_TO_CAMERA)

    assert source == "cameras"
    assert up == pytest.approx((0.0, 0.0, 1.0), abs=1e-9)


def test_gravity_samples_far_from_every_frame_are_not_used() -> None:
    model = make_model((0.0, 0.0, 4.0, 3.0))
    times = {p.frame_index: T0 + p.frame_index * STEP for p in model.poses}
    far = [rv.SensorSample(T0 + 60 * 10**9, "gravity", 0.0, 9.8, 0.0)]

    assert rv.estimate_up(model.poses, times, far, rv.DEVICE_TO_CAMERA)[1] == "cameras"


# --- planes + metric scale ------------------------------------------------------------------


def test_floor_walls_and_ceiling_are_fitted_and_scaled_by_a_floor_reference(tmp_path: Path) -> None:
    model = make_model((0.0, 0.0, 4.0, 3.0))
    package, _ = single_room(tmp_path, reference=floor_reference(model))

    result = run(package, [model])

    scene = result.scene_draft
    assert wall_lengths(scene) == [3.15, 3.15, 4.15, 4.15]  # centre line = room + wall thickness
    assert {w["height"] for w in scene["walls"]} == {2.5}
    assert {w["heightSource"] for w in scene["walls"]} == {"estimated"}
    assert scene["unit"] == "meters"
    assert not any("Sin medida de referencia" in w for w in result.warnings)


def test_the_reference_on_a_wall_intersects_the_fitted_wall_plane(tmp_path: Path) -> None:
    model = make_model((0.0, 0.0, 4.0, 3.0), pitch_deg=0.0)
    p1, p2 = (1.0, 0.5, 0.0), (1.0, 2.0, 0.0)
    reference = {
        "kind": "object", "label": "Marco", "lengthM": 1.5, "surface": "wall", "frameNs": T0 + 5 * STEP,
        "p1": project(model, 5, p1, 0.4, (3.0, -2.0, 5.0)),
        "p2": project(model, 5, p2, 0.4, (3.0, -2.0, 5.0)),
    }
    package = write_v2(tmp_path / "p", v2_manifest(reference=reference), sensors=gravity_lines([model]))

    result = run(package, [model])

    assert wall_lengths(result.scene_draft) == [3.15, 3.15, 4.15, 4.15]


def test_with_a_reference_the_scene_is_marked_metric(tmp_path: Path) -> None:
    model = make_model((0.0, 0.0, 4.0, 3.0))
    package = write_v2(tmp_path / "p", v2_manifest(reference=floor_reference(model)), sensors=gravity_lines([model]))

    result = run(package, [model])

    assert result.scene_draft["scale"] == {"mode": "metric"}


def test_without_a_reference_the_model_is_flagged_as_unscaled(tmp_path: Path) -> None:
    package, model = single_room(tmp_path)

    result = run(package, [model])

    assert any(w.startswith("Sin medida de referencia: el plano es proporcional") for w in result.warnings)
    assert result.scene_draft["scale"] == {"mode": "proportional"}
    # Nothing metric was applied: the 4x3 room is brought to a nominal 5-unit long side with one
    # factor, so the short side is 3/4 of it (plus the fixed wall thickness).
    assert wall_lengths(result.scene_draft)[0] == pytest.approx(3.75 + 0.15, abs=0.02)


def test_a_reference_that_misses_the_plane_is_reported_and_not_applied(tmp_path: Path) -> None:
    model = make_model((0.0, 0.0, 4.0, 3.0), pitch_deg=0.0)
    reference = {
        "kind": "object", "label": "Alfombra", "lengthM": 1.0, "surface": "floor", "frameNs": T0,
        "p1": {"x": 0.5, "y": 0.5},  # the optical axis is horizontal: it never reaches the floor
        "p2": {"x": 0.5, "y": 0.9},
    }
    package = write_v2(tmp_path / "p", v2_manifest(reference=reference), sensors=gravity_lines([model]))

    result = run(package, [model])

    assert any("referencia" in w and "no pudo ubicarse" in w for w in result.warnings)
    assert any(w.startswith("Sin medida de referencia") for w in result.warnings)


def test_missing_gravity_is_flagged(tmp_path: Path) -> None:
    model = make_model((0.0, 0.0, 4.0, 3.0), pitch_deg=0.0)
    package = write_v2(tmp_path / "p", sensors=gravity_lines([model], with_gravity=False))

    result = run(package, [model])

    assert any(w.startswith("Gravedad no disponible: no se distinguió piso de techo") for w in result.warnings)
    assert len(result.scene_draft["walls"]) == 4


def test_an_unobserved_wall_is_flagged_with_its_corners(tmp_path: Path) -> None:
    model = make_model((0.0, 0.0, 4.0, 3.0), skip_walls=("e",))
    package = write_v2(tmp_path / "p", v2_manifest(reference=floor_reference(model)),
                       sensors=gravity_lines([model]))

    result = run(package, [model])

    assert any(w.startswith("Pared sin observar entre") and "Estar" in w for w in result.warnings)


def test_a_missing_ceiling_gives_an_assumed_height(tmp_path: Path) -> None:
    model = make_model((0.0, 0.0, 4.0, 3.0), ceiling=False)
    package = write_v2(tmp_path / "p", v2_manifest(reference=floor_reference(model)),
                       sensors=gravity_lines([model]))

    result = run(package, [model])

    assert {w["heightSource"] for w in result.scene_draft["walls"]} == {"assumed"}
    assert {w["height"] for w in result.scene_draft["walls"]} == {reconstruct.ASSUMED_ROOM_HEIGHT_M}
    assert any("supuesta" in w for w in result.warnings)


def test_a_split_reconstruction_stays_proportional_when_the_reference_reaches_one_piece(tmp_path: Path) -> None:
    first = make_model((0.0, 0.0, 4.0, 3.0))
    second = make_model((0.0, 0.0, 3.0, 3.0), first_frame=8, scale=0.7, shift=(-4.0, 1.0, 2.0))
    manifest = v2_manifest(
        rooms=[
            {"id": "room-1", "name": "Estar", "fromNs": T0, "toNs": T0 + 8 * STEP},
            {"id": "room-2", "name": "Cuarto", "fromNs": T0 + 8 * STEP, "toNs": T0 + 20 * STEP},
        ],
        reference=floor_reference(first),
    )
    package = write_v2(tmp_path / "p", manifest, frames=frame_lines(16),
                       sensors=gravity_lines([first, second]))

    result = run(package, [first, second])

    scene = result.scene_draft
    assert [r["name"] for r in scene["rooms"]] == ["Estar", "Cuarto"]
    assert any("partida en 2 piezas" in w for w in result.warnings)
    # One scale for the whole walkthrough: a reference that reaches only one piece is not applied.
    assert scene["scale"] == {"mode": "proportional"}
    assert any("solo pudo aplicarse a una parte de las piezas" in w for w in result.warnings)
    assert not any(w.startswith("Sin medida de referencia") for w in result.warnings)


def test_every_result_declares_the_measures_as_estimates_and_stays_within_the_warning_cap(
    tmp_path: Path,
) -> None:
    package, model = single_room(tmp_path)

    result = run(package, [model])

    assert any("estimad" in w and "no se midió" in w for w in result.warnings)
    assert all(len(w) <= 500 for w in result.warnings)
    assert len(result.warnings) <= 200
    assert result.volume_views == []
    assert result.scene_draft["objects"] == []


def test_a_room_that_cannot_close_a_contour_is_dropped_with_a_warning(tmp_path: Path) -> None:
    model = make_model((0.0, 0.0, 4.0, 3.0), skip_walls=("e", "s", "w"))
    package = write_v2(tmp_path / "p", v2_manifest(reference=floor_reference(model)),
                       sensors=gravity_lines([model]))

    with pytest.raises(reconstruct.InvalidPackage, match="ningún ambiente"):
        run(package, [model])


def test_the_extractor_is_asked_for_a_stride_of_frames_plus_the_reference_frame(tmp_path: Path) -> None:
    model = make_model((0.0, 0.0, 4.0, 3.0))
    reference = floor_reference(model)
    reference["frameNs"] = T0 + 5 * STEP
    reference["p1"] = project(model, 5, (2.0, 0.0, 1.0), 0.4, (3.0, -2.0, 5.0))
    reference["p2"] = project(model, 5, (2.3, 0.0, 1.0), 0.4, (3.0, -2.0, 5.0))
    package = write_v2(tmp_path / "p", v2_manifest(reference=reference), sensors=gravity_lines([model]))
    extractor = FakeExtractor()

    run(package, [model], extractor)

    assert extractor.calls == [[0, 3, 5, 6]]  # 10 fps -> every 3rd frame, plus frame 5


# --- scene v2 gate ---------------------------------------------------------------------------


def test_the_draft_passes_the_scene_v2_gate_of_the_api(tmp_path: Path) -> None:
    pytest.importorskip("pydantic")
    backend = WORKER3D_DIR.parent / "backend"
    sys.path.insert(0, str(backend))
    try:
        from app.modules.catalog.schemas import ListingSceneDocument
        from app.modules.catalog.service import validate_scene_integrity
    finally:
        sys.path.remove(str(backend))
    model = make_model((0.0, 0.0, 4.0, 3.0))
    package, _ = single_room(tmp_path, reference=floor_reference(model))

    result = run(package, [model])

    validate_scene_integrity(ListingSceneDocument.model_validate(result.scene_draft))


# --- external tools --------------------------------------------------------------------------


def test_a_missing_ffmpeg_gives_a_clear_error(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(rv.shutil, "which", lambda _name: None)

    with pytest.raises(reconstruct.ExternalToolMissing, match="ffmpeg"):
        rv.FfmpegFrameExtractor().extract(tmp_path / "video.mp4", [0], tmp_path)


def test_a_missing_pycolmap_gives_a_clear_error(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setitem(sys.modules, "pycolmap", None)  # makes `import pycolmap` raise ImportError

    with pytest.raises(reconstruct.ExternalToolMissing, match="pycolmap"):
        rv.PycolmapPoseEstimator().estimate([rv.ExtractedFrame(0, tmp_path / "a.jpg")], tmp_path)


def test_ffmpeg_is_invoked_without_audio_or_autorotation_and_frames_are_mapped_by_index(
    tmp_path: Path,
) -> None:
    calls: list[list[str]] = []

    def runner(command: list[str], **_: Any) -> Any:
        calls.append(command)
        out = Path(command[-1]).parent
        for k in range(3):
            (out / f"{k + 1:06d}.jpg").write_bytes(b"jpg")
        return type("Done", (), {"returncode": 0, "stderr": b""})()

    extractor = rv.FfmpegFrameExtractor(which=lambda _n: "ffmpeg", runner=runner)
    frames = extractor.extract(tmp_path / "video.mp4", [0, 10, 25], tmp_path)

    assert [f.index for f in frames] == [0, 10, 25]
    assert all(f.path.is_file() for f in frames)
    assert "-noautorotate" in calls[0] and "-an" in calls[0]


def test_ffmpeg_input_is_restricted_to_local_files_and_the_mp4_demuxer(tmp_path: Path) -> None:
    calls: list[list[str]] = []

    def runner(command: list[str], **_: Any) -> Any:
        calls.append(command)
        out = Path(command[-1]).parent
        (out / "000001.jpg").write_bytes(b"jpg")
        return type("Done", (), {"returncode": 0, "stderr": b""})()

    rv.FfmpegFrameExtractor(which=lambda _n: "ffmpeg", runner=runner).extract(
        tmp_path / "video.mp4", [0], tmp_path
    )

    command = calls[0]
    at = command.index("-i")
    assert command[command.index("-protocol_whitelist") + 1] == "file"
    assert command.index("-protocol_whitelist") < at
    assert command[command.index("-f") + 1] == "mov"  # the MP4 family demuxer
    assert command.index("-f") < at


def test_fewer_decoded_frames_than_requested_is_a_retryable_runtime_error(tmp_path: Path) -> None:
    def runner(command: list[str], **_: Any) -> Any:
        out = Path(command[-1]).parent
        for k in range(2):
            (out / f"{k + 1:06d}.jpg").write_bytes(b"jpg")
        return type("Done", (), {"returncode": 0, "stderr": b""})()

    extractor = rv.FfmpegFrameExtractor(which=lambda _n: "ffmpeg", runner=runner)

    with pytest.raises(RuntimeError, match="2 of 3") as info:
        extractor.extract(tmp_path / "video.mp4", [0, 10, 25], tmp_path)
    assert not isinstance(info.value, reconstruct.InvalidPackage)


def test_a_failing_ffmpeg_is_a_retryable_runtime_error(tmp_path: Path) -> None:
    def runner(command: list[str], **_: Any) -> Any:
        return type("Done", (), {"returncode": 1, "stderr": b"boom"})()

    extractor = rv.FfmpegFrameExtractor(which=lambda _n: "ffmpeg", runner=runner)

    with pytest.raises(RuntimeError, match="ffmpeg failed") as info:
        extractor.extract(tmp_path / "video.mp4", [0], tmp_path)
    assert not isinstance(info.value, reconstruct.InvalidPackage)


def test_the_cli_reports_a_missing_tool_without_a_traceback(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    package = write_v2(tmp_path / "p")
    monkeypatch.setattr(rv.shutil, "which", lambda _name: None)

    code = reconstruct.main([str(package)])

    assert code == 1
    assert "ffmpeg" in capsys.readouterr().err


# --- job worker wiring -----------------------------------------------------------------------


def _v2_zip(package: Path) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as handle:
        for name in ("manifest.json", "video.mp4", "frames.jsonl", "sensors.jsonl"):
            handle.write(package / name, name)
    return buffer.getvalue()


def test_a_claimed_schema_2_job_runs_the_video_path(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    import reconstruction_worker
    from test_reconstruction_worker import FakeHttpClient, FakeQueue, _worker

    model = make_model((0.0, 0.0, 4.0, 3.0))
    package, _ = single_room(tmp_path, reference=floor_reference(model))
    monkeypatch.setattr(rv, "default_adapters", lambda: (FakeExtractor(), FakeEstimator([model])))
    http, queue = FakeHttpClient(package=_v2_zip(package)), FakeQueue()

    assert _worker(http, queue).run_once() is True

    url, _, body = http.posts[1]
    assert url.endswith("/complete")
    assert body is not None
    assert set(body) == {"sceneDraft", "warnings"}  # no volumeSuggestions: no furniture here (T6)
    assert len(body["sceneDraft"]["rooms"]) == 1
    assert len(body["warnings"]) <= reconstruction_worker.MAX_WARNINGS
    assert len(queue.deleted) == 1


def test_a_schema_2_job_with_a_missing_tool_is_retryable_not_invalid(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    from test_reconstruction_worker import FakeHttpClient, FakeQueue, _worker

    package = write_v2(tmp_path / "p")
    monkeypatch.setattr(rv.shutil, "which", lambda _name: None)
    http, queue = FakeHttpClient(package=_v2_zip(package)), FakeQueue()

    _worker(http, queue).run_once()

    url, _, body = http.posts[1]
    assert url.endswith("/fail")
    assert body is not None
    assert body["retryable"] is True
    assert "ExternalToolMissing" in body["reason"]


def test_a_schema_1_job_is_unchanged_by_the_video_path(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    from test_reconstruction_worker import FakeHttpClient, FakeQueue, _worker

    monkeypatch.setattr(rv, "default_adapters", lambda: (_ for _ in ()).throw(AssertionError("v1")))
    http, queue = FakeHttpClient(), FakeQueue()

    _worker(http, queue).run_once()

    _, _, body = http.posts[1]
    assert body is not None
    assert body["sceneDraft"]["version"] == "2.0"
