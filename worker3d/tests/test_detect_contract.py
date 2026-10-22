"""Contract tests for the furniture detection CLI.

These tests must run without PyTorch installed: they pin the CLI's observable
contract (exit codes, error messages, output schema) and prove that importing
the module does not require the inference runtime.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

WORKER3D_DIR = Path(__file__).resolve().parents[1]
DETECT_SCRIPT = WORKER3D_DIR / "detect.py"

sys.path.insert(0, str(WORKER3D_DIR))

import detect  # noqa: E402


def _run_cli(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(DETECT_SCRIPT), *args],
        capture_output=True,
        text=True,
        cwd=str(WORKER3D_DIR),
        check=False,
    )


def test_module_imports_and_help_runs_without_torch() -> None:
    assert "torch" not in sys.modules, "the contract must hold without the runtime installed"

    result = _run_cli("--help")

    assert result.returncode == 0
    assert "usage" in result.stdout.lower()


def test_record_schema_exposes_score_and_never_probability() -> None:
    record = detect.build_record(
        image_name="foto-01.jpg",
        model_meta=detect.MODEL_META,
        threshold=0.5,
        detections=[{"label": "chair", "score": 0.73, "box": [1.0, 2.0, 3.0, 4.0]}],
        latency_ms=12.5,
        peak_rss_mb=321.0,
        not_measured=["gpu_memory_mb", "thermal_state"],
    )

    assert set(record) == {
        "image",
        "model",
        "score_threshold",
        "detections",
        "latency_ms",
        "peak_rss_mb",
        "not_measured",
    }
    assert set(record["model"]) == {"package", "version", "weights_id"}
    assert set(record["detections"][0]) == {"label", "score", "box"}
    serialized = json.dumps(record)
    assert "probability" not in serialized
    assert record["not_measured"] == ["gpu_memory_mb", "thermal_state"]


def test_record_declares_unmeasured_fields_instead_of_estimating() -> None:
    record = detect.build_record(
        image_name="foto-02.jpg",
        model_meta=detect.MODEL_META,
        threshold=0.5,
        detections=[],
        latency_ms=None,
        peak_rss_mb=None,
        not_measured=["latency_ms", "peak_rss_mb"],
    )

    assert record["latency_ms"] is None
    assert record["peak_rss_mb"] is None
    assert record["not_measured"] == ["latency_ms", "peak_rss_mb"]


def test_missing_image_directory_fails_with_code_2_and_writes_no_output(tmp_path: Path) -> None:
    out = tmp_path / "detections.jsonl"

    result = _run_cli(
        "--images", str(tmp_path / "no-existe"),
        "--out", str(out),
    )

    assert result.returncode == 2
    assert "no-existe" in result.stderr
    assert out.exists() is False


def test_empty_image_directory_fails_with_code_3_and_writes_no_output(tmp_path: Path) -> None:
    images = tmp_path / "images"
    images.mkdir()
    out = tmp_path / "detections.jsonl"

    result = _run_cli("--images", str(images), "--out", str(out))

    assert result.returncode == 3
    assert "imagen" in result.stderr.lower()
    assert out.exists() is False


@pytest.mark.parametrize("threshold", ["1.5", "-0.1", "dos"])
def test_invalid_threshold_fails_with_code_2_and_writes_no_output(
    tmp_path: Path, threshold: str
) -> None:
    images = tmp_path / "images"
    images.mkdir()
    out = tmp_path / "detections.jsonl"

    result = _run_cli("--images", str(images), "--out", str(out), "--threshold", threshold)

    assert result.returncode == 2
    assert "threshold" in result.stderr.lower() or "umbral" in result.stderr.lower()
    assert out.exists() is False


def test_non_object_labels_are_excluded_from_detections() -> None:
    """COCO_V1 has 91 slots: index 0 is __background__ and ten slots are N/A.

    Those are not objects, so a suggestion must never carry them.
    """
    categories = ["__background__", "chair", "N/A"]

    detections = detect.build_detections(
        boxes=[[0.0, 0.0, 10.0, 10.0], [1.0, 2.0, 20.0, 30.0], [0.0, 0.0, 5.0, 5.0]],
        labels=[0, 1, 2],
        scores=[0.99, 0.73, 0.95],
        categories=categories,
        threshold=0.5,
    )

    assert detections == [{"label": "chair", "score": 0.73, "box": [1.0, 2.0, 20.0, 30.0]}]


def test_build_detections_applies_threshold_and_rounds_values() -> None:
    detections = detect.build_detections(
        boxes=[[0.123456, 1.987654, 10.0, 20.0]],
        labels=[1],
        scores=[0.499999],
        categories=["__background__", "couch"],
        threshold=0.5,
    )

    assert detections == []

    detections = detect.build_detections(
        boxes=[[0.123456, 1.987654, 10.0, 20.0]],
        labels=[1],
        scores=[0.512345],
        categories=["__background__", "couch"],
        threshold=0.5,
    )

    assert detections == [{"label": "couch", "score": 0.5123, "box": [0.12, 1.99, 10.0, 20.0]}]


def test_unreadable_image_is_skipped_and_reported(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    """One corrupt file must not discard the records of every other image."""
    images = tmp_path / "images"
    images.mkdir()
    good = images / "pilot-01.jpg"
    bad = images / "pilot-02.jpg"
    good.write_bytes(b"\xff\xd8\xff")
    bad.write_bytes(b"esto no es una imagen")

    class FakeWeights:
        meta = {"categories": ["__background__", "chair"]}

    class FakeModel:
        def __call__(self, tensors: list[object]) -> list[dict[str, object]]:
            return [{"boxes": [[0.0, 0.0, 1.0, 1.0]], "labels": [1], "scores": [0.9]}]

    def fake_read(path: Path, preprocess: object) -> object:
        if path.name == "pilot-02.jpg":
            raise detect.UnreadableImageError(path)
        return object()

    monkeypatch.setattr(
        detect, "load_detector", lambda device: (FakeModel(), FakeWeights(), lambda image: image)
    )
    monkeypatch.setattr(detect, "read_image_tensor", fake_read)

    records, skipped = detect.detect_images([good, bad], 0.5, "cpu")

    assert [record["image"] for record in records] == ["pilot-01.jpg"]
    assert skipped == ["pilot-02.jpg"]
