"""Enforce one pending staff invitation per normalized email.

Revision ID: 0004_pending_staff_email_uniq
Revises: 0003_agency_registry
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0004_pending_staff_email_uniq"
down_revision = "0003_agency_registry"
branch_labels = None
depends_on = None

_INDEX_NAME = "uq_staff_invitation_pending_normalized_email"


def upgrade() -> None:
    bind = op.get_bind()
    duplicate_groups = bind.execute(
        sa.text(
            "SELECT count(*) FROM ("
            "SELECT lower(trim(email)) "
            "FROM staff_invitation "
            "WHERE status = 'pending' "
            "GROUP BY lower(trim(email)) "
            "HAVING count(*) > 1"
            ")"
        )
    ).scalar_one()
    if duplicate_groups:
        raise RuntimeError(
            "Cannot create the pending normalized-email unique index: "
            f"{duplicate_groups} duplicate normalized pending-email group(s) exist; "
            "resolve them explicitly before retrying the migration."
        )

    op.create_index(
        _INDEX_NAME,
        "staff_invitation",
        [sa.func.lower(sa.func.trim(sa.column("email")))],
        unique=True,
        sqlite_where=sa.text("status = 'pending'"),
        postgresql_where=sa.text("status = 'pending'"),
    )


def downgrade() -> None:
    op.drop_index(_INDEX_NAME, table_name="staff_invitation")
