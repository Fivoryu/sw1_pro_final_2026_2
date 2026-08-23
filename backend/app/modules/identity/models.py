from __future__ import annotations

from datetime import datetime
from uuid import UUID

from sqlalchemy import CHAR, Boolean, DateTime, ForeignKey, Index, String, UniqueConstraint, text
from sqlalchemy.dialects.postgresql import UUID as PostgreSQLUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class UsuarioGlobal(Base):
    __tablename__ = "usuario_global"
    __table_args__ = (UniqueConstraint("correo", name="uq_usuario_global_correo"),)

    id: Mapped[UUID] = mapped_column(
        PostgreSQLUUID(as_uuid=True),
        primary_key=True,
        server_default=text("gen_random_uuid()"),
    )
    correo: Mapped[str] = mapped_column(String(255), nullable=False)
    hash_password: Mapped[str] = mapped_column(String(255), nullable=False)
    estado: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        server_default=text("'activo'"),
    )
    correo_verificado: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        server_default=text("false"),
    )
    creado_en: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=text("now()"),
    )


class Sesion(Base):
    __tablename__ = "sesion"
    __table_args__ = (
        UniqueConstraint("refresh_token_hash", name="uq_sesion_refresh_token_hash"),
        Index("ix_sesion_usuario_global_revocado", "usuario_global_id", "revocado"),
    )

    id: Mapped[UUID] = mapped_column(
        PostgreSQLUUID(as_uuid=True),
        primary_key=True,
        server_default=text("gen_random_uuid()"),
    )
    usuario_global_id: Mapped[UUID] = mapped_column(
        PostgreSQLUUID(as_uuid=True),
        ForeignKey("usuario_global.id"),
        nullable=False,
    )
    refresh_token_hash: Mapped[str] = mapped_column(CHAR(64), nullable=False)
    expira_en: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    ultima_actividad: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    revocado: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        server_default=text("false"),
    )
