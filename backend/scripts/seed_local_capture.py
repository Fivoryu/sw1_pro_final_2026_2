"""Seed a local database for the F07 capture test on a phone.

Creates one agency, an agent who can sign in to the capture app (password and TOTP
generated here) and a draft listing to capture. The credentials are written to the file
given as the first argument, which must live outside the repository, for example:

    set DATABASE_URL=postgresql+psycopg://roomforge:valor-dev-local@localhost:5434/roomforge_f07
    set STAFF_TOTP_ENCRYPTION_KEY=<the same key the local API uses>
    python scripts\\seed_local_capture.py %TEMP%\\roomforge-f07-agent.txt

Running it again keeps the records and rotates the agent's password and TOTP secret.
Local development only: never point it at a shared or production database.
"""
from __future__ import annotations

import os
import secrets
import sys
from decimal import Decimal
from pathlib import Path

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from app.core.security import encrypt_totp_secret, hash_password, make_totp_uri, new_totp_secret
from app.modules.catalog.models import Listing
from app.modules.identity.models import Agency, StaffAccount

DEFAULT_URL = "postgresql+psycopg://roomforge:valor-dev-local@localhost:5434/roomforge_f07"
AGENCY_ID = "agency-local-f07"
AGENT_ID = "staff-local-f07"
AGENT_EMAIL = "agente-f07@example.test"
LISTING_ID = "listing-f07-captura"


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: seed_local_capture.py <credentials file outside the repository>")
    target = Path(sys.argv[1]).resolve()
    repository = Path(__file__).resolve().parents[2]
    if target.is_relative_to(repository):
        sys.exit("refusing to write credentials inside the repository")
    encryption_key = os.environ.get("STAFF_TOTP_ENCRYPTION_KEY")
    if not encryption_key:
        sys.exit("STAFF_TOTP_ENCRYPTION_KEY must match the key the local API uses")

    password = secrets.token_urlsafe(12)
    totp_secret = new_totp_secret()
    engine = create_engine(os.environ.get("DATABASE_URL", DEFAULT_URL))
    with Session(engine) as session:
        session.merge(Agency(id=AGENCY_ID))
        session.merge(
            StaffAccount(
                id=AGENT_ID,
                email=AGENT_EMAIL,
                password_hash=hash_password(password),
                role="agent",
                tenant_id=AGENCY_ID,
                active=True,
                totp_secret_encrypted=encrypt_totp_secret(totp_secret, encryption_key),
                totp_enabled=True,
            )
        )
        if session.get(Listing, LISTING_ID) is None:
            session.add(
                Listing(
                    id=LISTING_ID,
                    agency_id=AGENCY_ID,
                    approval_status="draft",
                    is_published=False,
                    operation="sale",
                    base_price=Decimal("120000.00"),
                    currency="BOB",
                    offer_version=1,
                    city="La Paz",
                    city_key="la paz",
                    zone="Centro",
                    zone_key="centro",
                    bedrooms=2,
                    bathrooms=1,
                    description="Borrador local para probar la captura espacial (F07).",
                )
            )
        session.commit()

    target.write_text(
        f"email: {AGENT_EMAIL}\npassword: {password}\ntotp secret: {totp_secret}\n"
        f"otpauth: {make_totp_uri(totp_secret, AGENT_EMAIL)}\n",
        encoding="utf-8",
    )
    print(f"seeded {AGENCY_ID}, {AGENT_EMAIL} and {LISTING_ID}; credentials in {target}")


if __name__ == "__main__":
    main()
