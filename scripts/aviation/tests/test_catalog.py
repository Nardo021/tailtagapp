"""Catalog validation, ranking, and determinism tests. No network access."""

from __future__ import annotations

import copy
import hashlib
import json
import sys
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))

from cataloglib.build import _dump
from cataloglib.fixtures import ranking_cases
from cataloglib.normalize import compact_search_text, is_ascii_alnum, normalize_search_text
from cataloglib.search import (
    AIRCRAFT_CODE_FIELDS,
    AIRCRAFT_NAME_FIELDS,
    AIRPORT_CODE_FIELDS,
    AIRPORT_NAME_FIELDS,
    OPERATOR_CODE_FIELDS,
    OPERATOR_NAME_FIELDS,
    SearchIndex,
    _tier,
    resolve_query,
)
from cataloglib.validate import validate_catalog
from cataloglib.vocabulary import VOCABULARY

ROOT = SCRIPTS.parents[1]
FIXTURES = SCRIPTS / "fixtures"


def _source(source_id: str, license_name: str) -> dict:
    return {
        "id": source_id,
        "license": license_name,
        "licenseUrl": "https://example.invalid/license",
        "name": source_id,
        "publisher": source_id,
        "snapshot": "test",
        "url": "https://example.invalid",
    }


def _catalog_documents() -> dict[str, dict]:
    classifications = copy.deepcopy(VOCABULARY)
    operators = {
        "dataset": "operators",
        "records": [
            {
                "aliases": ["Qantas Airways"],
                "id": "wikidata:Q32491",
                "name": "Qantas",
                "sourceId": "wikidata",
                "tags": ["commercial-airline"],
            }
        ],
        "schemaVersion": 1,
    }
    manufacturers = {
        "dataset": "manufacturers",
        "records": [
            {
                "aliases": [],
                "id": "wikidata:Q67",
                "name": "Airbus",
                "sourceId": "wikidata",
            }
        ],
        "schemaVersion": 1,
    }
    aircraft = {
        "dataset": "aircraft",
        "records": [
            {
                "aliases": ["A359"],
                "displayName": "Airbus A350-900",
                "entryKind": "model",
                "id": "wikidata:Q92162002",
                "manufacturer": "Airbus",
                "manufacturerId": "wikidata:Q67",
                "model": "A350-900",
                "sourceId": "wikidata",
            }
        ],
        "schemaVersion": 1,
    }
    airports = {
        "dataset": "airports",
        "records": [
            {
                "aliases": [],
                "iataCode": "LHR",
                "icaoCode": "EGLL",
                "id": "ourairports:2434",
                "ident": "EGLL",
                "latitude": Decimal("51.470748"),
                "longitude": Decimal("-0.459909"),
                "name": "London Heathrow Airport",
                "scheduledService": True,
                "sourceId": "ourairports",
                "type": "large_airport",
            }
        ],
        "schemaVersion": 1,
    }
    documents = {
        "operators.json": operators,
        "manufacturers.json": manufacturers,
        "aircraft.json": aircraft,
        "airports.json": airports,
        "classifications.json": classifications,
    }
    raw = {name: _dump(document).encode("utf-8") for name, document in documents.items()}
    values = sum(len(item["values"]) for item in classifications["dimensions"])
    counts = {
        "aircraft": 1,
        "airports": 1,
        "classificationValues": values,
        "manufacturers": 1,
        "operators": 1,
    }
    files = {}
    for name, payload in raw.items():
        record_count = counts["classificationValues"] if name == "classifications.json" else counts[name.split(".")[0]]
        files[name] = {
            "bytes": len(payload),
            "records": record_count,
            "sha256": hashlib.sha256(payload).hexdigest(),
        }
    manifest = {
        "catalogVersion": "test",
        "counts": counts,
        "files": files,
        "schemaVersion": 1,
        "sources": [
            _source("ourairports", "Public Domain"),
            _source("wikidata", "CC0 1.0"),
            _source("tailtag-vocabulary", "Project-authored vocabulary"),
        ],
    }
    documents["catalog-manifest.json"] = manifest
    return documents


def _write_tree(root: Path, documents: dict[str, dict]) -> None:
    encoded = {name: _dump(document) for name, document in documents.items()}
    destinations = [
        root / "data" / "aviation",
        root / "iOS" / "AviationCatalogCore" / "Sources" / "AviationCatalog" / "Resources",
        root / "Android" / "app" / "src" / "main" / "assets" / "aviation",
    ]
    for destination in destinations:
        destination.mkdir(parents=True, exist_ok=True)
        for name, text in encoded.items():
            (destination / name).write_text(text, encoding="utf-8")


class CatalogValidationTests(unittest.TestCase):
    def test_minimal_catalog_is_valid(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _write_tree(root, _catalog_documents())
            self.assertEqual(validate_catalog(root), [])

    def test_invalid_json_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            documents = _catalog_documents()
            _write_tree(root, documents)
            path = root / "data" / "aviation" / "operators.json"
            path.write_text("{", encoding="utf-8")
            errors = validate_catalog(root)
            self.assertTrue(any("not valid JSON" in error for error in errors))

    def test_duplicate_ids_missing_fields_coordinates_and_references(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            documents = _catalog_documents()
            documents["operators.json"]["records"].append(copy.deepcopy(documents["operators.json"]["records"][0]))
            documents["operators.json"]["records"][1]["id"] = "wikidata:Q32491"
            documents["aircraft.json"]["records"][0].pop("displayName")
            documents["aircraft.json"]["records"][0]["manufacturerId"] = "wikidata:missing"
            documents["airports.json"]["records"][0]["latitude"] = Decimal("95")
            documents["airports.json"]["records"][0]["sourceId"] = "open-data"
            documents["catalog-manifest.json"]["schemaVersion"] = 99
            _write_tree(root, documents)
            errors = "\n".join(validate_catalog(root))
            self.assertIn("duplicate operators id", errors)
            self.assertIn("missing displayName", errors)
            self.assertIn("missing manufacturer", errors)
            self.assertIn("latitude is out of range", errors)
            self.assertIn("unknown sourceId", errors)
            self.assertIn("schemaVersion is not supported", errors)

    def test_openflights_and_empty_dataset_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            documents = _catalog_documents()
            documents["catalog-manifest.json"]["sources"].append(_source("openflights", "ODbL"))
            documents["operators.json"]["records"] = []
            _write_tree(root, documents)
            errors = "\n".join(validate_catalog(root))
            self.assertIn("OpenFlights must not be embedded", errors)
            self.assertIn("operators.json is unexpectedly empty", errors)

    def test_dump_is_deterministic(self) -> None:
        document = _catalog_documents()["operators.json"]
        shuffled = {
            "schemaVersion": document["schemaVersion"],
            "records": document["records"],
            "dataset": document["dataset"],
        }
        self.assertEqual(_dump(document), _dump(shuffled))
        self.assertTrue(_dump(document).endswith("\n"))


class SearchContractTests(unittest.TestCase):
    def test_normalization_fixture(self) -> None:
        payload = json.loads((FIXTURES / "normalization-cases.json").read_text(encoding="utf-8"))
        for sample in payload["cases"]:
            normalized = normalize_search_text(sample["input"])
            self.assertEqual(normalized, sample["normalized"], sample["input"])
            self.assertEqual(compact_search_text(normalized), sample["compact"], sample["input"])

    def test_ranking_fixture_and_stable_tie_break(self) -> None:
        catalog = json.loads((FIXTURES / "ranking-catalog.json").read_text(encoding="utf-8"))
        generated = ranking_cases(catalog)
        committed = json.loads((FIXTURES / "ranking-cases.json").read_text(encoding="utf-8"))
        self.assertEqual(generated, committed)
        operators = SearchIndex(catalog["operators"], OPERATOR_CODE_FIELDS, OPERATOR_NAME_FIELDS)
        reversed_index = SearchIndex(list(reversed(catalog["operators"])), OPERATOR_CODE_FIELDS, OPERATOR_NAME_FIELDS)
        self.assertEqual(
            [record["id"] for record in operators.search("QFA", 10)],
            [record["id"] for record in reversed_index.search("QFA", 10)],
        )
        self.assertEqual(operators.search("QFA", 10)[0]["id"], "fixture:prefix-carrier")
        self.assertEqual(operators.search("QF", 5)[0]["id"], "fixture:qantas")
        aircraft = SearchIndex(catalog["aircraft"], AIRCRAFT_CODE_FIELDS, AIRCRAFT_NAME_FIELDS)
        self.assertEqual(
            [record["id"] for record in aircraft.search("A320", 5)],
            ["fixture:a320-200", "fixture:a320-family"],
        )
        airports = SearchIndex(catalog["airports"], AIRPORT_CODE_FIELDS, AIRPORT_NAME_FIELDS)
        self.assertEqual(resolve_query("zzzz-not-a-place", airports.search("zzzz-not-a-place", 5))["kind"], "unmatched")
        self.assertEqual(resolve_query("   ", [])["kind"], "blank")
        self.assertEqual(airports.search("row", 5), [])
        self.assertEqual(airports.search("Heathrow", 5)[0]["id"], "fixture:heathrow")
        with self.assertRaises(ValueError):
            operators.search("QF", -1)
        self.assertEqual(operators.search("QF", 0), [])

    def test_identifier_digits_do_not_match_unrelated_records(self) -> None:
        records = [
            {
                "aliases": [],
                "displayName": "Thomas T-2",
                "id": "wikidata:Q7787944",
                "model": "Thomas T-2",
            }
        ]
        index = SearchIndex(records, ("id",), ("model", "displayName", "aliases"))
        self.assertEqual(index.search("787-9", 5), [])
        self.assertEqual(index.search("Q7787944", 5)[0]["id"], "wikidata:Q7787944")

    def test_reference_fixtures_match_across_platforms(self) -> None:
        names = ("ranking-catalog.json", "ranking-cases.json", "normalization-cases.json")
        destinations = [
            ROOT / "iOS" / "AviationCatalogCore" / "Tests" / "AviationCatalogTests" / "Fixtures",
            ROOT / "Android" / "app" / "src" / "test" / "resources" / "aviation",
        ]
        for name in names:
            original = (FIXTURES / name).read_bytes()
            for destination in destinations:
                self.assertEqual((destination / name).read_bytes(), original, f"{destination / name}")

    def test_candidate_index_matches_full_scan(self) -> None:
        catalog = json.loads((FIXTURES / "ranking-catalog.json").read_text(encoding="utf-8"))
        queries = ["QF", "QFA", "A320", "787-9", "Heathrow", "row", "SYD", "00AL", "International", "Malmö"]
        for dataset, codes, names in (
            ("operators", OPERATOR_CODE_FIELDS, OPERATOR_NAME_FIELDS),
            ("aircraft", AIRCRAFT_CODE_FIELDS, AIRCRAFT_NAME_FIELDS),
            ("airports", AIRPORT_CODE_FIELDS, AIRPORT_NAME_FIELDS),
        ):
            index = SearchIndex(catalog[dataset], codes, names)
            for query in queries:
                self.assertEqual(
                    [record["id"] for record in index.search(query, 10)],
                    _linear_ids(index, query, 10),
                    f"{dataset} {query}",
                )

    def test_common_aircraft_operator_ambiguity_and_history(self) -> None:
        data = ROOT / "data" / "aviation"
        aircraft = json.loads((data / "aircraft.json").read_text(encoding="utf-8"))["records"]
        operators = json.loads((data / "operators.json").read_text(encoding="utf-8"))["records"]
        airports = json.loads((data / "airports.json").read_text(encoding="utf-8"))["records"]
        by_id = {record["id"]: record for record in aircraft}
        dreamliner = by_id["wikidata:Q15111575"]
        self.assertEqual(dreamliner["model"], "Boeing 787-9")
        self.assertEqual(dreamliner["entryKind"], "model")
        self.assertIn("787-9", dreamliner["aliases"])
        self.assertIn("B789", dreamliner["aliases"])
        self.assertNotIn("icaoTypeDesignators", dreamliner)
        self.assertEqual(by_id["wikidata:Q57439868"]["model"], "Boeing 787-8")
        self.assertEqual(by_id["wikidata:Q57440517"]["model"], "Boeing 787-10")
        self.assertEqual(by_id["wikidata:Q106340166"]["entryKind"], "family")
        self.assertEqual(by_id["wikidata:Q106340166"]["model"], "Boeing 737 MAX 8")
        self.assertIn("wikidata:Q6475", by_id)
        self.assertNotIn("Airbus A380-800", {record["model"] for record in aircraft})
        for record in aircraft:
            self.assertFalse(record.get("icaoTypeDesignators"))
            self.assertFalse(record.get("iataEquipmentCodes"))
            self.assertTrue(record["id"].startswith("wikidata:Q"))
        aircraft_index = SearchIndex(aircraft, AIRCRAFT_CODE_FIELDS, AIRCRAFT_NAME_FIELDS)
        for query in ("787-9", "B789"):
            matches = aircraft_index.search(query, 5)
            self.assertEqual(matches[0]["id"], "wikidata:Q15111575", query)
            self.assertEqual(resolve_query(query, matches, aircraft_index.exact_code_count(query))["kind"], "matches")
        self.assertEqual(aircraft_index.search("A359", 5)[0]["id"], "wikidata:Q92162002")
        self.assertIn("wikidata:Q244479", {record["id"] for record in aircraft_index.search("Cessna 172", 10)})
        self.assertIn("wikidata:Q182027", {record["id"] for record in aircraft_index.search("C-130", 10)})
        operator_index = SearchIndex(operators, OPERATOR_CODE_FIELDS, OPERATOR_NAME_FIELDS)
        exact_ids = sorted(record["id"] for record in operators if "QF" in record.get("iataCodes", []))
        self.assertGreater(len(exact_ids), 1)
        self.assertIn("wikidata:Q32491", exact_ids)
        self.assertEqual([record["id"] for record in operator_index.search("QF", len(exact_ids))], exact_ids)
        limited = operator_index.search("QF", 1)
        resolution = resolve_query("QF", limited, operator_index.exact_code_count("QF"))
        self.assertEqual(resolution["kind"], "ambiguous")
        self.assertEqual(resolution["exactCodeCount"], len(exact_ids))
        self.assertEqual(limited[0]["id"], exact_ids[0])
        self.assertNotIn("active", operators[0])
        for record in operators:
            self.assertNotIn("active", record)
        historical = next(record for record in operators if record["id"] == "wikidata:Q100268337")
        self.assertTrue(historical["historical"])
        self.assertNotIn("dissolvedOn", historical)
        self.assertNotIn("active", historical)
        found = operator_index.search(historical["name"], 5)
        self.assertEqual(found[0]["id"], historical["id"])
        closed = next(record for record in airports if record["id"] == "ourairports:10002")
        self.assertEqual(closed["type"], "closed")
        airport_index = SearchIndex(airports, AIRPORT_CODE_FIELDS, AIRPORT_NAME_FIELDS)
        self.assertEqual(airport_index.search("Roto-Whirl", 5)[0]["id"], closed["id"])
        blank = resolve_query("   ", [], 0)
        self.assertEqual(blank["kind"], "blank")
        self.assertEqual(operator_index.search("", 5), [])


def _linear_ids(index: SearchIndex, query: str, limit: int) -> list[str]:
    normalized = normalize_search_text(query)
    compact = compact_search_text(normalized)
    if limit == 0 or not normalized or len(compact) < 2:
        return []
    short_code = len(compact) <= 3 and is_ascii_alnum(compact)
    ranked = []
    for entry in index.entries:
        tier = _tier(entry, normalized, compact, short_code)
        if tier is None:
            continue
        ranked.append((tier, entry.record_id))
    ranked.sort()
    return [record_id for _, record_id in ranked[:limit]]


if __name__ == "__main__":
    unittest.main()
