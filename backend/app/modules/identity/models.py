"""SQLAlchemy schema for staff identity and authentication state."""

from __future__ import annotations

from datetime import datetime
from uuid import uuid4

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Agency(Base):
    __tablename__ = "agency"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)


class StaffAccount(Base):
    __tablename__ = "staff_account"
    __table_args__ = (
        CheckConstraint(
            "role IN ('platform_admin', 'agency_admin', 'agent')",
            name="ck_staff_account_role",
        ),
        CheckConstraint(
            "(role = 'platform_admin' AND tenant_id IS NULL) "
            "OR (role IN ('agency_admin', 'agent') AND tenant_id IS NOT NULL)",
            name="ck_staff_account_role_tenant",
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    email: Mapped[str] = mapped_column(String(320), nullable=False, unique=True)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    role: Mapped[str] = mapped_column(String(32), nullable=False)
    tenant_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("agency.id"), nullable=True
    )
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    totp_secret_encrypted: Mapped[str | None] = mapped_column(Text, nullable=True)
    totp_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


Index(
    "uq_staff_account_single_platform_admin",
    StaffAccount.role,
    unique=True,
    sqlite_where=StaffAccount.role == "platform_admin",
    postgresql_where=StaffAccount.role == "platform_admin",
)


class StaffInvitation(Base):
    __tablename__ = "staff_invitation"
    __table_args__ = (
        CheckConstraint(
            "role IN ('platform_admin', 'agency_admin', 'agent')",
            name="ck_staff_invitation_role",
        ),
        CheckConstraint(
            "(role = 'platform_admin' AND tenant_id IS NULL) "
            "OR (role IN ('agency_admin', 'agent') AND tenant_id IS NOT NULL)",
            name="ck_staff_invitation_role_tenant",
        ),
        CheckConstraint(
            "status IN ('pending', 'accepted', 'expired', 'revoked')",
            name="ck_staff_invitation_status",
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    email: Mapped[str] = mapped_column(String(320), nullable=False)
    role: Mapped[str] = mapped_column(String(32), nullable=False)
    tenant_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("agency.id"), nullable=True
    )
    token_hash: Mapped[str] = mapped_column(String(128), nullable=False, unique=True)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
    issued_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    delivery_status: Mapped[str] = mapped_column(
        String(24), nullable=False, default="pending"
    )


Index(
    "uq_staff_invitation_pending_platform_admin",
    StaffInvitation.role,
    StaffInvitation.status,
    unique=True,
    sqlite_where=(
        (StaffInvitation.role == "platform_admin")
        & (StaffInvitation.status == "pending")
    ),
    postgresql_where=(
        (StaffInvitation.role == "platform_admin")
        & (StaffInvitation.status == "pending")
    ),
)

Index(
    "uq_staff_invitation_pending_normalized_email",
    func.lower(func.trim(StaffInvitation.email)),
    unique=True,
    sqlite_where=StaffInvitation.status == "pending",
    postgresql_where=StaffInvitation.status == "pending",
)


class StaffSession(Base):
    __tablename__ = "staff_session"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    user_id: Mapped[str] = mapped_column(
        ForeignKey("staff_account.id", ondelete="CASCADE"), nullable=False
    )
    refresh_hash: Mapped[str] = mapped_column(String(128), nullable=False, unique=True)
    csrf_hash: Mapped[str] = mapped_column(String(128), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    last_activity_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class StaffEnrollmentChallenge(Base):
    __tablename__ = "staff_enrollment_challenge"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    invitation_id: Mapped[str] = mapped_column(
        ForeignKey("staff_invitation.id", ondelete="CASCADE"), nullable=False, unique=True
    )
    token_hash: Mapped[str] = mapped_column(String(128), nullable=False, unique=True)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    totp_secret_encrypted: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class StaffLoginChallenge(Base):
    __tablename__ = "staff_login_challenge"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    user_id: Mapped[str] = mapped_column(
        ForeignKey("staff_account.id", ondelete="CASCADE"), nullable=False
    )
    token_hash: Mapped[str] = mapped_column(String(128), nullable=False, unique=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class StaffRecoveryCode(Base):
    __tablename__ = "staff_recovery_code"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    user_id: Mapped[str] = mapped_column(
        ForeignKey("staff_account.id", ondelete="CASCADE"), nullable=False
    )
    code_hash: Mapped[str] = mapped_column(String(128), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


Index(
    "uq_staff_recovery_code_user_hash",
    StaffRecoveryCode.user_id,
    StaffRecoveryCode.code_hash,
    unique=True,
)
