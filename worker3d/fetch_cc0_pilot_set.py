"""Fetch the CC0 pilot image set for F08.2 from Wikimedia Commons.

The pilot needs a small, authorized set of interior photographs. This script
searches Commons restricted to the `CC-Zero` tracking category, verifies the
license of every file through the Wikimedia API metadata, and writes a manifest
that records, per image, its author, license, terms of use and file page.

The images themselves are downloaded into `worker3d/pilot/input/`, which is
git-ignored: the repository keeps the provenance, not third-party bytes.

Usage:
    python fetch_cc0_pilot_set.py --target 24
    python fetch_cc0_pilot_set.py --target 24 --out ../docs/ai/f08-conjunto-cc0.json
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

API_ENDPOINT = "https://commons.wikimedia.org/w/api.php"
USER_AGENT = (
    "RoomForge-F08-pilot/1.0 (academic Software Engineering project; "
    "contact: repository owner)"
)
# Categoría de seguimiento de las obras liberadas bajo CC0 en Commons.
LICENSE_CATEGORY_FILTER = 'incategory:"CC-Zero"'
ACCEPTED_LICENSES = ("cc0",)
DEFAULT_TERMS: tuple[str, ...] = (
    "living room",
    "bedroom",
    "dining room",
    "kitchen",
    "sofa",
    "room interior",
)
THUMB_WIDTH = 1280
REQUEST_DELAY_SECONDS = 0.5
EXIT_EMPTY_SET = 3
# Gathered fewer images than asked for and --allow-partial was not given.
EXIT_SHORTFALL = 4
JPEG_MAGIC = b"\xff\xd8\xff"
PNG_MAGIC = b"\x89PNG"
HTML_TAG = re.compile(r"<[^>]+>")


class ApiError(RuntimeError):
    """Raised when the Commons API cannot be queried as expected."""


def _api(params: dict[str, str]) -> dict[str, Any]:
    url = f"{API_ENDPOINT}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace").strip()[:300]
        raise ApiError(f"Commons respondió HTTP {error.code}: {detail}") from error
    except (urllib.error.URLError, TimeoutError) as error:
        raise ApiError(f"falló la consulta a Commons: {error}") from error


def search(term: str, limit: int) -> list[dict[str, Any]]:
    payload = _api(
        {
            "action": "query",
            "format": "json",
            "generator": "search",
            "gsrsearch": f"{LICENSE_CATEGORY_FILTER} {term}",
            "gsrnamespace": "6",
            "gsrlimit": str(limit),
            "prop": "imageinfo",
            "iiprop": "url|extmetadata",
            "iiurlwidth": str(THUMB_WIDTH),
        }
    )
    pages = (payload.get("query") or {}).get("pages") or {}
    return list(pages.values())


def _meta_value(metadata: dict[str, Any], key: str) -> str:
    value = (metadata.get(key) or {}).get("value")
    if value is None:
        return ""
    return HTML_TAG.sub("", str(value)).strip()


def manifest_entry(page: dict[str, Any], file_name: str) -> dict[str, Any]:
    info = (page.get("imageinfo") or [{}])[0]
    metadata = info.get("extmetadata") or {}
    return {
        "file": file_name,
        "title": str(page.get("title", "")).removeprefix("File:"),
        "author": _meta_value(metadata, "Artist"),
        "license": _meta_value(metadata, "LicenseShortName"),
        "usage_terms": _meta_value(metadata, "UsageTerms"),
        "license_url": _meta_value(metadata, "LicenseUrl"),
        "source": "Wikimedia Commons",
        "landing_page": info.get("descriptionurl"),
        "download_url": info.get("thumburl") or info.get("url"),
        "width": info.get("thumbwidth") or info.get("width"),
        "height": info.get("thumbheight") or info.get("height"),
    }


def is_accepted_license(entry: dict[str, Any]) -> bool:
    return entry["license"].strip().lower() in ACCEPTED_LICENSES


def download(url: str, destination: Path) -> bool:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            content_type = response.headers.get("Content-Type", "")
            payload = response.read()
    except (urllib.error.URLError, TimeoutError) as error:
        print(f"  omitida ({error})", file=sys.stderr)
        return False

    if not content_type.startswith("image/"):
        print(f"  omitida (content-type {content_type!r})", file=sys.stderr)
        return False
    if not (payload.startswith(JPEG_MAGIC) or payload.startswith(PNG_MAGIC)):
        print("  omitida (los bytes no son JPEG ni PNG)", file=sys.stderr)
        return False

    destination.write_bytes(payload)
    return True


def shortfall_exit_code(gathered: int, target: int, *, allow_partial: bool) -> int:
    """Exit code for the gathered count.

    Asking for 40 and gathering 6 must not look like success. `main` handles the
    empty case first (EXIT_EMPTY_SET), so this only covers a partial set.
    """
    if allow_partial or gathered >= target:
        return 0
    return EXIT_SHORTFALL


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="fetch_cc0_pilot_set.py",
        description="Descarga un conjunto pequeño de fotos CC0 de ambientes y escribe su manifiesto.",
    )
    parser.add_argument("--target", type=int, default=24, help="cantidad de imágenes a reunir")
    parser.add_argument(
        "--allow-partial",
        action="store_true",
        help="aceptar un conjunto más chico que --target en lugar de fallar",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "docs" / "ai" / "f08-conjunto-cc0.json",
        help="archivo de manifiesto de salida",
    )
    parser.add_argument(
        "--input-dir",
        type=Path,
        default=Path(__file__).resolve().parent / "pilot" / "input",
        help="directorio destino de las imágenes (sin seguimiento en git)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    try:  # los títulos de Commons traen Unicode; la consola de Windows no siempre lo soporta
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:  # pragma: no cover - streams sin reconfigurar
        pass

    args = build_parser().parse_args(argv)
    args.input_dir.mkdir(parents=True, exist_ok=True)

    seen_pages: set[str] = set()
    entries: list[dict[str, Any]] = []

    for term in DEFAULT_TERMS:
        if len(entries) >= args.target:
            break
        print(f"consulta: {term} (categoría CC-Zero)")
        try:
            pages = search(term, limit=args.target)
        except ApiError as error:
            print(str(error), file=sys.stderr)
            continue

        for page in pages:
            if len(entries) >= args.target:
                break
            info = (page.get("imageinfo") or [{}])[0]
            landing_page = info.get("descriptionurl") or ""
            if not info.get("thumburl") and not info.get("url"):
                continue
            if landing_page in seen_pages:
                continue

            candidate_name = f"pilot-{len(entries) + 1:02d}.jpg"
            entry = manifest_entry(page, candidate_name)
            if not is_accepted_license(entry):
                print(f"  omitida (licencia {entry['license']!r}): {entry['title']}")
                continue

            if not download(entry["download_url"], args.input_dir / candidate_name):
                continue

            seen_pages.add(landing_page)
            entries.append(entry)
            print(f"  {candidate_name}  {entry['title']}")
            time.sleep(REQUEST_DELAY_SECONDS)

    if not entries:
        print("no se descargó ninguna imagen CC0", file=sys.stderr)
        return EXIT_EMPTY_SET

    manifest = {
        "generated_at_utc": datetime.now(UTC).isoformat(timespec="seconds"),
        "source_api": API_ENDPOINT,
        "source": "Wikimedia Commons",
        "license_category_filter": LICENSE_CATEGORY_FILTER,
        "accepted_licenses": list(ACCEPTED_LICENSES),
        "terms": list(DEFAULT_TERMS),
        "count": len(entries),
        "note": (
            "Las imágenes no se versionan: el repositorio conserva la procedencia y la licencia "
            "de cada archivo, no los bytes de terceros."
        ),
        "images": entries,
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{len(entries)} imágenes en {args.input_dir}")
    print(f"manifiesto en {args.out}")

    exit_code = shortfall_exit_code(len(entries), args.target, allow_partial=args.allow_partial)
    if exit_code != 0:
        print(
            f"se pidieron {args.target} imágenes y se reunieron {len(entries)}; "
            "el manifiesto con lo reunido queda escrito, pero el conjunto está incompleto. "
            "Usá --allow-partial si un conjunto parcial es aceptable.",
            file=sys.stderr,
        )
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
