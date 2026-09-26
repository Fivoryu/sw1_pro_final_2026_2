from __future__ import annotations

import argparse
import sys
from collections.abc import Callable
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session, sessionmaker

from app.core.config import Settings
from app.core.security import hash_secret, random_token
from app.db.session import create_session_factory
from app.modules.identity.models import StaffInvitation
from app.modules.identity.notifier import EmailSender, configured_email_sender


def normalize_email(email: str) -> str:
    return email.strip().lower()


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def issue_platform_admin_invitation(
    *,
    session_factory: sessionmaker[Session],
    email_sender: EmailSender,
    email: str,
    settings: Settings,
    clock: Callable[[], datetime],
) -> None:
    normalized_email = normalize_email(email)
    if not normalized_email:
        raise ValueError("Invitation email must not be empty")

    now = _as_utc(clock())
    with session_factory.begin() as session:
        pending = (
            session.query(StaffInvitation)
            .filter(
                StaffInvitation.role == "platform_admin",
                StaffInvitation.status == "pending",
            )
            .one_or_none()
        )
        if pending is not None:
            if _as_utc(pending.expires_at) > now:
                raise RuntimeError("An active platform-admin invitation already exists")
            pending.status = "expired"

    # Commit expiration first so a failed replacement delivery cannot reactivate the old link.
    with session_factory.begin() as session:
        pending = (
            session.query(StaffInvitation)
            .filter(
                StaffInvitation.role == "platform_admin",
                StaffInvitation.status == "pending",
            )
            .one_or_none()
        )
        if pending is not None:
            if _as_utc(pending.expires_at) > now:
                raise RuntimeError("An active platform-admin invitation already exists")
            pending.status = "expired"
            session.flush()

    with session_factory.begin() as session:
        pending = (
            session.query(StaffInvitation)
            .filter(
                StaffInvitation.role == "platform_admin",
                StaffInvitation.status == "pending",
            )
            .one_or_none()
        )
        if pending is not None:
            if _as_utc(pending.expires_at) > now:
                raise RuntimeError("An active platform-admin invitation already exists")
            pending.status = "expired"
            session.flush()

        raw_token = random_token()
        expires_at = now + timedelta(hours=settings.invitation_ttl_hours)
        invitation = StaffInvitation(
            email=normalized_email,
            role="platform_admin",
            tenant_id=None,
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

    try:
        email_sender.send_invitation(normalized_email, invitation_link, expires_at)
    except Exception:
        with session_factory.begin() as session:
            persisted_invitation = session.get(StaffInvitation, invitation_id)
            if persisted_invitation is None:
                raise RuntimeError(
                    "Platform-admin invitation could not be updated after delivery failure"
                ) from None
            persisted_invitation.status = "revoked"
            persisted_invitation.delivery_status = "failed"
        raise RuntimeError("Platform-admin invitation email delivery failed") from None

    with session_factory.begin() as session:
        persisted_invitation = session.get(StaffInvitation, invitation_id)
        if persisted_invitation is None:
            raise RuntimeError("Platform-admin invitation could not be marked as sent")
        persisted_invitation.delivery_status = "sent"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Issue an operator-only platform-admin invitation."
    )
    parser.add_argument("--email", required=True, help="Email address to invite")
    args = parser.parse_args()

    engine = None
    try:
        settings = Settings.from_env()
        email_sender = configured_email_sender()
        engine, session_factory = create_session_factory(settings.database_url)
        issue_platform_admin_invitation(
            session_factory=session_factory,
            email_sender=email_sender,
            email=normalize_email(args.email),
            settings=settings,
            clock=lambda: datetime.now(timezone.utc),
        )
        return 0
    except Exception:
        print("Platform-admin invitation failed.", file=sys.stderr)
        return 1
    finally:
        if engine is not None:
            engine.dispose()


if __name__ == "__main__":
    raise SystemExit(main())
