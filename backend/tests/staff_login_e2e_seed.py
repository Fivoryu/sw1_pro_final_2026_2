from __future__ import annotations

import base64
import os
import re
import sys
from datetime import datetime, timezone

from sqlalchemy.engine import make_url

from app.core.config import Settings
from app.core.security import encrypt_totp_secret, hash_password
from app.db.session import create_session_factory
from app.modules.identity.models import StaffAccount

_DATABASE_NAME = re.compile(r"roomforge_staff_e2e_([0-9a-f]{16})\Z")
_RUN_ID = re.compile(r"[0-9a-f]{16}\Z")
_EMAIL = re.compile(r"staff-e2e-[0-9a-f]{16}@example\.test\Z")
_TOTP_SECRET = re.compile(r"[A-Z2-7]{32}\Z")


def _required_environment(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise ValueError(f"Required E2E seed setting is missing: {name}")
    return value


def _validate_isolated_target(database_url: str, run_id: str) -> None:
    parsed_url = make_url(database_url)
    database_match = _DATABASE_NAME.fullmatch(parsed_url.database or "")
    if (
        parsed_url.get_backend_name() != "postgresql"
        or parsed_url.drivername != "postgresql+psycopg"
        or parsed_url.host != "127.0.0.1"
        or parsed_url.port is None
        or parsed_url.username is None
        or parsed_url.password is None
        or database_match is None
        or not _RUN_ID.fullmatch(run_id)
        or database_match.group(1) != run_id
    ):
        raise ValueError("The E2E seed target is not a uniquely named loopback PostgreSQL database")


def seed_staff_account() -> None:
    run_id = _required_environment("STAFF_LOGIN_E2E_RUN_ID")
    database_url = _required_environment("DATABASE_URL")
    email = _required_environment("STAFF_LOGIN_E2E_EMAIL")
    password = _required_environment("STAFF_LOGIN_E2E_PASSWORD")
    totp_secret = _required_environment("STAFF_LOGIN_E2E_TOTP_SECRET")

    _validate_isolated_target(database_url, run_id)
    if email != f"staff-e2e-{run_id}@example.test" or not _EMAIL.fullmatch(email):
        raise ValueError("The E2E seed email does not match the isolated run")
    if len(password) < 24:
        raise ValueError("The E2E seed password is too short")
    if not _TOTP_SECRET.fullmatch(totp_secret):
        raise ValueError("The E2E TOTP secret is malformed")
    base64.b32decode(totp_secret, casefold=False)

    settings = Settings.from_env()
    settings.validate()
    engine, session_factory = create_session_factory(database_url)
    try:
        with session_factory.begin() as session:
            if session.query(StaffAccount).count() != 0:
                raise ValueError("The isolated E2E database already contains a staff account")
            session.add(
                StaffAccount(
                    email=email,
                    password_hash=hash_password(password),
                    role="platform_admin",
                    tenant_id=None,
                    active=True,
                    totp_secret_encrypted=encrypt_totp_secret(
                        totp_secret, settings.totp_encryption_key
                    ),
                    totp_enabled=True,
                    created_at=datetime.now(timezone.utc),
                )
            )
    finally:
        engine.dispose()


def main() -> int:
    try:
        seed_staff_account()
    except Exception as error:
        print(f"Staff E2E seed failed ({type(error).__name__}).", file=sys.stderr)
        return 1

    print("Seeded one staff account in the uniquely named loopback E2E database.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
