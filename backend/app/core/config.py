from __future__ import annotations

import os
from dataclasses import dataclass


def _positive_timeout_from_env(environment_name: str, default: int) -> int:
    value = os.environ.get(environment_name)
    if value is None:
        return default
    try:
        timeout = int(value)
    except ValueError:
        raise RuntimeError(f"{environment_name} must be a positive integer") from None
    if timeout < 1:
        raise RuntimeError(f"{environment_name} must be a positive integer")
    return timeout


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
    database_connect_timeout_seconds: int = 5
    database_pool_timeout_seconds: int = 5
    database_statement_timeout_seconds: int = 10
    email_send_timeout_seconds: int = 10
    s3_endpoint_url: str | None = None
    s3_bucket_name: str | None = None
    s3_public_endpoint_url: str | None = None
    s3_region: str = "us-east-1"
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
            database_connect_timeout_seconds=_positive_timeout_from_env(
                "DATABASE_CONNECT_TIMEOUT_SECONDS", 5
            ),
            database_pool_timeout_seconds=_positive_timeout_from_env(
                "DATABASE_POOL_TIMEOUT_SECONDS", 5
            ),
            database_statement_timeout_seconds=_positive_timeout_from_env(
                "DATABASE_STATEMENT_TIMEOUT_SECONDS", 10
            ),
            email_send_timeout_seconds=_positive_timeout_from_env(
                "STAFF_EMAIL_SEND_TIMEOUT_SECONDS", 10
            ),
            s3_endpoint_url=os.environ.get("S3_ENDPOINT_URL"),
            s3_bucket_name=os.environ.get("S3_BUCKET_NAME") or None,
            s3_public_endpoint_url=os.environ.get("S3_PUBLIC_ENDPOINT_URL") or None,
            s3_region=os.environ.get("AWS_DEFAULT_REGION") or "us-east-1",
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
            self.database_connect_timeout_seconds,
            self.database_pool_timeout_seconds,
            self.database_statement_timeout_seconds,
            self.email_send_timeout_seconds,
        ) < 1:
            raise ValueError("Timeouts and recovery-code count must be positive")
