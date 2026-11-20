"""Opt-in native adapter checks; no downloads and no physical-capture accuracy claims.

ROOMFORGE_FFMPEG: absolute FFmpeg 7+ executable.
ROOMFORGE_SFM_IMAGES: directory of overlapping real photographs, already resized if needed.
"""

from __future__ import annotations

import math
import os
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import reconstruct_video as rv


def test_real_ffmpeg_selects_exact_decoded_indices(tmp_path: Path) -> None:
    executable = os.environ.get("ROOMFORGE_FFMPEG")
    if not executable:
        pytest.skip("set ROOMFORGE_FFMPEG to run the native extraction check")
    Image = pytest.importorskip("PIL.Image")
    # Distinct constant intensities make an index shift detectable after lossy H.264/JPEG.
    images = tmp_path / "input"
    images.mkdir()
    for index in range(12):
        Image.new("RGB", (160, 120), (20 * index,) * 3).save(images / f"{index:03d}.png")
    video = tmp_path / "video.mp4"
    subprocess.run(
        [executable, "-hide_banner", "-loglevel", "error", "-framerate", "6", "-i",
         str(images / "%03d.png"), "-c:v", "libx264", "-pix_fmt", "yuv420p", "-an", str(video)],
        check=True, capture_output=True, timeout=30,
    )
    extractor = rv.FfmpegFrameExtractor(which=lambda _: executable)
    timeline = [rv.FrameStamp(i, round(i * 1e9 / 6)) for i in range(12)]
    extractor.validate_timestamps(video, timeline)
    with pytest.raises(rv.InvalidPackage, match="frame count"):
        extractor.validate_timestamps(video, timeline[:-1])
    drifted = [rv.FrameStamp(f.i, f.t + (5_000_000 if f.i >= 6 else 0)) for f in timeline]
    with pytest.raises(rv.InvalidPackage, match="presentation timestamps"):
        extractor.validate_timestamps(video, drifted)
    frames = extractor.extract(video, [11, 0, 5, 5], tmp_path / "selected")
    assert [frame.index for frame in frames] == [0, 5, 11]
    for frame in frames:
        with Image.open(frame.path) as image:
            assert image.size == (160, 120)
            assert abs(image.getpixel((80, 60))[0] - 20 * frame.index) <= 4
    with pytest.raises(RuntimeError, match="1 of 2 requested"):
        extractor.extract(video, [0, 12], tmp_path / "truncated")


@pytest.mark.parametrize("count", [145, 300])
def test_real_ffmpeg_selects_large_index_sets_without_expression_depth_failure(
    tmp_path: Path, count: int,
) -> None:
    executable = os.environ.get("ROOMFORGE_FFMPEG")
    if not executable:
        pytest.skip("set ROOMFORGE_FFMPEG to run the native extraction check")
    Image = pytest.importorskip("PIL.Image")
    images = tmp_path / "input"
    images.mkdir()
    for index in range(count * 2):
        Image.new("RGB", (64, 48), (index % 200,) * 3).save(images / f"{index:03d}.png")
    video = tmp_path / "video.mp4"
    subprocess.run(
        [executable, "-hide_banner", "-loglevel", "error", "-framerate", "30", "-i",
         str(images / "%03d.png"), "-c:v", "libx264", "-pix_fmt", "yuv420p", "-an", str(video)],
        check=True, capture_output=True, timeout=30,
    )
    indices = list(range(1, count * 2, 2))
    frames = rv.FfmpegFrameExtractor(which=lambda _: executable).extract(
        video, list(reversed(indices)) + [indices[0]], tmp_path / "selected",
    )
    assert [frame.index for frame in frames] == indices
    for frame in frames:
        with Image.open(frame.path) as image:
            assert image.size == (64, 48)
            assert abs(image.getpixel((32, 24))[0] - frame.index % 200) <= 4


def test_real_pycolmap_reconstructs_photographs(tmp_path: Path) -> None:
    source = os.environ.get("ROOMFORGE_SFM_IMAGES")
    if not source:
        pytest.skip("set ROOMFORGE_SFM_IMAGES to run the native SfM check")
    pycolmap = pytest.importorskip("pycolmap")
    paths = sorted(p for p in Path(source).iterdir() if p.suffix.lower() in {".jpg", ".png"})
    assert len(paths) >= 3, "provide at least three overlapping real photographs"
    frames = [rv.ExtractedFrame(index, path) for index, path in enumerate(paths)]
    models = rv.PycolmapPoseEstimator().estimate(frames, tmp_path / "sfm")
    assert models, "native extraction/matching/mapping did not produce a sparse model"
    model = max(models, key=lambda m: len(m.poses))
    assert len(model.poses) >= 3
    assert len(model.points) >= 30
    assert model.intrinsics.fx > 0 and model.intrinsics.fy > 0
    indices = {pose.frame_index for pose in model.poses}
    assert indices <= set(range(len(paths)))
    for pose in model.poses:
        assert all(math.isfinite(v) for v in pose.center)
        for row in pose.rotation:
            assert sum(v * v for v in row) == pytest.approx(1, abs=1e-6)
    assert max(math.dist(a.center, b.center) for a in model.poses for b in model.poses) > 1e-6
    assert all(all(math.isfinite(v) for v in p.xyz) and set(p.frames) <= indices for p in model.points)
    for path in (tmp_path / "sfm" / "sparse").glob("*/cameras.bin"):
        reconstruction = pycolmap.Reconstruction(path.parent)
        assert len(reconstruction.cameras) == 1, "all video frames must share their calibration"
    print(f"native SfM: {len(model.poses)}/{len(paths)} poses, {len(model.points)} points")
