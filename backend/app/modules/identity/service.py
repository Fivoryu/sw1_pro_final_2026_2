from __future__ import annotations

from datetime import timedelta
from uuid import UUID, uuid4

from app.core.clock import ClockProtocol
from app.core.config import Settings
from app.core.security import PasswordHasherProtocol, verify_password_uniform
from app.core.tokens import InvalidAccessTokenError, TokenServiceProtocol
from app.modules.identity.models import Sesion, UsuarioGlobal
from app.modules.identity.repository import (
    DUPLICATE_EMAIL_MESSAGE,
    DuplicateEmailError,
    SessionRepositoryError,
    SessionRepositoryProtocol,
    UserRepositoryProtocol,
)
from app.modules.identity.schemas import (
    LoginRequest,
    MeResponse,
    RefreshRequest,
    RegistroRequest,
    TokenResponse,
)

INVALID_CREDENTIALS_MESSAGE = "Correo o contraseña inválidos"
INVALID_SESSION_MESSAGE = "Sesión inválida o expirada"


class InvalidCredentialsError(Exception):
    """Raised when login must use the generic credentials response."""


class InvalidSessionError(Exception):
    """Raised when a session or access token is not usable."""


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


class AuthenticationService:
    def __init__(
        self,
        *,
        user_repository: UserRepositoryProtocol,
        session_repository: SessionRepositoryProtocol,
        password_hasher: PasswordHasherProtocol,
        token_service: TokenServiceProtocol,
        clock: ClockProtocol,
        settings: Settings,
    ) -> None:
        self.user_repository = user_repository
        self.session_repository = session_repository
        self.password_hasher = password_hasher
        self.token_service = token_service
        self.clock = clock
        self.settings = settings

    def login(self, request: LoginRequest) -> TokenResponse:
        correo = str(request.correo).strip().lower()
        password = request.password.get_secret_value()
        usuario = self.user_repository.buscar_por_correo(correo)
        encoded_hash = usuario.hash_password if usuario is not None else None
        password_matches = verify_password_uniform(
            password,
            encoded_hash,
            self.password_hasher,
        )
        if usuario is None or not password_matches or usuario.estado != "activo":
            raise InvalidCredentialsError

        now = self.clock.now()
        session_id = uuid4()
        refresh_token = self.token_service.generar_refresh()
        refresh_hash = self.token_service.hash_refresh(refresh_token)
        refresh_expires_at = now + timedelta(days=self.settings.refresh_token_ttl_days)
        access_expires_at = now + timedelta(seconds=self.settings.access_token_ttl_seconds)
        access_token = self.token_service.emitir_access(
            usuario_id=usuario.id,
            sesion_id=session_id,
            emitido_en=now,
            expira_en=access_expires_at,
        )
        self.session_repository.crear(
            usuario_global_id=usuario.id,
            refresh_token_hash=refresh_hash,
            expira_en=refresh_expires_at,
            ultima_actividad=now,
            session_id=session_id,
        )
        return TokenResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            expira_en=refresh_expires_at,
        )

    def refresh(self, request: RefreshRequest) -> TokenResponse:
        now = self.clock.now()
        old_refresh = request.refresh_token.get_secret_value()
        old_hash = self.token_service.hash_refresh(old_refresh)
        new_refresh = self.token_service.generar_refresh()
        new_session_id = uuid4()
        new_refresh_hash = self.token_service.hash_refresh(new_refresh)
        new_expires_at = now + timedelta(days=self.settings.refresh_token_ttl_days)
        replacement = Sesion(
            id=new_session_id,
            usuario_global_id=UUID(int=0),
            refresh_token_hash=new_refresh_hash,
            expira_en=new_expires_at,
            ultima_actividad=now,
            revocado=False,
        )

        previous = self.session_repository.buscar_por_hash(old_hash)
        if previous is None:
            raise InvalidSessionError
        replacement.usuario_global_id = previous.usuario_global_id
        try:
            rotated = self.session_repository.rotar_por_hash(
                old_hash,
                replacement,
                now,
                self._inactivity_window(),
            )
        except SessionRepositoryError as error:
            raise InvalidSessionError from error
        if rotated is None:
            raise InvalidSessionError

        access_token = self.token_service.emitir_access(
            usuario_id=previous.usuario_global_id,
            sesion_id=new_session_id,
            emitido_en=now,
            expira_en=now + timedelta(seconds=self.settings.access_token_ttl_seconds),
        )
        return TokenResponse(
            access_token=access_token,
            refresh_token=new_refresh,
            expira_en=new_expires_at,
        )

    def logout(self, request: RefreshRequest) -> None:
        refresh_token = request.refresh_token.get_secret_value()
        refresh_hash = self.token_service.hash_refresh(refresh_token)
        self.session_repository.revocar_por_hash(refresh_hash)

    def me(self, access_token: str) -> MeResponse:
        now = self.clock.now()
        try:
            claims = self.token_service.decodificar_access(token=access_token, ahora=now)
        except (InvalidAccessTokenError, ValueError) as error:
            raise InvalidSessionError from error

        session = self.session_repository.validar_y_actualizar_actividad(
            claims.sesion_id,
            claims.usuario_id,
            now,
            self._inactivity_window(),
        )
        if session is None:
            raise InvalidSessionError
        usuario = self.user_repository.buscar_por_id(claims.usuario_id)
        if usuario is None or usuario.id != session.usuario_global_id:
            raise InvalidSessionError
        return MeResponse(id=usuario.id, correo=usuario.correo)

    def _inactivity_window(self) -> timedelta:
        return timedelta(minutes=self.settings.session_inactivity_minutes)


__all__ = [
    "AuthenticationService",
    "DUPLICATE_EMAIL_MESSAGE",
    "DuplicateEmailError",
    "IdentityService",
    "INVALID_CREDENTIALS_MESSAGE",
    "INVALID_SESSION_MESSAGE",
    "InvalidCredentialsError",
    "InvalidSessionError",
    "PasswordHasherProtocol",
]
