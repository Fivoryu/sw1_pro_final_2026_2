from __future__ import annotations

from argon2 import PasswordHasher, Type

from app.core.config import Settings, get_settings


def create_password_hasher(settings: Settings | None = None) -> PasswordHasher:
    resolved_settings = settings or get_settings()
    return PasswordHasher(type=Type.ID, **resolved_settings.argon2_options())
