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
    "version": "2.0",
    "unit": "meters",
    "walls": [
        {
            "id": "wall-estar-north",
            "start": {"x": 0, "z": 0},
            "end": {"x": 6, "z": 0},
            "height": 2.7,
            "thickness": 0.15,
        },
        {
            "id": "wall-interior",
            "start": {"x": 6, "z": 0},
            "end": {"x": 6, "z": 5},
            "height": 2.7,
            "thickness": 0.15,
        },
        {
            "id": "wall-estar-south",
            "start": {"x": 6, "z": 5},
            "end": {"x": 0, "z": 5},
            "height": 2.7,
            "thickness": 0.15,
        },
        {
            "id": "wall-estar-west",
            "start": {"x": 0, "z": 5},
            "end": {"x": 0, "z": 0},
            "height": 2.7,
            "thickness": 0.15,
        },
        {
            "id": "wall-bedroom-north",
            "start": {"x": 6, "z": 0},
            "end": {"x": 10, "z": 0},
            "height": 2.7,
            "thickness": 0.15,
        },
        {
            "id": "wall-bedroom-east",
            "start": {"x": 10, "z": 0},
            "end": {"x": 10, "z": 5},
            "height": 2.7,
            "thickness": 0.15,
        },
        {
            "id": "wall-bedroom-south",
            "start": {"x": 10, "z": 5},
            "end": {"x": 6, "z": 5},
            "height": 2.7,
            "thickness": 0.15,
        },
    ],
    "openings": [
        {
            "id": "open-puerta",
            "wallId": "wall-estar-north",
            "position": 0.5,
            "width": 1.0,
            "height": 2.1,
            "type": "door",
        },
        {
            "id": "open-ventana",
            "wallId": "wall-interior",
            "position": 0.5,
            "width": 1.6,
            "height": 1.2,
            "type": "window",
            "sillHeight": 1.0,
        },
        {
            "id": "open-puerta-int",
            "wallId": "wall-interior",
            "position": 0.5,
            "width": 0.9,
            "height": 2.1,
            "type": "door",
        },
    ],
    "rooms": [
        {
            "id": "room-estar",
            "wallIds": [
                "wall-estar-north",
                "wall-interior",
                "wall-estar-south",
                "wall-estar-west",
            ],
        },
        {
            "id": "room-dormitorio",
            "wallIds": [
                "wall-bedroom-north",
                "wall-bedroom-east",
                "wall-bedroom-south",
                "wall-interior",
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
            # Matches the pool-access extra so its hotspot can open a quote.
            "id": "extra-piscina",
            "type": "amenity",
            "position": {"x": 8, "y": 0.1, "z": 4},
            "dimensions": {"width": 1.5, "height": 0.2, "depth": 1.5},
            "color": "#4fc3f7",
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
