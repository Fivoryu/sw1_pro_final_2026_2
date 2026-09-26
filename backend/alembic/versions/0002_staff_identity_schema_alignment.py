"""Align the initial staff identity migration with current model metadata.

Revision ID: 0002_staff_identity_align
Revises: 0001_staff_identity
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "0002_staff_identity_align"
down_revision = "0001_staff_identity"
branch_labels = None
depends_on = None


_ACCOUNT_ROLE_TENANT_CHECK = (
    "(role = 'platform_admin' AND tenant_id IS NULL) "
    "OR (role IN ('agency_admin', 'agent') AND tenant_id IS NOT NULL)"
)
_INVITATION_ROLE_TENANT_CHECK = (
    "(role = 'platform_admin' AND tenant_id IS NULL) "
    "OR (role IN ('agency_admin', 'agent') AND tenant_id IS NOT NULL)"
)
_INVITATION_STATUS_CHECK = "status IN ('pending', 'accepted', 'expired', 'revoked')"


def upgrade() -> None:
    op.drop_constraint("ck_staff_account_tenant_role", "staff_account", type_="check")
    op.create_check_constraint(
        "ck_staff_account_role_tenant", "staff_account", _ACCOUNT_ROLE_TENANT_CHECK
    )

    op.drop_constraint("ck_staff_invitation_status", "staff_invitation", type_="check")
    op.execute(
        sa.text(
            "UPDATE staff_invitation SET status = 'revoked' WHERE status = 'invalidated'"
        )
    )
    op.create_check_constraint(
        "ck_staff_invitation_role_tenant",
        "staff_invitation",
        _INVITATION_ROLE_TENANT_CHECK,
    )
    op.create_check_constraint(
        "ck_staff_invitation_status", "staff_invitation", _INVITATION_STATUS_CHECK
    )

    op.drop_index("ix_staff_account_email", table_name="staff_account")
    op.create_unique_constraint(
        "uq_staff_account_email", "staff_account", ["email"]
    )
    op.drop_index("ix_staff_account_tenant_id", table_name="staff_account")
    op.drop_index("uq_staff_account_platform_admin", table_name="staff_account")
    op.create_index(
        "uq_staff_account_single_platform_admin",
        "staff_account",
        ["role"],
        unique=True,
        postgresql_where=sa.text("role = 'platform_admin'"),
    )

    op.drop_index(
        "uq_staff_invitation_pending_platform_admin", table_name="staff_invitation"
    )
    op.create_index(
        "uq_staff_invitation_pending_platform_admin",
        "staff_invitation",
        ["role", "status"],
        unique=True,
        postgresql_where=sa.text(
            "role = 'platform_admin' AND status = 'pending'"
        ),
    )

    op.alter_column(
        "staff_account",
        "password_hash",
        existing_type=sa.Text(),
        type_=sa.String(length=255),
        existing_nullable=False,
    )
    op.alter_column(
        "staff_account",
        "created_at",
        existing_type=sa.DateTime(timezone=True),
        existing_nullable=False,
        server_default=sa.text("now()"),
    )

    op.alter_column(
        "staff_invitation",
        "token_hash",
        existing_type=sa.String(length=64),
        type_=sa.String(length=128),
        existing_nullable=False,
    )
    op.alter_column(
        "staff_invitation",
        "delivery_status",
        existing_type=sa.String(length=16),
        type_=sa.String(length=24),
        existing_nullable=False,
    )
    op.alter_column(
        "staff_invitation",
        "issued_at",
        existing_type=sa.DateTime(timezone=True),
        existing_nullable=False,
        server_default=sa.text("now()"),
    )

    op.alter_column(
        "staff_enrollment_challenge",
        "token_hash",
        existing_type=sa.String(length=64),
        type_=sa.String(length=128),
        existing_nullable=False,
    )
    op.alter_column(
        "staff_enrollment_challenge",
        "password_hash",
        existing_type=sa.Text(),
        type_=sa.String(length=255),
        existing_nullable=False,
    )
    op.alter_column(
        "staff_enrollment_challenge",
        "attempts",
        existing_type=sa.Integer(),
        existing_nullable=False,
        server_default=None,
    )
    op.alter_column(
        "staff_enrollment_challenge",
        "created_at",
        existing_type=sa.DateTime(timezone=True),
        existing_nullable=False,
        server_default=sa.text("now()"),
    )

    op.alter_column(
        "staff_login_challenge",
        "token_hash",
        existing_type=sa.String(length=64),
        type_=sa.String(length=128),
        existing_nullable=False,
    )
    op.alter_column(
        "staff_login_challenge",
        "attempts",
        existing_type=sa.Integer(),
        existing_nullable=False,
        server_default=None,
    )
    op.alter_column(
        "staff_login_challenge",
        "created_at",
        existing_type=sa.DateTime(timezone=True),
        existing_nullable=False,
        server_default=sa.text("now()"),
    )

    op.alter_column(
        "staff_recovery_code",
        "code_hash",
        existing_type=sa.String(length=64),
        type_=sa.String(length=128),
        existing_nullable=False,
    )
    op.alter_column(
        "staff_recovery_code",
        "created_at",
        existing_type=sa.DateTime(timezone=True),
        existing_nullable=False,
        server_default=sa.text("now()"),
    )
    op.drop_constraint(
        "uq_staff_recovery_code_hash", "staff_recovery_code", type_="unique"
    )
    op.drop_index(
        "ix_staff_recovery_code_user_id", table_name="staff_recovery_code"
    )
    op.create_index(
        "uq_staff_recovery_code_user_hash",
        "staff_recovery_code",
        ["user_id", "code_hash"],
        unique=True,
    )

    op.alter_column(
        "staff_session",
        "refresh_hash",
        existing_type=sa.String(length=64),
        type_=sa.String(length=128),
        existing_nullable=False,
    )
    op.alter_column(
        "staff_session",
        "csrf_hash",
        existing_type=sa.String(length=64),
        type_=sa.String(length=128),
        existing_nullable=False,
    )
    op.alter_column(
        "staff_session",
        "created_at",
        existing_type=sa.DateTime(timezone=True),
        existing_nullable=False,
        server_default=sa.text("now()"),
    )
    op.alter_column(
        "staff_session",
        "last_activity_at",
        existing_type=sa.DateTime(timezone=True),
        existing_nullable=False,
        server_default=sa.text("now()"),
    )

    op.drop_index("ix_staff_login_challenge_user_id", table_name="staff_login_challenge")
    op.drop_index("ix_staff_session_user_id", table_name="staff_session")


def downgrade() -> None:
    op.create_index("ix_staff_session_user_id", "staff_session", ["user_id"])
    op.create_index(
        "ix_staff_login_challenge_user_id", "staff_login_challenge", ["user_id"]
    )

    op.alter_column(
        "staff_session",
        "last_activity_at",
        existing_type=sa.DateTime(timezone=True),
        existing_nullable=False,
        server_default=None,
    )
    op.alter_column(
        "staff_session",
        "created_at",
        existing_type=sa.DateTime(timezone=True),
        existing_nullable=False,
        server_default=None,
    )
    op.alter_column(
        "staff_session",
        "csrf_hash",
        existing_type=sa.String(length=128),
        type_=sa.String(length=64),
        existing_nullable=False,
    )
    op.alter_column(
        "staff_session",
        "refresh_hash",
        existing_type=sa.String(length=128),
        type_=sa.String(length=64),
        existing_nullable=False,
    )

    op.drop_index(
        "uq_staff_recovery_code_user_hash", table_name="staff_recovery_code"
    )
    op.create_index(
        "ix_staff_recovery_code_user_id", "staff_recovery_code", ["user_id"]
    )
    op.create_unique_constraint(
        "uq_staff_recovery_code_hash",
        "staff_recovery_code",
        ["user_id", "code_hash"],
    )
    op.alter_column(
        "staff_recovery_code",
        "created_at",
        existing_type=sa.DateTime(timezone=True),
        existing_nullable=False,
        server_default=None,
    )
    op.alter_column(
        "staff_recovery_code",
        "code_hash",
        existing_type=sa.String(length=128),
        type_=sa.String(length=64),
        existing_nullable=False,
    )

    op.alter_column(
        "staff_login_challenge",
        "created_at",
        existing_type=sa.DateTime(timezone=True),
        existing_nullable=False,
        server_default=None,
    )
    op.alter_column(
        "staff_login_challenge",
        "attempts",
        existing_type=sa.Integer(),
        existing_nullable=False,
        server_default="0",
    )
    op.alter_column(
        "staff_login_challenge",
        "token_hash",
        existing_type=sa.String(length=128),
        type_=sa.String(length=64),
        existing_nullable=False,
    )

    op.alter_column(
        "staff_enrollment_challenge",
        "created_at",
        existing_type=sa.DateTime(timezone=True),
        existing_nullable=False,
        server_default=None,
    )
    op.alter_column(
        "staff_enrollment_challenge",
        "attempts",
        existing_type=sa.Integer(),
        existing_nullable=False,
        server_default="0",
    )
    op.alter_column(
        "staff_enrollment_challenge",
        "password_hash",
        existing_type=sa.String(length=255),
        type_=sa.Text(),
        existing_nullable=False,
    )
    op.alter_column(
        "staff_enrollment_challenge",
        "token_hash",
        existing_type=sa.String(length=128),
        type_=sa.String(length=64),
        existing_nullable=False,
    )

    op.alter_column(
        "staff_invitation",
        "issued_at",
        existing_type=sa.DateTime(timezone=True),
        existing_nullable=False,
        server_default=None,
    )
    op.alter_column(
        "staff_invitation",
        "delivery_status",
        existing_type=sa.String(length=24),
        type_=sa.String(length=16),
        existing_nullable=False,
    )
    op.alter_column(
        "staff_invitation",
        "token_hash",
        existing_type=sa.String(length=128),
        type_=sa.String(length=64),
        existing_nullable=False,
    )

    op.drop_index(
        "uq_staff_invitation_pending_platform_admin", table_name="staff_invitation"
    )
    op.create_index(
        "uq_staff_invitation_pending_platform_admin",
        "staff_invitation",
        ["role"],
        unique=True,
        postgresql_where=sa.text(
            "role = 'platform_admin' AND status = 'pending'"
        ),
    )
    op.drop_constraint(
        "ck_staff_invitation_role_tenant", "staff_invitation", type_="check"
    )
    op.drop_constraint("ck_staff_invitation_status", "staff_invitation", type_="check")
    op.execute(
        sa.text("UPDATE staff_invitation SET status = 'invalidated' WHERE status = 'revoked'")
    )
    op.create_check_constraint(
        "ck_staff_invitation_status",
        "staff_invitation",
        "status IN ('pending', 'accepted', 'expired', 'invalidated')",
    )

    op.drop_index(
        "uq_staff_account_single_platform_admin", table_name="staff_account"
    )
    op.create_index(
        "uq_staff_account_platform_admin",
        "staff_account",
        ["role"],
        unique=True,
        postgresql_where=sa.text("role = 'platform_admin'"),
    )
    op.create_index("ix_staff_account_tenant_id", "staff_account", ["tenant_id"])
    op.drop_constraint("uq_staff_account_email", "staff_account", type_="unique")
    op.create_index("ix_staff_account_email", "staff_account", ["email"], unique=True)
    op.drop_constraint(
        "ck_staff_account_role_tenant", "staff_account", type_="check"
    )
    op.create_check_constraint(
        "ck_staff_account_tenant_role",
        "staff_account",
        "(role = 'platform_admin' AND tenant_id IS NULL) OR "
        "(role != 'platform_admin' AND tenant_id IS NOT NULL)",
    )
    op.alter_column(
        "staff_account",
        "created_at",
        existing_type=sa.DateTime(timezone=True),
        existing_nullable=False,
        server_default=None,
    )
    op.alter_column(
        "staff_account",
        "password_hash",
        existing_type=sa.String(length=255),
        type_=sa.Text(),
        existing_nullable=False,
    )
