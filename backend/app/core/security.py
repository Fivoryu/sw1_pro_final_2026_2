from __future__ import annotations

from typing import Protocol

from argon2 import PasswordHasher, Type

from app.core.config import Settings, get_settings


class PasswordHasherProtocol(Protocol):
    def hash(self, password: str) -> str:
        """Hash a plaintext password."""
        ...

    def verify(self, password: str, encoded_hash: str) -> bool:
        """Verify a plaintext password against an encoded hash."""
        ...


class Argon2PasswordHasher:
    """Adapter that exposes argon2-cffi through the project protocol."""

    def __init__(self, settings: Settings | None = None) -> None:
        resolved_settings = settings or get_settings()
        options = resolved_settings.argon2_options()
        self._hasher = PasswordHasher(
            type=Type.ID,
            time_cost=options.get("time_cost", 3),
            memory_cost=options.get("memory_cost", 65536),
            parallelism=options.get("parallelism", 1),
            hash_len=options.get("hash_len", 32),
            salt_len=options.get("salt_len", 16),
        )

    def hash(self, password: str) -> str:
        return self._hasher.hash(password)

    def verify(self, password: str, encoded_hash: str) -> bool:
        return self._hasher.verify(encoded_hash, password)


def create_password_hasher(settings: Settings | None = None) -> Argon2PasswordHasher:
    return Argon2PasswordHasher(settings)
