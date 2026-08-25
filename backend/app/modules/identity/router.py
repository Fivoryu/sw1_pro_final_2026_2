from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Response, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.clock import ClockProtocol, SystemClock
from app.core.config import Settings, get_settings
from app.core.security import PasswordHasherProtocol, create_password_hasher
from app.core.tokens import PyJWTTokenService, TokenServiceProtocol
from app.db.session import get_db
from app.modules.identity.repository import (
    DuplicateEmailError,
    SessionRepository,
    SessionRepositoryProtocol,
    UserRepository,
    UserRepositoryProtocol,
)
from app.modules.identity.schemas import (
    LoginRequest,
    MeResponse,
    RefreshRequest,
    RegistroRequest,
    RegistroResponse,
    TokenResponse,
)
from app.modules.identity.service import (
    INVALID_CREDENTIALS_MESSAGE,
    INVALID_SESSION_MESSAGE,
    AuthenticationService,
    IdentityService,
    InvalidCredentialsError,
    InvalidSessionError,
)

router = APIRouter(prefix="/auth", tags=["identity"])
bearer_scheme = HTTPBearer(auto_error=False)


def get_user_repository(db: Session = Depends(get_db)) -> UserRepositoryProtocol:
    return UserRepository(db)


def get_session_repository(db: Session = Depends(get_db)) -> SessionRepositoryProtocol:
    return SessionRepository(db)


def get_identity_hasher(settings: Settings = Depends(get_settings)) -> PasswordHasherProtocol:
    return create_password_hasher(settings)


def get_token_service(settings: Settings = Depends(get_settings)) -> TokenServiceProtocol:
    return PyJWTTokenService(settings)


def get_clock() -> ClockProtocol:
    return SystemClock()


def get_identity_service(
    repository: UserRepositoryProtocol = Depends(get_user_repository),
    password_hasher: PasswordHasherProtocol = Depends(get_identity_hasher),
) -> IdentityService:
    return IdentityService(repository, password_hasher)


def get_auth_service(
    user_repository: UserRepositoryProtocol = Depends(get_user_repository),
    session_repository: SessionRepositoryProtocol = Depends(get_session_repository),
    password_hasher: PasswordHasherProtocol = Depends(get_identity_hasher),
    token_service: TokenServiceProtocol = Depends(get_token_service),
    clock: ClockProtocol = Depends(get_clock),
    settings: Settings = Depends(get_settings),
) -> AuthenticationService:
    return AuthenticationService(
        user_repository=user_repository,
        session_repository=session_repository,
        password_hasher=password_hasher,
        token_service=token_service,
        clock=clock,
        settings=settings,
    )


def _invalid_credentials() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=INVALID_CREDENTIALS_MESSAGE,
    )


def _invalid_session() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=INVALID_SESSION_MESSAGE,
    )


@router.post(
    "/registro",
    response_model=RegistroResponse,
    status_code=status.HTTP_201_CREATED,
)
def registrar_cliente(
    request: RegistroRequest,
    service: IdentityService = Depends(get_identity_service),
) -> RegistroResponse:
    try:
        usuario = service.registrar(request)
    except DuplicateEmailError as error:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(error),
        ) from error

    return RegistroResponse.model_validate(usuario)


@router.post("/login", response_model=TokenResponse, status_code=status.HTTP_200_OK)
def login(
    request: LoginRequest,
    service: AuthenticationService = Depends(get_auth_service),
) -> TokenResponse:
    try:
        return service.login(request)
    except InvalidCredentialsError as error:
        raise _invalid_credentials() from error


@router.post("/refresh", response_model=TokenResponse, status_code=status.HTTP_200_OK)
def refresh(
    request: RefreshRequest,
    service: AuthenticationService = Depends(get_auth_service),
) -> TokenResponse:
    try:
        return service.refresh(request)
    except InvalidSessionError as error:
        raise _invalid_session() from error


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(
    request: RefreshRequest,
    service: AuthenticationService = Depends(get_auth_service),
) -> Response:
    service.logout(request)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
    service: AuthenticationService = Depends(get_auth_service),
) -> MeResponse:
    if credentials is None:
        raise _invalid_session()
    try:
        return service.me(credentials.credentials)
    except InvalidSessionError as error:
        raise _invalid_session() from error


@router.get("/me", response_model=MeResponse)
def me(current_user: MeResponse = Depends(get_current_user)) -> MeResponse:
    return current_user
