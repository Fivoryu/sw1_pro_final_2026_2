"""Characterization tests for the CC0 guard in the pilot set fetcher.

These tests cover behaviour that already exists: the license guard that rejects
any file whose Wikimedia metadata is not CC0, and the mapping from the Commons
API payload to the manifest entry. They are written after the fact and claim no
RED observation.

No network access: the payloads are synthetic.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

WORKER3D_DIR = Path(__file__).resolve().parents[1]

sys.path.insert(0, str(WORKER3D_DIR))

import fetch_cc0_pilot_set as fetcher  # noqa: E402


def _page(**extmetadata: str) -> dict[str, object]:
    return {
        "title": "File:Living room example.jpg",
        "imageinfo": [
            {
                "descriptionurl": "https://commons.wikimedia.org/wiki/File:Living_room_example.jpg",
                "thumburl": "https://upload.wikimedia.org/thumb/example.jpg",
                "thumbwidth": 1280,
                "thumbheight": 853,
                "extmetadata": {
                    key: {"value": value} for key, value in extmetadata.items()
                },
            }
        ],
    }


def test_manifest_entry_maps_commons_metadata_and_strips_html() -> None:
    entry = fetcher.manifest_entry(
        _page(
            LicenseShortName="CC0",
            UsageTerms="Creative Commons Zero, Public Domain Dedication",
            Artist='<a href="https://commons.wikimedia.org/wiki/User:Someone">Someone</a>',
            LicenseUrl="https://creativecommons.org/publicdomain/zero/1.0/",
        ),
        "pilot-01.jpg",
    )

    assert entry["file"] == "pilot-01.jpg"
    assert entry["title"] == "Living room example.jpg"
    assert entry["author"] == "Someone"
    assert entry["license"] == "CC0"
    assert entry["usage_terms"] == "Creative Commons Zero, Public Domain Dedication"
    assert entry["license_url"] == "https://creativecommons.org/publicdomain/zero/1.0/"
    assert entry["source"] == "Wikimedia Commons"
    assert entry["landing_page"].endswith("Living_room_example.jpg")


@pytest.mark.parametrize("license_name", ["CC0", "cc0", " CC0 "])
def test_cc0_variants_are_accepted(license_name: str) -> None:
    entry = fetcher.manifest_entry(_page(LicenseShortName=license_name), "pilot-01.jpg")

    assert fetcher.is_accepted_license(entry) is True


@pytest.mark.parametrize(
    "license_name",
    [
        "CC BY-SA 4.0",
        "CC BY 4.0",
        "Public domain",
        "CC BY-NC 2.0",
        "GFDL",
        "",
    ],
)
def test_non_cc0_licenses_are_rejected(license_name: str) -> None:
    entry = fetcher.manifest_entry(_page(LicenseShortName=license_name), "pilot-01.jpg")

    assert fetcher.is_accepted_license(entry) is False


def test_missing_extmetadata_is_rejected_rather_than_assumed() -> None:
    entry = fetcher.manifest_entry(
        {"title": "File:Unknown.jpg", "imageinfo": [{"thumburl": "https://example.test/x.jpg"}]},
        "pilot-01.jpg",
    )

    assert entry["license"] == ""
    assert fetcher.is_accepted_license(entry) is False


def test_shortfall_is_reported_unless_partial_is_allowed() -> None:
    """Asking for 40 and getting 6 must not look like success."""
    assert fetcher.shortfall_exit_code(24, 24, allow_partial=False) == 0
    assert fetcher.shortfall_exit_code(30, 24, allow_partial=False) == 0
    assert (
        fetcher.shortfall_exit_code(6, 40, allow_partial=False) == fetcher.EXIT_SHORTFALL
    )
    assert fetcher.shortfall_exit_code(6, 40, allow_partial=True) == 0
