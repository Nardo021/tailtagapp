# Smart spotting entry

The add and edit screens search the bundled aviation catalog. The catalog itself is described in `docs/aviation-catalog.md`. This document covers the spotting form: what a selection means, what is stored, and what the form refuses to guess.

Both apps stay native. iOS uses SwiftUI. Android uses Jetpack Compose and Material 3. There is no shared UI binary. The selection rules are implemented twice and covered by tests on both sides:

- iOS: `iOS/SmartEntryCore` (`SmartEntry`), used by the TailTag app
- Android: `com.josh.tailtag.aviation.entry`

Search ranking stays in the catalog packages. The form does not rank results again.

## Architecture

The form is one shared editor on each platform. Add and edit both use it.

iOS:

- `SpottingEditorModel` holds registration, notes, date, photo flags, and the reference state
- `SpottingReferenceForm` draws the operator, manufacturer, aircraft, airport, and classification rows
- Each row pushes `AviationSearchPicker` or `ClassificationPicker` on the add/edit navigation stack. A second sheet inside the editor sheet was laid out off screen and then dismissed, so the picker is a pushed page instead.
- `AviationCatalogUIService` loads one catalog for the process and runs search off the main actor
- `CatalogQueryModel` debounces typing by 120 ms and drops an older search when a newer one was issued

Android:

- `SpottingEditorState` is the same editor state
- `SpottingReferenceEditor` draws the rows
- Pickers are full-screen dialogs, so they are not nested inside the editor's bottom sheet
- `TailTagViewModel` keeps one cached catalog and the load phase

A picker keeps a draft. Cancel, or leaving the page or dialog, restores the value that was open when the picker opened. The field changes only when the user confirms.

Search shows at most 20 rows at first. "Load more" asks for 20 more, up to 100. The list is lazy. A query whose compact form is shorter than two characters does not search. The picker says to enter at least two characters. That matches the catalog, which returns no matches for a one-character query.

## Selection types

A field is one of four kinds. This is the same shape as `AviationReference` in the catalog package.

| Kind | Meaning |
| --- | --- |
| Catalog | A stable catalog id, plus the name and a short detail captured when the user selected it |
| Custom | Text the user typed. Whitespace-only text is rejected |
| Unknown | The user marked the value unknown. The stored display text is `Unknown` |
| Absent | No value |

`suggestedFromPhoto` and `unavailableInCatalog` are session flags. They are not written to the store.

There is no catalog operator named "Other", and the form does not invent one.

## Operator ambiguity

The control is labeled "Airline / Operator". Results can be airlines, other operators, military operators, and historical operators. A row shows the name, the codes that exist (IATA, ICAO, call sign), and the country when the record has one. `Historical` appears only when the record's `historical` flag is true. A missing dissolution date is not shown as "Active".

The user must tap a row. The form never takes the first hit.

`QF` and `QFA` each match more than one operator, including when the search limit is 1. `AmbiguityPolicy.automaticCatalogID` returns nil whenever the resolution is ambiguous, so a limit of 1 cannot become a chosen airline. Shared call signs stay ambiguous the same way. Qantas Airways is stored only after the user selects that record, and the saved id is that record's id.

A sighting can omit a commercial operator. Catalog, custom text, explicit Unknown, and absent are all valid operator values. Private and military entries do not need an airline. A location still needs a real value: a catalog airport, custom text, or Unknown. An empty location does not save.

## Manufacturer and aircraft

Manufacturer and aircraft are separate optional fields. The user can search aircraft without choosing a manufacturer first.

Aircraft rows are labeled Model, Family, or Unspecified from `entryKind`. A family is not presented as a specific variant. An alias such as `A359` or `B789` is a search key. The row shows an ICAO line only when `icaoTypeDesignators` is non-empty. This catalog leaves that field empty, so those aliases are not shown as official designators.

If the selected aircraft has a `manufacturerId`, the manufacturer field is set from that link. Boeing 787-9 (`wikidata:Q15111575`) has no manufacturer id in this catalog, so selecting it does not fill in Boeing. The user can select Boeing separately.

Choosing a manufacturer can narrow the aircraft list to that manufacturer. The picker can switch back to the full catalog. The manufacturer check happens before the result limit, so a matching aircraft is not dropped because other manufacturers filled the window.

If the user later picks a manufacturer that is not the aircraft's linked manufacturer, the form asks what to do:

- Keep the aircraft and restore the linked manufacturer
- Clear the aircraft and apply the new manufacturer

It does not replace the aircraft silently. An aircraft with no manufacturer id does not raise that prompt.

## Airport and custom location

Airport search uses the catalog's airport index: name, municipality, IATA, ICAO, ident, GPS code, local code, and aliases. A row shows the name, one primary code, municipality and country when present, the airport type, and Closed when `type` is `closed`.

The primary code is the IATA code when the record has one. Otherwise it is the ICAO code, then the OurAirports ident. The label says which kind of code it is. Ident is not presented as IATA. Most airports in the catalog have no IATA code.

The location field also accepts custom text, such as a park, a street, or an airshow, and explicit Unknown. Opening a picker does not rewrite an existing location string. "Sydney Airport" stays as typed until the user selects a catalog airport.

## Role and operation

Two independent choices, from `classifications.json`:

- Aircraft role: `civil`, `military`, `unknown`, `other`
- Operation type: `passenger`, `cargo`, `private`, `general-aviation`, `government`, `training`, `emergency-services`, `mixed`, `unknown`, `other`

Civil and passenger are not alternatives in one menu. Operator tags on a catalog record are not this control. The form does not infer a role or an operation from the aircraft name or the operator name.

`other` can carry a short note. Choosing a different value clears that note. Empty role and operation are allowed, including on records that were saved before these fields existed.

## Persistence

Legacy columns stay the readable text:

- `airline` — operator display text
- `aircraftType` — aircraft display text
- `location` — airport or custom location text
- `registration`, `notes`, `timestamp`, and photos are unchanged

Optional metadata is stored beside that text. Empty values are omitted on Android and stored as null on iOS.

| Stored field | Contents |
| --- | --- |
| `operatorCatalogId`, `operatorSelectionKind` | Operator id and kind |
| `manufacturerName`, `manufacturerCatalogId`, `manufacturerSelectionKind` | Manufacturer snapshot |
| `aircraftCatalogId`, `aircraftSelectionKind`, `aircraftEntryKind` | Aircraft id, kind, and Model/Family snapshot |
| `airportCatalogId`, `locationSelectionKind` | Airport id and location kind |
| `aircraftRoleId`, `aircraftRoleNote` | Role id and the note used when the role is `other` |
| `operationTypeId`, `operationTypeNote` | Operation id and the note used when the operation is `other` |

`aircraftEntryKind` stores the display snapshot (`Model`, `Family`, or `Unspecified`), not a second id.

iOS writes these as optional SwiftData strings on `SpottingRecord`, with defaults of nil. The CloudKit copy path copies them when it copies a record. The older Core Data entity does not have the columns. A record migrated from Core Data keeps its airline, location, and aircraft type text and leaves the new fields nil. That is intentional. This branch does not redeploy a CloudKit schema. A simulator build does not show that a remote schema accepted the new attributes.

Android keeps the existing JSON file. New keys are written only when they have text. A JSON object from before this change still decodes. Photo paths are unchanged. The store is still SharedPreferences plus private photo files.

If a saved id is no longer in the loaded catalog, the form keeps the saved text and can mark the row as missing from the current catalog. It does not clear the field. The user replaces it by choosing another value.

## Legacy records

Text saved without a selection kind is legacy. It is shown as custom text and `isLegacy` stays true until the user changes that field. Saving the entry without touching it does not invent a catalog id or a selection kind. The original characters are kept, including a name that does not match any catalog record.

A search hit that looks similar is not applied on open.

## Photo recognition

On-device registration and operator text still run. A result is a suggestion.

It is applied only when confidence is above 0.6, the registration or operator field is still empty, and the user has not edited that field. Operator text becomes custom text with `suggestedFromPhoto`. It is never a catalog id, so `QF` does not become Qantas Airways. An edit screen marks registration and operator as already edited, so a later detection does not replace the saved values. Detection does not fill the aircraft model and does not save the entry.

## Offline loading

The catalog is read from the app bundle or Android assets. The form does not download it.

iOS loads through `AviationCatalogRepository`, an actor that caches a successful load and does not cache a failure. Android uses the same cache rule on `AviationCatalogRepository`. The editor stays usable while that load runs. Pickers show a loading state. After a failure they show the error and a retry action, and custom text can still be entered.

Opening a second picker uses the cached catalog. Typing does not decode the JSON again.

Measured on this development Mac (Apple Silicon, not a phone):

- iOS `swift test` cold load of the bundled catalog: 10.275 seconds, printed as `SMART_ENTRY_COLD_LOAD_SECONDS` during the first catalog-backed suite
- iOS warm searches after that load, `Qantas`, `787-9`, and `Sydney` at limit 20: 0.00223 seconds
- Android JVM cold load, file read plus index build, across the four catalog tests: 2.198, 1.929, 2.041, and 1.992 seconds
- Android warm run of the same three searches, after that test's load: 0.00049 seconds

These are package and JVM timings. They are not a device budget, and they are not the iOS simulator's first launch of the app.

## Failure recovery

A failed load sets the phase to failed and leaves the previous catalog unset. Retry starts another load only from that failed phase. A successful catalog is kept.

Custom operator, aircraft, and location text can be saved while the catalog is unavailable. The form does not claim that a catalog record was chosen. A search that finishes after the user has moved on is ignored when its token is no longer current, and dismissing a picker cancels its query task without writing the draft.

## Tests

`swift test --package-path iOS/SmartEntryCore` covers selection round-trips, cancel, catalog versus custom, legacy text, missing ids, manufacturer conflicts, classification pairs, photo suggestions, load and retry state, stale search tokens, and the bundled catalog (`QF` / `QFA`, aircraft aliases, airports, closed fields). One in-memory SwiftData probe stores the optional metadata on a test model with the same fields. It is not the app's `SpottingRecord`, and it does not talk to CloudKit.

`TailTagTests` uses the app's `SpottingRecord` and `PhotoRecord` in an in-memory store. It checks a legacy entry (text, photos, timestamp) and a structured entry (catalog ids, custom location, classifications, save/reload, then edit/reload).

`TailTagUITests` drives the iPhone 17 Pro Max simulator: onboarding, Add Aircraft, ambiguous `QF` resolved to Qantas Airways, custom location "Nearby park", Civil and Passenger, save, reopen, edit the note, relaunch, and read the saved values back.

Android `./gradlew test` covers the same selection and catalog cases plus JSON load and save of legacy objects and the new keys. A manufacturer-filter regression checks that a match outside the unfiltered result window is still returned. Instrumented UI tests were not run. There is no Android emulator session in this environment.

`python3 scripts/aviation/validate_catalog.py` and `python3 scripts/aviation/tests/test_catalog.py` were run against the existing catalog. This change does not edit the catalog files.

The iOS app scheme builds `TailTagTests` and `TailTagUITests` with the app.

## Known limitations

- Boeing 787-9 does not carry a manufacturer id here, so the manufacturer field stays empty until the user selects one.
- Remote CloudKit schema deployment and sync are not verified.
- The iOS simulator UI test covered add, reopen, edit, `QF`, custom location, and the two classifications. Android instrumentation was not run.
- When the data-integrity work merges, its migration and save-result path must keep these optional fields. This branch does not include that work.
