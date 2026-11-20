"""Native runtime readiness only, never physical reconstruction/accuracy evidence."""
from __future__ import annotations

import importlib
import random
import subprocess
import tempfile
from pathlib import Path
from typing import Any

from reconstruct_video import FfmpegFrameExtractor, find_ffmpeg

pycolmap: Any = importlib.import_module("pycolmap")


def main() -> None:
    executable = find_ffmpeg("ffmpeg")
    assert executable is not None, "FFmpeg executable is unavailable"
    subprocess.run([executable, "-version"], check=True, capture_output=True)
    with tempfile.TemporaryDirectory(prefix="f07-native-smoke-") as directory:
        root = Path(directory)
        image = root / "texture.ppm"
        image.write_bytes(b"P6\n320 240\n255\n" + random.Random(17).randbytes(320 * 240 * 3))
        video = root / "video.mp4"
        subprocess.run([executable, "-hide_banner", "-loglevel", "error", "-loop", "1", "-i", str(image),
                        "-t", "0.2", "-r", "30", "-c:v", "libx264", "-pix_fmt", "yuv420p", str(video)],
                       check=True, capture_output=True, timeout=30)
        frames = FfmpegFrameExtractor().extract(video, [0, 2, 4], root / "frames")
        assert len(frames) == 3
        database = root / "database.db"
        pycolmap.extract_features(database, root / "frames", camera_mode=pycolmap.CameraMode.SINGLE,
                                  device=pycolmap.Device.cpu,
                                  extraction_options={"num_threads": 2, "max_image_size": 320})
        pycolmap.match_exhaustive(database, device=pycolmap.Device.cpu, matching_options={"num_threads": 2})
    print(f"Native readiness passed: FFmpeg encoder/decoder + PyCOLMAP {pycolmap.__version__} extraction/matching CPU")


if __name__ == "__main__":
    main()
