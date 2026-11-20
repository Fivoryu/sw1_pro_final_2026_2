"""On-disk cache for the expensive stages of a reconstruction (F07).

Structure from motion and the door model take minutes; the geometry that follows takes
milliseconds. Keeping the expensive results by key lets a threshold or a fitting rule be changed
and tried again without paying for them twice.

The cache is a local developer convenience, never a source of truth: a missing, corrupt or
unreadable entry is simply recomputed. Entries are pickles, so loading is restricted to a fixed
set of classes; anything else in a file is treated as a miss and no code from it is ever run.
"""

from __future__ import annotations

import hashlib
import os
import pickle
import tempfile
from collections.abc import Callable, Iterable
from pathlib import Path
from typing import Any

# Bump when the shape of a cached value changes, so old entries stop matching.
CACHE_VERSION = 1

_ALWAYS_ALLOWED = frozenset({("builtins", "set"), ("builtins", "frozenset")})


class _RestrictedUnpickler(pickle.Unpickler):
    def __init__(self, file: Any, allowed: frozenset[tuple[str, str]]) -> None:
        super().__init__(file)
        self._allowed = allowed

    def find_class(self, module: str, name: str) -> Any:
        if (module, name) not in self._allowed:
            raise pickle.UnpicklingError(f"{module}.{name} is not allowed in the stage cache")
        return super().find_class(module, name)


def fingerprint(paths: Iterable[Path]) -> str:
    """Hash of the contents of the files, in the given order."""
    digest = hashlib.sha256()
    for path in paths:
        digest.update(b"\0file\0")
        with Path(path).open("rb") as handle:
            for block in iter(lambda: handle.read(1 << 20), b""):
                digest.update(block)
    return digest.hexdigest()


class StageCache:
    """``fetch(stage, key, compute)``: the stored value for that stage and key, or ``compute()``."""

    def __init__(self, directory: Path, allowed: Iterable[type] = ()) -> None:
        self.directory = Path(directory)
        self._allowed = _ALWAYS_ALLOWED | {(cls.__module__, cls.__qualname__) for cls in allowed}

    def _path(self, stage: str, key: str) -> Path:
        digest = hashlib.sha256(f"{CACHE_VERSION}\0{stage}\0{key}".encode()).hexdigest()[:32]
        return self.directory / f"{stage}-{digest}.pkl"

    def _load(self, path: Path) -> tuple[bool, Any]:
        try:
            with path.open("rb") as handle:
                return True, _RestrictedUnpickler(handle, self._allowed).load()
        except Exception:  # noqa: BLE001 - any unreadable entry is a miss, whatever the cause
            return False, None

    def _store(self, path: Path, value: Any) -> None:
        try:
            self.directory.mkdir(parents=True, exist_ok=True)
            handle, temporary = tempfile.mkstemp(dir=self.directory, suffix=".tmp")
            with os.fdopen(handle, "wb") as out:
                pickle.dump(value, out, protocol=pickle.HIGHEST_PROTOCOL)
            os.replace(temporary, path)
        except (OSError, pickle.PicklingError):
            return  # a cache that cannot be written only costs the next run its time

    def fetch(self, stage: str, key: str, compute: Callable[[], Any], keep: Callable[[Any], bool] | None = None) -> Any:
        """Stored value, or the computed one (stored unless ``keep`` rejects it)."""
        path = self._path(stage, key)
        found, value = self._load(path)
        if found:
            return value
        value = compute()
        if keep is None or keep(value):
            self._store(path, value)
        return value
