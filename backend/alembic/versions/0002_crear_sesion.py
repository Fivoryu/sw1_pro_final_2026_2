"""Create the session table.

Revision ID: 0002
Revises: 0001
"""
from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0002"
down_revision: Union[str, Sequence[str], None] = "0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create only the sesion table and its supporting index."""
    op.create_table(
        "sesion",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("usuario_global_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("refresh_token_hash", sa.CHAR(length=64), nullable=False),
        sa.Column("expira_en", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ultima_actividad", sa.DateTime(timezone=True), nullable=True),
        sa.Column("revocado", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.ForeignKeyConstraint(["usuario_global_id"], ["usuario_global.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("refresh_token_hash", name="uq_sesion_refresh_token_hash"),
    )
    op.create_index(
        "ix_sesion_usuario_global_revocado",
        "sesion",
        ["usuario_global_id", "revocado"],
    )


def downgrade() -> None:
    """Drop only the sesion table."""
    op.drop_index("ix_sesion_usuario_global_revocado", table_name="sesion")
    op.drop_table("sesion")
