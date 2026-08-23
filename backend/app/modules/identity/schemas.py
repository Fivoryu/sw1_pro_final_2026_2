from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field, SecretStr


class RegistroRequest(BaseModel):
    correo: EmailStr = Field(max_length=255)
    password: SecretStr = Field(min_length=8)


class RegistroResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    correo: str
    estado: str
    correo_verificado: bool
    creado_en: datetime
