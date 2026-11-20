"""F07 synthetic bench (S1, S2): known geometry in, error figures out, deterministic and tunable.

The bench never hands the reconstructor the true dimensions; they only live in the generated
case and are compared with the scene afterwards. Its figures say how well the geometry and the
fusion logic recover a known room, not how the model or the phone behave on a real recording.
"""

from __future__ import annotations

import json
from pathlib import Path

import bench_synthetic as bench
import opening_placement
import openings
import pytest


def run(**options):
    return bench.run_bench(bench.BenchConfig(**options))


def test_the_same_seed_gives_the_same_report() -> None:
    assert run(cases=3, seed=3) == run(cases=3, seed=3)


def test_another_seed_gives_other_cases() -> None:
    assert run(cases=3, seed=3)["cases"] != run(cases=3, seed=4)["cases"]


def test_cases_are_generated_with_their_truth_and_never_exceed_the_requested_count() -> None:
    cases = bench.make_cases(6, seed=1)

    assert len(cases) == 6
    assert all(case.door_width > 0 and case.door_center - case.door_width / 2 > 0 for case in cases)
    assert all(case.door_center + case.door_width / 2 < case.db for case in cases)


def test_without_noise_the_scene_recovers_the_room_proportions_and_the_door() -> None:
    report = run(cases=8, seed=1)
    summary = report["summary"]

    assert summary["failed"] == 0
    assert summary["ratio_err"]["max"] < 0.1
    assert summary["area_ratio_err"]["max"] < 0.2
    assert summary["missed"] == 0
    assert summary["spurious"] == 0
    assert summary["duplicates"] == 0  # the wall two rooms share is welded: a shared door is one door
    assert summary["opening_position_err"]["max"] < 0.05
    assert summary["opening_width_err"]["max"] < 0.02
    # The detector's box is a bounding box: its fit must not leave a bias in the height (it was ~0.05).
    assert summary["opening_height_err"]["max"] < 0.02


def test_a_lookalike_never_becomes_an_opening_with_the_default_thresholds() -> None:
    report = run(cases=6, seed=2, decoys=True)

    assert report["summary"]["decoys"] > 0
    assert report["summary"]["spurious"] == 0


def test_overriding_a_threshold_changes_the_outcome_and_is_undone_afterwards() -> None:
    margin = openings.MIN_MARGIN

    loose = run(cases=6, seed=2, decoys=True, overrides=["openings.MIN_MARGIN=0.0"])

    assert loose["summary"]["spurious"] > 0
    assert openings.MIN_MARGIN == margin
    assert run(cases=6, seed=2, decoys=True)["summary"]["spurious"] == 0


def test_without_welding_the_shared_door_is_reported_by_each_room() -> None:
    welded = run(cases=5, seed=1)["summary"]
    apart = run(cases=5, seed=1, overrides=["reconstruct_video.SNAP_SHARED_WALLS=False"])["summary"]

    assert welded["duplicates"] == 0
    assert apart["duplicates"] > 0


def test_a_placement_constant_can_be_overridden_too() -> None:
    before = opening_placement.FLOOR_CONTACT_REL

    with bench.overrides(["opening_placement.FLOOR_CONTACT_REL=0.5"]):
        assert opening_placement.FLOOR_CONTACT_REL == 0.5

    assert opening_placement.FLOOR_CONTACT_REL == before


@pytest.mark.parametrize("assignment", ["os.sep=1", "openings.NOPE=1", "openings.MIN_SCORE", "MIN_SCORE=1"])
def test_an_override_outside_the_worker_modules_or_without_a_target_is_refused(assignment: str) -> None:
    with pytest.raises(ValueError), bench.overrides([assignment]):
        pass


def test_noise_makes_the_errors_grow_but_the_report_keeps_its_shape() -> None:
    clean = run(cases=4, seed=5)["summary"]
    noisy = run(cases=4, seed=5, point_noise=0.03, pixel_noise=4.0)["summary"]

    assert set(clean) == set(noisy)
    assert noisy["ratio_err"]["mean"] >= clean["ratio_err"]["mean"]


def test_the_command_line_writes_the_json_and_prints_a_table(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    out = tmp_path / "report.json"

    bench.main(["--cases", "3", "--seed", "1", "--out", str(out)])

    document = json.loads(out.read_text(encoding="utf-8"))
    assert document["config"]["cases"] == 3
    assert len(document["cases"]) == 3
    assert "ratio_err" in capsys.readouterr().out


def test_stray_cloud_points_do_not_change_the_room_or_the_opening_height() -> None:
    # 15 % of the cloud replaced by points that belong to no surface. Before S8 the measured
    # ceiling was lost (opening heights ~0.4 of the wall off) and, from ~10 %, phantom walls
    # distorted the rooms (error up to 0.5).
    summary = run(cases=5, seed=1, outliers=0.15)["summary"]

    assert summary["failed"] == 0 and summary["missed"] == 0 and summary["spurious"] == 0
    assert summary["ratio_err"]["max"] < 0.06
    assert summary["opening_height_err"]["max"] < 0.03


def test_cameras_that_are_a_little_off_do_not_lose_the_door() -> None:
    summary = run(cases=5, seed=1, pose_rotation_noise=2.0, pose_position_noise=0.05)["summary"]

    assert summary["failed"] == 0 and summary["missed"] == 0
    assert summary["opening_position_err"]["max"] < 0.12
    assert summary["ratio_err"]["max"] < 0.05
