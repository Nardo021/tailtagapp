"""Transform pinned snapshots into the aviation catalog."""

from __future__ import annotations

import csv
import hashlib
import json
import re
from decimal import Decimal, ROUND_HALF_EVEN
from pathlib import Path

from cataloglib import SCHEMA_VERSION
from cataloglib.normalize import WHITESPACE, clean_code, normalize_search_text
from cataloglib.vocabulary import AIRPORT_TYPES, OPERATOR_TAGS, VOCABULARY

ROOT = Path(__file__).resolve().parents[3]
SNAPSHOT_DIR = ROOT / "data" / "aviation" / "snapshots"
DATA_DIR = ROOT / "data" / "aviation"
TAG_MAP_PATH = Path(__file__).resolve().parents[1] / "operator_tag_map.json"
AIRCRAFT_MODEL = "Q15056995"
AIRCRAFT_FAMILY = "Q15056993"
IATA_AIRLINE = re.compile(r"^[A-Z0-9]{2}$")
ICAO_AIRLINE = re.compile(r"^[A-Z0-9]{2,3}$")
IATA_AIRPORT = re.compile(r"^[A-Z0-9]{3}$")
ICAO_AIRPORT = re.compile(r"^[A-Z0-9]{4}$")
COUNTRY_CODE = re.compile(r"^[A-Z0-9]{2}$")
DISSOLVED_DATE = re.compile(r"^\+(\d{4})-(\d{2})-(\d{2})T")


def build_documents(snapshot_dir: Path = SNAPSHOT_DIR) -> dict[str, str]:
    meta = _verified_meta(snapshot_dir)
    stats: dict[str, object] = {
        "excludedOperatorsMissingName": 0,
        "excludedAircraftMissingName": 0,
        "anomalousOperatorCodes": 0,
        "anomalousAirportCodes": 0,
        "operatorsWithMultipleCountries": 0,
        "airportsMissingScheduledService": 0,
    }
    tag_map = json.loads(TAG_MAP_PATH.read_text(encoding="utf-8"))["byLabel"]
    unknown_tags = sorted(set(tag_map.values()) - OPERATOR_TAGS)
    if unknown_tags:
        raise SystemExit(f"operator tag map contains unknown tags: {unknown_tags}")

    manufacturers = _build_manufacturers(snapshot_dir, stats)
    aircraft = _build_aircraft(snapshot_dir, manufacturers, stats)
    operators, unmapped = _build_operators(snapshot_dir, tag_map, stats)
    airports = _build_airports(snapshot_dir, stats)
    _assert_known_facts(operators, airports, aircraft)
    classifications = VOCABULARY
    dataset_texts = {
        "operators.json": _dump(_envelope("operators", operators)),
        "manufacturers.json": _dump(_envelope("manufacturers", manufacturers)),
        "aircraft.json": _dump(_envelope("aircraft", aircraft)),
        "airports.json": _dump(_envelope("airports", airports)),
        "classifications.json": _dump(classifications),
    }
    classification_values = sum(len(item["values"]) for item in classifications["dimensions"])
    manifest = {
        "catalogVersion": meta.get("catalogVersion") or meta["snapshotDate"].replace("-", "."),
        "counts": {
            "aircraft": len(aircraft),
            "aircraftFamilies": sum(1 for record in aircraft if record["entryKind"] == "family"),
            "aircraftModels": sum(1 for record in aircraft if record["entryKind"] == "model"),
            "airports": len(airports),
            "classificationValues": classification_values,
            "manufacturers": len(manufacturers),
            "operators": len(operators),
        },
        "files": {
            name: {
                "bytes": len(text.encode("utf-8")),
                "records": _file_record_count(name, operators, manufacturers, aircraft, airports, classification_values),
                "sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
            }
            for name, text in dataset_texts.items()
        },
        "generation": {
            "coordinateRounding": "6 decimal places, half even",
            "exclusions": stats,
            "generator": "scripts/aviation/build_catalog.py",
            "inputFiles": meta["files"],
            "limitations": [
                "ICAO aircraft type designators are not populated. No Wikidata property for them was verified; short names are searchable aliases and are not treated as designators.",
                "IATA aircraft equipment codes are not populated. No redistributable property was verified.",
                "Operators are Wikidata items with an IATA airline designator, an ICAO airline designator, or instance of air force Q61883. Missing dissolution data is not treated as proof that an operator is active.",
                "Aircraft coverage is English-Wikipedia aircraft models and aircraft families, plus a documented Wikidata overlay for common models that have no English Wikipedia sitelink.",
                "Airport coordinates from OurAirports are rounded to 6 decimal places.",
            ],
            "ourairportsCommit": meta["ourairports"]["commit"],
            "snapshotDate": meta["snapshotDate"],
            "unmappedOperatorTypeLabels": unmapped,
            "verifiedWikidataProperties": meta["wikidata"]["verifiedPropertyLabels"],
        },
        "schemaVersion": SCHEMA_VERSION,
        "sources": _sources(meta),
    }
    texts = dict(dataset_texts)
    texts["catalog-manifest.json"] = _dump(manifest)
    return texts


def write_catalog(texts: dict[str, str], root: Path = ROOT) -> None:
    destinations = [
        root / "data" / "aviation",
        root / "iOS" / "AviationCatalogCore" / "Sources" / "AviationCatalog" / "Resources",
        root / "Android" / "app" / "src" / "main" / "assets" / "aviation",
    ]
    for destination in destinations:
        destination.mkdir(parents=True, exist_ok=True)
        for name, text in texts.items():
            (destination / name).write_text(text, encoding="utf-8")


def _verified_meta(snapshot_dir: Path) -> dict:
    meta_path = snapshot_dir / "snapshot-meta.json"
    if not meta_path.is_file():
        raise SystemExit("missing snapshot-meta.json; run fetch_sources.py before building")
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    for name, info in meta["files"].items():
        path = snapshot_dir / name
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != info["sha256"]:
            raise SystemExit(f"snapshot hash mismatch for {name}")
    labels = meta["wikidata"]["verifiedPropertyLabels"]
    if "short name" not in labels.get("P1813", "").casefold():
        raise SystemExit("P1813 was not verified as short name")
    if "icao" not in labels.get("P230", "").casefold():
        raise SystemExit("P230 was not verified as an ICAO airline designator")
    return meta


def _curated_aircraft(snapshot_dir: Path) -> list[dict]:
    path = snapshot_dir / "wikidata-curated-aircraft.json"
    if not path.is_file():
        return []
    document = json.loads(path.read_text(encoding="utf-8"))
    records = []
    for item in document.get("records", []):
        qid = str(item.get("id", ""))
        if not qid.startswith("Q") or not qid[1:].isdigit():
            raise SystemExit(f"curated aircraft id is not a Wikidata Q-id: {qid}")
        records.append(
            {
                "aliases": [str(value) for value in item.get("aliases", [])],
                "families": [str(value) for value in item.get("families", [])],
                "id": qid,
                "instanceOf": [str(value) for value in item.get("instanceOf", [])],
                "label": str(item.get("label", "")),
                "manufacturers": [str(value) for value in item.get("manufacturers", [])],
            }
        )
    return records


def _build_manufacturers(snapshot_dir: Path, stats: dict) -> list[dict]:
    labels = _labels(snapshot_dir / "wikidata-manufacturers.json")
    countries = _grouped(snapshot_dir / "wikidata-manufacturers.json", "countryCode")
    aliases = _grouped(snapshot_dir / "wikidata-manufacturer-aliases.json", "alias")
    records = []
    for qid in sorted(labels, key=_qid_key):
        name = labels[qid]
        if _missing_label(name, qid):
            continue
        record = {
            "aliases": _aliases(aliases.get(qid, []), banned={name}),
            "id": f"wikidata:{qid}",
            "name": name,
            "sourceId": "wikidata",
        }
        country = _sole_country(countries.get(qid, []))
        if country:
            record["countryCode"] = country
        records.append(record)
    records.sort(key=lambda record: record["id"])
    return records


def _build_aircraft(snapshot_dir: Path, manufacturers: list[dict], stats: dict) -> list[dict]:
    labels = {}
    labels.update(_labels(snapshot_dir / "wikidata-aircraft-models.json"))
    labels.update(_labels(snapshot_dir / "wikidata-aircraft-families-items.json"))
    model_ids = set(_labels(snapshot_dir / "wikidata-aircraft-models.json"))
    family_ids = set(_labels(snapshot_dir / "wikidata-aircraft-families-items.json"))
    manufacturer_links = _grouped_qids(snapshot_dir / "wikidata-aircraft-manufacturers.json", "manufacturer")
    family_links = _grouped_qids(snapshot_dir / "wikidata-aircraft-families.json", "family")
    types = _grouped_qids(snapshot_dir / "wikidata-aircraft-types.json", "type")
    aliases = _grouped(snapshot_dir / "wikidata-aircraft-aliases.json", "alias")
    short_names = _grouped(snapshot_dir / "wikidata-aircraft-short-names.json", "alias")
    curated_added = 0
    for item in _curated_aircraft(snapshot_dir):
        qid = item["id"]
        if qid in labels or _missing_label(item["label"], qid):
            continue
        labels[qid] = item["label"]
        instance_of = list(item["instanceOf"])
        types[qid] = instance_of
        if AIRCRAFT_MODEL in instance_of:
            model_ids.add(qid)
        if AIRCRAFT_FAMILY in instance_of:
            family_ids.add(qid)
        if item["manufacturers"]:
            manufacturer_links[qid] = list(item["manufacturers"])
        if item["families"]:
            family_links[qid] = list(item["families"])
        if item["aliases"]:
            aliases[qid] = list(item["aliases"])
        curated_added += 1
    stats["curatedAircraftAdded"] = curated_added
    manufacturer_by_id = {record["id"]: record for record in manufacturers}
    preliminary: dict[str, dict] = {}
    for qid, label in labels.items():
        if _missing_label(label, qid):
            stats["excludedAircraftMissingName"] = int(stats["excludedAircraftMissingName"]) + 1
            continue
        type_ids = set(types.get(qid, []))
        if AIRCRAFT_MODEL in type_ids:
            entry_kind = "model"
        elif AIRCRAFT_FAMILY in type_ids or qid in family_ids and qid not in model_ids:
            entry_kind = "family"
        elif qid in model_ids:
            entry_kind = "model"
        else:
            entry_kind = "unspecified"
        linked = [item for item in manufacturer_links.get(qid, []) if f"wikidata:{item}" in manufacturer_by_id]
        linked.sort(key=_qid_key)
        names = []
        for item in linked:
            manufacturer_name = manufacturer_by_id[f"wikidata:{item}"]["name"]
            if manufacturer_name not in names:
                names.append(manufacturer_name)
        alias_values = aliases.get(qid, []) + short_names.get(qid, [])
        record = {
            "aliases": _aliases(alias_values, banned={label}),
            "displayName": _display_name(label, names[0] if names else None),
            "entryKind": entry_kind,
            "id": f"wikidata:{qid}",
            "model": label,
            "sourceId": "wikidata",
        }
        if names:
            record["manufacturer"] = names[0]
            record["manufacturerId"] = f"wikidata:{linked[0]}"
            if len(names) > 1:
                record["manufacturerNames"] = names
        preliminary[record["id"]] = record
        preliminary[record["id"]]["_parents"] = [
            f"wikidata:{parent}" for parent in family_links.get(qid, []) if parent != qid
        ]
    for record in preliminary.values():
        parents = sorted(parent for parent in record.pop("_parents") if parent in preliminary)
        if not parents:
            continue
        record["familyId"] = parents[0]
        record["family"] = preliminary[parents[0]]["model"]
        extra_names = [preliminary[parent]["model"] for parent in parents[1:]]
        if extra_names:
            record["aliases"] = _aliases(list(record["aliases"]) + extra_names, banned={record["model"]})
    aircraft = sorted(preliminary.values(), key=lambda record: record["id"])
    return aircraft


def _build_operators(snapshot_dir: Path, tag_map: dict[str, str], stats: dict) -> tuple[list[dict], list[dict]]:
    labels: dict[str, set[str]] = {}
    iata_values: dict[str, list[str]] = {}
    icao_values: dict[str, list[str]] = {}
    for row in _rows(snapshot_dir / "wikidata-operators-iata.json"):
        qid = _row_qid(row)
        label = _clean_label(row.get("itemLabel", {}).get("value", ""))
        if label:
            labels.setdefault(qid, set()).add(label)
        code = clean_code(row.get("iata", {}).get("value"))
        if code:
            iata_values.setdefault(qid, [])
            if code not in iata_values[qid]:
                iata_values[qid].append(code)
    for row in _rows(snapshot_dir / "wikidata-operators-icao.json"):
        qid = _row_qid(row)
        label = _clean_label(row.get("itemLabel", {}).get("value", ""))
        if label:
            labels.setdefault(qid, set()).add(label)
        code = clean_code(row.get("icao", {}).get("value"))
        if code:
            icao_values.setdefault(qid, [])
            if code not in icao_values[qid]:
                icao_values[qid].append(code)
    for qid, label in _labels(snapshot_dir / "wikidata-air-forces.json").items():
        labels.setdefault(qid, set()).add(label)
    aliases = _grouped(snapshot_dir / "wikidata-operator-aliases.json", "alias")
    short_names = _grouped(snapshot_dir / "wikidata-operator-short-names.json", "alias")
    official_names = _grouped(snapshot_dir / "wikidata-operator-names.json", "official")
    callsigns = _grouped(snapshot_dir / "wikidata-operator-callsigns.json", "callsign")
    countries = _grouped(snapshot_dir / "wikidata-operator-countries.json", "countryCode")
    dissolved = _grouped(snapshot_dir / "wikidata-operator-dissolved.json", "dissolved")
    type_labels: dict[str, set[str]] = {}
    label_counts: dict[str, int] = {}
    for row in _rows(snapshot_dir / "wikidata-operator-types.json"):
        qid = _row_qid(row)
        label = _clean_label(row.get("typeLabel", {}).get("value", ""))
        if not label:
            continue
        type_labels.setdefault(qid, set()).add(label)
        label_counts[label] = label_counts.get(label, 0) + 1
    records = []
    anomalous = 0
    multiple_countries = 0
    for qid in sorted(labels, key=_qid_key):
        name = sorted(labels[qid])[0]
        if _missing_label(name, qid):
            stats["excludedOperatorsMissingName"] = int(stats["excludedOperatorsMissingName"]) + 1
            continue
        iata_codes = _sorted_codes(iata_values.get(qid, []))
        icao_codes = _sorted_codes(icao_values.get(qid, []))
        anomalous += sum(1 for code in iata_codes if not IATA_AIRLINE.fullmatch(code))
        anomalous += sum(1 for code in icao_codes if not ICAO_AIRLINE.fullmatch(code))
        alias_values = aliases.get(qid, []) + short_names.get(qid, []) + official_names.get(qid, [])
        record = {
            "aliases": _aliases(alias_values, banned={name}),
            "id": f"wikidata:{qid}",
            "name": name,
            "sourceId": "wikidata",
            "tags": _operator_tags(type_labels.get(qid, set()), tag_map),
        }
        if iata_codes:
            record["iataCodes"] = iata_codes
        if icao_codes:
            record["icaoCodes"] = icao_codes
        calls = _sorted_unique(_clean_label(value) for value in callsigns.get(qid, []))
        if calls:
            record["callsigns"] = calls
        country_values = []
        for value in countries.get(qid, []):
            code = clean_code(value)
            if code and COUNTRY_CODE.fullmatch(code):
                country_values.append(code)
        country_values = _sorted_unique(country_values)
        if len(country_values) == 1:
            record["countryCode"] = country_values[0]
        elif len(country_values) > 1:
            multiple_countries += 1
        if qid in dissolved or dissolved.get(qid):
            record["historical"] = True
            dates = [match.group(0)[1:11] for value in dissolved.get(qid, []) if (match := DISSOLVED_DATE.match(value)) and match.group(2) != "00" and match.group(3) != "00"]
            if dates:
                record["dissolvedOn"] = sorted(dates)[0]
        records.append(record)
    records.sort(key=lambda record: record["id"])
    stats["anomalousOperatorCodes"] = anomalous
    stats["operatorsWithMultipleCountries"] = multiple_countries
    stats["duplicateIataCodeGroups"] = _duplicate_code_groups(records, "iataCodes")
    stats["duplicateIcaoCodeGroups"] = _duplicate_code_groups(records, "icaoCodes")
    unmapped = [
        {"count": count, "label": label}
        for label, count in sorted(label_counts.items(), key=lambda item: (-item[1], item[0]))
        if label not in tag_map
    ][:40]
    return records, unmapped


def _build_airports(snapshot_dir: Path, stats: dict) -> list[dict]:
    records = []
    seen: set[str] = set()
    anomalous = 0
    with (snapshot_dir / "ourairports-airports.csv").open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            source_id = row["id"].strip()
            if not source_id.isdigit():
                raise SystemExit(f"OurAirports id is not numeric: {source_id}")
            record_id = f"ourairports:{int(source_id)}"
            if record_id in seen:
                raise SystemExit(f"duplicate OurAirports id {record_id}")
            seen.add(record_id)
            airport_type = row["type"].strip()
            if airport_type not in AIRPORT_TYPES:
                raise SystemExit(f"undocumented OurAirports type {airport_type}")
            name = _clean_label(row["name"])
            ident = _clean_label(row["ident"])
            if not name or not ident:
                raise SystemExit(f"airport {record_id} is missing a name or ident")
            service = row["scheduled_service"].strip()
            if service not in {"yes", "no"}:
                stats["airportsMissingScheduledService"] = int(stats["airportsMissingScheduledService"]) + 1
                continue
            record = {
                "aliases": _aliases(row["keywords"].split(","), banned={name, ident}),
                "id": record_id,
                "ident": ident,
                "latitude": _coordinate(row["latitude_deg"], record_id, "latitude"),
                "longitude": _coordinate(row["longitude_deg"], record_id, "longitude"),
                "name": name,
                "scheduledService": service == "yes",
                "sourceId": "ourairports",
                "type": airport_type,
            }
            for field, column, pattern in (
                ("iataCode", "iata_code", IATA_AIRPORT),
                ("icaoCode", "icao_code", ICAO_AIRPORT),
                ("gpsCode", "gps_code", None),
                ("localCode", "local_code", None),
            ):
                code = clean_code(row[column])
                if not code:
                    continue
                if pattern is not None and not pattern.fullmatch(code):
                    anomalous += 1
                record[field] = code
            country = clean_code(row["iso_country"])
            if country and COUNTRY_CODE.fullmatch(country):
                record["countryCode"] = country
            municipality = _clean_label(row["municipality"])
            if municipality:
                record["municipality"] = municipality
            records.append(record)
    records.sort(key=lambda record: record["id"])
    stats["anomalousAirportCodes"] = anomalous
    return records


def _assert_known_facts(operators: list[dict], airports: list[dict], aircraft: list[dict]) -> None:
    qantas = [
        record
        for record in operators
        if "QF" in record.get("iataCodes", []) and "Qantas" in record["name"]
    ]
    if not qantas:
        raise SystemExit("Refusing to publish: Qantas with IATA QF was not in the verified operator snapshot")
    by_airport = {record["id"]: record for record in airports}
    heathrow = by_airport.get("ourairports:2434")
    if heathrow is None or heathrow.get("iataCode") != "LHR" or heathrow.get("icaoCode") != "EGLL":
        raise SystemExit("Refusing to publish: OurAirports sample id 2434 was not London Heathrow EGLL/LHR")
    sydney = by_airport.get("ourairports:27145")
    if sydney is None or sydney.get("iataCode") != "SYD" or sydney.get("icaoCode") != "YSSY":
        raise SystemExit("Refusing to publish: Sydney YSSY/SYD was not ourairports:27145")
    a350 = next((record for record in aircraft if record["id"] == "wikidata:Q92162002"), None)
    if a350 is None or "A350" not in a350["displayName"]:
        raise SystemExit("Refusing to publish: Wikidata Q92162002 Airbus A350-900 was not imported")


def _sources(meta: dict) -> list[dict]:
    return [
        {
            "id": "ourairports",
            "importedFields": [
                "id",
                "ident",
                "type",
                "name",
                "latitude_deg",
                "longitude_deg",
                "iso_country",
                "municipality",
                "scheduled_service",
                "icao_code",
                "iata_code",
                "gps_code",
                "local_code",
                "keywords",
            ],
            "license": "Public Domain",
            "licenseNote": "OurAirports states that the downloadable data is released to the public domain. The pinned GitHub LICENSE file uses the Unlicense text. This does not relicense TailTag application code.",
            "licenseUrl": "https://ourairports.com/data/",
            "name": "OurAirports",
            "publisher": "OurAirports",
            "snapshot": meta["ourairports"]["commit"],
            "url": "https://ourairports.com/data/",
        },
        {
            "id": "wikidata",
            "importedFields": [
                "English label",
                "English alias",
                "short name (P1813)",
                "IATA airline designator (P229)",
                "ICAO airline designator (P230)",
                "airline call sign (P432)",
                "country (P17) ISO 3166-1 alpha-2 (P297)",
                "dissolved, abolished or demolished date (P576)",
                "official name (P1448)",
                "instance of (P31)",
                "manufacturer (P176)",
                "subclass of (P279)",
            ],
            "license": "CC0 1.0",
            "licenseNote": "Structured data in the Wikidata main namespace is available under CC0 1.0. Short names are imported as aliases only.",
            "licenseUrl": "https://www.wikidata.org/wiki/Wikidata:Licensing",
            "name": "Wikidata",
            "publisher": "Wikidata contributors",
            "snapshot": meta["snapshotDate"],
            "url": "https://www.wikidata.org/",
        },
        {
            "id": "tailtag-vocabulary",
            "importedFields": ["dimension id", "value id", "English label"],
            "license": "Project-authored vocabulary distributed with this catalog. This notice does not relicense TailTag application code.",
            "licenseUrl": "https://github.com/JoshOn360Hz/TailTagApp",
            "name": "TailTag classification vocabulary",
            "publisher": "TailTag contributors",
            "snapshot": meta["snapshotDate"],
            "url": "https://github.com/JoshOn360Hz/TailTagApp",
        },
    ]


def _envelope(dataset: str, records: list[dict]) -> dict:
    return {"dataset": dataset, "records": records, "schemaVersion": SCHEMA_VERSION}


def _file_record_count(name, operators, manufacturers, aircraft, airports, classification_values) -> int:
    return {
        "operators.json": len(operators),
        "manufacturers.json": len(manufacturers),
        "aircraft.json": len(aircraft),
        "airports.json": len(airports),
        "classifications.json": classification_values,
    }[name]


def _rows(path: Path) -> list[dict]:
    if not path.is_file():
        raise SystemExit(f"missing snapshot {path.name}")
    payload = json.loads(path.read_text(encoding="utf-8"), strict=False)
    return payload.get("results", {}).get("bindings", [])


def _row_qid(row: dict, field: str = "item") -> str:
    token = row[field]["value"].rstrip("/").rsplit("/", 1)[-1]
    if not token.startswith("Q") or not token[1:].isdigit():
        raise SystemExit(f"unexpected Wikidata id {token}")
    return token


def _labels(path: Path) -> dict[str, str]:
    found: dict[str, list[str]] = {}
    for row in _rows(path):
        label = _clean_label(row.get("itemLabel", {}).get("value", ""))
        if not label:
            continue
        found.setdefault(_row_qid(row), [])
        if label not in found[_row_qid(row)]:
            found[_row_qid(row)].append(label)
    return {qid: sorted(values)[0] for qid, values in found.items()}


def _grouped(path: Path, field: str) -> dict[str, list[str]]:
    found: dict[str, list[str]] = {}
    for row in _rows(path):
        if field not in row:
            continue
        value = row[field]["value"]
        bucket = found.setdefault(_row_qid(row), [])
        if value not in bucket:
            bucket.append(value)
    return found


def _grouped_qids(path: Path, field: str) -> dict[str, list[str]]:
    found: dict[str, list[str]] = {}
    for row in _rows(path):
        if field not in row:
            continue
        value = _row_qid(row, field)
        bucket = found.setdefault(_row_qid(row), [])
        if value not in bucket:
            bucket.append(value)
    return found


def _duplicate_code_groups(records: list[dict], field: str) -> int:
    counts: dict[str, int] = {}
    for record in records:
        for code in record.get(field, []):
            counts[code] = counts.get(code, 0) + 1
    return sum(1 for count in counts.values() if count > 1)


def _aliases(values: list[str], banned: set[str]) -> list[str]:
    cleaned = []
    seen = set()
    for value in values:
        text = _clean_label(value)
        if not text or text in banned or text in seen or len(text) > 120:
            continue
        seen.add(text)
        cleaned.append(text)
    cleaned.sort()
    return cleaned


def _operator_tags(labels: set[str], tag_map: dict[str, str]) -> list[str]:
    tags = {tag_map[label] for label in labels if label in tag_map}
    return sorted(tags)


def _display_name(label: str, manufacturer: str | None) -> str:
    if not manufacturer:
        return label
    label_norm = normalize_search_text(label)
    manufacturer_norm = normalize_search_text(manufacturer)
    if manufacturer_norm and manufacturer_norm in label_norm:
        return label
    first = manufacturer_norm.split(" ", 1)[0] if manufacturer_norm else ""
    if len(first) >= 4 and first in label_norm:
        return label
    return f"{manufacturer} {label}"


def _sole_country(values: list[str]) -> str | None:
    codes = []
    for value in values:
        code = clean_code(value)
        if code and COUNTRY_CODE.fullmatch(code) and code not in codes:
            codes.append(code)
    if len(codes) == 1:
        return codes[0]
    return None


def _sorted_codes(values: list[str]) -> list[str]:
    return sorted(set(values))


def _sorted_unique(values) -> list[str]:
    return sorted({value for value in values if value})


def _clean_label(value: str) -> str:
    parts: list[str] = []
    current: list[str] = []
    for char in value:
        if char in WHITESPACE:
            if current:
                parts.append("".join(current))
                current = []
        else:
            current.append(char)
    if current:
        parts.append("".join(current))
    return " ".join(parts)


def _missing_label(label: str, qid: str) -> bool:
    return not label or label == qid


def _qid_key(qid: str) -> int:
    return int(qid[1:])


def _coordinate(value: str, record_id: str, field: str) -> Decimal:
    try:
        number = Decimal(value)
    except Exception as error:
        raise SystemExit(f"{record_id} has invalid {field}") from error
    if not number.is_finite():
        raise SystemExit(f"{record_id} has non-finite {field}")
    quantized = number.quantize(Decimal("0.000001"), rounding=ROUND_HALF_EVEN)
    if quantized < Decimal("-180") or quantized > Decimal("180"):
        raise SystemExit(f"{record_id} {field} is out of range")
    if field == "latitude" and (quantized < Decimal("-90") or quantized > Decimal("90")):
        raise SystemExit(f"{record_id} latitude is out of range")
    return quantized


def _dump(value) -> str:
    return _dump_value(value) + "\n"


def _dump_value(value) -> str:
    if isinstance(value, Decimal):
        return format(value, "f")
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "[" + ",".join(_dump_value(item) for item in value) + "]"
    if isinstance(value, dict):
        parts = []
        for key in sorted(value):
            parts.append(_dump_value(key) + ":" + _dump_value(value[key]))
        return "{" + ",".join(parts) + "}"
    raise TypeError(type(value))
