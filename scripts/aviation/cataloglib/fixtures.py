"""Write search fixtures from the reference implementation."""

from __future__ import annotations

import json
from pathlib import Path

from cataloglib.normalize import compact_search_text, normalize_search_text
from cataloglib.search import (
    AIRCRAFT_CODE_FIELDS,
    AIRCRAFT_NAME_FIELDS,
    AIRPORT_CODE_FIELDS,
    AIRPORT_NAME_FIELDS,
    OPERATOR_CODE_FIELDS,
    OPERATOR_NAME_FIELDS,
    SearchIndex,
    resolve_query,
)

ROOT = Path(__file__).resolve().parents[3]
FIXTURE_DIR = Path(__file__).resolve().parents[1] / "fixtures"
NORMALIZATION_SAMPLES = (
    "Qantas",
    "  QF  ",
    "A350-900",
    "Malmö",
    "São Paulo",
    "Zürich",
    "İstanbul",
    "straße",
    "Ærø",
    "Ñuñoa",
    "CAFÉ",
    "—dash—",
    "a/b_c",
    "  a   b  ",
    "Łódź",
    "İ",
    "I",
    "ı",
    "ß",
    "é",
    "É",
    "Ørland",
    "Ålesund",
    "Londres",
    "787-9",
    "\u00a0Qantas\u00a0",
)

DATASETS = {
    "operators": (OPERATOR_CODE_FIELDS, OPERATOR_NAME_FIELDS),
    "aircraft": (AIRCRAFT_CODE_FIELDS, AIRCRAFT_NAME_FIELDS),
    "airports": (AIRPORT_CODE_FIELDS, AIRPORT_NAME_FIELDS),
}


def ranking_cases(catalog: dict) -> dict:
    indexes = {
        name: SearchIndex(catalog[name], code_fields, name_fields)
        for name, (code_fields, name_fields) in DATASETS.items()
    }
    queries = [
        ("operators", "QF", 10),
        ("operators", "QFA", 10),
        ("operators", "Qantas", 10),
        ("operators", "  qantas  ", 10),
        ("operators", "qantas airways", 10),
        ("operators", "QANTAS", 10),
        ("operators", "RAAF", 10),
        ("operators", "Royal Australian", 10),
        ("operators", "not-an-airline", 10),
        ("operators", "   ", 10),
        ("operators", "A", 10),
        ("aircraft", "A359", 10),
        ("aircraft", "A320", 10),
        ("aircraft", "A350", 10),
        ("aircraft", "787-9", 10),
        ("aircraft", "B789", 10),
        ("aircraft", "Airbus", 10),
        ("aircraft", "Boeing", 10),
        ("aircraft", "Dragon", 10),
        ("aircraft", "no-such-aircraft", 10),
        ("airports", "SYD", 10),
        ("airports", "YSSY", 10),
        ("airports", "LHR", 10),
        ("airports", "EGLL", 10),
        ("airports", "Heathrow", 10),
        ("airports", "row", 10),
        ("airports", "Sydney", 10),
        ("airports", "Malmo", 10),
        ("airports", "Malmö", 10),
        ("airports", "YFGS", 10),
        ("airports", "00AL", 10),
        ("airports", "Mildenhall", 10),
        ("airports", "Londres", 10),
        ("airports", "zzzz-not-a-place", 10),
        ("airports", "International", 1),
        ("aircraft", "Airbus", 1),
    ]
    cases = []
    for dataset, query, limit in queries:
        matches = indexes[dataset].search(query, limit)
        resolution = resolve_query(query, matches, indexes[dataset].exact_code_count(query))
        case = {
            "dataset": dataset,
            "expectedIds": [record["id"] for record in matches],
            "limit": limit,
            "query": query,
            "resolution": resolution["kind"],
        }
        if resolution["kind"] == "unmatched":
            case["unmatchedText"] = resolution["text"]
        cases.append(case)
    return {"cases": cases}


def normalization_cases() -> dict:
    cases = []
    for sample in NORMALIZATION_SAMPLES:
        normalized = normalize_search_text(sample)
        cases.append(
            {
                "compact": compact_search_text(normalized),
                "input": sample,
                "normalized": normalized,
            }
        )
    return {"cases": cases}


def write_reference_fixtures() -> None:
    catalog = json.loads((FIXTURE_DIR / "ranking-catalog.json").read_text(encoding="utf-8"))
    _write_json(FIXTURE_DIR / "ranking-cases.json", ranking_cases(catalog))
    _write_json(FIXTURE_DIR / "normalization-cases.json", normalization_cases())


def write_search_cases(data_dir: Path) -> dict:
    documents = {
        "operators": json.loads((data_dir / "operators.json").read_text(encoding="utf-8"))["records"],
        "aircraft": json.loads((data_dir / "aircraft.json").read_text(encoding="utf-8"))["records"],
        "airports": json.loads((data_dir / "airports.json").read_text(encoding="utf-8"))["records"],
    }
    indexes = {
        name: SearchIndex(documents[name], code_fields, name_fields)
        for name, (code_fields, name_fields) in DATASETS.items()
    }
    planned = [
        ("operators", "Qantas", 5),
        ("operators", "qantas", 5),
        ("operators", "QF", 5),
        ("operators", "QFA", 5),
        ("operators", "  Qantas  ", 5),
        ("aircraft", "Airbus", 5),
        ("aircraft", "A350", 5),
        ("aircraft", "A350-900", 5),
        ("aircraft", "Boeing", 5),
        ("aircraft", "787-9", 5),
        ("aircraft", "B789", 5),
        ("airports", "Sydney", 5),
        ("airports", "SYD", 5),
        ("airports", "YSSY", 5),
        ("airports", "Heathrow", 5),
        ("airports", "LHR", 5),
        ("airports", "EGLL", 5),
        ("airports", "Frogs Hollow", 5),
        ("airports", "YFGS", 5),
        ("airports", "Mildenhall", 5),
        ("airports", "EGUN", 5),
        ("airports", "Epps", 5),
        ("airports", "00AL", 5),
        ("operators", "zzzz-not-an-operator", 5),
        ("aircraft", "zzzz-not-an-aircraft", 5),
        ("airports", "zzzz-not-a-place", 5),
        ("airports", "   ", 5),
        ("airports", "International", 3),
    ]
    military = next(
        (
            record
            for record in documents["operators"]
            if "military-operator" in record.get("tags", []) and not record.get("iataCodes")
        ),
        None,
    )
    if military is None:
        raise SystemExit("no military operator without an IATA code was imported")
    planned.append(("operators", military["name"], 5))
    alias_case = next(
        (
            record
            for record in documents["aircraft"]
            if record["id"] == "wikidata:Q92162002" and any(alias.upper() == "A359" for alias in record.get("aliases", []))
        ),
        None,
    )
    if alias_case is not None:
        planned.append(("aircraft", "A359", 5))
    dragon = next((record for record in documents["aircraft"] if not record.get("icaoTypeDesignators") and not record.get("iataEquipmentCodes")), None)
    if dragon is None:
        raise SystemExit("no aircraft without equipment codes was imported")
    token = dragon["model"].split()[-1]
    if len(normalize_search_text(token)) >= 4:
        planned.append(("aircraft", token, 5))
    cases = []
    for dataset, query, limit in planned:
        matches = indexes[dataset].search(query, limit)
        resolution = resolve_query(query, matches, indexes[dataset].exact_code_count(query))
        case = {
            "dataset": dataset,
            "expectedIds": [record["id"] for record in matches],
            "limit": limit,
            "query": query,
            "resolution": resolution["kind"],
        }
        if resolution["kind"] == "unmatched":
            case["unmatchedText"] = resolution["text"]
        cases.append(case)
    payload = {"cases": cases, "militaryOperatorId": military["id"]}
    destination = data_dir / "fixtures"
    destination.mkdir(parents=True, exist_ok=True)
    _write_json(destination / "search-cases.json", payload)
    return payload


def copy_fixtures(root: Path) -> None:
    payloads = {
        "ranking-catalog.json": (FIXTURE_DIR / "ranking-catalog.json").read_text(encoding="utf-8"),
        "ranking-cases.json": (FIXTURE_DIR / "ranking-cases.json").read_text(encoding="utf-8"),
        "normalization-cases.json": (FIXTURE_DIR / "normalization-cases.json").read_text(encoding="utf-8"),
        "search-cases.json": (root / "data" / "aviation" / "fixtures" / "search-cases.json").read_text(encoding="utf-8"),
    }
    destinations = [
        root / "data" / "aviation" / "fixtures",
        root / "iOS" / "AviationCatalogCore" / "Tests" / "AviationCatalogTests" / "Fixtures",
        root / "Android" / "app" / "src" / "test" / "resources" / "aviation",
    ]
    for destination in destinations:
        destination.mkdir(parents=True, exist_ok=True)
        for name, text in payloads.items():
            (destination / name).write_text(text, encoding="utf-8")


def _write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
