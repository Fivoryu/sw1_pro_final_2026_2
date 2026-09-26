from __future__ import annotations

import sqlite3
from collections.abc import Callable
from datetime import datetime, timedelta, timezone
from hashlib import sha256

from sqlalchemy import func, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.orm.attributes import InstrumentedAttribute
from sqlalchemy.sql.elements import ColumnElement

from app.core.config import Settings
from app.core.security import hash_secret, random_token
from app.modules.identity.models import (
    StaffAccount,
    StaffEnrollmentChallenge,
    StaffInvitation,
)
from app.modules.identity.notifier import EmailSender, configured_email_sender


class InvitationConflictError(RuntimeError):
    pass


class InvitationDeliveryError(RuntimeError):
    pass


_PENDING_EMAIL_INDEX = "uq_staff_invitation_pending_normalized_email"


def _is_pending_email_unique_conflict(error: IntegrityError) -> bool:
    original = error.orig
    sqlstate = getattr(original, "sqlstate", None) or getattr(
        original, "pgcode", None
    )
    if sqlstate == "23505":
        diagnostic = getattr(original, "diag", None)
        return (
            getattr(diagnostic, "constraint_name", None) == _PENDING_EMAIL_INDEX
        )

    if isinstance(original, sqlite3.IntegrityError):
        args = getattr(original, "args", ())
        message = str(args[-1]) if args else str(original)
        return message.strip().casefold() in {
            f"unique constraint failed: index '{_PENDING_EMAIL_INDEX}'",
            f'unique constraint failed: index "{_PENDING_EMAIL_INDEX}"',
        }
    return False


def normalize_email(email: str) -> str:
    return email.strip().lower()


def lock_normalized_email(session: Session, email: str) -> int | None:
    normalized_email = normalize_email(email)
    if session.get_bind().dialect.name != "postgresql":
        return None

    lock_key = int.from_bytes(
        sha256(normalized_email.encode("utf-8")).digest()[:8],
        byteorder="big",
        signed=True,
    )
    session.execute(
        text("SELECT pg_advisory_xact_lock(:lock_key)"),
        {"lock_key": lock_key},
    )
    return lock_key


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _email_match(
    column: InstrumentedAttribute[str] | ColumnElement[str], normalized_email: str
) -> ColumnElement[bool]:
    return func.lower(func.trim(column)) == normalized_email


def _pending_invitations_for_email(
    session: Session, normalized_email: str
) -> list[StaffInvitation]:
    return (
        session.query(StaffInvitation)
        .filter(
            _email_match(StaffInvitation.email, normalized_email),
            StaffInvitation.status == "pending",
        )
        .with_for_update()
        .all()
    )


def has_staff_account(session: Session, normalized_email: str) -> bool:
    return (
        session.query(StaffAccount.id)
        .filter(_email_match(StaffAccount.email, normalized_email))
        .with_for_update()
        .first()
        is not None
    )


def has_active_enrollment_claim(
    session: Session,
    normalized_email: str,
    now: datetime,
    *,
    exclude_invitation_id: str | None = None,
) -> bool:
    query = (
        session.query(StaffEnrollmentChallenge.id)
        .join(
            StaffInvitation,
            StaffInvitation.id == StaffEnrollmentChallenge.invitation_id,
        )
        .filter(
            _email_match(StaffInvitation.email, normalized_email),
            StaffInvitation.status == "accepted",
            StaffEnrollmentChallenge.expires_at > now,
        )
    )
    if exclude_invitation_id is not None:
        query = query.filter(StaffInvitation.id != exclude_invitation_id)
    return query.with_for_update().first() is not None


def has_email_claim_conflict(
    session: Session,
    normalized_email: str,
    now: datetime,
    *,
    exclude_invitation_id: str | None = None,
) -> bool:
    if has_staff_account(session, normalized_email):
        return True

    active_pending_invitation = False
    for pending in _pending_invitations_for_email(session, normalized_email):
        if _as_utc(pending.expires_at) <= now:
            pending.status = "expired"
        elif pending.id != exclude_invitation_id:
            active_pending_invitation = True

    return active_pending_invitation or has_active_enrollment_claim(
        session,
        normalized_email,
        now,
        exclude_invitation_id=exclude_invitation_id,
    )


def issue_agency_admin_invitation(
    *,
    session_factory: sessionmaker[Session],
    email_sender: EmailSender | None,
    email: str,
    tenant_id: str,
    settings: Settings,
    clock: Callable[[], datetime],
) -> None:
    normalized_email = normalize_email(email)
    if not normalized_email:
        raise ValueError("Invitation email must not be empty")

    now = _as_utc(clock())
    conflict = False
    invitation_id: str | None = None
    invitation_link: str | None = None
    expires_at: datetime | None = None

    try:
        with session_factory.begin() as session:
            lock_normalized_email(session, normalized_email)
            if has_email_claim_conflict(session, normalized_email, now):
                conflict = True
            else:
                raw_token = random_token()
                expires_at = now + timedelta(hours=settings.invitation_ttl_hours)
                invitation = StaffInvitation(
                    email=normalized_email,
                    role="agency_admin",
                    tenant_id=tenant_id,
                    token_hash=hash_secret(raw_token),
                    status="pending",
                    issued_at=now,
                    expires_at=expires_at,
                )
                session.add(invitation)
                session.flush()
                invitation_id = invitation.id
                invitation_link = (
                    f"{settings.web_origin.rstrip('/')}/invitations/accept/{raw_token}"
                )
    except IntegrityError as error:
        if not _is_pending_email_unique_conflict(error):
            raise
        raise InvitationConflictError(
            "An account or active invitation already uses this email"
        ) from None

    if conflict:
        raise InvitationConflictError(
            "An account or active invitation already uses this email"
        )
    if invitation_id is None or invitation_link is None or expires_at is None:
        raise RuntimeError("Agency-admin invitation could not be created")

    try:
        sender = email_sender if email_sender is not None else configured_email_sender()
        sender.send_invitation(normalized_email, invitation_link, expires_at)
    except Exception:
        with session_factory.begin() as session:
            persisted_invitation = session.get(StaffInvitation, invitation_id)
            if persisted_invitation is None:
                raise RuntimeError(
                    "Agency-admin invitation could not be updated after delivery failure"
                ) from None
            persisted_invitation.status = "revoked"
            persisted_invitation.delivery_status = "failed"
        raise InvitationDeliveryError("Agency-admin invitation email delivery failed") from None

    with session_factory.begin() as session:
        persisted_invitation = session.get(StaffInvitation, invitation_id)
        if persisted_invitation is None:
            raise RuntimeError("Agency-admin invitation could not be marked as sent")
        persisted_invitation.delivery_status = "sent"


def reject_cross_role_pending_invitation(
    *, session: Session, normalized_email: str, now: datetime, current_role: str
) -> None:
    cross_role_conflict = False
    for pending in _pending_invitations_for_email(session, normalized_email):
        if _as_utc(pending.expires_at) <= now:
            pending.status = "expired"
        elif pending.role != current_role:
            cross_role_conflict = True
    if cross_role_conflict:
        raise InvitationConflictError("An active invitation already uses this email")
