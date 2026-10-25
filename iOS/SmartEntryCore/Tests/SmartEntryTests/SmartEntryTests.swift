import AviationCatalog
import SwiftData
import XCTest
@testable import SmartEntry

final class SelectionStateTests: XCTestCase {
    func testCatalogCustomUnknownAndAbsentRoundTrip() {
        let catalog = AviationSelection.catalog(id: "wikidata:Q32491", displayText: "Qantas Airways", detail: "AU")
        let custom = AviationSelection.custom(from: "  Some small charter company  ")
        let unknown = AviationSelection.unknown()
        let absent = AviationSelection.absent

        XCTAssertEqual(PersistedAviationField(selection: catalog).selection().catalogId, "wikidata:Q32491")
        XCTAssertEqual(custom?.displayText, "Some small charter company")
        XCTAssertEqual(PersistedAviationField(selection: unknown).kind, "unknown")
        XCTAssertEqual(PersistedAviationField(selection: absent).kind, "absent")
        XCTAssertNil(PersistedAviationField(selection: absent).catalogId)
        XCTAssertNil(AviationSelection.custom(from: "   "))
    }

    func testLegacyTextIsNotPromotedToACatalogRecord() {
        let legacy = AviationSelection.legacy(text: "Some small charter company")
        let stored = PersistedAviationField(selection: legacy)
        XCTAssertNil(stored.kind)
        XCTAssertNil(stored.catalogId)
        XCTAssertEqual(stored.text, "Some small charter company")
        let restored = stored.selection()
        XCTAssertTrue(restored.isLegacy)
        XCTAssertEqual(restored.kind, .custom)
        XCTAssertFalse(restored.hasCatalogIdentity)
    }

    func testCancelKeepsTheCommittedValue() {
        let committed = AviationSelection.catalog(id: "wikidata:Q1", displayText: "Qantas Airways")
        var session = PickerSession(committed: committed)
        session.draft = .unknown()
        XCTAssertEqual(session.cancel(), committed)
        XCTAssertEqual(session.confirm(), .unknown())
    }

    func testSwitchingBetweenCatalogAndCustom() {
        var selection = AviationSelection.catalog(id: "wikidata:Q1", displayText: "Qantas Airways")
        selection = AviationSelection.custom(from: "Local club")!
        XCTAssertEqual(selection.kind, .custom)
        XCTAssertNil(selection.catalogId)
        selection = .catalog(id: "wikidata:Q2", displayText: "Jetstar")
        XCTAssertEqual(selection.catalogId, "wikidata:Q2")
        selection = .absent
        XCTAssertEqual(PersistedAviationField(selection: selection).text, "")
    }

    func testMissingCatalogIdKeepsTheSavedLabel() {
        let saved = AviationSelection.catalog(id: "wikidata:Qmissing", displayText: "Old name")
        XCTAssertTrue(saved.reconciled(existsInCatalog: false).unavailableInCatalog)
        XCTAssertEqual(saved.reconciled(existsInCatalog: false).displayText, "Old name")
        XCTAssertFalse(saved.reconciled(existsInCatalog: nil).unavailableInCatalog)
        XCTAssertFalse(saved.reconciled(existsInCatalog: true).unavailableInCatalog)
    }

    func testReferenceRoundTripPreservesLegacyAndStructuredFields() throws {
        let original = SpottingReferenceState.legacy(
            airline: "Some small charter company",
            location: "Nearby park",
            aircraftType: "Unknown aircraft"
        )
        let stored = original.forStorage()
        XCTAssertNil(stored.operatorField.kind)
        XCTAssertEqual(stored.operatorField.text, "Some small charter company")
        XCTAssertEqual(stored.locationField.text, "Nearby park")
        XCTAssertEqual(stored.aircraftField.text, "Unknown aircraft")
        XCTAssertNil(stored.classification.roleId)

        let selected = SpottingReferenceState(
            operatorField: .catalog(id: "op-1", displayText: "Qantas Airways"),
            manufacturerField: .catalog(id: "m-1", displayText: "Boeing"),
            aircraftField: .catalog(id: "a-1", displayText: "Boeing 787-9", detail: "Model"),
            locationField: .catalog(id: "p-1", displayText: "Sydney Airport (SYD)"),
            classification: ClassificationChoice(
                roleId: "other",
                roleNote: "  Survey  ",
                operationTypeId: "cargo",
                operationTypeNote: "should drop"
            )
        )
        let encoded = try JSONEncoder().encode(selected.forStorage())
        let decoded = try JSONDecoder().decode(PersistedSpottingReference.self, from: encoded).restored()
        XCTAssertEqual(decoded.operatorField.catalogId, "op-1")
        XCTAssertEqual(decoded.aircraftField.detail, "Model")
        XCTAssertEqual(decoded.classification.roleId, "other")
        XCTAssertEqual(decoded.classification.roleNote, "Survey")
        XCTAssertEqual(decoded.classification.operationTypeId, "cargo")
        XCTAssertNil(decoded.classification.operationTypeNote)
    }

    func testEditingWithoutTouchingLegacyFieldsDoesNotInventIds() {
        let reference = SpottingReferenceState.legacy(
            airline: "Some small charter company",
            location: "Nearby park",
            aircraftType: "Unknown aircraft"
        )
        let stored = reference.forStorage()
        XCTAssertNil(stored.operatorField.catalogId)
        XCTAssertNil(stored.aircraftField.catalogId)
        XCTAssertNil(stored.locationField.catalogId)
        XCTAssertEqual(stored.restored().storedOperatorText, "Some small charter company")
        XCTAssertEqual(stored.restored().storedLocationText, "Nearby park")
        XCTAssertEqual(stored.restored().storedAircraftText, "Unknown aircraft")
    }

    func testClassificationPairsStayIndependent() {
        let pairs: [(String, String)] = [
            ("civil", "passenger"),
            ("civil", "cargo"),
            ("civil", "private"),
            ("military", "cargo"),
            ("military", "training"),
            ("unknown", "unknown"),
        ]
        for pair in pairs {
            let choice = ClassificationChoice(roleId: pair.0, operationTypeId: pair.1).normalized()
            XCTAssertEqual(choice.roleId, pair.0)
            XCTAssertEqual(choice.operationTypeId, pair.1)
        }
        XCTAssertEqual(ClassificationCopy.roleOrder.count, 4)
        XCTAssertEqual(ClassificationCopy.operationOrder.count, 10)
        XCTAssertFalse(ClassificationCopy.roleOrder.contains("passenger"))
        XCTAssertFalse(ClassificationCopy.operationOrder.contains("military"))
    }

    func testValidationAcceptsPrivateAndMilitaryWithoutAnAirline() {
        var reference = SpottingReferenceState.legacy(airline: "", location: "Park beside the fence", aircraftType: "Cessna 172")
        reference.operatorField = .absent
        reference.locationField = .custom(from: "Park beside the fence")!
        reference.aircraftField = .custom(from: "Cessna 172")!
        reference.classification = ClassificationChoice(roleId: "civil", operationTypeId: "private")
        XCTAssertTrue(EntryRules.canSave(registration: "VH-TEST", photoCount: 1, reference: reference))

        reference.operatorField = .unknown()
        reference.classification.roleId = "military"
        reference.classification.operationTypeId = "training"
        XCTAssertTrue(EntryRules.canSave(registration: "A97-001", photoCount: 1, reference: reference))

        reference.operatorField = .custom(from: "   ") ?? .absent
        reference.operatorField = AviationSelection(kind: .custom, displayText: "   ")
        XCTAssertFalse(EntryRules.operatorIsValid(reference.operatorField))
        reference.locationField = .absent
        XCTAssertFalse(EntryRules.locationIsValid(reference.locationField))
        reference.locationField = .unknown()
        XCTAssertTrue(EntryRules.locationIsValid(reference.locationField))
    }

    func testManufacturerChangeRequiresADecision() {
        let aircraft = AviationSelection.catalog(id: "a-787", displayText: "Boeing 787-9", detail: "Model")
        let boeing = AviationSelection.catalog(id: "m-boeing", displayText: "Boeing")
        let airbus = AviationSelection.catalog(id: "m-airbus", displayText: "Airbus")
        let applied = EntryRulesAircraft.applyingAircraft(aircraft, currentManufacturer: .absent, linkedManufacturer: boeing)
        XCTAssertEqual(applied.manufacturer.catalogId, "m-boeing")
        XCTAssertEqual(applied.aircraft.catalogId, "a-787")

        let change = EntryRulesAircraft.proposeManufacturerChange(
            aircraft: aircraft,
            aircraftManufacturerId: "m-boeing",
            aircraftManufacturerName: "Boeing",
            currentManufacturer: boeing,
            proposed: airbus
        )
        guard case .confirm(let conflict, let proposed, let restore) = change else {
            return XCTFail("Expected a confirmation")
        }
        XCTAssertEqual(conflict.aircraftId, "a-787")
        XCTAssertEqual(proposed.catalogId, "m-airbus")
        let kept = EntryRulesAircraft.resolveConflict(keepAircraft: true, proposed: proposed, restore: restore)
        XCTAssertNil(kept.aircraft)
        XCTAssertEqual(kept.manufacturer.catalogId, "m-boeing")
        let cleared = EntryRulesAircraft.resolveConflict(keepAircraft: false, proposed: proposed, restore: restore)
        XCTAssertEqual(cleared.aircraft, .absent)
        XCTAssertEqual(cleared.manufacturer.catalogId, "m-airbus")

        let noLink = EntryRulesAircraft.proposeManufacturerChange(
            aircraft: AviationSelection.catalog(id: "a-x", displayText: "Homebuilt", detail: "Model"),
            aircraftManufacturerId: nil,
            aircraftManufacturerName: nil,
            currentManufacturer: .absent,
            proposed: airbus
        )
        guard case .apply(let appliedManufacturer) = noLink else {
            return XCTFail("Expected the manufacturer change to apply")
        }
        XCTAssertEqual(appliedManufacturer.catalogId, "m-airbus")
    }

    func testPhotoSuggestionDoesNotSelectOrOverwrite() {
        let suggestion = PhotoTextSuggestion(registration: "VH-OQH", operatorText: "QF", confidence: 0.91)
        let empty = OperatorFieldState(selection: .absent, userEdited: false)
        let filled = PhotoSuggestions.applyOperator(field: empty, suggestion: suggestion)
        XCTAssertEqual(filled.selection.kind, .custom)
        XCTAssertEqual(filled.selection.displayText, "QF")
        XCTAssertNil(filled.selection.catalogId)
        XCTAssertTrue(filled.selection.suggestedFromPhoto)
        XCTAssertNil(AmbiguityPolicy.automaticCatalogID(matchCount: 1, exactCodeCount: 7))

        let manual = OperatorFieldState(
            selection: .catalog(id: "wikidata:Q32491", displayText: "Qantas Airways"),
            userEdited: true
        )
        XCTAssertEqual(PhotoSuggestions.applyOperator(field: manual, suggestion: suggestion).selection, manual.selection)

        let custom = OperatorFieldState(selection: .custom(from: "Local club")!, userEdited: true)
        XCTAssertEqual(PhotoSuggestions.applyOperator(field: custom, suggestion: suggestion).selection.displayText, "Local club")

        let weak = PhotoTextSuggestion(registration: "VH-OQH", operatorText: "QF", confidence: 0.4)
        XCTAssertEqual(PhotoSuggestions.applyOperator(field: empty, suggestion: weak).selection.kind, .absent)
        XCTAssertEqual(PhotoSuggestions.applyRegistration(current: "", userEdited: false, suggestion: suggestion), "VH-OQH")
        XCTAssertEqual(PhotoSuggestions.applyRegistration(current: "VH-OLD", userEdited: false, suggestion: suggestion), "VH-OLD")
        XCTAssertEqual(PhotoSuggestions.applyRegistration(current: "", userEdited: true, suggestion: suggestion), "")
    }

    func testAircraftChoiceDoesNotInferClassificationOrInventDesignators() {
        let choice = ClassificationChoice(roleId: "military", operationTypeId: "cargo")
        XCTAssertEqual(classificationUnchanged(byAircraftSelection: choice), choice)
        XCTAssertNil(officialDesignatorText([]))
        XCTAssertEqual(officialDesignatorText(["B789"]), "B789")
        XCTAssertEqual(aircraftKindLabel("family"), "Family")
        XCTAssertEqual(aircraftKindLabel("model"), "Model")
        XCTAssertNotEqual(aircraftKindLabel("family"), "Model")
    }

    func testCatalogLoadRetryAndShortQueries() {
        var state = CatalogLoadState()
        XCTAssertTrue(state.begin())
        XCTAssertFalse(state.begin())
        state.fail()
        XCTAssertEqual(state.phase, .failed)
        XCTAssertTrue(state.retry())
        XCTAssertEqual(state.phase, .loading)
        state.succeed()
        XCTAssertFalse(state.retry())
        XCTAssertEqual(catalogQueryGuidance(""), .prompt)
        XCTAssertEqual(catalogQueryGuidance("Q"), .tooShort)
        XCTAssertEqual(catalogQueryGuidance("QF"), .ready)
        XCTAssertEqual(catalogQueryGuidance("A-"), .tooShort)
    }

    func testLoadFailureStillAllowsCustomEntry() {
        var state = CatalogLoadState()
        _ = state.begin()
        state.fail()
        var reference = SpottingReferenceState()
        reference.operatorField = .custom(from: "Unlisted operator")!
        reference.aircraftField = .custom(from: "Unlisted type")!
        reference.locationField = .custom(from: "Street outside the airfield")!
        reference.classification = ClassificationChoice(roleId: "civil", operationTypeId: "other", operationTypeNote: "Banner tow")
        XCTAssertEqual(state.phase, .failed)
        XCTAssertTrue(EntryRules.canSave(registration: "N123", photoCount: 2, reference: reference))
        XCTAssertEqual(reference.forStorage().classification.operationTypeNote, "Banner tow")
    }
}

final class SearchCoordinationTests: XCTestCase {
    func testOutOfOrderSearchResultsAreDropped() async {
        let gate = LatestQueryGate()
        let first = await gate.issue()
        let second = await gate.issue()
        let stale = await gate.accept(token: first, value: ["first"])
        let fresh = await gate.accept(token: second, value: ["second"])
        XCTAssertNil(stale)
        XCTAssertEqual(fresh, ["second"])
        let ignored = await gate.accept(token: first, value: "late")
        XCTAssertNil(ignored)
    }

    func testDismissalWhileLoadingDoesNotChangeTheSelection() {
        let committed = AviationSelection.legacy(text: "Nearby park")
        let session = PickerSession(committed: committed, draft: AviationSelection.catalog(id: "ourairports:1", displayText: "Sydney"))
        var loading = CatalogLoadState()
        XCTAssertTrue(loading.begin())
        XCTAssertEqual(session.cancel(), committed)
        XCTAssertEqual(loading.phase, .loading)
    }
}

final class CatalogEntryBehaviorTests: XCTestCase {
    private static let catalog: AviationCatalog = {
        let clock = ContinuousClock()
        let started = clock.now
        do {
            let loaded = try AviationCatalogLoader.load()
            print("SMART_ENTRY_COLD_LOAD_SECONDS \(started.duration(to: clock.now))")
            return loaded
        } catch {
            fatalError("Catalog failed to load: \(error)")
        }
    }()

    private var catalog: AviationCatalog { Self.catalog }

    func testQFAndQFAStayAmbiguousAtLimitOne() throws {
        for query in ["QF", "QFA"] {
            let broad = try catalog.resolveOperators(query: query, limit: 20)
            let narrow = try catalog.resolveOperators(query: query, limit: 1)
            XCTAssertEqual(broad.kindName, "ambiguous", query)
            XCTAssertEqual(narrow.kindName, "ambiguous", query)
            guard case .ambiguous(let records) = narrow else {
                return XCTFail("Expected ambiguous records")
            }
            XCTAssertNil(AmbiguityPolicy.automaticCatalogID(matchCount: records.count, exactCodeCount: 2))
            if records.count >= 2 {
                XCTAssertNotEqual(records[0].id, records[1].id)
            }
        }
        let qantas = try XCTUnwrap(catalog.searchOperators(query: "Qantas Airways", limit: 20).first { $0.name == "Qantas Airways" })
        let selection = AviationSelection.catalog(id: qantas.id, displayText: qantas.name)
        XCTAssertEqual(selection.catalogId, qantas.id)
        XCTAssertNotEqual(selection.catalogId, "")
        let limited = try catalog.resolveOperators(query: "QF", limit: 1)
        guard case .ambiguous(let firstOnly) = limited else { return XCTFail("Expected a limited ambiguous result") }
        if firstOnly.first?.id != qantas.id {
            XCTAssertNotEqual(selection.catalogId, firstOnly.first?.id)
        }
    }

    func testAircraftAliasesAreNotShownAsOfficialDesignators() throws {
        let a359 = try XCTUnwrap(catalog.searchAircraft(query: "A359", limit: 5).first)
        XCTAssertTrue(a359.displayName.localizedCaseInsensitiveContains("A350") || a359.model.localizedCaseInsensitiveContains("A350"))
        XCTAssertNil(officialDesignatorText(a359.icaoTypeDesignators))
        XCTAssertFalse(CatalogPresentation.aircraftSubtitle(a359).contains("ICAO"))

        let b789 = try XCTUnwrap(catalog.searchAircraft(query: "B789", limit: 5).first)
        XCTAssertTrue(b789.displayName.contains("787-9") || b789.model.contains("787-9"))
        XCTAssertEqual(aircraftSelection(from: b789).detail, aircraftKindLabel(b789.entryKind))
        XCTAssertNil(officialDesignatorText(b789.icaoTypeDesignators))
        XCTAssertNil(linkedManufacturerSelection(from: b789), "B789 has no manufacturer id in this catalog, so none is invented")
        let a350 = try XCTUnwrap(catalog.searchAircraft(query: "A359", limit: 5).first)
        XCTAssertEqual(linkedManufacturerSelection(from: a350)?.catalogId, a350.manufacturerId)
        XCTAssertEqual(linkedManufacturerSelection(from: a350)?.displayText, a350.manufacturer)

        let byName = try XCTUnwrap(catalog.searchAircraft(query: "787-9", limit: 5).first { $0.id == b789.id })
        XCTAssertEqual(byName.id, b789.id)

        for query in ["A321neo", "737-800", "Cessna 172", "C-130"] {
            let match = try XCTUnwrap(catalog.searchAircraft(query: query, limit: 5).first)
            let selection = aircraftSelection(from: match)
            XCTAssertEqual(selection.detail, aircraftKindLabel(match.entryKind), query)
            if match.entryKind == "family" {
                XCTAssertEqual(selection.detail, "Family", query)
                XCTAssertNotEqual(selection.detail, "Model")
            }
        }
    }

    func testAirportsCodesClosedAndCustomLocations() throws {
        let sydney = try XCTUnwrap(catalog.searchAirports(query: "YSSY", limit: 5).first { $0.iataCode == "SYD" })
        XCTAssertEqual(CatalogPresentation.primaryAirportCode(sydney)?.title, "IATA")
        XCTAssertEqual(CatalogPresentation.primaryAirportCode(sydney)?.code, "SYD")
        let heathrow = try XCTUnwrap(catalog.searchAirports(query: "EGLL", limit: 5).first { $0.iataCode == "LHR" })
        XCTAssertEqual(CatalogPresentation.primaryAirportCode(heathrow)?.code, "LHR")

        let noIata = try XCTUnwrap(catalog.airports.first { $0.iataCode == nil })
        let primary = try XCTUnwrap(CatalogPresentation.primaryAirportCode(noIata))
        XCTAssertNotEqual(primary.title, "IATA")
        XCTAssertFalse(CatalogPresentation.airportSnapshot(noIata).contains("IATA"))

        let closed = try XCTUnwrap(catalog.airports.first { $0.type == "closed" })
        XCTAssertTrue(CatalogPresentation.isClosedAirport(closed))
        XCTAssertEqual(CatalogPresentation.airportTypeLabel(closed.type), "Closed")

        let custom = SpottingReferenceState.legacy(airline: "Club", location: "Nearby park", aircraftType: nil)
        XCTAssertEqual(custom.locationField.displayText, "Nearby park")
        XCTAssertNil(custom.forStorage().locationField.catalogId)
        XCTAssertNotEqual(custom.locationField.displayText, CatalogPresentation.airportSnapshot(sydney))
    }

    func testSearchLatencyOnTheLoadedCatalog() throws {
        let clock = ContinuousClock()
        let started = clock.now
        let operators = try catalog.searchOperators(query: "Qantas", limit: 20)
        let aircraft = try catalog.searchAircraft(query: "787-9", limit: 20)
        let airports = try catalog.searchAirports(query: "Sydney", limit: 20)
        let elapsed = started.duration(to: clock.now)
        XCTAssertFalse(operators.isEmpty)
        XCTAssertFalse(aircraft.isEmpty)
        XCTAssertFalse(airports.isEmpty)
        XCTAssertLessThan(elapsed, .seconds(2))
        print("SMART_ENTRY_SEARCH_SECONDS \(elapsed)")
    }
}

@Model
final class ReferenceProbeRecord {
    var registration: String = ""
    var airline: String = ""
    var location: String = ""
    var aircraftType: String? = nil
    var notes: String? = nil
    var timestamp: Date = Date()
    var photoToken: String = ""
    var operatorCatalogId: String? = nil
    var operatorSelectionKind: String? = nil
    var manufacturerName: String? = nil
    var manufacturerCatalogId: String? = nil
    var manufacturerSelectionKind: String? = nil
    var aircraftCatalogId: String? = nil
    var aircraftSelectionKind: String? = nil
    var aircraftEntryKind: String? = nil
    var airportCatalogId: String? = nil
    var locationSelectionKind: String? = nil
    var aircraftRoleId: String? = nil
    var aircraftRoleNote: String? = nil
    var operationTypeId: String? = nil
    var operationTypeNote: String? = nil

    init() {}
}

final class SwiftDataReferenceProbeTests: XCTestCase {
    func testLegacyAndStructuredRecordsRoundTrip() throws {
        let container = try ModelContainer(
            for: ReferenceProbeRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let legacy = ReferenceProbeRecord()
        legacy.registration = "VH-LEG"
        legacy.airline = "Some small charter company"
        legacy.location = "Nearby park"
        legacy.aircraftType = "Unknown aircraft"
        legacy.notes = "Keep me"
        legacy.photoToken = "photo-a"
        legacy.timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(legacy)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ReferenceProbeRecord>())
        let record = try XCTUnwrap(fetched.first { $0.registration == "VH-LEG" })
        XCTAssertEqual(record.airline, "Some small charter company")
        XCTAssertNil(record.operatorCatalogId)
        XCTAssertNil(record.operatorSelectionKind)
        XCTAssertNil(record.aircraftRoleId)
        XCTAssertEqual(record.photoToken, "photo-a")
        XCTAssertEqual(record.notes, "Keep me")

        record.operatorCatalogId = "wikidata:Q32491"
        record.operatorSelectionKind = "catalog"
        record.airline = "Qantas Airways"
        record.manufacturerCatalogId = "m-boeing"
        record.manufacturerSelectionKind = "catalog"
        record.manufacturerName = "Boeing"
        record.aircraftCatalogId = "wikidata:Q15111575"
        record.aircraftSelectionKind = "catalog"
        record.aircraftEntryKind = "Model"
        record.aircraftType = "Boeing 787-9"
        record.airportCatalogId = "ourairports:sydney"
        record.locationSelectionKind = "catalog"
        record.location = "Sydney Airport (SYD)"
        record.aircraftRoleId = "civil"
        record.operationTypeId = "passenger"
        try context.save()

        let again = try context.fetch(FetchDescriptor<ReferenceProbeRecord>())
        let saved = try XCTUnwrap(again.first { $0.registration == "VH-LEG" })
        XCTAssertEqual(saved.operatorCatalogId, "wikidata:Q32491")
        XCTAssertEqual(saved.aircraftEntryKind, "Model")
        XCTAssertEqual(saved.aircraftRoleId, "civil")
        XCTAssertEqual(saved.operationTypeId, "passenger")
        XCTAssertEqual(saved.photoToken, "photo-a")
        XCTAssertEqual(saved.timestamp, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(saved.notes, "Keep me")
    }
}
