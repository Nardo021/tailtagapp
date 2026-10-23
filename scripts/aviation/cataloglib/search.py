"""Deterministic offline search.

Tiers, best first:
0. Exact normalised code or exact compact code.
1. Exact normalised name or alias, including compact equality.
2. Code prefix, when the compact query has at least 2 characters.
3. Name or alias prefix.
4. Other substring. For an ASCII alphanumeric compact query of length
   3 or less, name substrings are suppressed. Code substrings require a
   compact query of at least 4 characters.

Blank queries and compact queries shorter than 2 characters do not match.
Tie-break is ascending record id, compared by Unicode code point.
"""

from __future__ import annotations

from dataclasses import dataclass

from cataloglib.normalize import compact_search_text, is_ascii_alnum, normalize_search_text

OPERATOR_CODE_FIELDS = ("iataCodes", "icaoCodes", "callsigns", "id")
OPERATOR_NAME_FIELDS = ("name", "aliases")
AIRCRAFT_CODE_FIELDS = ("icaoTypeDesignators", "iataEquipmentCodes", "id")
AIRCRAFT_NAME_FIELDS = (
    "manufacturer",
    "manufacturerNames",
    "family",
    "model",
    "displayName",
    "aliases",
)
AIRPORT_CODE_FIELDS = ("iataCode", "icaoCode", "ident", "gpsCode", "localCode", "id")
AIRPORT_NAME_FIELDS = ("name", "municipality", "aliases")
MANUFACTURER_CODE_FIELDS = ("id",)
MANUFACTURER_NAME_FIELDS = ("name", "aliases")


@dataclass(frozen=True)
class IndexedRecord:
    record: dict
    record_id: str
    codes_norm: tuple[str, ...]
    codes_compact: tuple[str, ...]
    names_norm: tuple[str, ...]
    names_compact: tuple[str, ...]
    identifier_compacts: frozenset[str]


class SearchIndex:
    def __init__(self, records: list[dict], code_fields: tuple[str, ...], name_fields: tuple[str, ...]):
        entries: list[IndexedRecord] = []
        for record in records:
            record_id = str(record["id"])
            local_id = record_id.split(":", 1)[-1]
            code_values = _field_values(record, code_fields)
            if local_id and local_id != record_id:
                code_values.append(local_id)
            codes_norm: list[str] = []
            codes_compact: list[str] = []
            for value in code_values:
                normalized = normalize_search_text(value)
                compact = compact_search_text(normalized)
                if compact:
                    codes_norm.append(normalized)
                    codes_compact.append(compact)
            names_norm: list[str] = []
            names_compact: list[str] = []
            for value in _field_values(record, name_fields):
                normalized = normalize_search_text(value)
                if normalized:
                    names_norm.append(normalized)
                    names_compact.append(compact_search_text(normalized))
            entries.append(
                IndexedRecord(
                    record=record,
                    record_id=record_id,
                    codes_norm=tuple(codes_norm),
                    codes_compact=tuple(codes_compact),
                    names_norm=tuple(names_norm),
                    names_compact=tuple(names_compact),
                    identifier_compacts=frozenset(
                        compact
                        for compact in (
                            compact_search_text(normalize_search_text(record_id)),
                            compact_search_text(normalize_search_text(local_id)),
                        )
                        if compact
                    ),
                )
            )
        self.entries = entries
        exact_codes: dict[str, list[int]] = {}
        prefix_buckets: dict[str, list[int]] = {}
        trigram_buckets: dict[str, list[int]] = {}
        for index, entry in enumerate(entries):
            prefix_seen: set[str] = set()
            trigram_seen: set[str] = set()
            seen_exact: set[str] = set()
            for code_compact in entry.codes_compact:
                if code_compact not in seen_exact:
                    exact_codes.setdefault(code_compact, []).append(index)
                    seen_exact.add(code_compact)
                if len(code_compact) >= 2:
                    key = code_compact[:2]
                    if key not in prefix_seen:
                        prefix_buckets.setdefault(key, []).append(index)
                        prefix_seen.add(key)
                if code_compact not in entry.identifier_compacts and len(code_compact) >= 3:
                    for offset in range(len(code_compact) - 2):
                        tri = code_compact[offset : offset + 3]
                        if tri not in trigram_seen:
                            trigram_buckets.setdefault(tri, []).append(index)
                            trigram_seen.add(tri)
            for name_compact in entry.names_compact:
                if len(name_compact) >= 2:
                    key = name_compact[:2]
                    if key not in prefix_seen:
                        prefix_buckets.setdefault(key, []).append(index)
                        prefix_seen.add(key)
                if len(name_compact) >= 3:
                    for offset in range(len(name_compact) - 2):
                        tri = name_compact[offset : offset + 3]
                        if tri not in trigram_seen:
                            trigram_buckets.setdefault(tri, []).append(index)
                            trigram_seen.add(tri)
        self.exact_codes = exact_codes
        self.prefix_buckets = prefix_buckets
        self.trigram_buckets = trigram_buckets

    def exact_code_count(self, query: str) -> int:
        compact = compact_search_text(normalize_search_text(query))
        return len(self.exact_codes.get(compact, ()))

    def search(self, query: str, limit: int) -> list[dict]:
        if not isinstance(limit, int) or isinstance(limit, bool):
            raise ValueError("limit must be an integer")
        if limit < 0:
            raise ValueError("limit must be >= 0")
        normalized = normalize_search_text(query)
        compact = compact_search_text(normalized)
        if limit == 0 or not normalized or len(compact) < 2:
            return []
        short_code = len(compact) <= 3 and is_ascii_alnum(compact)
        candidates = set(self.prefix_buckets.get(compact[:2], ()))
        if len(compact) >= 3:
            candidates.update(self.trigram_buckets.get(compact[:3], ()))
        ranked: list[tuple[int, str, dict]] = []
        for index in candidates:
            entry = self.entries[index]
            tier = _tier(entry, normalized, compact, short_code)
            if tier is None:
                continue
            ranked.append((tier, entry.record_id, entry.record))
        ranked.sort(key=lambda item: (item[0], item[1]))
        return [item[2] for item in ranked[:limit]]


def resolve_query(query: str, matches: list[dict], exact_code_count: int = 0) -> dict:
    """Classify a query without substituting a different catalog record.

    ``ambiguous`` means more than one record has the same exact code. The
    matches stay in deterministic order and the first match is not a chosen
    airline, model, or airport.
    """
    if not normalize_search_text(query):
        return {"kind": "blank", "matches": [], "text": None, "exactCodeCount": 0}
    if matches:
        kind = "ambiguous" if exact_code_count > 1 else "matches"
        return {"kind": kind, "matches": matches, "text": None, "exactCodeCount": exact_code_count}
    return {"kind": "unmatched", "matches": [], "text": query.strip(), "exactCodeCount": 0}


def _tier(entry: IndexedRecord, query_norm: str, query_compact: str, short_code: bool) -> int | None:
    best: int | None = None
    for code_norm, code_compact in zip(entry.codes_norm, entry.codes_compact):
        if code_compact == query_compact or code_norm == query_norm:
            return 0
        if len(query_compact) >= 2 and code_compact.startswith(query_compact):
            tier = 2
        elif code_compact not in entry.identifier_compacts and len(query_compact) >= 4 and query_compact in code_compact:
            tier = 4
        else:
            continue
        if best is None or tier < best:
            best = tier
    for name_norm, name_compact in zip(entry.names_norm, entry.names_compact):
        if name_norm == query_norm or name_compact == query_compact:
            tier = 1
        elif name_norm.startswith(query_norm) or (
            len(query_compact) >= 2 and name_compact.startswith(query_compact)
        ):
            tier = 3
        elif (
            not short_code
            and len(query_compact) >= 3
            and (query_norm in name_norm or query_compact in name_compact)
        ):
            tier = 4
        else:
            continue
        if best is None or tier < best:
            best = tier
    return best


def _field_values(record: dict, fields: tuple[str, ...]) -> list[str]:
    values: list[str] = []
    for field in fields:
        raw = record.get(field)
        if raw is None:
            continue
        if isinstance(raw, list):
            for item in raw:
                if item is not None and str(item).strip():
                    values.append(str(item))
        elif str(raw).strip():
            values.append(str(raw))
    return values
