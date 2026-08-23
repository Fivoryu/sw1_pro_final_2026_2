from __future__ import annotations

import hashlib
import secrets
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Protocol
from uuid import UUID

import jwt
from jwt import PyJWTError

from app.core.config import Settings


class SecurityConfigurationError(ValueError):
    """Raised when security settings are incomplete or unsafe."""


class InvalidAccessTokenError(ValueError):
    """Raised when an access token cannot be trusted."""


@dataclass(frozen=True)
class AccessClaims:
    usuario_id: UUID
    sesion_id: UUID
    emitido_en: datetime
    expira_en: datetime


class TokenServiceProtocol(Protocol):
    def generar_refresh(self) -> str: ...

    def hash_refresh(self, refresh_token: str) -> str: ...

    def emitir_access(
        self,
        *,
        usuario_id: UUID,
        sesion_id: UUID,
        emitido_en: datetime,
        expira_en: datetime,
    ) -> str: ...

    def decodificar_access(self, *, token: str, ahora: datetime) -> AccessClaims: ...


class PyJWTTokenService:
    def __init__(self, settings: Settings) -> None:
        secret = settings.jwt_secret
        if secret is None or not secret.strip():
            raise SecurityConfigurationError("JWT_SECRET must be configured")
        self._secret = secret

    def generar_refresh(self) -> str:
        return secrets.token_urlsafe(32)

    def hash_refresh(self, refresh_token: str) -> str:
        return hashlib.sha256(refresh_token.encode("utf-8")).hexdigest()

    def emitir_access(
        self,
        *,
        usuario_id: UUID,
        sesion_id: UUID,
        emitido_en: datetime,
        expira_en: datetime,
    ) -> str:
        issued_at = _as_utc(emitido_en)
        expires_at = _as_utc(expira_en)
        payload = {
            "sub": str(usuario_id),
            "sid": str(sesion_id),
            "type": "access",
            "iat": int(issued_at.timestamp()),
            "exp": int(expires_at.timestamp()),
        }
        return str(jwt.encode(payload, self._secret, algorithm="HS256"))

    def decodificar_access(self, *, token: str, ahora: datetime) -> AccessClaims:
        try:
            payload = jwt.decode(
                token,
                self._secret,
                algorithms=["HS256"],
                options={
                    "require": ["sub", "sid", "type", "iat", "exp"],
                    "verify_exp": False,
                },
            )
            if payload.get("type") != "access":
                raise InvalidAccessTokenError("invalid access token type")

            usuario_id = UUID(str(payload["sub"]))
            sesion_id = UUID(str(payload["sid"]))
            issued_at = _timestamp(payload["iat"])
            expires_at = _timestamp(payload["exp"])
            if _as_utc(ahora) >= expires_at:
                raise InvalidAccessTokenError("access token expired")
            return AccessClaims(
                usuario_id=usuario_id,
                sesion_id=sesion_id,
                emitido_en=issued_at,
                expira_en=expires_at,
            )
        except InvalidAccessTokenError:
            raise
        except (KeyError, TypeError, ValueError, OverflowError, PyJWTError) as error:
            raise InvalidAccessTokenError("invalid access token") from error


def _timestamp(value: object) -> datetime:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("JWT timestamp must be numeric")
    return datetime.fromtimestamp(value, UTC)


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("security timestamps must be timezone-aware")
    return value.astimezone(UTC)


__all__ = [
    "AccessClaims",
    "InvalidAccessTokenError",
    "PyJWTTokenService",
    "SecurityConfigurationError",
    "TokenServiceProtocol",
]
