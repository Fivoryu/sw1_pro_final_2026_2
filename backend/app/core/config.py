from __future__ import annotations

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    database_url: str | None = Field(default=None, validation_alias="DATABASE_URL")
    argon2_time_cost: int | None = Field(default=None, validation_alias="ARGON2_TIME_COST")
    argon2_memory_cost: int | None = Field(default=None, validation_alias="ARGON2_MEMORY_COST")
    argon2_parallelism: int | None = Field(default=None, validation_alias="ARGON2_PARALLELISM")
    argon2_hash_len: int | None = Field(default=None, validation_alias="ARGON2_HASH_LEN")
    argon2_salt_len: int | None = Field(default=None, validation_alias="ARGON2_SALT_LEN")
    app_env: str = Field(default="development", validation_alias="APP_ENV")

    def argon2_options(self) -> dict[str, int]:
        values = {
            "time_cost": self.argon2_time_cost,
            "memory_cost": self.argon2_memory_cost,
            "parallelism": self.argon2_parallelism,
            "hash_len": self.argon2_hash_len,
            "salt_len": self.argon2_salt_len,
        }
        return {key: value for key, value in values.items() if value is not None}


@lru_cache
def get_settings() -> Settings:
    return Settings()
