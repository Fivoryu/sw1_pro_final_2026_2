from __future__ import annotations

import hashlib
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import Settings, get_settings
from app.core.tokens import PyJWTTokenService, SecurityConfigurationError
from app.main import create_app
from app.modules.identity.models import UsuarioGlobal
from app.modules.identity.repository import FakeSessionRepository
from app.modules.identity.router import get_auth_service
from app.modules.identity.service import AuthenticationService


class FakeClock:
    def __init__(self, current: datetime) -> None:
        self.current = current

    def now(self) -> datetime:
        return self.current

    def advance(self, amount: timedelta) -> None:
        self.current += amount


class FakeUserRepository:
    def __init__(self, users: list[UsuarioGlobal] | None = None) -> None:
        self.users_by_email = {user.correo: user for user in users or []}
        self.users_by_id = {user.id: user for user in users or []}

    def buscar_por_correo(self, correo: str) -> UsuarioGlobal | None:
        return self.users_by_email.get(correo)

    def buscar_por_id(self, usuario_id):
        return self.users_by_id.get(usuario_id)

    def guardar(self, usuario: UsuarioGlobal) -> UsuarioGlobal:
        self.users_by_email[usuario.correo] = usuario
        self.users_by_id[usuario.id] = usuario
        return usuario


class FakeHasher:
    def verify(self, password: str, encoded_hash: str) -> bool:
        return encoded_hash == f"hash:{password}"

    def hash(self, password: str) -> str:
        return f"hash:{password}"


def make_client() -> tuple[TestClient, FakeClock, FakeSessionRepository, UsuarioGlobal]:
    now = datetime(2026, 1, 1, tzinfo=UTC)
    user = UsuarioGlobal(
        id=uuid4(),
        correo="usuario@example.com",
        hash_password="hash:password123",
        estado="activo",
        correo_verificado=False,
        creado_en=now,
    )
    settings = Settings(jwt_secret="test-secret-for-authentication-32-bytes-long")
    clock = FakeClock(now)
    sessions = FakeSessionRepository()
    service = AuthenticationService(
        user_repository=FakeUserRepository([user]),
        session_repository=sessions,
        password_hasher=FakeHasher(),
        token_service=PyJWTTokenService(settings),
        clock=clock,
        settings=settings,
    )
    app = create_app(settings)
    app.dependency_overrides[get_auth_service] = lambda: service
    return TestClient(app), clock, sessions, user


def test_auth_routes_are_listed_in_openapi() -> None:
    client, _, _, _ = make_client()
    with client:
        paths = client.get("/openapi.json").json()["paths"]

    assert "/api/v1/auth/login" in paths
    assert "/api/v1/auth/refresh" in paths
    assert "/api/v1/auth/logout" in paths
    assert "/api/v1/auth/me" in paths


def test_login_returns_public_token_pair() -> None:
    client, _, sessions, user = make_client()
    with client:
        response = client.post(
            "/api/v1/auth/login",
            json={"correo": " USUARIO@EXAMPLE.COM ", "password": "password123"},
        )

    assert response.status_code == 200
    body = response.json()
    assert set(body) == {"access_token", "refresh_token", "expira_en"}
    assert user.id
    assert len(sessions.sessions()) == 1


def test_login_persists_exact_sha256_hash_without_plaintext() -> None:
    client, _, sessions, _ = make_client()
    with client:
        response = login_client(client)

    refresh_token = response.json()["refresh_token"]
    expected_hash = hashlib.sha256(refresh_token.encode("utf-8")).hexdigest()
    persisted = sessions.sessions()

    assert response.status_code == 200
    assert len(persisted) == 1
    assert persisted[0].refresh_token_hash == expected_hash
    assert persisted[0].refresh_token_hash != refresh_token
    assert all(refresh_token not in session.refresh_token_hash for session in persisted)


def test_me_without_bearer_is_401_not_403() -> None:
    client, _, _, _ = make_client()
    with client:
        response = client.get("/api/v1/auth/me")

    assert response.status_code == 401
    assert response.json() == {"detail": "Sesión inválida o expirada"}


def login_client(client: TestClient):
    return client.post(
        "/api/v1/auth/login",
        json={"correo": "usuario@example.com", "password": "password123"},
    )


def test_login_does_not_enumerate_missing_email_or_wrong_password() -> None:
    existing_client, _, _, _ = make_client()
    missing_client, _, _, _ = make_client()
    with existing_client, missing_client:
        wrong_password = existing_client.post(
            "/api/v1/auth/login",
            json={"correo": "usuario@example.com", "password": "wrongpass"},
        )
        missing_email = missing_client.post(
            "/api/v1/auth/login",
            json={"correo": "missing@example.com", "password": "wrongpass"},
        )

    assert wrong_password.status_code == 401
    assert missing_email.status_code == 401
    expected = {"detail": "Correo o contraseña inválidos"}
    assert wrong_password.json() == missing_email.json() == expected


def test_inactive_account_uses_same_generic_login_error() -> None:
    client, _, sessions, user = make_client()
    user.estado = "inactivo"
    with client:
        inactive = login_client(client)
        missing = client.post(
            "/api/v1/auth/login",
            json={"correo": "missing@example.com", "password": "password123"},
        )

    expected = {"detail": "Correo o contraseña inválidos"}
    assert inactive.status_code == missing.status_code == 401
    assert inactive.json() == missing.json() == expected
    assert sessions.sessions() == ()


def test_refresh_rotates_and_reuse_is_rejected() -> None:
    client, _, sessions, _ = make_client()
    with client:
        logged_in = login_client(client)
        old_refresh = logged_in.json()["refresh_token"]
        refreshed = client.post("/api/v1/auth/refresh", json={"refresh_token": old_refresh})
        reused = client.post("/api/v1/auth/refresh", json={"refresh_token": old_refresh})

    assert logged_in.status_code == 200
    assert refreshed.status_code == 200
    assert refreshed.json()["refresh_token"] != old_refresh
    assert reused.status_code == 401
    assert reused.json() == {"detail": "Sesión inválida o expirada"}
    assert len([session for session in sessions.sessions() if not session.revocado]) == 1


def test_refresh_uses_atomic_rotation_without_prior_hash_lookup(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    client, _, sessions, user = make_client()
    with client:
        logged_in = login_client(client)
        old_refresh = logged_in.json()["refresh_token"]

        def fail_lookup(refresh_hash: str):
            del refresh_hash
            raise AssertionError("refresh must rotate without a prior lookup")

        monkeypatch.setattr(sessions, "buscar_por_hash", fail_lookup)
        refreshed = client.post("/api/v1/auth/refresh", json={"refresh_token": old_refresh})

    assert refreshed.status_code == 200
    claims = jwt.decode(
        refreshed.json()["access_token"],
        "test-secret-for-authentication-32-bytes-long",
        algorithms=["HS256"],
        options={"verify_exp": False},
    )
    assert claims["sub"] == str(user.id)


def test_logout_is_idempotent_and_revokes_refresh() -> None:
    client, _, sessions, _ = make_client()
    with client:
        logged_in = login_client(client)
        refresh_token = logged_in.json()["refresh_token"]
        first = client.post("/api/v1/auth/logout", json={"refresh_token": refresh_token})
        second = client.post("/api/v1/auth/logout", json={"refresh_token": refresh_token})
        reused = client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})
        unknown = client.post("/api/v1/auth/logout", json={"refresh_token": "unknown"})

    assert first.status_code == second.status_code == unknown.status_code == 204
    assert first.content == second.content == unknown.content == b""
    assert reused.status_code == 401
    assert all(session.revocado for session in sessions.sessions())


def test_me_returns_minimal_identity_and_updates_activity() -> None:
    client, clock, sessions, user = make_client()
    with client:
        logged_in = login_client(client)
        refresh_token = logged_in.json()["refresh_token"]
        # El access JWT expira a los 15 min (REQ-03); un cliente activo renueva
        # por refresh dentro de la ventana de 30 min y la sesión sigue viva.
        clock.advance(timedelta(minutes=20))
        renewed = client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})
        assert renewed.status_code == 200
        access_token = renewed.json()["access_token"]
        clock.advance(timedelta(minutes=9))  # t0+29: dentro de la ventana de 30 min
        response = client.get(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {access_token}"},
        )

    assert response.status_code == 200
    assert response.json() == {"id": str(user.id), "correo": user.correo}
    assert set(response.json()) == {"id", "correo"}
    activa = [s for s in sessions.sessions() if not s.revocado]
    assert len(activa) == 1
    assert activa[0].ultima_actividad == clock.current


def test_inactivity_rejects_me_and_refresh_with_generic_error() -> None:
    client, clock, sessions, _ = make_client()
    with client:
        logged_in = login_client(client)
        access_token = logged_in.json()["access_token"]
        refresh_token = logged_in.json()["refresh_token"]
        clock.advance(timedelta(minutes=31))
        me_response = client.get(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {access_token}"},
        )
        refresh_response = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": refresh_token},
        )

    assert me_response.status_code == refresh_response.status_code == 401
    assert me_response.json() == refresh_response.json() == {"detail": "Sesión inválida o expirada"}
    assert sessions.sessions()[0].revocado is True


def test_expired_refresh_is_rejected_with_generic_error() -> None:
    client, clock, sessions, _ = make_client()
    with client:
        logged_in = login_client(client)
        refresh_token = logged_in.json()["refresh_token"]
        sessions.sessions()[0].expira_en = clock.current - timedelta(seconds=1)
        response = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": refresh_token},
        )

    assert response.status_code == 401
    assert response.json() == {"detail": "Sesión inválida o expirada"}
    assert sessions.sessions()[0].revocado is True


def test_me_invalid_token_variants_are_401_not_403() -> None:
    client, _, sessions, user = make_client()
    with client:
        logged_in = login_client(client)
        access_token = logged_in.json()["access_token"]
        claims = jwt.decode(
            access_token,
            "test-secret-for-authentication-32-bytes-long",
            algorithms=["HS256"],
            options={"verify_exp": False},
        )
        session_id = sessions.sessions()[0].id
        variants = [
            "not-a-jwt",
            jwt.encode(
                claims,
                "another-test-secret-that-is-long-enough",
                algorithm="HS256",
            ),
            jwt.encode(
                {**claims, "type": "refresh"},
                "test-secret-for-authentication-32-bytes-long",
                algorithm="HS256",
            ),
            jwt.encode(
                {**claims, "sid": str(uuid4())},
                "test-secret-for-authentication-32-bytes-long",
                algorithm="HS256",
            ),
            jwt.encode(
                {**claims, "sub": str(uuid4()), "sid": str(session_id)},
                "test-secret-for-authentication-32-bytes-long",
                algorithm="HS256",
            ),
        ]
        responses = [
            client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {variant}"})
            for variant in variants
        ]

    assert len(responses) == 5
    assert all(response.status_code == 401 for response in responses)
    assert all(
        response.json() == {"detail": "Sesión inválida o expirada"}
        for response in responses
    )
    assert user.id == sessions.sessions()[0].usuario_global_id


def test_validation_rejects_malformed_requests_before_session_creation() -> None:
    client, _, sessions, _ = make_client()
    with client:
        invalid_login = client.post(
            "/api/v1/auth/login", json={"correo": "not-an-email", "password": "short"}
        )
        invalid_refresh = client.post("/api/v1/auth/refresh", json={"refresh_token": ""})
        invalid_logout = client.post("/api/v1/auth/logout", json={})

        assert (
            invalid_login.status_code
            == invalid_refresh.status_code
            == invalid_logout.status_code
            == 422
        )
    assert sessions.sessions() == ()


def test_create_app_fails_closed_without_jwt_secret() -> None:
    with pytest.raises(SecurityConfigurationError):
        create_app(Settings(jwt_secret=None))


def test_create_app_fails_closed_when_environment_lacks_jwt_secret(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("JWT_SECRET", raising=False)
    get_settings.cache_clear()  # type: ignore[attr-defined]
    try:
        with pytest.raises(SecurityConfigurationError):
            create_app()
    finally:
        get_settings.cache_clear()  # type: ignore[attr-defined]
