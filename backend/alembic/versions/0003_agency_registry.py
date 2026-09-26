"""Add persisted agencies and link staff tenants to the registry.

Revision ID: 0003_agency_registry
Revises: 0002_staff_identity_align
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "0003_agency_registry"
down_revision = "0002_staff_identity_align"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "agency",
        sa.Column("id", sa.String(length=36), primary_key=True),
    )
    op.execute(
        sa.text(
            "INSERT INTO agency (id) "
            "SELECT tenant_id FROM staff_account WHERE tenant_id IS NOT NULL "
            "UNION "
            "SELECT tenant_id FROM staff_invitation WHERE tenant_id IS NOT NULL"
        )
    )

    with op.batch_alter_table("staff_account") as batch_op:
        batch_op.create_foreign_key(
            "fk_staff_account_tenant_agency",
            "agency",
            ["tenant_id"],
            ["id"],
        )

    with op.batch_alter_table("staff_invitation") as batch_op:
        batch_op.create_foreign_key(
            "fk_staff_invitation_tenant_agency",
            "agency",
            ["tenant_id"],
            ["id"],
        )


def downgrade() -> None:
    with op.batch_alter_table("staff_invitation") as batch_op:
        batch_op.drop_constraint(
            "fk_staff_invitation_tenant_agency", type_="foreignkey"
        )

    with op.batch_alter_table("staff_account") as batch_op:
        batch_op.drop_constraint("fk_staff_account_tenant_agency", type_="foreignkey")

    op.drop_table("agency")
