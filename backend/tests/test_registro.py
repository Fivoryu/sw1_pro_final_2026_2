from __future__ import annotations

from datetime import UTC, datetime
from types import SimpleNamespace
from uuid import UUID, uuid4

import pytest
from argon2 import PasswordHasher, Type
from argon2.exceptions import VerifyMismatchError
from fastapi.testclient import TestClient
from sqlalchemy.exc import IntegrityError

from app.core.config import Settings
from app.main import create_app
from app.modules.identity.models import UsuarioGlobal
from app.modules.identity.repository import DuplicateEmailError, UserRepository
from app.modules.identity.router import get_identity_service
from app.modules.identity.service import IdentityService


class FakeRepository:
    def __init__(self) -> None:
        self.records: dict[str, UsuarioGlobal] = {}
        self.save_calls = 0

    def buscar_por_correo(self, correo: str) -> UsuarioGlobal | None:
        return self.records.get(correo)

    def guardar(self, usuario: UsuarioGlobal) -> UsuarioGlobal:
        self.save_calls += 1
        if usuario.correo in self.records:
            raise DuplicateEmailError("Ya existe una cuenta con este correo")
        usuario.id = uuid4()
        usuario.creado_en = datetime.now(UTC)
        self.records[usuario.correo] = usuario
        return usuario


class RecordingHasher:
    def __init__(self) -> None:
        self.hash_calls = 0

    def hash(self, password: str) -> str:
        self.hash_calls += 1
        return f"recorded:{password}"

    def verify(self, password: str, encoded_hash: str) -> bool:
        return encoded_hash == f"recorded:{password}"


class _PgUniqueError(Exception):
    """Fake psycopg-style unique violation for repository tests."""

    sqlstate = "23505"
    diag = SimpleNamespace(constraint_name="uq_usuario_global_correo")


class IntegrityErrorSession:
    def __init__(self, constraint: str = "uq_usuario_global_correo") -> None:
        self.constraint = constraint
        self.rollback_calls = 0

    def scalar(self, statement: object) -> None:
        return None

    def add(self, usuario: UsuarioGlobal) -> None:
        del usuario

    def flush(self) -> None:
        error = _PgUniqueError()
        error.sqlstate = "23505"
        error.diag = SimpleNamespace(constraint_name=self.constraint)
        raise IntegrityError("INSERT usuario_global", {}, error)

    def commit(self) -> None:
        raise AssertionError("commit must not run after a failed flush")

    def refresh(self, usuario: UsuarioGlobal) -> None:
        del usuario

    def rollback(self) -> None:
        self.rollback_calls += 1


def make_client(
    repository: FakeRepository,
    password_hasher: object,
) -> TestClient:
    app = create_app(Settings())
    service = IdentityService(repository, password_hasher)  # type: ignore[arg-type]
    app.dependency_overrides[get_identity_service] = lambda: service
    return TestClient(app)


def test_registro_valido_responde_201_y_normaliza_correo() -> None:
    repository = FakeRepository()
    hasher = RecordingHasher()

    with make_client(repository, hasher) as client:
        response = client.post(
            "/api/v1/auth/registro",
            json={"correo": "Usuario@Example.com", "password": "password"},
        )

    body = response.json()
    assert response.status_code == 201
    assert UUID(body["id"])
    assert body["correo"] == "usuario@example.com"
    assert body["estado"] == "activo"
    assert body["correo_verificado"] is False
    assert body["creado_en"]
    assert repository.save_calls == 1


def test_correo_invalido_responde_422_sin_crear_cuenta() -> None:
    repository = FakeRepository()
    hasher = RecordingHasher()

    with make_client(repository, hasher) as client:
        response = client.post(
            "/api/v1/auth/registro",
            json={"correo": "no-es-correo", "password": "password"},
        )

    assert response.status_code == 422
    assert repository.records == {}
    assert repository.save_calls == 0
    assert "password" not in response.text


def test_password_corta_responde_422_y_no_llama_al_hasher() -> None:
    repository = FakeRepository()
    hasher = RecordingHasher()

    with make_client(repository, hasher) as client:
        response = client.post(
            "/api/v1/auth/registro",
            json={"correo": "usuario@example.com", "password": "1234567"},
        )

    assert response.status_code == 422
    assert hasher.hash_calls == 0
    assert repository.records == {}


def test_duplicado_con_mayusculas_responde_409_con_mensaje_exacto() -> None:
    repository = FakeRepository()
    hasher = RecordingHasher()

    with make_client(repository, hasher) as client:
        first = client.post(
            "/api/v1/auth/registro",
            json={"correo": "usuario@example.com", "password": "password"},
        )
        duplicate = client.post(
            "/api/v1/auth/registro",
            json={"correo": "USUARIO@EXAMPLE.COM", "password": "password"},
        )

    assert first.status_code == 201
    assert duplicate.status_code == 409
    assert duplicate.json() == {"detail": "Ya existe una cuenta con este correo"}
    assert len(repository.records) == 1
    assert repository.save_calls == 1


def test_hash_argon2id_es_verificable_y_no_es_plano() -> None:
    repository = FakeRepository()
    hasher = PasswordHasher(
        time_cost=1,
        memory_cost=8 * 1024,
        parallelism=1,
        hash_len=16,
        salt_len=16,
        type=Type.ID,
    )

    with make_client(repository, hasher) as client:
        response = client.post(
            "/api/v1/auth/registro",
            json={"correo": "hash@example.com", "password": "password"},
        )

    stored_hash = repository.records["hash@example.com"].hash_password
    assert response.status_code == 201
    assert stored_hash != "password"
    assert stored_hash.startswith("$argon2id$")
    assert hasher.verify(stored_hash, "password") is True
    with pytest.raises(VerifyMismatchError):
        hasher.verify(stored_hash, "otra-password")


def test_respuestas_no_exponen_hash_ni_password() -> None:
    repository = FakeRepository()
    hasher = RecordingHasher()

    with make_client(repository, hasher) as client:
        created = client.post(
            "/api/v1/auth/registro",
            json={"correo": "public@example.com", "password": "password"},
        )
        duplicate = client.post(
            "/api/v1/auth/registro",
            json={"correo": "PUBLIC@EXAMPLE.COM", "password": "otherpass"},
        )
        invalid = client.post(
            "/api/v1/auth/registro",
            json={"correo": "invalid", "password": "short"},
        )

    for response in (created, duplicate, invalid):
        assert "hash_password" not in response.text
        assert "password" not in response.text


def test_carrera_de_unicidad_hace_rollback_y_responde_409() -> None:
    session = IntegrityErrorSession()
    repository = UserRepository(session)  # type: ignore[arg-type]
    service = IdentityService(repository, RecordingHasher())
    app = create_app(Settings())
    app.dependency_overrides[get_identity_service] = lambda: service

    with TestClient(app) as client:
        response = client.post(
            "/api/v1/auth/registro",
            json={"correo": "race@example.com", "password": "password"},
        )

        assert response.status_code == 409
        assert response.json() == {"detail": "Ya existe una cuenta con este correo"}
        assert session.rollback_calls == 1


def test_violacion_unica_ajena_no_se_clasifica_como_duplicado() -> None:
    session = IntegrityErrorSession(constraint="otra_restriccion_unica")
    repository = UserRepository(session)  # type: ignore[arg-type]

    with pytest.raises(IntegrityError):
        repository.guardar(UsuarioGlobal(correo="race@example.com", hash_password="x"))

    assert session.rollback_calls == 1
