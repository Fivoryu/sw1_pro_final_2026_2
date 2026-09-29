from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    database_url: str
    jwt_secret: str
    totp_encryption_key: str
    web_origin: str
    secure_cookies: bool = True
    access_token_minutes: int = 15
    refresh_token_days: int = 30
    invitation_ttl_hours: int = 168
    enrollment_ttl_minutes: int = 15
    login_challenge_minutes: int = 5
    admin_idle_minutes: int = 30
    recovery_code_count: int = 10
    escrow_rpc_url: str | None = None
    escrow_address: str | None = None
    escrow_chain_id: str | None = None
    escrow_signer_private_key: str | None = None

    @classmethod
    def from_env(cls) -> Settings:
        required = {
            "database_url": "DATABASE_URL",
            "jwt_secret": "JWT_SECRET",
            "totp_encryption_key": "STAFF_TOTP_ENCRYPTION_KEY",
            "web_origin": "STAFF_WEB_ORIGIN",
        }
        values: dict[str, str] = {}
        for field, env_name in required.items():
            value = os.environ.get(env_name)
            if not value:
                raise RuntimeError(f"Required configuration is missing: {env_name}")
            values[field] = value
        if len(values["jwt_secret"].encode("utf-8")) < 32:
            raise RuntimeError("JWT_SECRET must contain at least 32 bytes")
        origin = values["web_origin"].rstrip("/")
        if not origin.startswith(("https://", "http://localhost", "http://127.0.0.1")):
            raise RuntimeError("STAFF_WEB_ORIGIN must be an exact HTTP(S) origin")
        return cls(
            database_url=values["database_url"],
            jwt_secret=values["jwt_secret"],
            totp_encryption_key=values["totp_encryption_key"],
            web_origin=origin,
            secure_cookies=os.environ.get("STAFF_SECURE_COOKIES", "true").lower() != "false",
            escrow_rpc_url=os.environ.get("ROOMFORGE_ESCROW_RPC_URL"),
            escrow_address=os.environ.get("ROOMFORGE_ESCROW_ADDRESS"),
            escrow_chain_id=os.environ.get("ROOMFORGE_ESCROW_CHAIN_ID"),
            escrow_signer_private_key=os.environ.get("ROOMFORGE_ESCROW_SIGNER_PRIVATE_KEY"),
        )

    def validate(self) -> None:
        if len(self.jwt_secret.encode("utf-8")) < 32:
            raise ValueError("JWT signing key must contain at least 32 bytes")
        if not self.web_origin.startswith(("https://", "http://localhost", "http://127.0.0.1")):
            raise ValueError("Web origin must be an exact HTTP(S) origin")
        if min(
            self.access_token_minutes,
            self.refresh_token_days,
            self.invitation_ttl_hours,
            self.enrollment_ttl_minutes,
            self.login_challenge_minutes,
            self.admin_idle_minutes,
            self.recovery_code_count,
        ) < 1:
            raise ValueError("Authentication timeouts and recovery-code count must be positive")
