from __future__ import annotations

from typing import Protocol

from argon2 import PasswordHasher, Type
from argon2.exceptions import VerificationError

from app.core.config import Settings, get_settings

DUMMY_PASSWORD_HASH = (
    "$argon2id$v=19$m=65536,t=3,p=4$uqJf/ClU+3IPUFf6NEc4RQ$"
    "BY96MWrJX4netX/cxR+rZg7ZpXNdj0eOl0ww+yb7ZFs"
)


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


def verify_password_uniform(
    password: str,
    encoded_hash: str | None,
    password_hasher: PasswordHasherProtocol,
) -> bool:
    """Verify an account or dummy Argon2id hash without an existence branch."""
    try:
        return password_hasher.verify(password, encoded_hash or DUMMY_PASSWORD_HASH)
    except VerificationError:
        return False


def create_password_hasher(settings: Settings | None = None) -> Argon2PasswordHasher:
    return Argon2PasswordHasher(settings)
