"""Contract tests for the manual review sheet builder.

These tests run without Pillow installed: they pin the CLI contract (exit codes,
error messages, pagination) and leave rendering to the container, which is the
only place the image library is guaranteed.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

WORKER3D_DIR = Path(__file__).resolve().parents[1]
REVIEW_SCRIPT = WORKER3D_DIR / "review_sheet.py"

sys.path.insert(0, str(WORKER3D_DIR))

import review_sheet  # noqa: E402


def _run_cli(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(REVIEW_SCRIPT), *args],
        capture_output=True,
        text=True,
        cwd=str(WORKER3D_DIR),
        check=False,
    )


def test_module_imports_and_help_runs_without_pillow() -> None:
    assert "PIL" not in sys.modules, "the contract must hold without the image library installed"

    result = _run_cli("--help")

    assert result.returncode == 0
    assert "usage" in result.stdout.lower()


def test_plan_sheets_paginates_records() -> None:
    assert review_sheet.plan_sheets(24, 6) == [6, 6, 6, 6]
    assert review_sheet.plan_sheets(7, 6) == [6, 1]
    assert review_sheet.plan_sheets(6, 6) == [6]
    assert review_sheet.plan_sheets(0, 6) == []


def test_missing_records_file_fails_with_code_2_and_writes_no_sheets(tmp_path: Path) -> None:
    out_dir = tmp_path / "sheets"

    result = _run_cli(
        "--records", str(tmp_path / "no-existe.jsonl"),
        "--images", str(tmp_path),
        "--out-dir", str(out_dir),
    )

    assert result.returncode == 2
    assert "no-existe.jsonl" in result.stderr
    assert out_dir.exists() is False


def test_empty_records_file_fails_with_code_3_and_writes_no_sheets(tmp_path: Path) -> None:
    records = tmp_path / "detections.jsonl"
    records.write_text("", encoding="utf-8")
    out_dir = tmp_path / "sheets"

    result = _run_cli(
        "--records", str(records),
        "--images", str(tmp_path),
        "--out-dir", str(out_dir),
    )

    assert result.returncode == 3
    assert "registro" in result.stderr.lower()
    assert out_dir.exists() is False


@pytest.mark.parametrize("per_sheet", ["0", "-3", "no-numero"])
def test_invalid_per_sheet_fails_with_code_2_and_writes_no_sheets(
    tmp_path: Path, per_sheet: str
) -> None:
    records = tmp_path / "detections.jsonl"
    records.write_text(
        json.dumps({"image": "pilot-01.jpg", "detections": []}) + "\n", encoding="utf-8"
    )
    out_dir = tmp_path / "sheets"

    result = _run_cli(
        "--records", str(records),
        "--images", str(tmp_path),
        "--out-dir", str(out_dir),
        "--per-sheet", per_sheet,
    )

    assert result.returncode == 2
    assert "per-sheet" in result.stderr.lower()
    assert out_dir.exists() is False


def test_fit_box_preserves_aspect_and_never_exceeds_the_cell() -> None:
    """Every tile must fit inside a fixed cell, or captions overlap images."""
    assert review_sheet.fit_box(1920, 1080, 640) == (640, 360)
    assert review_sheet.fit_box(1080, 1920, 640) == (360, 640)
    assert review_sheet.fit_box(640, 640, 640) == (640, 640)
    assert review_sheet.fit_box(100, 50, 640) == (640, 320)
    assert review_sheet.fit_box(4032, 3024, 640) == (640, 480)


def test_fit_box_keeps_every_dimension_within_the_cell() -> None:
    for width, height in [(4032, 3024), (3024, 4032), (800, 800), (100, 3000), (3000, 100)]:
        fitted_width, fitted_height = review_sheet.fit_box(width, height, 640)
        assert fitted_width <= 640
        assert fitted_height <= 640
        assert max(fitted_width, fitted_height) == 640


def test_cell_origin_gives_disjoint_ordered_cells() -> None:
    """Every tile owns a disjoint cell, so one tile's boxes can never land on another."""
    cells = [review_sheet.cell_origin(slot, 3, 640, 24) for slot in range(6)]

    assert cells == [
        (0, 0),
        (640, 0),
        (1280, 0),
        (0, 664),
        (640, 664),
        (1280, 664),
    ]
    assert len(set(cells)) == len(cells)


def test_malformed_jsonl_fails_with_code_2_and_writes_no_sheets(tmp_path: Path) -> None:
    records = tmp_path / "detections.jsonl"
    records.write_text("{esto no es json}\n", encoding="utf-8")
    out_dir = tmp_path / "sheets"

    result = _run_cli(
        "--records", str(records),
        "--images", str(tmp_path),
        "--out-dir", str(out_dir),
    )

    assert result.returncode == 2
    assert "json" in result.stderr.lower()
    assert out_dir.exists() is False


def test_runtime_unavailable_exit_code_matches_the_detector_cli() -> None:
    """Both tools must report a missing runtime the same way."""
    import detect

    assert review_sheet.EXIT_RUNTIME_UNAVAILABLE == detect.EXIT_RUNTIME_UNAVAILABLE
