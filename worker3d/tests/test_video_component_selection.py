"""Component merit and reference evidence; synthetic geometry, no native dependencies."""
from __future__ import annotations

import json
import logging
import sqlite3
from dataclasses import replace
from pathlib import Path

import pytest
import reconstruct_video as rv
import test_reconstruct_video as T
import test_reconstruct_video_rect as R


@pytest.mark.parametrize("outside", [False, True])
def test_selected_contour_without_inside_cameras_warns_without_inventing_rejection(
    tmp_path: Path, caplog: pytest.LogCaptureFixture, outside: bool,
) -> None:
    caplog.set_level(logging.INFO, logger=rv.__name__)
    model = T.make_model((0.0, 0.0, 4.0, 3.0))
    if outside:
        offset = T._mv(T.ROT, (40.0, 0.0, 0.0))
        model = replace(model, poses=[replace(p, center=(
            p.center[0] + offset[0], p.center[1] + offset[1], p.center[2] + offset[2],
        )) for p in model.poses])
    package = T.write_v2(tmp_path / "p", T.v2_manifest(), sensors=T.gravity_lines([model]))
    result = T.run(package, [model])
    assert len(result.scene_draft["walls"]) >= 3
    assert result.scene_draft["unit"] == "arbitrary"
    assert any(w.startswith("GEOMETRY_CAMERA_SUPPORT_MISSING:") for w in result.warnings) is outside
    assert diagnostics(caplog)["selected_rooms_without_inside_cameras"] == int(outside)


def diagnostics(caplog: pytest.LogCaptureFixture) -> dict:
    records = [r for r in caplog.records if r.message.startswith("F07 reconstruction diagnostic:")]
    assert len(records) == 1
    return json.loads(records[0].message.split(": ", 1)[1])


def test_best_observed_room_wins_independently_of_mapper_order(tmp_path: Path) -> None:
    incomplete = T.make_model((0.0, 0.0, 4.0, 3.0), skip_walls=("e",))
    complete = T.make_model((0.0, 0.0, 4.0, 3.0))
    package = T.write_v2(tmp_path / "p", T.v2_manifest(), sensors=T.gravity_lines([complete]))
    results = [T.run(package, order) for order in ([incomplete, complete], [complete, incomplete])]
    assert results[0].scene_draft == results[1].scene_draft
    for result in results:
        assert len(result.scene_draft["walls"]) == 4
        assert not any("Pared sin observar" in w for w in result.warnings)
        assert result.scene_draft["measurement"]["alignment"] == "disconnected"
        assert result.scene_draft["unit"] == "arbitrary"


def test_missing_reference_pose_is_not_reported_as_missing_support_plane(
    tmp_path: Path, caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.INFO, logger=rv.__name__)
    origin = T.make_model((0.0, 0.0, 4.0, 3.0))
    model = T.make_model((0.0, 0.0, 4.0, 3.0), first_frame=1)
    package = T.write_v2(tmp_path / "p", T.v2_manifest(reference=T.floor_reference(origin)),
                         sensors=T.gravity_lines([model]))
    result = T.run(package, [model])
    assert result.scene_draft["unit"] == "arbitrary"
    assert any(w.startswith("REFERENCE_FRAME_NOT_REGISTERED:") for w in result.warnings)
    assert not any(w.startswith("REFERENCE_SUPPORT_PLANE_MISSING:") for w in result.warnings)
    record = diagnostics(caplog)
    assert record["reference_outcome"] == "FRAME_NOT_REGISTERED"
    assert record["reference_pose_registered"] is False
    assert record["reference_registration_reason"] == "ADAPTER_DETAILS_UNAVAILABLE"
    assert record["output_acceptable"] is None


@pytest.mark.parametrize("inconsistent", [False, True])
def test_reference_applied_and_inconsistent_are_distinct_and_never_bypass_scale(
    tmp_path: Path, caplog: pytest.LogCaptureFixture, inconsistent: bool,
) -> None:
    caplog.set_level(logging.INFO, logger=rv.__name__)
    model = T.make_model((0.0, 0.0, 4.0, 3.0))
    reference = R.rect_reference(model, height_m=0.45 if inconsistent else 0.3)
    result = R.run_rect(tmp_path, reference, corner_refiner=lambda _p, corners: corners)
    record = diagnostics(caplog)
    assert record["reference_pose_registered"] is True
    assert record["reference_support"] is True
    assert record["reference_outcome"] == ("RECT_INCONSISTENT" if inconsistent else "REFERENCE_APPLIED")
    assert record["reference_applied"] is (not inconsistent)
    assert result.scene_draft["unit"] == ("arbitrary" if inconsistent else "meters")
    assert record["output_acceptable"] is None


def test_completed_draft_emits_one_small_private_safe_record(tmp_path: Path, caplog: pytest.LogCaptureFixture) -> None:
    caplog.set_level(logging.INFO, logger=rv.__name__)
    package, model = T.single_room(tmp_path)
    result = T.run(package, [model])
    record = diagnostics(caplog)
    assert record["outcome"] == "completed_draft"
    assert record["poses_unique"] == 8
    assert record["frames_extracted"] == record["frames_selected"]
    assert record["verified_matches"] is None  # A fake adapter cannot supply native evidence.
    assert record["selected_inferred_edges"] == 0
    assert record["selected_observed_edges"] == 4
    assert all(v >= 0 for v in record["stage_durations"].values())
    assert record["output_metric"] is False
    assert result.scene_draft["measurement"]["scale"] == "unscaled"
    text = json.dumps(record)
    for private in ["capture-2", "listing-1", str(package), "signed", "token"]:
        assert private not in text
    def keys(value: object) -> set[str]:
        if isinstance(value, dict):
            return set(value) | {key for item in value.values() for key in keys(item)}
        if isinstance(value, list):
            return {key for item in value for key in keys(item)}
        return set()
    assert keys(record).isdisjoint({"center", "rotation", "xyz", "corners", "image", "frame_stats"})


def test_failed_validation_emits_single_record_without_exception_text(
    tmp_path: Path, caplog: pytest.LogCaptureFixture,
) -> None:
    with pytest.raises(rv.InvalidPackage):
        T.run(tmp_path / "private-path", [])
    record = diagnostics(caplog)
    assert record["outcome"] == "failed"
    assert record["frames_validated"] == 0
    assert "private-path" not in json.dumps(record)


def test_matching_summary_maps_reference_by_filename_not_database_image_id(tmp_path: Path) -> None:
    path = tmp_path / "database.db"
    with sqlite3.connect(path) as db:
        db.executescript("CREATE TABLE images(image_id INTEGER,name TEXT);"
                         "CREATE TABLE keypoints(image_id INTEGER,rows INTEGER);"
                         "CREATE TABLE two_view_geometries(pair_id INTEGER,rows INTEGER);")
        db.executemany("INSERT INTO images VALUES(?,?)", [(2, "first.jpg"), (1, "second.jpg"), (3, "third.jpg")])
        db.executemany("INSERT INTO keypoints VALUES(?,?)", [(2, 93), (1, 650), (3, 700)])
        db.executemany("INSERT INTO two_view_geometries VALUES(?,?)", [(2147483647 + 2, 0), (2147483647 + 3, 40)])
    result = rv._matching_diagnostics(path, {"first.jpg": 0, "second.jpg": 15, "third.jpg": 30})
    assert result["verified_matches"] == 1
    assert result["verified_inliers"] == 40
    assert result["frame_stats"]["0"] == {"features": 93, "verified_pairs": 0, "inliers": 0}
    assert result["frame_stats"]["15"]["verified_pairs"] == 1
    assert "first.jpg" not in json.dumps(result)


@pytest.mark.parametrize(("features", "pairs", "reason"), [
    (0, 0, "NO_FEATURES"), (93, 0, "NO_VERIFIED_MATCHES"),
    (93, 2, "MAPPER_DID_NOT_REGISTER_VERIFIED_FRAME"),
])
def test_unregistered_reference_reason_uses_native_evidence_only(
    tmp_path: Path, caplog: pytest.LogCaptureFixture, features: int, pairs: int, reason: str,
) -> None:
    caplog.set_level(logging.INFO, logger=rv.__name__)
    origin = T.make_model((0.0, 0.0, 4.0, 3.0))
    model = T.make_model((0.0, 0.0, 4.0, 3.0), first_frame=1)
    estimator = T.FakeEstimator([model])
    # The native adapter sidecar is injected; no geometry or metric acceptance is changed.
    class InstrumentedEstimator:
        def __init__(self) -> None:
            self.diagnostics = {"frame_stats": {"0": {"features": features, "verified_pairs": pairs, "inliers": pairs * 20}}}

        def estimate(self, frames: list[rv.ExtractedFrame], work_dir: Path) -> list[rv.SparseModel]:
            return estimator.estimate(frames, work_dir)

    package = T.write_v2(tmp_path / "p", T.v2_manifest(reference=T.floor_reference(origin)),
                         sensors=T.gravity_lines([model]))
    result = rv.reconstruct_video(package, extractor=T.FakeExtractor(), estimator=InstrumentedEstimator())
    assert result.scene_draft["unit"] == "arbitrary"
    assert diagnostics(caplog)["reference_registration_reason"] == reason


def test_one_scaled_piece_does_not_hide_another_inconsistent_reference(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.INFO, logger=rv.__name__)
    model = T.make_model((0.0, 0.0, 4.0, 3.0))
    estimates = iter([(2.5, False), (2.5, True)])
    monkeypatch.setattr(rv, "rect_scale", lambda *_: next(estimates))
    package = T.write_v2(tmp_path / "p", T.v2_manifest(reference=R.rect_reference(model)),
                         sensors=T.gravity_lines([model]))
    result = T.run(package, [model, model])
    assert rv.WARNING_RECT_INCONSISTENT in result.warnings
    assert result.scene_draft["unit"] == "arbitrary"
    assert result.scene_draft["measurement"]["alignment"] == "disconnected"
    assert {p["reference_outcome"] for p in diagnostics(caplog)["components"]} == {
        "REFERENCE_APPLIED", "RECT_INCONSISTENT",
    }
