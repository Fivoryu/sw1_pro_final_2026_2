"""Bounded ZIP integrity and identity checks before releasing the device's copy."""
from __future__ import annotations

import io
import json
import zipfile
import zlib
import time
from pathlib import PurePosixPath
from typing import Any

MAX_UNPACKED_BYTES = 1024 * 1024 * 1024
VALIDATION_TIMEOUT_SECONDS = 120


def inspect_package(data: bytes, capture_id: str, listing_id: str) -> dict[str, Any]:
    deadline = time.monotonic() + VALIDATION_TIMEOUT_SECONDS
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            entries = archive.infolist()
            names = [entry.filename for entry in entries]
            if len(names) != len({name.casefold() for name in names}) or len(names) > 2500:
                raise ValueError("duplicate or excessive ZIP entries")
            if sum(entry.file_size for entry in entries) > MAX_UNPACKED_BYTES:
                raise ValueError("ZIP exceeds unpacked limit")
            for entry in entries:
                path = PurePosixPath(entry.filename.replace("\\", "/"))
                if path.is_absolute() or ".." in path.parts or ":" in entry.filename:
                    raise ValueError("unsafe ZIP path")
                if entry.flag_bits & 1:
                    raise ValueError("encrypted ZIP is unsupported")
            info = archive.getinfo("manifest.json")
            if info.file_size > 1024 * 1024:
                raise ValueError("manifest exceeds limit")
            manifest = json.loads(archive.read(info))
            if (not isinstance(manifest, dict) or type(manifest.get("schemaVersion", 1)) is not int
                or manifest.get("schemaVersion", 1) not in (1, 2)):
                raise ValueError("unsupported capture manifest")
            for field, expected in (("captureId", capture_id), ("listingId", listing_id)):
                if manifest.get(field) != expected:
                    raise ValueError(f"manifest {field} does not match capture")
            if manifest.get("schemaVersion") == 2 and not {
                "video.mp4", "frames.jsonl", "sensors.jsonl"
            }.issubset(names):
                raise ValueError("video package is incomplete")
            # Reading each member through ZipExtFile verifies CRC without one
            # uninterruptible testzip() pass or allocating a whole unpacked member.
            for entry in entries:
                with archive.open(entry) as member:
                    while member.read(1024 * 1024):
                        if time.monotonic() >= deadline:
                            raise ValueError("ZIP validation deadline exceeded")
            return manifest
    except (KeyError, zipfile.BadZipFile, zlib.error, UnicodeError, json.JSONDecodeError, RuntimeError) as error:
        raise ValueError("invalid capture ZIP") from error
