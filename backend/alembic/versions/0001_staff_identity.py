"""Create isolated staff identity and authentication tables.

Revision ID: 0001_staff_identity
Revises:
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "0001_staff_identity"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "staff_account",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("email", sa.String(length=320), nullable=False),
        sa.Column("password_hash", sa.Text(), nullable=False),
        sa.Column("role", sa.String(length=32), nullable=False),
        sa.Column("tenant_id", sa.String(length=36), nullable=True),
        sa.Column("active", sa.Boolean(), nullable=False),
        sa.Column("totp_secret_encrypted", sa.Text(), nullable=True),
        sa.Column("totp_enabled", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("role IN ('platform_admin', 'agency_admin', 'agent')", name="ck_staff_account_role"),
        sa.CheckConstraint(
            "(role = 'platform_admin' AND tenant_id IS NULL) OR (role != 'platform_admin' AND tenant_id IS NOT NULL)",
            name="ck_staff_account_tenant_role",
        ),
    )
    op.create_index("ix_staff_account_email", "staff_account", ["email"], unique=True)
    op.create_index("ix_staff_account_tenant_id", "staff_account", ["tenant_id"])
    op.create_index(
        "uq_staff_account_platform_admin",
        "staff_account",
        ["role"],
        unique=True,
        sqlite_where=sa.text("role = 'platform_admin'"),
        postgresql_where=sa.text("role = 'platform_admin'"),
    )

    op.create_table(
        "staff_invitation",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("email", sa.String(length=320), nullable=False),
        sa.Column("role", sa.String(length=32), nullable=False),
        sa.Column("tenant_id", sa.String(length=36), nullable=True),
        sa.Column("token_hash", sa.String(length=64), nullable=False, unique=True),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("issued_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("accepted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("delivery_status", sa.String(length=16), nullable=False),
        sa.CheckConstraint("role IN ('platform_admin', 'agency_admin', 'agent')", name="ck_staff_invitation_role"),
        sa.CheckConstraint("status IN ('pending', 'accepted', 'expired', 'invalidated')", name="ck_staff_invitation_status"),
    )
    op.create_index(
        "uq_staff_invitation_pending_platform_admin",
        "staff_invitation",
        ["role"],
        unique=True,
        sqlite_where=sa.text("role = 'platform_admin' AND status = 'pending'"),
        postgresql_where=sa.text("role = 'platform_admin' AND status = 'pending'"),
    )

    op.create_table(
        "staff_enrollment_challenge",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("invitation_id", sa.String(length=36), sa.ForeignKey("staff_invitation.id", ondelete="CASCADE"), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False, unique=True),
        sa.Column("password_hash", sa.Text(), nullable=False),
        sa.Column("totp_secret_encrypted", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("consumed_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("invitation_id", name="uq_staff_enrollment_invitation"),
    )

    op.create_table(
        "staff_login_challenge",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("user_id", sa.String(length=36), sa.ForeignKey("staff_account.id", ondelete="CASCADE"), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False, unique=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("consumed_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_staff_login_challenge_user_id", "staff_login_challenge", ["user_id"])

    op.create_table(
        "staff_recovery_code",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("user_id", sa.String(length=36), sa.ForeignKey("staff_account.id", ondelete="CASCADE"), nullable=False),
        sa.Column("code_hash", sa.String(length=64), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("user_id", "code_hash", name="uq_staff_recovery_code_hash"),
    )
    op.create_index("ix_staff_recovery_code_user_id", "staff_recovery_code", ["user_id"])

    op.create_table(
        "staff_session",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("user_id", sa.String(length=36), sa.ForeignKey("staff_account.id", ondelete="CASCADE"), nullable=False),
        sa.Column("refresh_hash", sa.String(length=64), nullable=False, unique=True),
        sa.Column("csrf_hash", sa.String(length=64), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_activity_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_staff_session_user_id", "staff_session", ["user_id"])


def downgrade() -> None:
    op.drop_index("ix_staff_session_user_id", table_name="staff_session")
    op.drop_table("staff_session")
    op.drop_index("ix_staff_recovery_code_user_id", table_name="staff_recovery_code")
    op.drop_table("staff_recovery_code")
    op.drop_index("ix_staff_login_challenge_user_id", table_name="staff_login_challenge")
    op.drop_table("staff_login_challenge")
    op.drop_table("staff_enrollment_challenge")
    op.drop_index("uq_staff_invitation_pending_platform_admin", table_name="staff_invitation")
    op.drop_table("staff_invitation")
    op.drop_index("uq_staff_account_platform_admin", table_name="staff_account")
    op.drop_index("ix_staff_account_tenant_id", table_name="staff_account")
    op.drop_index("ix_staff_account_email", table_name="staff_account")
    op.drop_table("staff_account")
