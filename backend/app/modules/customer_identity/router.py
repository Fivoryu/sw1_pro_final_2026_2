from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request, Response, status
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import Settings
from app.core.errors import ERROR_RESPONSES, ErrorResponse
from app.modules.customer_identity.schemas import (
    CustomerCredentials,
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

router = APIRouter(
    prefix="/api/v1/customer/auth",
    tags=["customer-auth"],
    responses=ERROR_RESPONSES,
)
wallet_router = APIRouter(
    prefix="/api/v1/customer",
    tags=["customer-wallets"],
    responses=ERROR_RESPONSES,
)


def _session_factory(request: Request) -> sessionmaker[Session]:
    return request.app.state.session_factory


@router.post(
    "/register",
    status_code=status.HTTP_201_CREATED,
    response_model=CustomerRegistrationResponse,
    responses={409: {"model": ErrorResponse}},
)
def register(credentials: CustomerRegistration, request: Request) -> CustomerRegistrationResponse:
    try:
        account = register_customer(
            session_factory=_session_factory(request),
            email=credentials.email,
            password=credentials.password,
        )
    except DuplicateCustomerEmailError:
        raise HTTPException(
            status_code=409,
            detail="The request conflicts with existing data.",
        ) from None
    return CustomerRegistrationResponse.model_validate(account)


@router.post(
    "/login",
    response_model=CustomerTokenPairResponse,
    responses={401: {"model": ErrorResponse}},
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
        raise HTTPException(status_code=401, detail="Authentication failed.") from None


@router.post(
    "/refresh",
    response_model=CustomerTokenPairResponse,
    responses={401: {"model": ErrorResponse}},
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
        raise HTTPException(status_code=401, detail="Authentication failed.") from None


@router.post(
    "/logout",
    status_code=status.HTTP_204_NO_CONTENT,
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
    responses={401: {"model": ErrorResponse}},
)
def me(request: Request) -> CustomerIdentityResponse:
    return CustomerIdentityResponse.model_validate(get_active_customer(request))


@wallet_router.post(
    "/wallet-challenges",
    status_code=status.HTTP_201_CREATED,
    response_model=CustomerWalletChallengeResponse,
    responses={
        401: {"model": ErrorResponse},
        409: {"model": ErrorResponse},
    },
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
        raise HTTPException(
            status_code=409,
            detail="The request conflicts with existing data.",
        ) from None
    return CustomerWalletChallengeResponse.model_validate(challenge)


@wallet_router.post(
    "/wallets",
    status_code=status.HTTP_201_CREATED,
    response_model=CustomerWalletResponse,
    responses={
        401: {"model": ErrorResponse},
        409: {"model": ErrorResponse},
    },
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
        raise HTTPException(status_code=401, detail="Authentication failed.") from None
    except CustomerWalletAlreadyLinkedError:
        raise HTTPException(
            status_code=409,
            detail="The request conflicts with existing data.",
        ) from None
    except CustomerWalletAddressConflictError:
        raise HTTPException(
            status_code=409,
            detail="The request conflicts with existing data.",
        ) from None
    return CustomerWalletResponse.model_validate(wallet)


@wallet_router.get(
    "/wallets",
    response_model=list[CustomerWalletResponse],
    responses={401: {"model": ErrorResponse}},
)
def get_wallets(request: Request) -> list[CustomerWalletResponse]:
    customer = get_active_customer(request)
    wallets = list_customer_wallets(
        session_factory=_session_factory(request), customer_id=customer["id"]
    )
    return [CustomerWalletResponse.model_validate(wallet) for wallet in wallets]
