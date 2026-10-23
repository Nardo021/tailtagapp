# Aviation reference catalog

TailTag ships one offline aviation catalog. `data/aviation/` is the source that both apps bundle. iOS and Android do not keep separate hand-edited copies. There is no account, backend, or runtime download.

## Architecture

`scripts/aviation/fetch_sources.py` downloads pinned inputs into `data/aviation/snapshots/`. That command is only for a refresh. `scripts/aviation/build_catalog.py` reads those snapshots and writes the same JSON bytes to:

- `data/aviation/`
- `iOS/AviationCatalogCore/Sources/AviationCatalog/Resources/`
- `Android/app/src/main/assets/aviation/`

The iOS reader is the local Swift package `iOS/AviationCatalogCore`, linked from the TailTag app. The Android reader is `com.josh.tailtag.aviation`. Both check the manifest SHA-256 before they accept a file. A missing or hash-mismatched file throws. There is no substitute catalog.

Schema version and catalog version are separate. Schema version `1` describes the JSON shape. Catalog version `2026.10.23` is the content version. The bulk Wikidata and OurAirports snapshots are dated 2026-10-22. The four curated aircraft records were retrieved on 2026-10-23, so the content version moved to `2026.10.23`. A content refresh can keep schema version `1`.

## Files

| File                    | Contents                                                     |
| ----------------------- | ------------------------------------------------------------ |
| `operators.json`        | Airlines and other operators                                 |
| `manufacturers.json`    | Aircraft manufacturers referenced by a model or family       |
| `aircraft.json`         | Aircraft models and families                                 |
| `airports.json`         | Aerodromes from OurAirports                                  |
| `classifications.json`  | Role, operation, and operator-tag vocabulary                 |
| `catalog-manifest.json` | Versions, counts, file hashes, sources, and generation notes |

Each dataset file is one JSON object with `schemaVersion`, `dataset`, and `records`, except classifications, which uses `dimensions`. Files are UTF-8, key-sorted, compact, and end with a newline. The same inputs and this generator produce the same bytes. The snapshot date is supplied by `snapshot-meta.json`. The generator does not read the clock.

## Identifiers

Ids are `wikidata:Q…` or `ourairports:` plus the OurAirports numeric id. IATA and ICAO codes are optional attributes. They can be missing, shared, or reassigned, so they are not primary keys. Records are stored in ascending id order using Unicode code point order. `ourairports:10000` sorts before `ourairports:2434`.

## Operators

Required: `id`, `name`, `aliases`, `tags`, `sourceId`.

Optional: `iataCodes`, `icaoCodes`, `callsigns`, `countryCode`, `historical`, `dissolvedOn`.

An operator does not need an IATA code. Military and other operators are included when Wikidata records an ICAO designator or when the item is an air force. Tags are a list, not one exclusive category. Empty `tags` means the source type was not in the allow-list. `historical` is present only when Wikidata has a dissolution date. That date is copied into `dissolvedOn` when the month and day are real. Missing dissolution data is not converted into `active: true`.

## Aircraft

Required: `id`, `model`, `displayName`, `entryKind`, `aliases`, `sourceId`.

`entryKind` is `model`, `family`, or `unspecified`.

Optional: `manufacturer`, `manufacturerId`, `manufacturerNames`, `family`, `familyId`, `icaoTypeDesignators`, `iataEquipmentCodes`.

`manufacturerId` points at `manufacturers.json`. `familyId` points at another aircraft record and is never the record itself. Extra manufacturers stay in `manufacturerNames` and are searchable. The display name adds the manufacturer only when the model label does not already contain the manufacturer name, or the manufacturer's first word when that word is at least four characters.

`icaoTypeDesignators` and `iataEquipmentCodes` are part of the schema so a later verified source can fill them. This catalog leaves them empty. A short name such as `A359` on the Airbus A350-900 record is an alias. Searching for `A359` can find that alias. The record does not claim that `A359` is an ICAO type designator.

A model is not labeled passenger or cargo from its name.

## Airports

Required: `id`, `ident`, `name`, `type`, `latitude`, `longitude`, `scheduledService`, `aliases`, `sourceId`.

Optional: `iataCode`, `icaoCode`, `gpsCode`, `localCode`, `countryCode`, `municipality`.

`ident` is the OurAirports identifier. It is often an ICAO code and sometimes a local or regional code. `gpsCode` and `icaoCode` are stored only when the source has them. Airports without IATA or ICAO codes remain in the catalog. `type: closed` is a closed location. `scheduledService` copies the source yes/no value and is not a promise of current airline service.

## Classification vocabulary

Three dimensions, not one combined enum:

- Aircraft role: `civil`, `military`, `unknown`, `other`
- Operation type: `passenger`, `cargo`, `private`, `general-aviation`, `government`, `training`, `emergency-services`, `mixed`, `unknown`, `other`
- Operator tag: `commercial-airline`, `cargo-operator`, `military-operator`, `government-operator`, `private-operator`, `other`

Role and operation each include `unknown` and `other`. Operator tags include `other` as a vocabulary value for a future explicit choice. The importer does not assign `other` by default.

These values are not stored on a spotting entry in this change. A later entry-model change can persist a user's selection.

## Unknown and custom values

`AviationReference` has four cases:

- `catalog(id)` — a real record
- `unknown` — the user does not know the value
- `custom(text)` — text that did not match, kept as entered
- `absent` — no value

There is no catalog operator named "Other". Search that matches nothing returns an empty list. `resolve` then reports `unmatched` and the trimmed original text. It does not substitute the first hit. Blank input, after normalisation, is `blank`. When more than one record has the same exact code, `resolve` reports `ambiguous` and still returns the deterministic list. The exact-code count is computed before `limit` is applied, so a limit of 1 does not hide the collision or turn the first id into a chosen airline.

## Search

Normalisation, in order:

1. Unicode NFD, drop combining marks, casefold, then strip marks again.
2. Map hyphen-like characters, underscore, slash, and backslash to a space.
3. Collapse the Python `str.isspace()` whitespace set to a single space and trim.

Display strings are not modified. Casefold is locale-independent. Kotlin uses the same casefold exceptions as Python, including `ß` to `ss`. Swift uses `CFStringFold` with a nil locale.

A query whose compact form is shorter than 2 characters matches nothing. Ranking, best first:

1. Exact code, including the stable id
2. Exact name or alias
3. Code prefix of at least 2 characters
4. Name or alias prefix
5. Other substring

An ASCII alphanumeric compact query of length 3 or less does not use name substrings, so `row` does not match Heathrow. Code substrings require at least 4 characters. Stable ids are exact or prefix matches only. A digit query is not allowed to match an unrelated Wikidata id that merely contains those digits. Equal tiers sort by record id, not by file position and not by the user's locale. `limit` below 0 is an error. `limit` of 0 returns an empty list.

Operators are searched on name, aliases, IATA codes, ICAO codes, call signs, and id. Aircraft are searched on manufacturer names, family, model, display name, aliases, designator fields when present, and id. Airports are searched on name, municipality, aliases, IATA, ICAO, ident, GPS code, local code, and id.

Candidate lookup uses a two-character prefix bucket and, for queries of three or more characters, the first trigram. Stable ids are not inserted into the trigram buckets. Each candidate is still ranked with the tiers above, so the index does not change which records match. Historical and closed records stay in the same ranking. An unknown operational status is not treated as active, and historical records are not dropped to make a result look current.

## Loading

iOS: `AviationCatalogLoader.load()` reads the package resource bundle on a caller-chosen executor. `AviationCatalogRepository` is an actor. It caches a successful load and does not cache a failure.

Android: `AviationCatalogLoader.load(context)` reads `assets/aviation/`. `AviationCatalogRepository` caches a successful load only. Search builds its normalised keys and the prefix/trigram buckets once when the catalog object is created.

Both reject schema versions other than `1`.

## Regenerate, validate, and add records

```bash
python3 scripts/aviation/build_catalog.py
python3 scripts/aviation/validate_catalog.py
python3 scripts/aviation/tests/test_catalog.py
```

The validator checks JSON, schema version, unique sorted ids, required text, coordinates, manufacturer and family references, classification ids, source ids, manifest hashes and counts, license phrases for OurAirports and Wikidata, non-empty datasets, and byte-identical platform copies. It rejects an `openflights` source id.

To add a record, extend the pinned snapshot or the generator with a source that is already documented in `docs/aviation-data-sources.md`. Do not type an airline code that the source does not contain. Run the build twice if you need to confirm the bytes do not change, then run the validator.

## Cross-platform compatibility

Python, Swift, and Kotlin share `scripts/aviation/fixtures/ranking-cases.json` and `normalization-cases.json`. The same files are copied into the Swift and Android test resources. Search-case expectations are generated from the built catalog and checked again on both platforms.

Existing spotting fields `airline`, `aircraftType`, and `location` are unchanged. CloudKit, iCloud migration, Android `SharedPreferences`, and photo storage are unchanged.

## Size and performance

Catalog version `2026.10.23`, schema version `1`. Counts are also in `catalog-manifest.json`.

| Dataset | Records |
| --- | --- |
| Operators | 3,950 |
| Manufacturers | 812 |
| Aircraft | 4,735, of which 3,071 are models and 1,664 are families |
| Airports | 86,258 |
| Classification values | 20 |

Airport coverage is the full pinned OurAirports file: 42,820 small airports, 13,574 closed locations, 23,248 heliports, and the other source types. 77,207 airports have no IATA code. 1,198 operators have no IATA code. 251 operators are tagged `military-operator`. 1,973 operators have a Wikidata dissolution date and are marked historical. 813 IATA codes and 383 ICAO codes are shared by more than one operator. Those groups are kept.

Generated JSON is about 25.8 MB before it is copied into each app. `airports.json` is 23.7 MB. The same bytes are stored in `data/aviation/`, the iOS package resources, and the Android assets.

These timings are from this machine. They are not a comparison between iOS and Android, and they are not a claim about every device. The Swift numbers below are package tests on this Mac. The earlier full-catalog scan is the baseline from before the prefix/trigram buckets.

| Platform | Cold load | Warm load | Sample searches |
| --- | --- | --- | --- |
| Swift package test on this Mac, before buckets | 6.343 s | not measured | 0.888 s for YSSY, Qantas, A350, and Heathrow |
| Swift package test on this Mac, after buckets | 8.096 s | 0.000 s from `AviationCatalogRepository` after the first load | 0.021 s for the same four queries |
| iOS Simulator, iPhone 17 Pro Max, after buckets | 7.313 s | 0.000 s | 0.018 s for the same four queries |
| Android JVM test, before buckets | 1.215 s | not measured | 0.099 s for the same four queries |
| Android JVM test, after buckets | 2.076 s | repository cache returns the same object | 0.009 s for the same four queries |

On the iOS Simulator run, 75 queries (15 common queries, 5 passes) had p50 0.432 ms and p95 13.734 ms. The slowest first-pass query in that set was Heathrow at 17.428 ms. `B789` was 0.298 ms and `787-9` was 0.044 ms. The same battery on the Mac package test had p50 0.466 ms and p95 15.859 ms. The simulator process resident size after load was about 475 MB. That figure includes the test process, not only the catalog. Building the buckets during load is why cold load is slower than the earlier full scan. Repeated queries do not scan the full catalog. The sub-100 ms figure is this simulator run, not a promise for every device.

One operator IATA value, `LAC` on Lineas Aereas Canedo, is three characters. It is kept and counted as an anomaly. Dash-only code markers are omitted. `QF` is an exact IATA code on seven distinct operators, in id order: Jetconnect, National Jet Systems, QantasLink, Qantas Airways, Eastern Australia Airlines, Qantas Freight, and Sunstate Airlines. `resolve` reports `ambiguous`. It does not pick Qantas Airways because it is the best-known name. `QFA` is shared by Qantas Airways and Qantas Freight. The call sign `QANTAS` is also shared, including by Australian air Express, so a query of `Qantas` is exact-code ambiguous as well. `787-9` and `B789` match `wikidata:Q15111575`, Boeing 787-9. Those strings are Wikidata aliases. The record does not claim an ICAO type designator. `A359` matches the A350-900 record only as a short-name alias.

## Limitations

- ICAO type designators and IATA equipment codes are empty. `B788`, `B789`, `B78X`, and `B38M` are aliases, not asserted designators.
- Operator coverage is Wikidata items with an airline designator or an air-force type, not every private owner.
- Aircraft coverage is English Wikipedia models and families, plus four curated Wikidata items that have no English Wikipedia sitelink. It is not a complete variant list or a global fleet database.
- There is no catalog model whose English label is `Airbus A320`. The family is `Airbus A320 family`. A query for `A320` ranks the A320-211 and A320-232 models before that family.
- There is no catalog record labeled `Airbus A380-800`. The family record is `Airbus A380`.
- `A321neo`, `737-800`, and `777-300ER` are family records in this snapshot. `Cessna 172` matches the family `Cessna 172 Skyhawk`. `C-130` matches the family `Lockheed C-130 Hercules`.
- A missing dissolution date does not mean the operator is current. `historical` is set only when Wikidata has a dissolution date. `dissolvedOn` is set only when that date has a real month and day. Rheingau Air Service is historical and has no `dissolvedOn`.
- Closed airports remain, with `type` set to `closed`.
- Search uses an in-memory prefix and trigram index. It is not a full-text database.

## Later interface work

Searchable airline and model pickers, custom-entry persistence, collection filters, maps, and registration lookup are separate changes. They can call `searchOperators`, `searchAircraft`, `searchAirports`, the `byId` lookups, and `AviationReference` without a new catalog format.
