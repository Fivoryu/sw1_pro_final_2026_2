"""Seed the local measurement database for the F06 customer walkthrough (S23 FE).

Creates one agency, a published sale listing with extras and a parametric
scene, and a published rent listing without a scene (honest fallback). Run it
against a fresh database, for example:

    set DATABASE_URL=postgresql+psycopg://roomforge:valor-dev-local@localhost:5434/roomforge_f06
    python scripts\seed_local_walkthrough.py
"""
from __future__ import annotations

import os
from datetime import datetime, timezone
from decimal import Decimal

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from app.modules.catalog.models import Listing, ListingExtra, ListingScene
from app.modules.identity.models import Agency, StaffAccount

DEFAULT_URL = "postgresql+psycopg://roomforge:valor-dev-local@localhost:5434/roomforge_f06"

SCENE = {
    "version": "1.0",
    "unit": "meters",
    "rooms": [
        {
            "id": "room-estar",
            "height": 2.7,
            "contours": [
                {"x": 0, "z": 0},
                {"x": 6, "z": 0},
                {"x": 6, "z": 5},
                {"x": 0, "z": 5},
            ],
            "openings": [
                {
                    "id": "open-puerta",
                    "type": "door",
                    "position": {"x": 3, "y": 0, "z": 0},
                    "width": 1.0,
                    "height": 2.1,
                },
                {
                    "id": "open-ventana",
                    "type": "window",
                    "position": {"x": 6, "y": 1.0, "z": 2.5},
                    "width": 1.6,
                    "height": 1.2,
                },
            ],
        },
        {
            "id": "room-dormitorio",
            "height": 2.7,
            "contours": [
                {"x": 6, "z": 0},
                {"x": 10, "z": 0},
                {"x": 10, "z": 5},
                {"x": 6, "z": 5},
            ],
            "openings": [
                {
                    "id": "open-puerta-int",
                    "type": "door",
                    "position": {"x": 6, "y": 0, "z": 2.5},
                    "width": 0.9,
                    "height": 2.1,
                },
            ],
        },
    ],
    "objects": [
        {
            # Matches an extra id, so the commercial hotspot shows a price.
            "id": "extra-amoblado",
            "type": "furniture",
            "position": {"x": 1.5, "y": 0.35, "z": 1.2},
            "dimensions": {"width": 2.2, "height": 0.7, "depth": 0.9},
            "color": "#8d6e63",
        },
        {
            # No published price: the honest hotspot path.
            "id": "ref-pilar",
            "type": "structural",
            "position": {"x": 8, "y": 1.35, "z": 2.5},
            "dimensions": {"width": 0.4, "height": 2.7, "depth": 0.4},
            "color": "#9e9e9e",
        },
    ],
}


def main() -> None:
    engine = create_engine(os.environ.get("DATABASE_URL", DEFAULT_URL))
    with Session(engine) as session:
        agency = Agency(id="agency-local-f06")
        session.merge(agency)

        staff = StaffAccount(
            id="staff-local-f06",
            email="staff-f06@example.test",
            password_hash="not-a-real-login",
            role="agency_admin",
            tenant_id=agency.id,
            active=False,
        )
        session.merge(staff)

        venta = Listing(
            id="listing-f06-venta",
            agency_id=agency.id,
            approval_status="approved",
            is_published=True,
            operation="sale",
            base_price=Decimal("350000.00"),
            currency="BOB",
            offer_version=1,
            city="La Paz",
            city_key="la paz",
            zone="Calacoto",
            zone_key="calacoto",
            bedrooms=3,
            bathrooms=2,
            description="Departamento de demostración para el recorrido 3D.",
            extras=[
                ListingExtra(
                    id="extra-amoblado",
                    listing_id="listing-f06-venta",
                    name="Amoblado completo",
                    price=Decimal("1500.00"),
                    category="furniture",
                    room="living",
                    origin="agency",
                ),
                ListingExtra(
                    id="extra-piscina",
                    listing_id="listing-f06-venta",
                    name="Acceso a piscina",
                    price=Decimal("800.00"),
                    category="amenity",
                    origin="agency",
                ),
            ],
        )
        session.merge(venta)
        session.merge(
            ListingScene(
                listing_id=venta.id,
                scene=SCENE,
                updated_at=datetime.now(timezone.utc),
                updated_by=staff.id,
            )
        )

        session.merge(
            Listing(
                id="listing-f06-alquiler",
                agency_id=agency.id,
                approval_status="approved",
                is_published=True,
                operation="rent",
                base_price=Decimal("3500.00"),
                currency="BOB",
                offer_version=1,
                city="La Paz",
                city_key="la paz",
                zone="Sopocachi",
                zone_key="sopocachi",
                bedrooms=2,
                bathrooms=1,
                description="Publicado sin escena: prueba del estado honesto.",
            )
        )
        session.commit()
        print("seeded: listing-f06-venta (scene + extras), listing-f06-alquiler (no scene)")


if __name__ == "__main__":
    main()
