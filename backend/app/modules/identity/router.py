from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.security import create_password_hasher
from app.db.session import get_db
from app.modules.identity.repository import (
    DuplicateEmailError,
    UserRepository,
    UserRepositoryProtocol,
)
from app.modules.identity.schemas import RegistroRequest, RegistroResponse
from app.modules.identity.service import IdentityService, PasswordHasherProtocol

router = APIRouter(prefix="/auth", tags=["identity"])


def get_user_repository(db: Session = Depends(get_db)) -> UserRepositoryProtocol:
    return UserRepository(db)


def get_identity_hasher(settings: Settings = Depends(get_settings)) -> PasswordHasherProtocol:
    return create_password_hasher(settings)


def get_identity_service(
    repository: UserRepositoryProtocol = Depends(get_user_repository),
    password_hasher: PasswordHasherProtocol = Depends(get_identity_hasher),
) -> IdentityService:
    return IdentityService(repository, password_hasher)


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
