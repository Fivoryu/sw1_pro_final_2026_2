from __future__ import annotations

from fastapi import APIRouter, Request, Response, status
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import Settings
from app.modules.customer_identity.errors import CustomerApiError
from app.modules.customer_identity.schemas import (
    CustomerCredentials,
    CustomerErrorResponse,
    CustomerIdentityResponse,
    CustomerRefreshRequest,
    CustomerRegistration,
    CustomerRegistrationResponse,
    CustomerTokenPairResponse,
    CustomerWalletChallengeRequest,
    CustomerWalletChallengeResponse,
    CustomerWalletResponse,
    CustomerWalletVerificationRequest,
)
from app.modules.customer_identity.service import (
    CustomerWalletAddressConflictError,
    CustomerWalletAlreadyLinkedError,
    DuplicateCustomerEmailError,
    InvalidCustomerCredentialsError,
    InvalidCustomerSessionError,
    InvalidCustomerWalletChallengeError,
    create_customer_wallet_challenge,
    list_customer_wallets,
    login_customer,
    logout_customer_session,
    refresh_customer_session,
    register_customer,
    verify_and_link_customer_wallet,
)
from app.modules.customer_identity.session import get_active_customer

router = APIRouter(prefix="/api/v1/customer/auth", tags=["customer-auth"])
wallet_router = APIRouter(prefix="/api/v1/customer", tags=["customer-wallets"])

_CUSTOMER_401 = {
    "model": CustomerErrorResponse,
    "description": "Invalid customer credentials or session",
}
_CUSTOMER_409 = {
    "model": CustomerErrorResponse,
    "description": "Customer account conflict",
}
_CUSTOMER_422 = {
    "model": CustomerErrorResponse,
    "description": "Customer request validation error",
}


def _session_factory(request: Request) -> sessionmaker[Session]:
    return request.app.state.session_factory


@router.post(
    "/register",
    status_code=status.HTTP_201_CREATED,
    response_model=CustomerRegistrationResponse,
    responses={409: _CUSTOMER_409, 422: _CUSTOMER_422},
)
def register(credentials: CustomerRegistration, request: Request) -> CustomerRegistrationResponse:
    try:
        account = register_customer(
            session_factory=_session_factory(request),
            email=credentials.email,
            password=credentials.password,
        )
    except DuplicateCustomerEmailError:
        raise CustomerApiError(status_code=409, code="account_conflict") from None
    return CustomerRegistrationResponse.model_validate(account)


@router.post(
    "/login",
    response_model=CustomerTokenPairResponse,
    responses={401: _CUSTOMER_401, 422: _CUSTOMER_422},
)
def login(credentials: CustomerCredentials, request: Request) -> dict[str, str | int]:
    settings: Settings = request.app.state.settings
    try:
        return login_customer(
            session_factory=_session_factory(request),
            settings=settings,
            email=credentials.email,
            password=credentials.password,
            now=request.app.state.clock(),
        )
    except InvalidCustomerCredentialsError:
        raise CustomerApiError(status_code=401, code="invalid_credentials") from None


@router.post(
    "/refresh",
    response_model=CustomerTokenPairResponse,
    responses={401: _CUSTOMER_401, 422: _CUSTOMER_422},
)
def refresh(
    credentials: CustomerRefreshRequest, request: Request
) -> dict[str, str | int]:
    settings: Settings = request.app.state.settings
    try:
        return refresh_customer_session(
            session_factory=_session_factory(request),
            settings=settings,
            refresh_token=credentials.refresh_token,
            now=request.app.state.clock(),
        )
    except InvalidCustomerSessionError:
        raise CustomerApiError(status_code=401, code="invalid_session") from None


@router.post(
    "/logout",
    status_code=status.HTTP_204_NO_CONTENT,
    responses={422: _CUSTOMER_422},
)
def logout(credentials: CustomerRefreshRequest, request: Request) -> Response:
    logout_customer_session(
        session_factory=_session_factory(request),
        refresh_token=credentials.refresh_token,
        now=request.app.state.clock(),
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get(
    "/me",
    response_model=CustomerIdentityResponse,
    responses={401: _CUSTOMER_401},
)
def me(request: Request) -> CustomerIdentityResponse:
    return CustomerIdentityResponse.model_validate(get_active_customer(request))


@wallet_router.post(
    "/wallet-challenges",
    status_code=status.HTTP_201_CREATED,
    response_model=CustomerWalletChallengeResponse,
    responses={401: _CUSTOMER_401, 409: _CUSTOMER_409, 422: _CUSTOMER_422},
)
def create_wallet_challenge(
    body: CustomerWalletChallengeRequest, request: Request
) -> CustomerWalletChallengeResponse:
    customer = get_active_customer(request)
    try:
        challenge = create_customer_wallet_challenge(
            session_factory=_session_factory(request),
            customer_id=customer["id"],
            address=body.address,
            now=request.app.state.clock(),
        )
    except CustomerWalletAlreadyLinkedError:
        raise CustomerApiError(status_code=409, code="wallet_already_linked") from None
    return CustomerWalletChallengeResponse.model_validate(challenge)


@wallet_router.post(
    "/wallets",
    status_code=status.HTTP_201_CREATED,
    response_model=CustomerWalletResponse,
    responses={401: _CUSTOMER_401, 409: _CUSTOMER_409, 422: _CUSTOMER_422},
)
def link_wallet(
    body: CustomerWalletVerificationRequest, request: Request
) -> CustomerWalletResponse:
    customer = get_active_customer(request)
    try:
        wallet = verify_and_link_customer_wallet(
            session_factory=_session_factory(request),
            customer_id=customer["id"],
            challenge_id=body.challenge_id,
            signature=body.signature,
            now=request.app.state.clock(),
        )
    except InvalidCustomerWalletChallengeError:
        raise CustomerApiError(status_code=401, code="invalid_wallet_challenge") from None
    except CustomerWalletAlreadyLinkedError:
        raise CustomerApiError(status_code=409, code="wallet_already_linked") from None
    except CustomerWalletAddressConflictError:
        raise CustomerApiError(status_code=409, code="wallet_conflict") from None
    return CustomerWalletResponse.model_validate(wallet)


@wallet_router.get(
    "/wallets",
    response_model=list[CustomerWalletResponse],
    responses={401: _CUSTOMER_401},
)
def get_wallets(request: Request) -> list[CustomerWalletResponse]:
    customer = get_active_customer(request)
    wallets = list_customer_wallets(
        session_factory=_session_factory(request), customer_id=customer["id"]
    )
    return [CustomerWalletResponse.model_validate(wallet) for wallet in wallets]
