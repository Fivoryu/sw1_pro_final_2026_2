from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import jwt
import pytest

from app.core.config import Settings
from app.core.tokens import (
    InvalidAccessTokenError,
    PyJWTTokenService,
    SecurityConfigurationError,
)


@pytest.fixture
def token_service() -> PyJWTTokenService:
    return PyJWTTokenService(Settings(jwt_secret="test-secret-for-authentication-32-bytes-long"))


def test_access_token_uses_hs256_claims_and_configured_ttl(
    token_service: PyJWTTokenService,
) -> None:
    issued_at = datetime(2026, 1, 1, tzinfo=UTC)
    expires_at = issued_at + timedelta(seconds=900)
    user_id = uuid4()
    session_id = uuid4()

    token = token_service.emitir_access(
        usuario_id=user_id,
        sesion_id=session_id,
        emitido_en=issued_at,
        expira_en=expires_at,
    )

    claims = jwt.decode(
        token,
        "test-secret-for-authentication-32-bytes-long",
        algorithms=["HS256"],
        options={"verify_exp": False},
    )
    assert claims["sub"] == str(user_id)
    assert claims["sid"] == str(session_id)
    assert claims["type"] == "access"
    assert claims["exp"] - claims["iat"] == 900


def test_access_token_rejects_wrong_type_signature_and_expiration(
    token_service: PyJWTTokenService,
) -> None:
    issued_at = datetime(2026, 1, 1, tzinfo=UTC)
    user_id = uuid4()
    session_id = uuid4()
    valid_claims = {
        "sub": str(user_id),
        "sid": str(session_id),
        "type": "access",
        "iat": int(issued_at.timestamp()),
        "exp": int((issued_at + timedelta(minutes=15)).timestamp()),
    }

    wrong_type = jwt.encode(
        {**valid_claims, "type": "refresh"},
        "test-secret-for-authentication-32-bytes-long",
        algorithm="HS256",
    )
    invalid_signature = jwt.encode(
        valid_claims,
        "another-test-secret-that-is-long-enough",
        algorithm="HS256",
    )
    expired = jwt.encode(
        {**valid_claims, "exp": int((issued_at - timedelta(seconds=1)).timestamp())},
        "test-secret-for-authentication-32-bytes-long",
        algorithm="HS256",
    )

    for token in (wrong_type, invalid_signature, expired):
        with pytest.raises(InvalidAccessTokenError):
            token_service.decodificar_access(token=token, ahora=issued_at)


def test_refresh_token_is_opaque_and_hashed_with_sha256(
    token_service: PyJWTTokenService,
) -> None:
    refresh_token = token_service.generar_refresh()
    refresh_hash = token_service.hash_refresh(refresh_token)

    assert refresh_token != refresh_hash
    assert len(refresh_hash) == 64
    assert all(character in "0123456789abcdef" for character in refresh_hash)


def test_token_service_fails_closed_without_jwt_secret(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("JWT_SECRET", raising=False)

    with pytest.raises(SecurityConfigurationError):
        PyJWTTokenService(Settings(jwt_secret=None))
