from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from uuid import uuid4

from app.modules.identity.models import Sesion
from app.modules.identity.repository import FakeSessionRepository

NOW = datetime(2026, 1, 1, 12, 0, tzinfo=UTC)
WINDOW = timedelta(minutes=30)


def make_session(
    *,
    user_id=None,
    refresh_hash: str = "a" * 64,
    session_id=None,
    last_activity: datetime | None = NOW,
    expires_at: datetime = NOW + timedelta(days=7),
) -> Sesion:
    return Sesion(
        id=session_id or uuid4(),
        usuario_global_id=user_id or uuid4(),
        refresh_token_hash=refresh_hash,
        expira_en=expires_at,
        ultima_actividad=last_activity,
        revocado=False,
    )


def test_create_stores_active_session_with_hash_and_activity() -> None:
    repository = FakeSessionRepository()
    user_id = uuid4()
    session = repository.crear(
        usuario_global_id=user_id,
        refresh_token_hash="a" * 64,
        expira_en=NOW + timedelta(days=7),
        ultima_actividad=NOW,
        session_id=uuid4(),
    )

    assert session.revocado is False
    assert session.usuario_global_id == user_id
    assert session.ultima_actividad == NOW
    assert session.refresh_token_hash == "a" * 64
    assert all("refresh-token" not in value for value in repository.hashes())


def test_rotation_revokes_previous_hash_and_reuse_is_rejected() -> None:
    repository = FakeSessionRepository()
    user_id = uuid4()
    repository.crear(
        usuario_global_id=user_id,
        refresh_token_hash="a" * 64,
        expira_en=NOW + timedelta(days=7),
        ultima_actividad=NOW,
        session_id=uuid4(),
    )
    replacement = make_session(user_id=user_id, refresh_hash="b" * 64)

    rotated = repository.rotar_por_hash("a" * 64, replacement, NOW, WINDOW)

    assert rotated is replacement
    previous = repository.buscar_por_hash("a" * 64)
    assert previous is not None
    assert previous.revocado is True
    assert repository.rotar_por_hash("a" * 64, make_session(user_id=user_id), NOW, WINDOW) is None


def test_concurrent_rotation_allows_at_most_one_replacement() -> None:
    repository = FakeSessionRepository()
    user_id = uuid4()
    repository.crear(
        usuario_global_id=user_id,
        refresh_token_hash="a" * 64,
        expira_en=NOW + timedelta(days=7),
        ultima_actividad=NOW,
        session_id=uuid4(),
    )

    def rotate(index: int) -> Sesion | None:
        return repository.rotar_por_hash(
            "a" * 64,
            make_session(user_id=user_id, refresh_hash=f"{index:064x}"),
            NOW,
            WINDOW,
        )

    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(rotate, (1, 2)))

    successful = [result for result in results if result is not None]
    assert len(successful) == 1
    active_replacements = [
        session
        for session in repository.sessions()
        if session.refresh_token_hash != "a" * 64 and not session.revocado
    ]
    assert len(active_replacements) == 1


def test_activity_is_valid_at_29_minutes_and_invalid_at_31_minutes() -> None:
    repository = FakeSessionRepository()
    user_id = uuid4()
    session = repository.crear(
        usuario_global_id=user_id,
        refresh_token_hash="a" * 64,
        expira_en=NOW + timedelta(days=7),
        ultima_actividad=NOW,
        session_id=uuid4(),
    )

    assert repository.sesion_valida(session, NOW + timedelta(minutes=29), WINDOW)
    refreshed = repository.validar_y_actualizar_actividad(
        session.id,
        user_id,
        NOW + timedelta(minutes=29),
        WINDOW,
    )
    assert refreshed is session
    assert session.ultima_actividad == NOW + timedelta(minutes=29)

    assert repository.validar_y_actualizar_actividad(
        session.id,
        user_id,
        NOW + timedelta(minutes=61),
        WINDOW,
    ) is None
    assert session.revocado is True


def test_revocation_is_idempotent() -> None:
    repository = FakeSessionRepository()
    session = repository.crear(
        usuario_global_id=uuid4(),
        refresh_token_hash="a" * 64,
        expira_en=NOW + timedelta(days=7),
        ultima_actividad=NOW,
        session_id=uuid4(),
    )

    repository.revocar(session)
    repository.revocar(session)
    repository.revocar_por_hash("a" * 64)

    assert session.revocado is True
