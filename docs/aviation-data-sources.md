# Aviation data sources

This note records where the offline catalog data comes from, what was imported, and why it can be redistributed inside TailTag. It does not add a license for the TailTag application. A data license applies only to the dataset it covers.

The bulk snapshot date is **2026-10-22**. Catalog content version **2026.10.23** also includes four aircraft records retrieved from Wikidata on 2026-10-23. The generated catalog contains 3,950 operators, 812 manufacturers, 4,735 aircraft records, 86,258 airports, and 20 classification values. Application builds do not download these sources.

## OurAirports

|                 |                                                                                                                                                                                            |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Source          | OurAirports airports download                                                                                                                                                              |
| URL             | https://ourairports.com/data/                                                                                                                                                              |
| Dictionary      | https://ourairports.com/help/data-dictionary.html                                                                                                                                          |
| Publisher       | OurAirports                                                                                                                                                                                |
| Pinned snapshot | GitHub `davidmegginson/ourairports-data` commit `b529623d2a0b09a9be78d37fc7a7a5e1e16e3451` (2026-10-16)                                                                                    |
| Files           | `airports.csv`, `LICENSE`                                                                                                                                                                  |
| License         | Public domain. The pinned repository `LICENSE` file uses the Unlicense text. OurAirports states that the downloadable data is released to the public domain: https://ourairports.com/data/ |

Imported columns: `id`, `ident`, `type`, `name`, `latitude_deg`, `longitude_deg`, `iso_country`, `municipality`, `scheduled_service`, `icao_code`, `iata_code`, `gps_code`, `local_code`, `keywords`.

Transformations:

- Stable id is `ourairports:` plus the source numeric `id`. `ident`, `gps_code`, and `icao_code` are stored separately because they are not always the same.
- Coordinates are rounded to 6 decimal places, half away from ties toward even. Original display names are preserved apart from collapsing source whitespace.
- Keywords become aliases. Empty and null markers such as `\N` are omitted.
- Codes that do not match the usual IATA or ICAO shape are kept and counted as anomalies. They are not rewritten.
- Every documented type in this snapshot is included: `large_airport`, `medium_airport`, `small_airport`, `heliport`, `seaplane_base`, `balloonport`, and `closed`. The data dictionary's `closed_airport` name does not appear in this file; the value in the file is `closed`. Closed locations stay `closed`. They are not relabeled as operational.
- The snapshot contains 86,258 airport rows. Rows with a scheduled-service value other than `yes` or `no` would be skipped. This snapshot has none.

Attribution: retain the OurAirports source entry in `catalog-manifest.json`. Public-domain data does not require a copyright notice, and the catalog still records the source.

OpenFlights airport data is not used.

## Wikidata

|             |                                                            |
| ----------- | ---------------------------------------------------------- |
| Source      | Wikidata Query Service                                     |
| URL         | https://query.wikidata.org/                                |
| Publisher   | Wikidata contributors                                      |
| Snapshot    | SPARQL results retrieved on 2026-10-22                     |
| License     | CC0 1.0 for structured data in the Wikidata main namespace |
| License URL | https://www.wikidata.org/wiki/Wikidata:Licensing           |

The fetch script checks English labels of the properties it uses and stops if a label does not match. Properties used:

| Property | Verified role                           |
| -------- | --------------------------------------- |
| P229     | IATA airline designator                 |
| P230     | ICAO airline designator                 |
| P432     | airline call sign                       |
| P1813    | short name                              |
| P176     | manufacturer                            |
| P297     | ISO 3166-1 alpha-2 code                 |
| P576     | dissolved, abolished or demolished date |
| P17      | country                                 |
| P31      | instance of                             |
| P279     | subclass of                             |
| P1448    | official name                           |

P1813 is a short name. It is stored as an alias. It is not treated as an ICAO aircraft type designator. No Wikidata property for ICAO aircraft type designators or IATA equipment codes was verified, so those catalog fields are left empty. P8305 and P9040 were inspected and are unrelated identifiers. They are not imported.

Operator scope:

- Items with an IATA airline designator (P229), an ICAO airline designator (P230), or `instance of` air force (Q61883).
- English label, English aliases, English official names, short names, call signs, a single ISO country code, and a dissolution date when present.
- Operator tags come only from an explicit English type-label list in `scripts/aviation/operator_tag_map.json`. Unmapped types stay untagged. An empty tag list means unclassified. It is not stored as `other`.
- A dissolution date marks `historical: true`. Absence of that date is not treated as proof that the operator is active. `active` is not set.
- Several codes on one item are all kept. The code is not the primary key.

Aircraft scope:

- English Wikipedia items that are an aircraft model (Q15056995) or an aircraft family (Q15056993).
- Four additional Wikidata items that have no English Wikipedia sitelink: Boeing 787-8 (Q57439868), Boeing 787-9 (Q15111575), Boeing 787-10 (Q57440517), and Boeing 737 MAX 8 (Q106340166). They were retrieved on 2026-10-23 into `wikidata-curated-aircraft.json` by `scripts/aviation/fetch_curated_aircraft.py`. The generator merges that file. The catalog JSON is not edited by hand.
- Only the English label, English aliases, P31, P279, and P176 are imported for those four items. Wikipedia article text and item descriptions are not copied. `B789` on the 787-9 record is an alias from Wikidata. It is not stored as an ICAO type designator.
- Items checked and not imported: Q18784360 is labeled Airbus A320 but its instance-of value is an aircraft classification, not an aircraft model or family. Q136076079 is labeled Boeing 737-800 and has no claims. There is no Wikidata item with the English label Airbus A380-800 in this import.
- Manufacturer links (P176) and family links (P279) are kept only when the target is also in this catalog. A generic parent such as "aircraft" does not become a family.
- Multiple manufacturers are searchable. The primary manufacturer is the one with the lowest numeric Wikidata id.
- The model string is not split into an invented variant.

Manufacturer records are the P176 targets of those aircraft, with English labels, English aliases, and a country code when exactly one ISO code is present.

Attribution: retain the Wikidata source entry. CC0 does not require attribution. The catalog records the source anyway.

Wikidata is not a complete or current airline timetable. Historical items remain when the source still describes them. Labels can change. This snapshot is one retrieval, not a live feed.

## Classification vocabulary

The role, operation, and operator-tag terms in `classifications.json` are written for this project. They are not copied from OurAirports or Wikidata. The vocabulary license in the manifest does not relicense TailTag application code.

Aircraft role and operation type are not inferred from a model. A civil airframe can fly cargo, and the same model family can be used for more than one operation.

## Sources that were not imported

| Source                                    | Reason                                                                                                                                                                                                                   |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| OpenFlights `airlines.dat` and plane data | Published under the Open Database License and Database Contents License. Those terms were not accepted for embedding. The airline file also includes historical rows and is not treated as a current operator directory. |
| ICAO Document 8643                        | Copyrighted. No unrestricted redistribution was verified. ICAO type designators are therefore omitted rather than guessed. Public access to a code list is not treated as permission to copy it in bulk. |
| FAA aircraft or registry extracts         | Not imported. Redistribution rights were not evaluated for a bulk copy. |
| IATA equipment codes                      | No redistributable dataset was verified. The fields exist in the schema and are empty in this catalog. |
| Subscription or scraped airline databases | Not used.                                                                                                                                                                                                                |

## How to refresh

Refreshing needs network access and is not part of an app build:

```bash
python3 scripts/aviation/fetch_sources.py --snapshot-date YYYY-MM-DD
python3 scripts/aviation/fetch_curated_aircraft.py
python3 scripts/aviation/build_catalog.py
python3 scripts/aviation/validate_catalog.py
```

`fetch_sources.py` reuses snapshot files that are already present. Delete a snapshot file to download it again. `fetch_curated_aircraft.py` rewrites only `wikidata-curated-aircraft.json`. The build checks SHA-256 values in `data/aviation/snapshots/snapshot-meta.json` and stops if an input changed without a matching meta file. Do not commit a newly downloaded file until its license is still the one recorded here.
