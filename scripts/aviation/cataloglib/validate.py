"""Catalog validation. Returns a list of human-readable errors."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from cataloglib import CATALOG_FILES, SCHEMA_VERSION
from cataloglib.vocabulary import AIRPORT_TYPES, OPERATOR_TAGS

REQUIRED_SOURCE_FIELDS = ("id", "name", "url", "publisher", "license", "licenseUrl", "snapshot")


def validate_catalog(root: Path) -> list[str]:
    errors: list[str] = []
    data_dir = root / "data" / "aviation"
    documents: dict[str, dict] = {}
    raw: dict[str, bytes] = {}
    for name in CATALOG_FILES:
        path = data_dir / name
        if not path.is_file():
            errors.append(f"missing {name}")
            continue
        file_bytes = path.read_bytes()
        raw[name] = file_bytes
        if not file_bytes.endswith(b"\n"):
            errors.append(f"{name} must end with a newline")
        try:
            documents[name] = json.loads(file_bytes)
        except json.JSONDecodeError as error:
            errors.append(f"{name} is not valid JSON: {error}")
    if "catalog-manifest.json" not in documents:
        return errors
    manifest = documents["catalog-manifest.json"]
    errors.extend(_validate_manifest(manifest, raw))
    datasets = {}
    for name, document in documents.items():
        if name == "catalog-manifest.json":
            continue
        dataset = document.get("dataset")
        datasets[name] = document
        if document.get("schemaVersion") != SCHEMA_VERSION:
            errors.append(f"{name} schemaVersion must be {SCHEMA_VERSION}")
        if not dataset:
            errors.append(f"{name} is missing dataset")
        records = document.get("records")
        if name != "classifications.json" and not isinstance(records, list):
            errors.append(f"{name} records must be an array")
        elif isinstance(records, list) and len(records) == 0:
            errors.append(f"{name} is unexpectedly empty")
    if "classifications.json" in documents:
        errors.extend(_validate_classifications(documents["classifications.json"]))
    operators = _records(documents, "operators.json")
    manufacturers = _records(documents, "manufacturers.json")
    aircraft = _records(documents, "aircraft.json")
    airports = _records(documents, "airports.json")
    errors.extend(_unique_ids("operators", operators))
    errors.extend(_unique_ids("manufacturers", manufacturers))
    errors.extend(_unique_ids("aircraft", aircraft))
    errors.extend(_unique_ids("airports", airports))
    manufacturer_ids = {record.get("id") for record in manufacturers}
    aircraft_ids = {record.get("id") for record in aircraft}
    source_ids = {source.get("id") for source in manifest.get("sources", []) if isinstance(source, dict)}
    for record in operators:
        errors.extend(_require_text(record, "operators", ("id", "name", "sourceId")))
        errors.extend(_string_list(record, "operators", "aliases"))
        errors.extend(_string_list(record, "operators", "tags"))
        errors.extend(_string_list(record, "operators", "iataCodes", required=False))
        errors.extend(_string_list(record, "operators", "icaoCodes", required=False))
        errors.extend(_string_list(record, "operators", "callsigns", required=False))
        if record.get("sourceId") not in source_ids:
            errors.append(f"operators source {record.get('id')} has unknown sourceId")
        for tag in record.get("tags") or []:
            if tag not in OPERATOR_TAGS:
                errors.append(f"operator {record.get('id')} has unknown tag {tag}")
        if record.get("historical") not in (None, True):
            errors.append(f"operator {record.get('id')} historical must be true when present")
    for record in manufacturers:
        errors.extend(_require_text(record, "manufacturers", ("id", "name", "sourceId")))
        errors.extend(_string_list(record, "manufacturers", "aliases"))
        if record.get("sourceId") not in source_ids:
            errors.append(f"manufacturer {record.get('id')} has unknown sourceId")
    for record in aircraft:
        errors.extend(_require_text(record, "aircraft", ("id", "model", "displayName", "entryKind", "sourceId")))
        errors.extend(_string_list(record, "aircraft", "aliases"))
        if record.get("entryKind") not in {"model", "family", "unspecified"}:
            errors.append(f"aircraft {record.get('id')} has invalid entryKind")
        if record.get("sourceId") not in source_ids:
            errors.append(f"aircraft {record.get('id')} has unknown sourceId")
        manufacturer_id = record.get("manufacturerId")
        if manufacturer_id is not None and manufacturer_id not in manufacturer_ids:
            errors.append(f"aircraft {record.get('id')} references missing manufacturer {manufacturer_id}")
        family_id = record.get("familyId")
        if family_id is not None and family_id not in aircraft_ids:
            errors.append(f"aircraft {record.get('id')} references missing family {family_id}")
        if family_id == record.get("id"):
            errors.append(f"aircraft {record.get('id')} references itself as family")
    for record in airports:
        errors.extend(_require_text(record, "airports", ("id", "ident", "name", "type", "sourceId")))
        errors.extend(_string_list(record, "airports", "aliases"))
        if record.get("type") not in AIRPORT_TYPES:
            errors.append(f"airport {record.get('id')} has undocumented type {record.get('type')}")
        if record.get("sourceId") not in source_ids:
            errors.append(f"airport {record.get('id')} has unknown sourceId")
        errors.extend(_coordinate(record, "latitude", -90, 90))
        errors.extend(_coordinate(record, "longitude", -180, 180))
        if not isinstance(record.get("scheduledService"), bool):
            errors.append(f"airport {record.get('id')} scheduledService must be boolean")
    if isinstance(manifest.get("counts"), dict):
        count_checks = {
            "operators": len(operators),
            "manufacturers": len(manufacturers),
            "aircraft": len(aircraft),
            "airports": len(airports),
        }
        for key, actual in count_checks.items():
            if manifest["counts"].get(key) != actual:
                errors.append(f"manifest count for {key} does not match records")
        classification_values = 0
        for dimension in (documents.get("classifications.json") or {}).get("dimensions", []):
            classification_values += len(dimension.get("values", []))
        if manifest["counts"].get("classificationValues") != classification_values:
            errors.append("manifest classification count does not match vocabulary")
    errors.extend(_copies_match(root, raw))
    return errors


def _validate_manifest(manifest: dict, raw: dict[str, bytes]) -> list[str]:
    errors: list[str] = []
    if manifest.get("schemaVersion") != SCHEMA_VERSION:
        errors.append("manifest schemaVersion is not supported")
    if not manifest.get("catalogVersion"):
        errors.append("manifest catalogVersion is empty")
    sources = manifest.get("sources")
    if not isinstance(sources, list) or not sources:
        errors.append("manifest sources are missing")
        return errors
    seen = set()
    for source in sources:
        if not isinstance(source, dict):
            errors.append("manifest source is not an object")
            continue
        for field in REQUIRED_SOURCE_FIELDS:
            if not str(source.get(field, "")).strip():
                errors.append(f"source {source.get('id')} is missing {field}")
        source_id = source.get("id")
        if source_id in seen:
            errors.append(f"duplicate source {source_id}")
        seen.add(source_id)
        license_name = str(source.get("license", ""))
        if source_id == "ourairports" and "Public Domain" not in license_name:
            errors.append("OurAirports license metadata is not Public Domain")
        if source_id == "wikidata" and "CC0" not in license_name:
            errors.append("Wikidata license metadata is not CC0")
        if source_id == "openflights":
            errors.append("OpenFlights must not be embedded")
    files = manifest.get("files")
    if not isinstance(files, dict):
        errors.append("manifest files are missing")
        return errors
    for name, file_bytes in raw.items():
        if name == "catalog-manifest.json":
            continue
        listed = files.get(name)
        if not isinstance(listed, dict):
            errors.append(f"manifest is missing {name}")
            continue
        digest = hashlib.sha256(file_bytes).hexdigest()
        if listed.get("sha256") != digest:
            errors.append(f"manifest hash mismatch for {name}")
        if listed.get("bytes") != len(file_bytes):
            errors.append(f"manifest byte count mismatch for {name}")
    counts = manifest.get("counts")
    if not isinstance(counts, dict):
        errors.append("manifest counts are missing")
    else:
        expected = {
            "operators.json": counts.get("operators"),
            "manufacturers.json": counts.get("manufacturers"),
            "aircraft.json": counts.get("aircraft"),
            "airports.json": counts.get("airports"),
            "classifications.json": counts.get("classificationValues"),
        }
        for name, count in expected.items():
            listed = files.get(name, {})
            if listed.get("records") != count:
                errors.append(f"manifest record count mismatch for {name}")
    return errors


def _validate_classifications(document: dict) -> list[str]:
    errors: list[str] = []
    dimensions = document.get("dimensions")
    if not isinstance(dimensions, list) or not dimensions:
        return ["classifications dimensions are empty"]
    seen_dimensions = set()
    for dimension in dimensions:
        dimension_id = dimension.get("id")
        if not dimension_id or dimension_id in seen_dimensions:
            errors.append(f"invalid classification dimension {dimension_id}")
        seen_dimensions.add(dimension_id)
        seen_values = set()
        for value in dimension.get("values", []):
            value_id = value.get("id")
            if not value_id or not value.get("label") or value_id in seen_values:
                errors.append(f"invalid classification value in {dimension_id}: {value_id}")
            seen_values.add(value_id)
        if dimension_id in {"aircraft-role", "operation-type"} and ("unknown" not in seen_values or "other" not in seen_values):
            errors.append(f"{dimension_id} must include unknown and other")
        if dimension_id == "operator-tag" and "other" not in seen_values:
            errors.append("operator-tag must include other")
    return errors


def _records(documents: dict, name: str) -> list[dict]:
    document = documents.get(name) or {}
    records = document.get("records")
    if not isinstance(records, list):
        return []
    return [record for record in records if isinstance(record, dict)]


def _unique_ids(dataset: str, records: list[dict]) -> list[str]:
    errors = []
    seen = set()
    previous = ""
    for record in records:
        record_id = record.get("id")
        if not isinstance(record_id, str) or not record_id.strip():
            errors.append(f"{dataset} has a record without an id")
            continue
        if record_id in seen:
            errors.append(f"duplicate {dataset} id {record_id}")
        if previous and record_id < previous:
            errors.append(f"{dataset} ids are not sorted at {record_id}")
        seen.add(record_id)
        previous = record_id
    return errors


def _require_text(record: dict, dataset: str, fields: tuple[str, ...]) -> list[str]:
    errors = []
    for field in fields:
        value = record.get(field)
        if not isinstance(value, str) or not value.strip():
            errors.append(f"{dataset} {record.get('id')} is missing {field}")
    return errors


def _string_list(record: dict, dataset: str, field: str, required: bool = True) -> list[str]:
    if field not in record:
        if required:
            return [f"{dataset} {record.get('id')} is missing {field}"]
        return []
    value = record.get(field)
    if not isinstance(value, list):
        return [f"{dataset} {record.get('id')} {field} must be an array"]
    errors = []
    seen = set()
    for item in value:
        if not isinstance(item, str) or not item.strip():
            errors.append(f"{dataset} {record.get('id')} has an empty {field} entry")
            continue
        if item in seen:
            errors.append(f"{dataset} {record.get('id')} has duplicate {field} {item}")
        seen.add(item)
    return errors


def _coordinate(record: dict, field: str, low: float, high: float) -> list[str]:
    value = record.get(field)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return [f"airport {record.get('id')} has invalid {field}"]
    if value < low or value > high:
        return [f"airport {record.get('id')} {field} is out of range"]
    return []


def _copies_match(root: Path, raw: dict[str, bytes]) -> list[str]:
    errors = []
    destinations = [
        root / "iOS" / "AviationCatalogCore" / "Sources" / "AviationCatalog" / "Resources",
        root / "Android" / "app" / "src" / "main" / "assets" / "aviation",
    ]
    for destination in destinations:
        for name, file_bytes in raw.items():
            path = destination / name
            if not path.is_file():
                errors.append(f"bundled copy missing: {path}")
                continue
            if path.read_bytes() != file_bytes:
                errors.append(f"bundled copy differs: {path}")
    return errors
