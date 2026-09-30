from __future__ import annotations

import hmac
import sqlite3
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel
from sqlalchemy.exc import IntegrityError, OperationalError
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import Settings
from app.core.errors import ERROR_RESPONSES
from app.core.security import (
    create_access_token,
    decrypt_totp_secret,
    encrypt_totp_secret,
    hash_password,
    hash_secret,
    make_totp_uri,
    new_recovery_codes,
    new_totp_secret,
    random_token,
    verify_password,
    verify_totp,
)
from app.modules.identity.invitations import (
    has_email_claim_conflict,
    lock_normalized_email,
    normalize_email,
)
from app.modules.identity.models import (
    Agency,
    StaffAccount,
    StaffEnrollmentChallenge,
    StaffInvitation,
    StaffLoginChallenge,
    StaffRecoveryCode,
    StaffSession,
)
from app.modules.identity.session import get_active_staff

router = APIRouter(
    prefix="/api/v1/auth", tags=["staff-auth"], responses=ERROR_RESPONSES
)
_MAX_ENROLLMENT_ATTEMPTS = 5


class InvitationAcceptance(BaseModel):
    token: str
    password: str
    password_confirmation: str


class TotpEnrollmentVerification(BaseModel):
    enrollment_token: str
    code: str


class LoginCredentials(BaseModel):
    email: str
    password: str


class TotpLoginVerification(BaseModel):
    challenge_token: str
    code: str | None = None
    recovery_code: str | None = None


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _invitation_supports_onboarding(
    session: Session, invitation: StaffInvitation
) -> bool:
    if invitation.role == "platform_admin":
        return invitation.tenant_id is None
    return (
        invitation.role in {"agency_admin", "agent"}
        and invitation.tenant_id is not None
        and session.get(Agency, invitation.tenant_id) is not None
    )


def _is_concurrent_conflict(error: IntegrityError | OperationalError) -> bool:
    original = error.orig
    sqlstate = getattr(original, "sqlstate", None) or getattr(
        original, "pgcode", None
    )
    if sqlstate in {"40001", "40P01"}:
        return True
    if sqlstate == "23505":
        diagnostic = getattr(original, "diag", None)
        return (
            getattr(diagnostic, "constraint_name", None)
            == "staff_enrollment_challenge_invitation_id_key"
        )

    original_args = getattr(original, "args", ())
    message = str(original_args[-1]) if original_args else str(original)
    sqlite_errorcode = getattr(original, "sqlite_errorcode", None)
    if isinstance(error, IntegrityError):
        if sqlite_errorcode == sqlite3.SQLITE_CONSTRAINT_UNIQUE:
            return message.strip().lower() == (
                "unique constraint failed: "
                "staff_enrollment_challenge.invitation_id"
            )
        if original_args and original_args[0] == 1062:
            normalized_message = message.strip().lower()
            if not normalized_message.startswith("duplicate entry "):
                return False
            if " for key " not in normalized_message:
                return False
            key = normalized_message.rsplit(" for key ", 1)[1].strip().strip("'\"`")
            return key in {
                "staff_enrollment_challenge.invitation_id",
                "invitation_id",
            }
        return False

    if isinstance(sqlite_errorcode, int) and (
        sqlite_errorcode & 0xFF
    ) in {sqlite3.SQLITE_BUSY, sqlite3.SQLITE_LOCKED}:
        return True
    return bool(original_args) and original_args[0] in {1205, 1213}


@router.post("/invitations/accept", response_model=None)
def accept_invitation(
    acceptance: InvitationAcceptance, request: Request
) -> dict[str, str]:
    if not acceptance.password.strip() or not acceptance.password_confirmation.strip():
        raise HTTPException(status_code=422, detail="Password must not be blank")
    if acceptance.password != acceptance.password_confirmation:
        raise HTTPException(status_code=422, detail="Passwords do not match")

    settings: Settings = request.app.state.settings
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    now = _as_utc(request.app.state.clock())
    enrollment_response: dict[str, str] | None = None
    invalid_invitation = False

    try:
        with session_factory.begin() as session:
            token_hash = hash_secret(acceptance.token)
            invitation_hint = (
                session.query(StaffInvitation.email)
                .filter(StaffInvitation.token_hash == token_hash)
                .scalar()
            )
            if invitation_hint is None:
                invalid_invitation = True
            else:
                normalized_email = normalize_email(invitation_hint)
                lock_normalized_email(session, normalized_email)
                invitation = (
                    session.query(StaffInvitation)
                    .filter(StaffInvitation.token_hash == token_hash)
                    .with_for_update()
                    .one_or_none()
                )
                if (
                    invitation is None
                    or invitation.status != "pending"
                    or normalize_email(invitation.email) != normalized_email
                    or not _invitation_supports_onboarding(session, invitation)
                ):
                    invalid_invitation = True
                elif _as_utc(invitation.expires_at) <= now:
                    invitation.status = "expired"
                    invalid_invitation = True
                elif has_email_claim_conflict(
                    session,
                    normalized_email,
                    now,
                    exclude_invitation_id=invitation.id,
                ):
                    invalid_invitation = True
                else:
                    enrollment_token = random_token()
                    totp_secret = new_totp_secret()
                    challenge = StaffEnrollmentChallenge(
                        invitation_id=invitation.id,
                        token_hash=hash_secret(enrollment_token),
                        password_hash=hash_password(acceptance.password),
                        totp_secret_encrypted=encrypt_totp_secret(
                            totp_secret, settings.totp_encryption_key
                        ),
                        created_at=now,
                        expires_at=now
                        + timedelta(minutes=settings.enrollment_ttl_minutes),
                    )
                    claimed = (
                        session.query(StaffInvitation)
                        .filter(
                            StaffInvitation.id == invitation.id,
                            StaffInvitation.status == "pending",
                            StaffInvitation.role == invitation.role,
                            StaffInvitation.tenant_id == invitation.tenant_id,
                            StaffInvitation.expires_at > now,
                        )
                        .update(
                            {
                                StaffInvitation.status: "accepted",
                                StaffInvitation.accepted_at: now,
                            },
                            synchronize_session=False,
                        )
                    )
                    if claimed != 1:
                        invalid_invitation = True
                    else:
                        session.add(challenge)
                        enrollment_response = {
                            "enrollment_token": enrollment_token,
                            "totp_secret": totp_secret,
                            "provisioning_uri": make_totp_uri(
                                totp_secret, invitation.email
                            ),
                        }
    except (IntegrityError, OperationalError) as error:
        if not _is_concurrent_conflict(error):
            raise
        raise HTTPException(
            status_code=401, detail="Invitation is invalid or expired"
        ) from None

    if invalid_invitation or enrollment_response is None:
        raise HTTPException(status_code=401, detail="Invitation is invalid or expired")
    return enrollment_response


@router.post("/totp/enroll/verify", response_model=None)
def verify_totp_enrollment(
    verification: TotpEnrollmentVerification, request: Request
) -> dict[str, object]:
    settings: Settings = request.app.state.settings
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    now = _as_utc(request.app.state.clock())
    unauthorized = False
    account_identity: dict[str, str | None] | None = None
    recovery_codes: list[str] = []

    with session_factory.begin() as session:
        token_hash = hash_secret(verification.enrollment_token)
        invitation_id_hint = (
            session.query(StaffEnrollmentChallenge.invitation_id)
            .filter(StaffEnrollmentChallenge.token_hash == token_hash)
            .scalar()
        )
        if invitation_id_hint is None:
            unauthorized = True
        else:
            email_hint = (
                session.query(StaffInvitation.email)
                .filter(StaffInvitation.id == invitation_id_hint)
                .scalar()
            )
            if email_hint is None:
                unauthorized = True
            else:
                normalized_email = normalize_email(email_hint)
                lock_normalized_email(session, normalized_email)
                challenge = (
                    session.query(StaffEnrollmentChallenge)
                    .filter(StaffEnrollmentChallenge.token_hash == token_hash)
                    .with_for_update()
                    .one_or_none()
                )
                if challenge is None or challenge.invitation_id != invitation_id_hint:
                    unauthorized = True
                elif challenge.consumed_at is not None:
                    unauthorized = True
                elif challenge.attempts >= _MAX_ENROLLMENT_ATTEMPTS:
                    challenge.consumed_at = now
                    unauthorized = True
                elif _as_utc(challenge.expires_at) <= now:
                    challenge.consumed_at = now
                    unauthorized = True
                else:
                    invitation = (
                        session.query(StaffInvitation)
                        .filter(StaffInvitation.id == challenge.invitation_id)
                        .with_for_update()
                        .one_or_none()
                    )
                    if (
                        invitation is None
                        or invitation.status != "accepted"
                        or normalize_email(invitation.email) != normalized_email
                        or not _invitation_supports_onboarding(session, invitation)
                    ):
                        challenge.consumed_at = now
                        unauthorized = True
                    elif has_email_claim_conflict(
                        session,
                        normalized_email,
                        now,
                        exclude_invitation_id=invitation.id,
                    ):
                        challenge.consumed_at = now
                        unauthorized = True
                    else:
                        try:
                            totp_secret = decrypt_totp_secret(
                                challenge.totp_secret_encrypted,
                                settings.totp_encryption_key,
                            )
                            valid_code = verify_totp(
                                totp_secret, verification.code, now
                            )
                        except ValueError:
                            valid_code = False

                        if not valid_code:
                            challenge.attempts += 1
                            if challenge.attempts >= _MAX_ENROLLMENT_ATTEMPTS:
                                challenge.consumed_at = now
                            unauthorized = True
                        else:
                            account = StaffAccount(
                                email=normalize_email(invitation.email),
                                password_hash=challenge.password_hash,
                                role=invitation.role,
                                tenant_id=invitation.tenant_id,
                                active=True,
                                totp_secret_encrypted=challenge.totp_secret_encrypted,
                                totp_enabled=True,
                                created_at=now,
                            )
                            session.add(account)
                            session.flush()
                            challenge.consumed_at = now
                            recovery_codes = new_recovery_codes(
                                settings.recovery_code_count
                            )
                            session.add_all(
                                StaffRecoveryCode(
                                    user_id=account.id,
                                    code_hash=hash_secret(code),
                                    created_at=now,
                                )
                                for code in recovery_codes
                            )
                            account_identity = {
                                "id": account.id,
                                "email": account.email,
                                "role": account.role,
                                "tenant_id": account.tenant_id,
                            }

    if unauthorized or account_identity is None:
        raise HTTPException(status_code=401, detail="Enrollment is invalid or expired")
    return {"account": account_identity, "recovery_codes": recovery_codes}


@router.post("/login", response_model=None)
def login(credentials: LoginCredentials, request: Request) -> dict[str, str]:
    settings: Settings = request.app.state.settings
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    now = _as_utc(request.app.state.clock())
    normalized_email = credentials.email.strip().lower()
    challenge_token: str | None = None

    with session_factory.begin() as session:
        account = (
            session.query(StaffAccount)
            .filter(
                StaffAccount.email == normalized_email,
                StaffAccount.active.is_(True),
                StaffAccount.totp_enabled.is_(True),
            )
            .with_for_update()
            .one_or_none()
        )
        if account is None or not verify_password(account.password_hash, credentials.password):
            unauthorized = True
        else:
            unauthorized = False
            challenge_token = random_token()
            session.add(
                StaffLoginChallenge(
                    user_id=account.id,
                    token_hash=hash_secret(challenge_token),
                    created_at=now,
                    expires_at=now + timedelta(minutes=settings.login_challenge_minutes),
                    attempts=0,
                )
            )

    if unauthorized or challenge_token is None:
        raise HTTPException(status_code=401, detail="Invalid email or password")
    return {"challenge_token": challenge_token}


@router.post("/login/totp", response_model=None)
def complete_login_challenge(
    verification: TotpLoginVerification, request: Request, response: Response
) -> dict[str, object]:
    if (verification.code is None) == (verification.recovery_code is None):
        raise HTTPException(status_code=422, detail="Provide exactly one login proof")

    settings: Settings = request.app.state.settings
    if request.headers.get("origin") != settings.web_origin:
        raise HTTPException(status_code=403, detail="Origin is not allowed")

    session_factory: sessionmaker[Session] = request.app.state.session_factory
    now = _as_utc(request.app.state.clock())
    unauthorized = False
    login_response: dict[str, object] | None = None
    refresh_token: str | None = None

    with session_factory.begin() as session:
        challenge = (
            session.query(StaffLoginChallenge)
            .filter(
                StaffLoginChallenge.token_hash == hash_secret(verification.challenge_token)
            )
            .with_for_update()
            .one_or_none()
        )
        if challenge is None:
            unauthorized = True
        elif challenge.consumed_at is not None:
            unauthorized = True
        elif challenge.attempts >= _MAX_ENROLLMENT_ATTEMPTS:
            challenge.consumed_at = now
            unauthorized = True
        elif _as_utc(challenge.expires_at) <= now:
            challenge.consumed_at = now
            unauthorized = True
        else:
            account = (
                session.query(StaffAccount)
                .filter(StaffAccount.id == challenge.user_id)
                .with_for_update()
                .one_or_none()
            )
            if (
                account is None
                or not account.active
                or not account.totp_enabled
                or account.totp_secret_encrypted is None
            ):
                unauthorized = True
            else:
                if verification.code is not None:
                    try:
                        totp_secret = decrypt_totp_secret(
                            account.totp_secret_encrypted,
                            settings.totp_encryption_key,
                        )
                        valid_proof = verify_totp(totp_secret, verification.code, now)
                    except (TypeError, ValueError):
                        valid_proof = False
                else:
                    consumed_recovery_code = (
                        session.query(StaffRecoveryCode)
                        .filter(
                            StaffRecoveryCode.user_id == account.id,
                            StaffRecoveryCode.code_hash
                            == hash_secret(verification.recovery_code or ""),
                            StaffRecoveryCode.used_at.is_(None),
                        )
                        .update(
                            {StaffRecoveryCode.used_at: now},
                            synchronize_session=False,
                        )
                    )
                    valid_proof = consumed_recovery_code == 1

                if not valid_proof:
                    challenge.attempts += 1
                    if challenge.attempts >= _MAX_ENROLLMENT_ATTEMPTS:
                        challenge.consumed_at = now
                    unauthorized = True
                else:
                    challenge.consumed_at = now
                    refresh_token = random_token()
                    csrf_token = random_token()
                    staff_session = StaffSession(
                        user_id=account.id,
                        refresh_hash=hash_secret(refresh_token),
                        csrf_hash=hash_secret(csrf_token),
                        created_at=now,
                        last_activity_at=now,
                        expires_at=now + timedelta(days=settings.refresh_token_days),
                    )
                    session.add(staff_session)
                    session.flush()
                    access_token = create_access_token(
                        user_id=account.id,
                        session_id=staff_session.id,
                        signing_key=settings.jwt_secret,
                        now=now,
                        lifetime_minutes=settings.access_token_minutes,
                    )
                    login_response = {
                        "access_token": access_token,
                        "csrf_token": csrf_token,
                        "user": {
                            "id": account.id,
                            "email": account.email,
                            "role": account.role,
                            "tenant_id": account.tenant_id,
                        },
                    }

    if unauthorized or login_response is None or refresh_token is None:
        raise HTTPException(status_code=401, detail="Login challenge is invalid or expired")

    response.set_cookie(
        key="roomforge_refresh",
        value=refresh_token,
        httponly=True,
        secure=settings.secure_cookies,
        samesite="lax",
        path="/api/v1/auth",
        max_age=settings.refresh_token_days * 24 * 60 * 60,
    )
    return login_response


@router.post("/refresh", response_model=None)
def refresh_session(request: Request, response: Response) -> dict[str, str]:
    settings: Settings = request.app.state.settings
    if request.headers.get("origin") != settings.web_origin:
        raise HTTPException(status_code=403, detail="Origin is not allowed")

    csrf_token = request.headers.get("x-csrf-token")
    if not csrf_token:
        raise HTTPException(status_code=403, detail="CSRF token is required")

    refresh_token = request.cookies.get("roomforge_refresh")
    if not refresh_token:
        raise HTTPException(status_code=401, detail="Session is invalid or expired")

    session_factory: sessionmaker[Session] = request.app.state.session_factory
    now = _as_utc(request.app.state.clock())
    unauthorized = False
    invalid_csrf = False
    refreshed_response: dict[str, str] | None = None
    rotated_refresh_token: str | None = None
    cookie_max_age = 0

    with session_factory.begin() as session:
        staff_session = (
            session.query(StaffSession)
            .filter(StaffSession.refresh_hash == hash_secret(refresh_token))
            .with_for_update()
            .one_or_none()
        )
        if staff_session is None or staff_session.revoked_at is not None:
            unauthorized = True
        elif not hmac.compare_digest(
            staff_session.csrf_hash, hash_secret(csrf_token)
        ):
            invalid_csrf = True
        elif (
            _as_utc(staff_session.expires_at) <= now
            or _as_utc(staff_session.last_activity_at)
            + timedelta(minutes=settings.admin_idle_minutes)
            <= now
        ):
            staff_session.revoked_at = now
            unauthorized = True
        else:
            account = (
                session.query(StaffAccount)
                .filter(StaffAccount.id == staff_session.user_id)
                .with_for_update()
                .one_or_none()
            )
            if account is None or not account.active:
                unauthorized = True
            else:
                rotated_refresh_token = random_token()
                next_csrf_token = random_token()
                staff_session.refresh_hash = hash_secret(rotated_refresh_token)
                staff_session.csrf_hash = hash_secret(next_csrf_token)
                staff_session.last_activity_at = now
                cookie_max_age = max(
                    0, int((_as_utc(staff_session.expires_at) - now).total_seconds())
                )
                access_token = create_access_token(
                    user_id=staff_session.user_id,
                    session_id=staff_session.id,
                    signing_key=settings.jwt_secret,
                    now=now,
                    lifetime_minutes=settings.access_token_minutes,
                )
                refreshed_response = {
                    "access_token": access_token,
                    "csrf_token": next_csrf_token,
                }

    if invalid_csrf:
        raise HTTPException(status_code=403, detail="CSRF token is invalid")
    if unauthorized or refreshed_response is None or rotated_refresh_token is None:
        raise HTTPException(status_code=401, detail="Session is invalid or expired")

    response.set_cookie(
        key="roomforge_refresh",
        value=rotated_refresh_token,
        httponly=True,
        secure=settings.secure_cookies,
        samesite="lax",
        path="/api/v1/auth",
        max_age=cookie_max_age,
    )
    return refreshed_response


@router.post("/logout", response_model=None)
def logout(request: Request, response: Response) -> Response:
    settings: Settings = request.app.state.settings
    if request.headers.get("origin") != settings.web_origin:
        raise HTTPException(status_code=403, detail="Origin is not allowed")

    refresh_token = request.cookies.get("roomforge_refresh")
    if refresh_token is not None:
        csrf_token = request.headers.get("x-csrf-token")
        if csrf_token is None:
            raise HTTPException(status_code=403, detail="CSRF token is required")

        session_factory: sessionmaker[Session] = request.app.state.session_factory
        now = _as_utc(request.app.state.clock())
        invalid_csrf = False

        with session_factory.begin() as session:
            staff_session = (
                session.query(StaffSession)
                .filter(StaffSession.refresh_hash == hash_secret(refresh_token))
                .with_for_update()
                .one_or_none()
            )
            if staff_session is not None and staff_session.revoked_at is None:
                if (
                    _as_utc(staff_session.expires_at) <= now
                    or _as_utc(staff_session.last_activity_at)
                    + timedelta(minutes=settings.admin_idle_minutes)
                    <= now
                ):
                    staff_session.revoked_at = now
                elif not hmac.compare_digest(
                    staff_session.csrf_hash, hash_secret(csrf_token)
                ):
                    invalid_csrf = True
                else:
                    staff_session.revoked_at = now

        if invalid_csrf:
            raise HTTPException(status_code=403, detail="CSRF token is invalid")

    response.delete_cookie(
        key="roomforge_refresh",
        path="/api/v1/auth",
        secure=settings.secure_cookies,
        httponly=True,
        samesite="lax",
    )
    response.status_code = 204
    return response


@router.get("/me", response_model=None)
def me(request: Request) -> dict[str, object]:
    return {"user": get_active_staff(request)}
