"""Seam between worker3d and the API: a reconstructed draft must pass the strict scene v2 validation
that `POST /api/v1/reconstruction/jobs/{job_id}/complete` applies before storing it."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

_WORKER = Path(__file__).resolve().parents[2] / "worker3d"
sys.path.insert(0, str(_WORKER))
sys.path.insert(0, str(_WORKER / "tests"))

import reconstruct  # noqa: E402  # pyright: ignore[reportMissingImports]
import test_reconstruct as worker_cases  # noqa: E402  # pyright: ignore[reportMissingImports]
from test_reconstruct_synthetic import room_package, write_package  # noqa: E402  # pyright: ignore[reportMissingImports]

from app.modules.catalog.schemas import ListingSceneDocument  # noqa: E402
from app.modules.catalog.service import validate_scene_integrity  # noqa: E402


def _assert_api_accepts(scene_draft: dict[str, object]) -> None:
    document = ListingSceneDocument.model_validate(scene_draft)
    validate_scene_integrity(document)


def test_room_without_depth_is_accepted_by_the_api(tmp_path: Path) -> None:
    result = reconstruct.reconstruct(write_package(tmp_path / "p", room_package()))

    _assert_api_accepts(result.scene_draft)


def test_room_with_a_depth_volume_is_accepted_by_the_api(tmp_path: Path) -> None:
    package = worker_cases._depth_package(tmp_path / "p", [(1.5, 1.0, 2.5, 2.0, 0.8)])
    result = reconstruct.reconstruct(package)

    assert result.scene_draft["objects"], "the synthetic box must produce a volume"
    _assert_api_accepts(result.scene_draft)


if __name__ == "__main__":
    sys.exit(pytest.main([__file__]))
