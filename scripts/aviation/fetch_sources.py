#!/usr/bin/env python3
"""Download pinned aviation source snapshots.

This script is intentionally separate from catalog builds and tests.
Re-running it contacts OurAirports and Wikidata. Application builds must
use the snapshots already stored in data/aviation/snapshots.
"""

from __future__ import annotations

import argparse
import hashlib
import http.client
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

USER_AGENT = (
    "TailTagCatalogBuilder/1.0 "
    "(https://github.com/JoshOn360Hz/TailTagApp; offline aviation reference catalog)"
)
OURAIRPORTS_COMMIT = "b529623d2a0b09a9be78d37fc7a7a5e1e16e3451"
ROOT = Path(__file__).resolve().parents[2]
SNAPSHOT_DIR = ROOT / "data" / "aviation" / "snapshots"

EXPECTED_PROPERTY_LABELS = {
    "P229": ("iata", "airline"),
    "P230": ("icao", "airline"),
    "P432": ("call",),
    "P1813": ("short name",),
    "P176": ("manufacturer",),
    "P297": ("iso",),
    "P576": ("dissol",),
    "P17": ("country",),
    "P31": ("instance of",),
    "P279": ("subclass of",),
    "P1448": ("official name",),
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fetch_bytes(url: str, timeout: int = 120) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "*/*"})
    last_error: Exception | None = None
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            last_error = error
            if error.code not in {429, 500, 502, 503, 504}:
                raise
            time.sleep(2 + attempt * 3)
        except urllib.error.URLError as error:
            last_error = error
            time.sleep(2 + attempt * 3)
    raise RuntimeError(f"failed to fetch {url}: {last_error}")


def fetch_json(url: str) -> dict:
    return json.loads(fetch_bytes(url).decode("utf-8"))


def verify_properties() -> dict[str, str]:
    labels: dict[str, str] = {}
    for prop, required_parts in EXPECTED_PROPERTY_LABELS.items():
        payload = fetch_json(f"https://www.wikidata.org/wiki/Special:EntityData/{prop}.json")
        label = payload["entities"][prop]["labels"]["en"]["value"]
        lowered = label.casefold()
        missing = [part for part in required_parts if part not in lowered]
        if missing:
            raise SystemExit(
                f"Refusing to import {prop}: English label {label!r} "
                f"does not contain {missing}. The property id may have been reused."
            )
        labels[prop] = label
        time.sleep(0.3)
    return labels


def sparql(query: str) -> dict:
    data = urllib.parse.urlencode({"query": query}).encode("utf-8")
    request = urllib.request.Request(
        "https://query.wikidata.org/sparql",
        data=data,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "application/sparql-results+json",
            "Content-Type": "application/x-www-form-urlencoded",
        },
    )
    last_error: Exception | None = None
    for attempt in range(12):
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                body = response.read().decode("utf-8")
                return json.loads(body, strict=False)
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")[:500]
            last_error = RuntimeError(f"HTTP {error.code}: {detail}")
            if error.code not in {429, 500, 502, 503, 504}:
                raise last_error from error
            time.sleep(min(60, 5 + attempt * 8))
        except (urllib.error.URLError, http.client.IncompleteRead, TimeoutError, json.JSONDecodeError, ConnectionError) as error:
            last_error = error
            time.sleep(min(60, 5 + attempt * 8))
    raise RuntimeError(f"SPARQL query failed: {last_error}")


def save_query(name: str, query: str) -> int:
    path = SNAPSHOT_DIR / name
    if path.is_file() and path.stat().st_size > 0:
        payload = json.loads(path.read_text(encoding="utf-8"), strict=False)
        count = len(payload.get("results", {}).get("bindings", []))
        print(f"reusing {name}: {count} rows")
        return count
    payload = sparql(query)
    path = SNAPSHOT_DIR / name
    path.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    count = len(payload.get("results", {}).get("bindings", []))
    print(f"saved {name}: {count} rows")
    time.sleep(1.0)
    return count


def qid_from_uri(uri: str) -> str:
    token = uri.rstrip("/").rsplit("/", 1)[-1]
    if not token.startswith("Q") or not token[1:].isdigit():
        raise ValueError(f"unexpected Wikidata item URI: {uri}")
    return token


def qids_in(filename: str, field: str = "item") -> list[str]:
    payload = json.loads((SNAPSHOT_DIR / filename).read_text(encoding="utf-8"))
    found = []
    for row in payload.get("results", {}).get("bindings", []):
        if field in row:
            found.append(qid_from_uri(row[field]["value"]))
    return found


def save_for_items(name: str, item_ids: list[str], query_template: str, chunk_size: int = 60) -> int:
    path = SNAPSHOT_DIR / name
    if path.is_file() and path.stat().st_size > 0:
        payload = json.loads(path.read_text(encoding="utf-8"), strict=False)
        count = len(payload.get("results", {}).get("bindings", []))
        print(f"reusing {name}: {count} rows")
        return count
    partial = SNAPSHOT_DIR / f"{name}.partial.json"
    bindings: list[dict] = []
    start = 0
    if partial.is_file():
        saved = json.loads(partial.read_text(encoding="utf-8"), strict=False)
        bindings = saved.get("bindings", [])
        start = int(saved.get("next", 0))
        print(f"resuming {name} at {start} ({len(bindings)} rows)")
    while start < len(item_ids):
        values = " ".join(f"wd:{item_id}" for item_id in item_ids[start : start + chunk_size])
        payload = sparql(query_template.format(values=values))
        page = payload.get("results", {}).get("bindings", [])
        bindings.extend(page)
        start += chunk_size
        partial.write_text(
            json.dumps({"next": start, "bindings": bindings}, ensure_ascii=False, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )
        print(f"{name} {start - chunk_size}: {len(page)} rows")
        time.sleep(0.6)
    path.write_text(
        json.dumps({"head": {"vars": []}, "results": {"bindings": bindings}}, ensure_ascii=False, separators=(",", ":"))
        + "\n",
        encoding="utf-8",
    )
    partial.unlink(missing_ok=True)
    print(f"saved {name}: {len(bindings)} rows")
    return len(bindings)


def save_paged(name: str, query_template: str, page_size: int = 5000) -> int:
    path = SNAPSHOT_DIR / name
    if path.is_file() and path.stat().st_size > 0:
        payload = json.loads(path.read_text(encoding="utf-8"), strict=False)
        count = len(payload.get("results", {}).get("bindings", []))
        print(f"reusing {name}: {count} rows")
        return count
    partial = SNAPSHOT_DIR / f"{name}.partial.json"
    bindings: list[dict] = []
    offset = 0
    if partial.is_file():
        saved = json.loads(partial.read_text(encoding="utf-8"), strict=False)
        bindings = saved.get("bindings", [])
        offset = int(saved.get("next", 0))
        print(f"resuming {name} at offset {offset} ({len(bindings)} rows)")
    while True:
        query = query_template.format(limit=page_size, offset=offset)
        payload = sparql(query)
        page = payload.get("results", {}).get("bindings", [])
        bindings.extend(page)
        offset += page_size
        partial.write_text(
            json.dumps({"next": offset, "bindings": bindings}, ensure_ascii=False, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )
        print(f"{name} offset {offset - page_size}: {len(page)} rows")
        if len(page) < page_size:
            break
        time.sleep(1.0)
    path.write_text(
        json.dumps({"head": {"vars": []}, "results": {"bindings": bindings}}, ensure_ascii=False, separators=(",", ":"))
        + "\n",
        encoding="utf-8",
    )
    partial.unlink(missing_ok=True)
    print(f"saved {name}: {len(bindings)} rows")
    time.sleep(1.0)
    return len(bindings)


def download_ourairports() -> None:
    csv_path = SNAPSHOT_DIR / "ourairports-airports.csv"
    license_path = SNAPSHOT_DIR / "ourairports-LICENSE.txt"
    if csv_path.is_file() and license_path.is_file() and csv_path.stat().st_size > 0:
        print(f"reusing airports.csv ({csv_path.stat().st_size} bytes)")
        return
    base = f"https://raw.githubusercontent.com/davidmegginson/ourairports-data/{OURAIRPORTS_COMMIT}"
    csv_path.write_bytes(fetch_bytes(f"{base}/airports.csv"))
    license_path.write_bytes(fetch_bytes(f"{base}/LICENSE"))
    print(f"saved airports.csv ({csv_path.stat().st_size} bytes)")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--snapshot-date", required=True, help="Explicit snapshot date, YYYY-MM-DD")
    args = parser.parse_args()
    if len(args.snapshot_date) != 10 or args.snapshot_date[4] != "-" or args.snapshot_date[7] != "-":
        raise SystemExit("snapshot date must be YYYY-MM-DD")
    SNAPSHOT_DIR.mkdir(parents=True, exist_ok=True)

    print("verifying Wikidata property labels")
    labels = verify_properties()
    download_ourairports()

    queries = {
        "wikidata-operators-iata.json": """
            SELECT ?item ?itemLabel ?iata WHERE {
              ?item wdt:P229 ?iata .
              SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
            }
        """,
        "wikidata-operators-icao.json": """
            SELECT ?item ?itemLabel ?icao WHERE {
              ?item wdt:P230 ?icao .
              SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
            }
        """,
        "wikidata-air-forces.json": """
            SELECT ?item ?itemLabel WHERE {
              ?item wdt:P31 wd:Q61883 .
              SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
            }
        """,
        "wikidata-operator-callsigns.json": """
            SELECT ?item ?callsign WHERE {
              ?item wdt:P432 ?callsign .
              { ?item wdt:P229 ?code } UNION { ?item wdt:P230 ?code } UNION { ?item wdt:P31 wd:Q61883 }
            }
        """,
    }
    for name, query in queries.items():
        save_query(name, query)

    operator_ids = sorted(
        set(qids_in("wikidata-operators-iata.json"))
        | set(qids_in("wikidata-operators-icao.json"))
        | set(qids_in("wikidata-air-forces.json")),
        key=lambda item: int(item[1:]),
    )
    print(f"fetching details for {len(operator_ids)} operators")
    save_for_items(
        "wikidata-operator-countries.json",
        operator_ids,
        """
        SELECT ?item ?countryCode WHERE {{
          VALUES ?item {{ {values} }}
          ?item wdt:P17 ?country .
          ?country wdt:P297 ?countryCode .
        }}
        """,
    )
    save_for_items(
        "wikidata-operator-dissolved.json",
        operator_ids,
        """
        SELECT ?item ?dissolved WHERE {{
          VALUES ?item {{ {values} }}
          ?item wdt:P576 ?dissolved .
        }}
        """,
    )
    save_for_items(
        "wikidata-operator-aliases.json",
        operator_ids,
        """
        SELECT ?item ?alias WHERE {{
          VALUES ?item {{ {values} }}
          ?item skos:altLabel ?alias .
          FILTER(LANG(?alias) = "en")
        }}
        """,
    )
    save_for_items(
        "wikidata-operator-short-names.json",
        operator_ids,
        """
        SELECT ?item ?alias WHERE {{
          VALUES ?item {{ {values} }}
          ?item wdt:P1813 ?alias .
        }}
        """,
    )
    save_for_items(
        "wikidata-operator-names.json",
        operator_ids,
        """
        SELECT ?item ?official WHERE {{
          VALUES ?item {{ {values} }}
          ?item wdt:P1448 ?official .
          FILTER(LANG(?official) = "en")
        }}
        """,
    )
    save_for_items(
        "wikidata-operator-types.json",
        operator_ids,
        """
        SELECT ?item ?type ?typeLabel WHERE {{
          VALUES ?item {{ {values} }}
          ?item wdt:P31 ?type .
          SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
        }}
        """,
    )

    save_paged(
        "wikidata-aircraft-models.json",
        """
        SELECT ?item ?itemLabel WHERE {{
          ?item wdt:P31 wd:Q15056995 .
          ?article schema:about ?item ; schema:isPartOf <https://en.wikipedia.org/> .
          SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
        }}
        LIMIT {limit} OFFSET {offset}
        """,
    )
    save_paged(
        "wikidata-aircraft-families-items.json",
        """
        SELECT ?item ?itemLabel WHERE {{
          ?item wdt:P31 wd:Q15056993 .
          ?article schema:about ?item ; schema:isPartOf <https://en.wikipedia.org/> .
          SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
        }}
        LIMIT {limit} OFFSET {offset}
        """,
    )
    aircraft_ids = sorted(
        set(qids_in("wikidata-aircraft-models.json")) | set(qids_in("wikidata-aircraft-families-items.json")),
        key=lambda item: int(item[1:]),
    )
    print(f"fetching details for {len(aircraft_ids)} aircraft items")
    save_for_items(
        "wikidata-aircraft-manufacturers.json",
        aircraft_ids,
        """
        SELECT ?item ?manufacturer ?manufacturerLabel WHERE {{
          VALUES ?item {{ {values} }}
          ?item wdt:P176 ?manufacturer .
          SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
        }}
        """,
    )
    save_for_items(
        "wikidata-aircraft-families.json",
        aircraft_ids,
        """
        SELECT ?item ?family ?familyLabel WHERE {{
          VALUES ?item {{ {values} }}
          ?item wdt:P279 ?family .
          SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
        }}
        """,
    )
    save_for_items(
        "wikidata-aircraft-types.json",
        aircraft_ids,
        """
        SELECT ?item ?type WHERE {{
          VALUES ?item {{ {values} }}
          ?item wdt:P31 ?type .
        }}
        """,
    )
    save_for_items(
        "wikidata-aircraft-aliases.json",
        aircraft_ids,
        """
        SELECT ?item ?alias WHERE {{
          VALUES ?item {{ {values} }}
          ?item skos:altLabel ?alias .
          FILTER(LANG(?alias) = "en")
        }}
        """,
    )
    save_for_items(
        "wikidata-aircraft-short-names.json",
        aircraft_ids,
        """
        SELECT ?item ?alias WHERE {{
          VALUES ?item {{ {values} }}
          ?item wdt:P1813 ?alias .
        }}
        """,
    )
    manufacturer_ids = sorted(set(qids_in("wikidata-aircraft-manufacturers.json", "manufacturer")), key=lambda item: int(item[1:]))
    print(f"fetching {len(manufacturer_ids)} manufacturers")
    save_for_items(
        "wikidata-manufacturers.json",
        manufacturer_ids,
        """
        SELECT ?item ?itemLabel ?countryCode WHERE {{
          VALUES ?item {{ {values} }}
          OPTIONAL {{
            ?item wdt:P17 ?country .
            ?country wdt:P297 ?countryCode .
          }}
          SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
        }}
        """,
    )
    save_for_items(
        "wikidata-manufacturer-aliases.json",
        manufacturer_ids,
        """
        SELECT ?item ?alias WHERE {{
          VALUES ?item {{ {values} }}
          ?item skos:altLabel ?alias .
          FILTER(LANG(?alias) = "en")
        }}
        """,
    )

    files = {}
    for path in sorted(SNAPSHOT_DIR.iterdir()):
        if path.name == "snapshot-meta.json" or path.name.endswith(".partial.json") or not path.is_file():
            continue
        files[path.name] = {"sha256": sha256_file(path), "bytes": path.stat().st_size}
    meta = {
        "snapshotDate": args.snapshot_date,
        "ourairports": {
            "repository": "https://github.com/davidmegginson/ourairports-data",
            "commit": OURAIRPORTS_COMMIT,
            "file": "airports.csv",
            "licenseFile": "LICENSE",
            "termsUrl": "https://ourairports.com/data/",
            "dictionaryUrl": "https://ourairports.com/help/data-dictionary.html",
        },
        "wikidata": {
            "endpoint": "https://query.wikidata.org/sparql",
            "licenseUrl": "https://www.wikidata.org/wiki/Wikidata:Licensing",
            "verifiedPropertyLabels": labels,
        },
        "files": files,
    }
    (SNAPSHOT_DIR / "snapshot-meta.json").write_text(
        json.dumps(meta, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print("wrote snapshot-meta.json")


if __name__ == "__main__":
    main()
