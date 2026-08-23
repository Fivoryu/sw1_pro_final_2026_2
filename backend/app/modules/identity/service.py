from __future__ import annotations

from app.core.security import PasswordHasherProtocol
from app.modules.identity.models import UsuarioGlobal
from app.modules.identity.repository import (
    DUPLICATE_EMAIL_MESSAGE,
    DuplicateEmailError,
    UserRepositoryProtocol,
)
from app.modules.identity.schemas import RegistroRequest


class IdentityService:
    def __init__(
        self,
        repository: UserRepositoryProtocol,
        password_hasher: PasswordHasherProtocol,
    ):
        self.repository = repository
        self.password_hasher = password_hasher

    def registrar(self, request: RegistroRequest) -> UsuarioGlobal:
        correo = str(request.correo).strip().lower()
        if self.repository.buscar_por_correo(correo) is not None:
            raise DuplicateEmailError(DUPLICATE_EMAIL_MESSAGE)

        hash_password = self.password_hasher.hash(request.password.get_secret_value())
        usuario = UsuarioGlobal(
            correo=correo,
            hash_password=hash_password,
            estado="activo",
            correo_verificado=False,
        )
        return self.repository.guardar(usuario)


__all__ = ["DUPLICATE_EMAIL_MESSAGE", "DuplicateEmailError", "IdentityService"]
