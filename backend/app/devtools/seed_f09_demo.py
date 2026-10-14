"""Seed one local-only customer, agency wallet, and published F09 listing.

This intentionally bypasses the wallet-signature and listing-review workflows
to make the customer reservation UI testable against an empty local database.
It requires an explicit local Compose flag and never changes existing rows.
"""

from __future__ import annotations

import argparse
import os
import re
from datetime import datetime, timezone
from decimal import Decimal

from app.core.config import Settings
from app.db.session import create_session_factory
from app.modules.agencies.models import AgencyWallet
from app.modules.catalog.models import Listing, ListingTransition
from app.modules.customer_identity.models import CustomerAccount, CustomerWallet
from app.modules.identity.models import Agency, StaffAccount

DEMO_AGENCY_ID = "f09-demo-agency"
DEMO_LISTING_ID = "f09-demo-listing"
DEMO_CUSTOMER_WALLET = "0x70997970c51812dc3a010c7d01b50e0d17dc79c8"
DEMO_CUSTOMER_WALLET_SECONDARY = "0x90f79bf6eb2c4f870365e785982e1f101e93b906"
DEMO_AGENCY_WALLET = "0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc"


def seed(customer_email: str, customer_wallet_address: str) -> None:
    if os.environ.get("ROOMFORGE_ALLOW_LOCAL_DEMO_SEED") != "true":
        raise RuntimeError(
            "Refusing to seed: set ROOMFORGE_ALLOW_LOCAL_DEMO_SEED=true only in local development."
        )

    settings = Settings.from_env()
    engine, factory = create_session_factory(
        settings.database_url,
        connect_timeout_seconds=settings.database_connect_timeout_seconds,
        pool_timeout_seconds=settings.database_pool_timeout_seconds,
        statement_timeout_seconds=settings.database_statement_timeout_seconds,
    )
    now = datetime.now(timezone.utc)
    email = customer_email.strip().lower()
    wallet_address = customer_wallet_address.strip().lower()
    if re.fullmatch(r"0x[0-9a-f]{40}", wallet_address) is None:
        raise ValueError("Customer wallet address must be a 20-byte EVM address.")
    listing_created = False
    customer_wallet_created = False
    agency_wallet_created = False

    try:
        with factory.begin() as session:
            customer = (
                session.query(CustomerAccount)
                .filter(CustomerAccount.email == email)
                .one_or_none()
            )
            if customer is None:
                raise RuntimeError("No customer account exists for the supplied email.")

            platform_admin = (
                session.query(StaffAccount)
                .filter(
                    StaffAccount.role == "platform_admin",
                    StaffAccount.active.is_(True),
                )
                .one_or_none()
            )
            if platform_admin is None:
                raise RuntimeError("Create and activate the local platform admin first.")

            agency = session.get(Agency, DEMO_AGENCY_ID)
            if agency is None:
                agency = Agency(id=DEMO_AGENCY_ID)
                session.add(agency)
                session.flush()

            customer_wallet = (
                session.query(CustomerWallet)
                .filter(CustomerWallet.customer_id == customer.id)
                .one_or_none()
            )
            if customer_wallet is None:
                session.add(
                    CustomerWallet(
                        customer_id=customer.id,
                        address=wallet_address,
                        linked_at=now,
                    )
                )
                customer_wallet_created = True
            elif customer_wallet.address != wallet_address:
                raise RuntimeError(
                    "The customer already has another linked wallet; refusing to replace it."
                )

            agency_wallet = (
                session.query(AgencyWallet)
                .filter(AgencyWallet.agency_id == DEMO_AGENCY_ID)
                .one_or_none()
            )
            if agency_wallet is None:
                session.add(
                    AgencyWallet(
                        agency_id=DEMO_AGENCY_ID,
                        address=DEMO_AGENCY_WALLET,
                        linked_at=now,
                    )
                )
                agency_wallet_created = True
            elif agency_wallet.address != DEMO_AGENCY_WALLET:
                raise RuntimeError(
                    "The demo agency already has another wallet; refusing to replace it."
                )

            listing = session.get(Listing, DEMO_LISTING_ID)
            if listing is None:
                listing = Listing(
                    id=DEMO_LISTING_ID,
                    agency_id=DEMO_AGENCY_ID,
                    approval_status="draft",
                    is_published=False,
                    operation="sale",
                    base_price=Decimal("250000.00"),
                    currency="BOB",
                    deposit_amount=Decimal("10.00"),
                    offer_version=1,
                    city="La Paz",
                    city_key="la paz",
                    zone="Sopocachi",
                    zone_key="sopocachi",
                    bedrooms=2,
                    bathrooms=1,
                    created_at=now,
                    description="Inmueble local de demostración F09.",
                    exact_address="Zona de demostración",
                    photos=None,
                )
                session.add(listing)
                session.flush()
                listing_created = True

                transitions = [
                    ("create", None, None, "draft", False),
                    ("submit", "draft", False, "pending", False),
                    ("approve", "pending", False, "approved", False),
                    ("publish", "approved", False, "approved", True),
                ]
                current_time = now
                for action, from_status, from_published, to_status, to_published in transitions:
                    session.add(
                        ListingTransition(
                            agency_id=DEMO_AGENCY_ID,
                            listing_id=DEMO_LISTING_ID,
                            action=action,
                            from_status=from_status,
                            from_published=from_published,
                            to_status=to_status,
                            to_published=to_published,
                            observation="Local F09 demo seed; review workflow bypassed.",
                            actor_id=platform_admin.id,
                            actor_role="platform_admin",
                            created_at=current_time,
                        )
                    )
                    listing.approval_status = to_status
                    listing.is_published = to_published
                    session.flush()

    finally:
        engine.dispose()

    print("F09 local demo seed ready")
    print(f"agency_id={DEMO_AGENCY_ID}")
    print(f"listing_id={DEMO_LISTING_ID}")
    print(f"customer_wallet_address={wallet_address}")
    print("listing=BOB 250000.00 sale; deposit=BOB 10.00")
    print(f"listing_created={str(listing_created).lower()}")
    print(f"customer_wallet_created={str(customer_wallet_created).lower()}")
    print(f"agency_wallet_created={str(agency_wallet_created).lower()}")
    print("wallet signatures are bypassed local demo fixtures; do not use outside local Hardhat.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--customer-email", required=True)
    parser.add_argument(
        "--customer-wallet-address",
        default=DEMO_CUSTOMER_WALLET,
        help="Local Hardhat test account; use account #3 for a second local customer.",
    )
    args = parser.parse_args()
    seed(args.customer_email, args.customer_wallet_address)


if __name__ == "__main__":
    main()
