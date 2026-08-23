from __future__ import annotations

from datetime import datetime, timedelta
from threading import RLock
from typing import Protocol
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.modules.identity.models import Sesion, UsuarioGlobal

DUPLICATE_EMAIL_MESSAGE = "Ya existe una cuenta con este correo"


class DuplicateEmailError(Exception):
    """Raised when the normalized email already exists."""


class SessionRepositoryError(RuntimeError):
    """Raised when persistence cannot complete an atomic session operation."""


class UserRepositoryProtocol(Protocol):
    def buscar_por_correo(self, correo: str) -> UsuarioGlobal | None:
        """Find a user by its normalized email."""
        ...

    def buscar_por_id(self, usuario_id: UUID) -> UsuarioGlobal | None:
        """Find a user by its global identifier."""
        ...

    def guardar(self, usuario: UsuarioGlobal) -> UsuarioGlobal:
        """Persist a user and return the refreshed entity."""
        ...


class SessionRepositoryProtocol(Protocol):
    def crear(
        self,
        *,
        usuario_global_id: UUID,
        refresh_token_hash: str,
        expira_en: datetime,
        ultima_actividad: datetime | None,
        session_id: UUID,
    ) -> Sesion:
        ...

    def buscar_por_hash(self, refresh_token_hash: str) -> Sesion | None:
        ...

    def buscar_por_id(self, session_id: UUID) -> Sesion | None:
        ...

    def rotar_por_hash(
        self,
        hash_anterior: str,
        nueva_sesion: Sesion,
        ahora: datetime,
        ventana: timedelta,
    ) -> Sesion | None:
        ...

    def validar_y_actualizar_actividad(
        self,
        session_id: UUID,
        usuario_id: UUID,
        ahora: datetime,
        ventana: timedelta,
    ) -> Sesion | None:
        ...

    def revocar_por_hash(self, refresh_token_hash: str) -> None:
        ...

    def revocar(self, sesion: Sesion) -> None:
        ...

    def sesion_valida(
        self,
        sesion: Sesion,
        ahora: datetime,
        ventana: timedelta,
    ) -> bool:
        ...


class UserRepository:
    def __init__(self, session: Session):
        self.session = session

    def buscar_por_correo(self, correo: str) -> UsuarioGlobal | None:
        statement = select(UsuarioGlobal).where(UsuarioGlobal.correo == correo)
        return self.session.scalar(statement)

    def buscar_por_id(self, usuario_id: UUID) -> UsuarioGlobal | None:
        statement = select(UsuarioGlobal).where(UsuarioGlobal.id == usuario_id)
        return self.session.scalar(statement)

    def guardar(self, usuario: UsuarioGlobal) -> UsuarioGlobal:
        self.session.add(usuario)
        try:
            self.session.flush()
            self.session.commit()
            self.session.refresh(usuario)
            return usuario
        except IntegrityError as error:
            self.session.rollback()
            if _is_duplicate_email_error(error):
                raise DuplicateEmailError(DUPLICATE_EMAIL_MESSAGE) from error
            raise


class SessionRepository:
    def __init__(self, session: Session):
        self.session = session

    def crear(
        self,
        *,
        usuario_global_id: UUID,
        refresh_token_hash: str,
        expira_en: datetime,
        ultima_actividad: datetime | None,
        session_id: UUID,
    ) -> Sesion:
        sesion = Sesion(
            id=session_id,
            usuario_global_id=usuario_global_id,
            refresh_token_hash=refresh_token_hash,
            expira_en=expira_en,
            ultima_actividad=ultima_actividad,
            revocado=False,
        )
        self.session.add(sesion)
        try:
            self.session.flush()
            self.session.commit()
            self.session.refresh(sesion)
            return sesion
        except IntegrityError:
            self.session.rollback()
            raise

    def buscar_por_hash(self, refresh_token_hash: str) -> Sesion | None:
        statement = select(Sesion).where(Sesion.refresh_token_hash == refresh_token_hash)
        return self.session.scalar(statement)

    def buscar_por_id(self, session_id: UUID) -> Sesion | None:
        statement = select(Sesion).where(Sesion.id == session_id)
        return self.session.scalar(statement)

    def rotar_por_hash(
        self,
        hash_anterior: str,
        nueva_sesion: Sesion,
        ahora: datetime,
        ventana: timedelta,
    ) -> Sesion | None:
        try:
            with self.session.begin():
                statement = (
                    select(Sesion)
                    .where(Sesion.refresh_token_hash == hash_anterior)
                    .with_for_update()
                )
                anterior = self.session.scalar(statement)
                if anterior is None:
                    return None
                if not sesion_valida(anterior, ahora, ventana):
                    anterior.revocado = True
                    return None

                anterior.revocado = True
                self.session.add(nueva_sesion)
                self.session.flush()
                return nueva_sesion
        except IntegrityError as error:
            self.session.rollback()
            raise SessionRepositoryError("session rotation could not be committed") from error

    def validar_y_actualizar_actividad(
        self,
        session_id: UUID,
        usuario_id: UUID,
        ahora: datetime,
        ventana: timedelta,
    ) -> Sesion | None:
        with self.session.begin():
            statement = select(Sesion).where(Sesion.id == session_id).with_for_update()
            sesion = self.session.scalar(statement)
            if sesion is None or sesion.usuario_global_id != usuario_id:
                return None
            if not sesion_valida(sesion, ahora, ventana):
                sesion.revocado = True
                return None
            sesion.ultima_actividad = ahora
            return sesion

    def revocar_por_hash(self, refresh_token_hash: str) -> None:
        with self.session.begin():
            statement = (
                select(Sesion)
                .where(Sesion.refresh_token_hash == refresh_token_hash)
                .with_for_update()
            )
            sesion = self.session.scalar(statement)
            if sesion is not None:
                sesion.revocado = True

    def revocar(self, sesion: Sesion) -> None:
        with self.session.begin():
            sesion.revocado = True

    def sesion_valida(
        self,
        sesion: Sesion,
        ahora: datetime,
        ventana: timedelta,
    ) -> bool:
        return sesion_valida(sesion, ahora, ventana)


class FakeSessionRepository:
    """In-memory session repository for deterministic unit and API tests."""

    def __init__(self) -> None:
        self._sessions_by_hash: dict[str, Sesion] = {}
        self._sessions_by_id: dict[UUID, Sesion] = {}
        self._lock = RLock()

    def crear(
        self,
        *,
        usuario_global_id: UUID,
        refresh_token_hash: str,
        expira_en: datetime,
        ultima_actividad: datetime | None,
        session_id: UUID,
    ) -> Sesion:
        with self._lock:
            if refresh_token_hash in self._sessions_by_hash:
                raise SessionRepositoryError("refresh token hash already exists")
            sesion = Sesion(
                id=session_id,
                usuario_global_id=usuario_global_id,
                refresh_token_hash=refresh_token_hash,
                expira_en=expira_en,
                ultima_actividad=ultima_actividad,
                revocado=False,
            )
            self._sessions_by_hash[refresh_token_hash] = sesion
            self._sessions_by_id[session_id] = sesion
            return sesion

    def buscar_por_hash(self, refresh_token_hash: str) -> Sesion | None:
        with self._lock:
            return self._sessions_by_hash.get(refresh_token_hash)

    def buscar_por_id(self, session_id: UUID) -> Sesion | None:
        with self._lock:
            return self._sessions_by_id.get(session_id)

    def rotar_por_hash(
        self,
        hash_anterior: str,
        nueva_sesion: Sesion,
        ahora: datetime,
        ventana: timedelta,
    ) -> Sesion | None:
        with self._lock:
            anterior = self._sessions_by_hash.get(hash_anterior)
            if anterior is None:
                return None
            if not sesion_valida(anterior, ahora, ventana):
                anterior.revocado = True
                return None
            if nueva_sesion.refresh_token_hash in self._sessions_by_hash:
                raise SessionRepositoryError("refresh token hash already exists")

            anterior.revocado = True
            self._sessions_by_hash[nueva_sesion.refresh_token_hash] = nueva_sesion
            self._sessions_by_id[nueva_sesion.id] = nueva_sesion
            return nueva_sesion

    def validar_y_actualizar_actividad(
        self,
        session_id: UUID,
        usuario_id: UUID,
        ahora: datetime,
        ventana: timedelta,
    ) -> Sesion | None:
        with self._lock:
            sesion = self._sessions_by_id.get(session_id)
            if sesion is None or sesion.usuario_global_id != usuario_id:
                return None
            if not sesion_valida(sesion, ahora, ventana):
                sesion.revocado = True
                return None
            sesion.ultima_actividad = ahora
            return sesion

    def revocar_por_hash(self, refresh_token_hash: str) -> None:
        with self._lock:
            sesion = self._sessions_by_hash.get(refresh_token_hash)
            if sesion is not None:
                sesion.revocado = True

    def revocar(self, sesion: Sesion) -> None:
        with self._lock:
            sesion.revocado = True

    def sesion_valida(
        self,
        sesion: Sesion,
        ahora: datetime,
        ventana: timedelta,
    ) -> bool:
        with self._lock:
            return sesion_valida(sesion, ahora, ventana)

    def sesiones(self) -> tuple[Sesion, ...]:
        with self._lock:
            return tuple(self._sessions_by_id.values())

    def sessions(self) -> tuple[Sesion, ...]:
        return self.sesiones()

    def hashes(self) -> tuple[str, ...]:
        with self._lock:
            return tuple(self._sessions_by_hash)


def sesion_valida(sesion: Sesion, ahora: datetime, ventana: timedelta) -> bool:
    if sesion.revocado or sesion.expira_en <= ahora or sesion.ultima_actividad is None:
        return False
    return ahora <= sesion.ultima_actividad + ventana


def _is_duplicate_email_error(error: IntegrityError) -> bool:
    original = error.orig
    sqlstate = getattr(original, "sqlstate", None) or getattr(original, "pgcode", None)
    if sqlstate != "23505":
        return False

    diagnostics = getattr(original, "diag", None)
    constraint_name = getattr(diagnostics, "constraint_name", None)
    return constraint_name in ("uq_usuario_global_correo", "usuario_global_correo_correo_key")
