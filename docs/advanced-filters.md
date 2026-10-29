# Advanced spotting filters

Advanced Filters narrows the sightings already saved on the device. It does not search the global aviation catalog as a collection of sightings. Catalog search remains the way to pick a reference while adding or editing a spotting.

Nothing in this feature writes a spotting record. There is no new field on `SpottingRecord`, no migration, and no change to the Android `SharedPreferences` JSON. Filter state lives in memory for the current app session.

Both apps use the same rules. The implementations are separate:

- iOS: `SpottingFilterState` and `SpottingFilterEngine` in `iOS/SmartEntryCore` (`SmartEntry`). The TailTag app calls them from Search.
- Android: `com.josh.tailtag.filters` and `com.josh.tailtag.filters.ui`.

## Filter dimensions

A filter can constrain any of these, together:

| Dimension | What it matches |
| --- | --- |
| Operator | Catalog operator id, custom operator text, Unknown, or no operator |
| Manufacturer | Saved manufacturer id, a verified aircraft manufacturer link, custom text, Unknown, or no manufacturer |
| Aircraft | An exact model id, a family id, custom text, Unknown, or no aircraft |
| Aircraft role | Civil, Military, Unknown, or Other |
| Operation type | Passenger, Cargo, Private, General Aviation, Government, Training, Emergency Services, Mixed, Unknown, or Other |
| Airport / location | Catalog airport id, custom location text, Unknown, or no location |
| Registration | A case-insensitive prefix of the saved registration |
| Sighting date | A start day, an end day, or both, using the sighting timestamp |

Role and operation type stay independent. Civil + Cargo, Military + Cargo, and Civil + Private are all valid. An unset classification is not Unknown, and an airline name does not imply Civil.

## OR and AND

Values inside one dimension combine with OR. Different dimensions combine with AND. Free-text search is another AND. An empty dimension does not restrict results.

Operator Qantas or Jetstar, role Civil, and operation Passenger means:

`(Qantas OR Jetstar) AND Civil AND Passenger`

The pipeline is:

1. Saved entries
2. Free-text search
3. Structured filters
4. Sort

A sighting that matches two selected values in the same dimension appears once. Sort order is unchanged until the user picks another sort. The default remains newest sighting first. Ties keep the original order.

## Filter state

`SpottingFilterState` holds the selected operators, manufacturers, aircraft, roles, operation types, locations, registration query, and date range. It can insert or remove a value, clear one dimension, reset everything, count active conditions, and build chip labels.

Catalog selections compare by stable id. The display label is not part of equality. Custom text compares by a trimmed, whitespace-collapsed, case-insensitive name. Duplicate selections collapse to one.

iOS keeps this state on `ContentView`, so leaving Search for another tab and coming back keeps it. Android keeps it on `TailTagViewModel`, so a tab change or rotation keeps it. It is not written to spotting storage or to iCloud.

Cancel on the filter screen drops the draft. Apply replaces the session state.

## Catalog ID matching

A catalog filter matches a saved catalog id exactly. `QF` and `QFA` are not expanded to every operator that shares a code. A stored id still matches after that catalog record is removed from a later catalog.

A legacy or custom record with no catalog id can match a catalog filter only when all of these are true:

- The saved value is custom or legacy text, not a catalog id.
- The normalized display name equals the filter label.
- That display name occurs once in the loaded catalog.

Codes and aliases are not used. If two catalog records share a display name, legacy text does not attach to either id. If the catalog is unavailable, this name fallback is skipped. Stored ids still match.

A custom filter does not include a catalog record that happens to use the same words.

## Manufacturer matching

For each sighting, the manufacturer used for filtering is resolved in this order:

1. The saved manufacturer catalog id, when the field is a catalog selection.
2. Unknown, when the user marked the manufacturer unknown.
3. The saved custom or legacy manufacturer text, when it is non-empty.
4. The aircraft record's `manufacturerId`, when the saved manufacturer is absent, the aircraft is a catalog selection, and that id is non-blank.
5. Absent.

A missing `manufacturerId` is not filled in from the aircraft name. The bundled Boeing 787-9 record has no manufacturer id, so it does not match a Boeing filter unless the user saved Boeing on that sighting. A saved manufacturer id wins over the aircraft link. A model that does carry a manufacturer id, such as the catalog's Boeing 787-8, matches that manufacturer when the saved manufacturer is absent.

Explicit absent and an empty legacy manufacturer look the same once they have been stored. When the aircraft has a verified manufacturer id, that link is used.

## Model and family matching

Exact model and family are different filters. Family is not stored on the spotting record. It is read from the catalog at query time and never written back.

An exact model filter matches that aircraft catalog id. A family filter matches either of these:

- The saved aircraft id is the family id.
- The catalog aircraft's `familyId` equals the family id.

There is no substring match. A model with no `familyId` is not assigned a family. A missing catalog cannot verify a child relationship, so only an explicit family id on the sighting matches. Custom and legacy aircraft text match a custom aircraft filter, or a family filter when the text equals one unique family display name.

## Legacy data

Older sightings may have only registration, airline, aircraft type, location, and timestamp. Filtering does not add catalog ids, rewrite text, or treat missing metadata as Unknown.

A legacy sighting is found by its original text: a custom filter for that text, the registration prefix, the date, or free-text search. A filter that needs an id or a verified catalog relationship does not match it by guessing. Ambiguous codes such as `QF` do not become Qantas Airways.

## Unknown and absent

These are different:

| Value | Meaning |
| --- | --- |
| Catalog id | The user selected that reference record |
| Custom text | The user typed a value that is not a catalog record |
| Unknown | The user explicitly marked the field unknown |
| Absent | The field was left unspecified |

Other is also different from Unknown. An Other filter with no note matches every Other value. An Other filter with a note matches that note only. Unset role or operation matches neither Unknown nor Other.

## Custom locations

A catalog airport filter uses the saved airport id. IATA, ICAO, and OurAirports ident are not substituted for each other. A sighting with no airport id is not given one.

Custom text such as "Nearby park" is a location filter of its own. Options for operator, manufacturer, aircraft, and location are built from the saved collection, plus Unknown and Absent. The small fixed role and operation lists are always shown. Searching the full catalog is a separate action on the filter screen and uses the existing catalog search, limited to a page of results. It does not scan every operator while drawing each row.

## Date range

The range uses the sighting timestamp and the device calendar that is displaying the date. Tests use UTC. Comparison is year, month, and day. It does not compare formatted strings.

- No dates: no date restriction.
- Start only: that day and later.
- End only: that day and earlier. The end day includes sightings for the whole calendar day.
- Both: inclusive on both days.

An end day before the start day matches nothing. The screen shows that the end date is too early and disables Apply. The two dates are not swapped. Saved timestamps are not changed.

## Free-text search

The existing search field stays separate from the registration filter. Free text is a case-insensitive substring over registration, operator, location, aircraft, manufacturer, and role or operation labels and notes. Empty or whitespace-only text does not filter. Notes and photos are not part of the free-text fields. The registration filter is a prefix of the registration only, with case folding and spaces removed, hyphens kept.

## Sorting

`SortOption` is unchanged. Filtering runs first, then the selected sort. Clearing filters restores the wider set and does not delete sightings. The selected sort stays selected.

## iOS UI

Search keeps the existing tab. On iOS 26 the search tab hides the navigation bar, so Filters and Sort sit in the search content instead of only in the toolbar. Active filters appear as removable chips. The result line reads "N of M sightings" while a filter or search text is active, and "N sightings" otherwise.

Filters opens one sheet with its own `NavigationStack`. Catalog search replaces the form inside that stack. It is not a second sheet. Apply commits the draft. Cancel discards it. Reset all clears the draft. Each section can clear itself. An invalid date range disables Apply.

Empty collection, no matching sightings, and an unavailable catalog use different messages. The catalog message says family and manufacturer links may not resolve. Saved ids still match.

## Android UI

Search is still the existing Compose screen. Filters opens one full-screen dialog. Catalog search and the date picker stay inside that dialog so a second dialog is not required. Apply, Cancel, chips, and Reset all follow the same rules as iOS. The dialog does not dismiss when the user taps outside it, so a draft is not dropped by accident.

## Performance

The catalog is prepared once into id and name maps. Filtering does not decode the catalog again, rebuild the search index, or load photos. Results are not cached across edits.

These are package and JVM timings for synthetic collections, not a device budget. Photo bytes are not included.

iOS `swift test` on this machine, debug arm64:

| Records | Single | Multi | Text + filters | Family lookup | Reset | Sort after filter |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 100 | 0.19 ms | 0.24 ms | 1.96 ms | 0.63 ms | 0.37 ms | 0.24 ms |
| 1,000 | 1.46 ms | 2.11 ms | 19.73 ms | 2.90 ms | 3.80 ms | 3.57 ms |
| 10,000 | 14.18 ms | 21.76 ms | 199.37 ms | 28.66 ms | 37.43 ms | 34.38 ms |

The 10,000-record case with 10 operator filters and with 3,000 operator filters took 21.98 ms and 21.76 ms.

Android `./gradlew test` on this machine, latest JVM run:

| Records | Single | Multi | Text + filters | Family lookup | Reset | Sort after filter |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 100 | 0.15 ms | 0.22 ms | 1.22 ms | 0.25 ms | 0.31 ms | 0.11 ms |
| 1,000 | 0.44 ms | 0.64 ms | 5.33 ms | 0.52 ms | 0.55 ms | 0.65 ms |
| 10,000 | 2.49 ms | 3.74 ms | 24.98 ms | 2.89 ms | 3.51 ms | 2.88 ms |

An earlier JVM run of the same test was slower and less even at 10,000 records (single 23.83 ms, text 26.17 ms). Both runs stayed under five seconds. The 10-versus-3,000 operator comparison on that later run was 1.62 ms and 3.74 ms.

## Automated tests

`swift test --package-path iOS/SmartEntryCore` — 56 tests, 0 failures. 35 of those are `SpottingFilterTests`: empty filters, OR and AND, manufacturer and aircraft, model versus family, airport versus custom location, registration prefix, date boundaries, text plus filters, sort after filter, reset, chip removal, duplicates, no matches, empty collection, missing catalog metadata, missing catalog resources, unknown versus absent, Other versus Unknown, legacy text, a catalog id that no longer exists, ambiguous codes, identical display names, and session retention. Family cases cover Boeing 787-9, A350-900, Cessna 172, C-130, a model with no family, and a custom type. Filtering does not mutate the entry.

`swift test --package-path iOS/AviationCatalogCore` — 6 tests, 0 failures.

`TailTagTests` — 2 tests, 0 failures, on the same simulator destination. The in-memory store is created with `cloudKitDatabase: .none`. Without that, the current SDK rejects the store because a relationship is not optional. The app's CloudKit container is unchanged. The tests cover a legacy entry and a structured save, reload, and edit.

`TailTagUITests/AdvancedFiltersUITests` on the iPhone 17 Pro Max simulator (iOS 26.1, `E9DED661-DF9A-4C29-8FE5-C916ACFFE86B`) — 1 test, passed. It seeds three sightings, applies Civil and Passenger, adds Qantas or Jetstar, removes the Jetstar chip, leaves Search and returns, clears filters, and sorts by registration.

`TailTagUITests/SmartEntryUITests` on the same simulator — 1 test, passed. Onboarding, ambiguous `QF`, a custom location, Civil and Passenger, save, reopen, and edit still work.

Android `./gradlew test` — 56 tests, 0 failures, 0 skipped. 35 are `SpottingFilterTest` and cover the same cases. `./gradlew assembleDebug` succeeded.

`python3 scripts/aviation/validate_catalog.py` — ok. `python3 -m unittest scripts/aviation/tests/test_catalog.py` — 11 tests, ok. The catalog files were not regenerated.

Android instrumentation was not run. No emulator or device was connected.

## Manual tests

The iOS UI test covers the search flow on a simulator. These were not repeated by hand after that run: light and dark appearance, a VoiceOver pass, and a rotation pass on Android. The Android filter screen was compiled and covered by unit tests. It was not opened on a device.

## Known limitations

- Filters last for the session only. Force-quit clears them.
- iOS sort state lives on the Search view. Android sort state lives with the tab host. A process restart resets sort to newest first.
- A missing catalog skips family links and unique-name fallback. Stored ids still match.
- Explicit absent and empty legacy manufacturer text are the same after save, so a verified aircraft manufacturer id is used for both.
- Boeing 787-9 has no manufacturer id in this catalog, so it is not treated as Boeing unless the sighting saved a manufacturer.
- A model with no `familyId` is not placed in a family.
- Identical catalog display names do not claim legacy text.
- The in-memory iOS persistence tests set `cloudKitDatabase: .none`. The automatic CloudKit setting refuses that store because a relationship is not optional. The app container is unchanged.

## Future merge considerations

This branch is based on Smart Entry (`feat/smart-entry`, `8c53e5720d722178e00bbff4c3f9627645805059`). Data Integrity and the aviation catalog branch are still open and unmerged. This feature does not include those diffs.

When they merge, keep filtering read-only. Reconcile the final `SpottingRecord` and Android entry shape with `FilterableSpotting`, and keep the rule that a filter pass does not write family or manufacturer ids back onto old records. Do not treat that reconciliation as done here.
