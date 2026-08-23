from __future__ import annotations

from typing import Protocol

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.modules.identity.models import UsuarioGlobal

DUPLICATE_EMAIL_MESSAGE = "Ya existe una cuenta con este correo"


class DuplicateEmailError(Exception):
    """Raised when the normalized email already exists."""


class UserRepositoryProtocol(Protocol):
    def buscar_por_correo(self, correo: str) -> UsuarioGlobal | None:
        """Find a user by its normalized email."""
        ...

    def guardar(self, usuario: UsuarioGlobal) -> UsuarioGlobal:
        """Persist a user and return the refreshed entity."""
        ...


class UserRepository:
    def __init__(self, session: Session):
        self.session = session

    def buscar_por_correo(self, correo: str) -> UsuarioGlobal | None:
        statement = select(UsuarioGlobal).where(UsuarioGlobal.correo == correo)
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


def _is_duplicate_email_error(error: IntegrityError) -> bool:
    original = error.orig
    sqlstate = getattr(original, "sqlstate", None) or getattr(original, "pgcode", None)
    if sqlstate != "23505":
        return False

    diagnostics = getattr(original, "diag", None)
    constraint_name = getattr(diagnostics, "constraint_name", None)
    return constraint_name in ("uq_usuario_global_correo", "usuario_global_correo_correo_key")
