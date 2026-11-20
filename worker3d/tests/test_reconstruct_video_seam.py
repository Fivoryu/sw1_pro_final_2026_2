"""Seam regressions: packages shaped like the capture app's writer output (compact JSON,
Java-style doubles, merged sorted sensors) and error-reporting rules of the schema 2 reader."""

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
import test_reconstruct_video as T

BASE = 5_123_456_789_012_345
STEP = 33_366_666
SHIFT = (3.0, -2.0, 5.0)
Row = tuple[int, str, float, float, float]


def java_double(v: float) -> str:
    """Kotlin/Java ``Double.toString`` style: ``0.0``, ``-0.0``, ``1.0E-4``, ``1.0E7``."""
    if v == 0:
        return "-0.0" if math.copysign(1.0, v) < 0 else "0.0"
    if abs(v) < 1e-3 or abs(v) >= 1e7:
        mantissa, exponent = f"{v:.6e}".split("e")
        mantissa = mantissa.rstrip("0")
        mantissa = mantissa + "0" if mantissa.endswith(".") else mantissa
        return f"{mantissa}E{int(exponent)}"
    return repr(float(v))


def manifest_text(
    rooms: list[tuple[str, str, int, int]],
    reference: dict[str, Any] | None,
    *,
    started: int = BASE,
    orientation: int = 90,
    source: str = "realtime",
) -> str:
    manifest: dict[str, Any] = {
        "schemaVersion": 2, "captureId": "c-1", "listingId": "listing-1",
        "device": {"model": "SM-S711B", "os": "android", "osVersion": "14"},
        "video": {
            "file": "video.mp4", "width": 1280, "height": 720, "fps": 30, "startedAtNs": started,
            "framesFile": "frames.jsonl", "timestampSource": source, "sensorOrientation": orientation,
        },
        "sensors": {"file": "sensors.jsonl", "rateHz": 100},
        "rooms": [{"id": i, "name": n, "fromNs": a, "toNs": b} for i, n, a, b in rooms],
    }  # fmt: skip
    if reference:
        manifest["reference"] = reference
    return json.dumps(manifest, separators=(",", ":"))


def frames_text(count: int) -> str:
    return "".join(f'{{"i":{i},"t":{BASE + i * STEP}}}\n' for i in range(count))


def sensors_text(models: list[rv.SparseModel]) -> str:
    matrix = rv.device_to_camera_matrix(90)
    up_s = T._mv(T.ROT, T.UP)
    rows: list[Row] = []
    for model in models:
        for pose in model.poses:
            t = BASE + pose.frame_index * STEP
            g = T._mv(T._t(matrix), T._mv(T._t(pose.rotation), up_s))
            rows += [
                (t - 500, "gyro", 1e-4, -0.0, 0.02),
                (t + 300, "accel", 0.1, 9.7, 0.3),
                (t + 1000, "gravity", 9.81 * g[0], 9.81 * g[1], 9.81 * g[2]),
                (t + 1200, "mag", 20.5, -3.1, 40.0),
            ]
    rows.sort(key=lambda r: r[0])
    return "".join(
        f'{{"t":{t},"type":"{k}","x":{java_double(x)},"y":{java_double(y)},"z":{java_double(z)}}}\n'
        for t, k, x, y, z in rows
    )


def write(directory: Path, manifest: str, frames: str, sensors: str) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "manifest.json").write_text(manifest, encoding="utf-8")
    (directory / "frames.jsonl").write_text(frames, encoding="utf-8")
    (directory / "sensors.jsonl").write_text(sensors, encoding="utf-8")
    (directory / "video.mp4").write_bytes(b"\0")
    return directory


def go(directory: Path, models: list[rv.SparseModel]) -> reconstruct.ReconstructionResult:
    return rv.reconstruct_video(
        directory, extractor=T.FakeExtractor(), estimator=T.FakeEstimator(models)
    )


def floor_ref(model: rv.SparseModel, frame: int, p1: Any, p2: Any) -> dict[str, Any]:
    return {
        "kind": "object", "label": "Alfombra", "lengthM": round(math.dist(p1, p2), 6),
        "surface": "floor", "frameNs": BASE + frame * STEP,
        "p1": T.project(model, frame, p1, 0.4, SHIFT), "p2": T.project(model, frame, p2, 0.4, SHIFT),
    }  # fmt: skip


def one_room(last_frame: int = 11) -> list[tuple[str, str, int, int]]:
    return [("room-1", "A", BASE - 5, BASE + last_frame * STEP + 1)]


# --- error reporting ------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("old", "new", "expected"),
    [
        ('"sensorOrientation":90', '"sensorOrientation":45', "sensorOrientation"),
        ('"listingId":"listing-1"', '"listingId":null', "listingId"),
    ],
)
def test_validation_failures_keep_their_own_message(
    tmp_path: Path, old: str, new: str, expected: str
) -> None:
    text = manifest_text(one_room(), None).replace(old, new)
    package = write(tmp_path / "p", text, frames_text(12), "")

    with pytest.raises(reconstruct.InvalidPackage) as info:
        rv.load_package(package)

    assert expected in str(info.value)
    assert "not valid JSON" not in str(info.value)


def test_an_infinite_reference_length_keeps_its_own_message(tmp_path: Path) -> None:
    model = T.make_model((0.0, 0.0, 4.0, 3.0))
    ref = floor_ref(model, 0, (1.9, 0.0, 1.3), (2.4, 0.0, 1.9))
    text = manifest_text(one_room(), dict(ref, lengthM=1)).replace('"lengthM":1', '"lengthM":Infinity')
    package = write(tmp_path / "p", text, frames_text(12), "")

    with pytest.raises(reconstruct.InvalidPackage, match="lengthM"):
        rv.load_package(package)


def test_a_manifest_that_is_not_json_is_still_reported_as_such(tmp_path: Path) -> None:
    package = write(tmp_path / "p", "{nope", frames_text(2), "")

    with pytest.raises(reconstruct.InvalidPackage, match="not valid JSON"):
        rv.load_package(package)


@pytest.mark.parametrize("target", ["sensors.jsonl", "frames.jsonl"])
def test_a_deeply_nested_jsonl_line_is_an_invalid_package_not_a_crash(
    tmp_path: Path, target: str
) -> None:
    package = write(tmp_path / "p", manifest_text(one_room(), None), frames_text(12), "")
    (package / target).write_text("[" * 200_000 + "\n", encoding="utf-8")

    with pytest.raises(reconstruct.InvalidPackage, match=target):
        rv.load_package(package)


# --- packages shaped like the writer's output -------------------------------------------------


def test_writer_shaped_package_with_a_floor_reference_reconstructs(tmp_path: Path) -> None:
    model = T.make_model((0.0, 0.0, 4.0, 3.0))
    ref = floor_ref(model, 0, (1.9, 0.0, 1.3), (2.4, 0.0, 1.9))
    # startedAtNs is earlier than the first frame; the room starts before it too.
    rooms = [("room-1", "Ambiente 1", BASE - 5_000_000, BASE + 11 * STEP + 1)]
    package = write(
        tmp_path / "p",
        manifest_text(rooms, ref, started=BASE - 5_000_000),
        frames_text(12),
        sensors_text([model]),
    )

    result = go(package, [model])

    assert T.wall_lengths(result.scene_draft) == [3.15, 3.15, 4.15, 4.15]
    assert not any(w.startswith("Sin medida de referencia") for w in result.warnings)


def test_java_style_doubles_parse_in_sensor_lines(tmp_path: Path) -> None:
    line = '{"t":1,"type":"gyro","x":1.0E-4,"y":-0.0,"z":1.0E7}\n'
    package = write(tmp_path / "p", manifest_text(one_room(), None), frames_text(12), line)

    sample = rv.load_package(package).sensors[0]

    assert (sample.x, sample.z) == (1.0e-4, 1.0e7)
    assert math.copysign(1.0, sample.y) < 0


def test_a_reference_on_the_last_frame_inside_the_last_room(tmp_path: Path) -> None:
    model = T.make_model((0.0, 0.0, 4.0, 3.0))
    ref = floor_ref(model, 7, (2.2, 0.0, 1.3), (2.6, 0.0, 1.7))
    package = write(
        tmp_path / "p", manifest_text(one_room(7), ref), frames_text(8), sensors_text([model])
    )

    result = go(package, [model])

    assert T.wall_lengths(result.scene_draft) == [3.15, 3.15, 4.15, 4.15]


def test_two_rooms_whose_boundary_is_a_frame_timestamp(tmp_path: Path) -> None:
    first = T.make_model((0.0, 0.0, 4.0, 3.0))
    second = T.make_model((0.0, 0.0, 3.0, 3.0), first_frame=8, shift=(10.0, -2.0, 5.0))
    boundary = BASE + 8 * STEP
    rooms = [
        ("room-1", "Ambiente 1", BASE - 5, boundary),
        ("room-2", "Ambiente 2", boundary, BASE + 15 * STEP + 1),
    ]
    package = write(
        tmp_path / "p", manifest_text(rooms, None), frames_text(16), sensors_text([first, second])
    )

    result = go(package, [first, second])

    assert [r["name"] for r in result.scene_draft["rooms"]] == ["Ambiente 1", "Ambiente 2"]


def test_an_unknown_timestamp_source_is_flagged_and_still_reconstructs(tmp_path: Path) -> None:
    model = T.make_model((0.0, 0.0, 4.0, 3.0))
    package = write(
        tmp_path / "p",
        manifest_text(one_room(), None, source="unknown"),
        frames_text(12),
        sensors_text([model]),
    )

    result = go(package, [model])

    assert any("marca de tiempo" in w for w in result.warnings)
    assert result.scene_draft["rooms"]


def test_unordered_sensors_are_rejected(tmp_path: Path) -> None:
    model = T.make_model((0.0, 0.0, 4.0, 3.0))
    rows = sensors_text([model]).splitlines(keepends=True)
    rows[0], rows[5] = rows[5], rows[0]
    package = write(tmp_path / "p", manifest_text(one_room(), None), frames_text(12), "".join(rows))

    with pytest.raises(reconstruct.InvalidPackage, match="ordered by t"):
        rv.load_package(package)


def test_a_zip_entry_that_escapes_the_folder_is_rejected(tmp_path: Path) -> None:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as handle:
        handle.writestr("../evil.txt", "x")
        handle.writestr("manifest.json", "{}")
    archive = tmp_path / "evil.zip"
    archive.write_bytes(buffer.getvalue())

    with pytest.raises(reconstruct.InvalidPackage, match="escapes"):
        reconstruct.extract_package(archive, tmp_path / "out")
    assert not (tmp_path / "evil.txt").exists()
