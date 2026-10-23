#!/usr/bin/env python3
"""Download the small curated aircraft overlay from Wikidata entity data.

This is not part of an application build. It writes one snapshot file.
"""

from __future__ import annotations

import json
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SNAPSHOT = ROOT / "data" / "aviation" / "snapshots" / "wikidata-curated-aircraft.json"
ID_FILE = Path(__file__).resolve().parent / "curated_aircraft_ids.json"
USER_AGENT = "TailTagCatalogBuilder/1.0 (curated aircraft overlay)"


def _ids(claims: dict, pid: str) -> list[str]:
    found = []
    for statement in claims.get(pid, []):
        value = statement.get("mainsnak", {}).get("datavalue", {}).get("value")
        if isinstance(value, dict) and str(value.get("id", "")).startswith("Q"):
            token = value["id"]
            if token not in found:
                found.append(token)
    return found


def main() -> None:
    selected = json.loads(ID_FILE.read_text(encoding="utf-8"))
    query = urllib.parse.urlencode(
        {
            "action": "wbgetentities",
            "ids": "|".join(selected["items"]),
            "props": "labels|aliases|claims",
            "languages": "en",
            "format": "json",
        }
    )
    request = urllib.request.Request(
        "https://www.wikidata.org/w/api.php?" + query,
        headers={"User-Agent": USER_AGENT},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        payload = json.loads(response.read().decode("utf-8"))
    records = []
    for qid in selected["items"]:
        entity = payload["entities"][qid]
        label = entity.get("labels", {}).get("en", {}).get("value", "")
        aliases = [alias["value"] for alias in entity.get("aliases", {}).get("en", [])]
        claims = entity.get("claims", {})
        records.append(
            {
                "aliases": aliases,
                "families": _ids(claims, "P279"),
                "id": qid,
                "instanceOf": _ids(claims, "P31"),
                "label": label,
                "manufacturers": _ids(claims, "P176"),
            }
        )
    document = {
        "license": selected["license"],
        "licenseUrl": selected["licenseUrl"],
        "note": selected["note"],
        "records": records,
        "retrieved": selected["retrieved"],
        "source": "https://www.wikidata.org/wiki/Wikidata:Licensing",
    }
    SNAPSHOT.parent.mkdir(parents=True, exist_ok=True)
    SNAPSHOT.write_text(json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {SNAPSHOT.name} ({len(records)} records)")


if __name__ == "__main__":
    main()
