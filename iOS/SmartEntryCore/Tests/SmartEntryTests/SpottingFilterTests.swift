import Foundation
import SmartEntry
import XCTest

final class SpottingFilterTests: XCTestCase {
    private let calendar = filterTestCalendar()
    private let catalog = sampleFilterCatalog()
    private let stamp = filterTestDate(year: 2024, month: 6, day: 15, hour: 9)

    func testEmptyFiltersReturnEveryEntryInInputOrder() {
        let entries = [qantas(), jetstar(), legacy()]
        let results = run(entries, filters: SpottingFilterState())
        XCTAssertEqual(results.map(\.id), entries.map(\.id))
    }

    func testOneOperatorFilterUsesCatalogID() {
        let entries = [qantas(), jetstar(), legacy(airline: "QF")]
        var filters = SpottingFilterState()
        filters.insert(.reference(.operatorField, .catalog(id: "wikidata:Q32491", label: "Qantas Airways")))
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["qantas"])
    }

    func testOperatorsCombineWithOr() {
        let entries = [qantas(), jetstar(), military()]
        var filters = SpottingFilterState()
        filters.insert(.reference(.operatorField, .catalog(id: "wikidata:Q32491", label: "Qantas Airways")))
        filters.insert(.reference(.operatorField, .catalog(id: "wikidata:Q26468", label: "Jetstar")))
        XCTAssertEqual(Set(run(entries, filters: filters).map(\.id)), ["qantas", "jetstar"])
    }

    func testOperatorAndRoleCombineWithAnd() {
        let entries = [qantas(), jetstarCargo(), military()]
        var filters = SpottingFilterState()
        filters.insert(.reference(.operatorField, .catalog(id: "wikidata:Q32491", label: "Qantas Airways")))
        filters.insert(.reference(.operatorField, .catalog(id: "wikidata:Q26468", label: "Jetstar")))
        filters.insert(.role(.role("civil")))
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["qantas", "jetstar-cargo"])
    }

    func testRoleAndOperationCombineWithAnd() {
        let entries = [qantas(), jetstarCargo(), military()]
        var filters = SpottingFilterState()
        filters.insert(.role(.role("civil")))
        filters.insert(.operation(.operation("cargo")))
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["jetstar-cargo"])
    }

    func testManufacturerAndAircraftCombine() {
        let entries = [boeing788(), airbus(), cessna()]
        var filters = SpottingFilterState()
        filters.insert(.reference(.manufacturer, .catalog(id: "mfr:boeing", label: "Boeing")))
        filters.insert(.aircraft(.model(id: "ac:b788", label: "Boeing 787-8")))
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["b788"])
    }

    func testExactModelDoesNotIncludeSiblingModels() {
        let entries = [boeing789(), boeing788(), family787()]
        var filters = SpottingFilterState()
        filters.insert(.aircraft(.model(id: "ac:b789", label: "Boeing 787-9")))
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["b789"])
    }

    func testFamilyMatchesFamilyRecordAndVerifiedChildrenOnly() {
        let entries = [boeing789(), boeing788(), family787(), airbus(), c130(), customAircraft(), legacyAircraft()]
        var filters = SpottingFilterState()
        filters.insert(.aircraft(.family(id: "ac:b787", label: "Boeing 787")))
        XCTAssertEqual(Set(run(entries, filters: filters).map(\.id)), ["b789", "b788", "family-787"])
    }

    func testModelWithoutFamilyIsNotAssignedToAnInventedFamily() {
        let entries = [c130(), mystery(), boeing789()]
        var filters = SpottingFilterState()
        filters.insert(.aircraft(.family(id: "ac:b787", label: "Boeing 787")))
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["b789"])
        filters = SpottingFilterState()
        filters.insert(.aircraft(.family(id: "ac:c130-family", label: "C-130")))
        XCTAssertTrue(run(entries, filters: filters).isEmpty)
    }

    func testLegacyAircraftTextAndCustomTypesStaySearchable() {
        let entries = [legacyAircraft(), customAircraft(), boeing789()]
        var filters = SpottingFilterState()
        filters.insert(.aircraft(.custom(text: "Homebuilt")))
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["custom-aircraft"])
        filters = SpottingFilterState()
        filters.insert(.aircraft(.custom(text: "boeing 787-9")))
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["legacy-aircraft"])
    }

    func testMissingAircraftCatalogIDDoesNotCrash() {
        let entries = [legacyAircraft(), spotting(id: "blank-aircraft", aircraft: .absent)]
        var filters = SpottingFilterState()
        filters.insert(.aircraft(.model(id: "ac:missing", label: "Missing")))
        XCTAssertTrue(run(entries, filters: filters).isEmpty)
        XCTAssertEqual(run(entries, filters: SpottingFilterState()).count, 2)
    }

    func testFilteringDoesNotWriteFamilyOrMutateEntries() {
        let entries = [boeing789(), legacyAircraft(), qantas()]
        let before = entries
        _ = run(entries, filters: {
            var filters = SpottingFilterState()
            filters.insert(.aircraft(.family(id: "ac:b787", label: "Boeing 787")))
            return filters
        }())
        XCTAssertEqual(entries, before)
        XCTAssertNil(entries[0].reference.aircraftField.detail.flatMap { $0 == "family-written" ? $0 : nil })
        XCTAssertEqual(entries[0].reference.aircraftField.catalogId, "ac:b789")
    }

    func testAirportDoesNotMatchADifferentCustomLocation() {
        let entries = [sydney(), nearbyPark(), legacy(location: "SYD")]
        var filters = SpottingFilterState()
        filters.insert(.reference(.location, .catalog(id: "apt:yssy", label: "Sydney Airport")))
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["sydney"])
        filters = SpottingFilterState()
        filters.insert(.reference(.location, .custom(text: "Nearby park")))
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["park"])
    }

    func testRegistrationPrefixIsCaseInsensitive() {
        let entries = [
            spotting(id: "vh", registration: "vh-oja"),
            spotting(id: "n", registration: "N12345"),
            spotting(id: "g", registration: "G-EZTH"),
            spotting(id: "other", registration: "NVH-OJA"),
        ]
        var filters = SpottingFilterState()
        filters.registrationQuery = "vh-"
        XCTAssertEqual(Set(run(entries, filters: filters).map(\.id)), ["vh"])
        filters.registrationQuery = "n123"
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["n"])
        filters.registrationQuery = "g-"
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["g"])
    }

    func testDateRangeIncludesTheEndCalendarDay() {
        let entries = [
            spotting(id: "before", timestamp: filterTestDate(year: 2024, month: 1, day: 1, hour: 23, minute: 59, second: 59)),
            spotting(id: "start", timestamp: filterTestDate(year: 2024, month: 1, day: 2, hour: 0, minute: 0, second: 0)),
            spotting(id: "end", timestamp: filterTestDate(year: 2024, month: 1, day: 3, hour: 23, minute: 59, second: 59)),
            spotting(id: "after", timestamp: filterTestDate(year: 2024, month: 1, day: 4, hour: 0, minute: 0, second: 0)),
        ]
        var filters = SpottingFilterState()
        filters.dateRange = FilterDateRange(
            start: FilterCalendarDay(year: 2024, month: 1, day: 2),
            end: FilterCalendarDay(year: 2024, month: 1, day: 3)
        )
        XCTAssertEqual(run(entries, filters: filters, sort: .dateOldest).map(\.id), ["start", "end"])

        filters.dateRange = FilterDateRange(start: FilterCalendarDay(year: 2024, month: 1, day: 4), end: nil)
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["after"])

        filters.dateRange = FilterDateRange(start: nil, end: FilterCalendarDay(year: 2024, month: 1, day: 1))
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["before"])

        filters.dateRange = FilterDateRange(
            start: FilterCalendarDay(year: 2024, month: 1, day: 3),
            end: FilterCalendarDay(year: 2024, month: 1, day: 2)
        )
        XCTAssertFalse(filters.dateRange.isValid)
        XCTAssertTrue(run(entries, filters: filters).isEmpty)
    }

    func testFreeTextAndFiltersCombineWithAnd() {
        let entries = [qantas(), jetstar(), military()]
        var filters = SpottingFilterState()
        filters.insert(.role(.role("civil")))
        XCTAssertEqual(Set(run(entries, searchText: "jetstar", filters: filters).map(\.id)), ["jetstar"])
        XCTAssertTrue(run(entries, searchText: "jetstar", filters: {
            var militaryOnly = SpottingFilterState()
            militaryOnly.insert(.role(.role("military")))
            return militaryOnly
        }()).isEmpty)
    }

    func testSortingHappensAfterFiltering() {
        let entries = [
            spotting(id: "b", registration: "VH-BBB", airline: .catalog(id: "wikidata:Q32491", displayText: "Qantas Airways"), role: "civil"),
            spotting(id: "a", registration: "VH-AAA", airline: .catalog(id: "wikidata:Q32491", displayText: "Qantas Airways"), role: "civil"),
            spotting(id: "c", registration: "VH-CCC", airline: .catalog(id: "wikidata:Q26468", displayText: "Jetstar"), role: "civil"),
        ]
        var filters = SpottingFilterState()
        filters.insert(.reference(.operatorField, .catalog(id: "wikidata:Q32491", label: "Qantas Airways")))
        let results = run(entries, filters: filters, sort: .registrationAZ)
        XCTAssertEqual(results.map(\.id), ["a", "b"])
    }

    func testResetClearsEveryDimension() {
        var filters = SpottingFilterState()
        filters.insert(.role(.role("civil")))
        filters.registrationQuery = "VH-"
        filters.dateRange = FilterDateRange(start: FilterCalendarDay(year: 2024, month: 1, day: 1), end: nil)
        XCTAssertTrue(filters.isActive)
        filters.reset()
        XCTAssertFalse(filters.isActive)
        XCTAssertEqual(filters.activeConditionCount, 0)
        XCTAssertEqual(run([qantas(), military()], filters: filters).count, 2)
    }

    func testRemovingOneChipLeavesTheOtherFilter() {
        var filters = SpottingFilterState()
        filters.insert(.reference(.operatorField, .catalog(id: "wikidata:Q32491", label: "Qantas Airways")))
        filters.insert(.reference(.operatorField, .catalog(id: "wikidata:Q26468", label: "Jetstar")))
        let removed = filters.chips().first { $0.label.contains("Jetstar") }
        filters.removeChip(removed?.id ?? "")
        XCTAssertEqual(filters.operators.count, 1)
        XCTAssertEqual(run([qantas(), jetstar()], filters: filters).map(\.id), ["qantas"])
    }

    func testDuplicateSelectionsCountOnceAndMatchOnce() {
        var filters = SpottingFilterState()
        let value = ReferenceFilter.catalog(id: "wikidata:Q32491", label: "Qantas Airways")
        filters.insert(.reference(.operatorField, value))
        filters.insert(.reference(.operatorField, .catalog(id: "wikidata:Q32491", label: "QANTAS AIRWAYS")))
        XCTAssertEqual(filters.activeConditionCount, 1)
        XCTAssertEqual(run([qantas(), qantas(id: "qantas-2")], filters: filters).map(\.id), ["qantas", "qantas-2"])
    }

    func testNoMatchingEntriesAndEmptyCollection() {
        var filters = SpottingFilterState()
        filters.insert(.role(.role("military")))
        XCTAssertTrue(run([qantas()], filters: filters).isEmpty)
        XCTAssertTrue(run([], filters: filters).isEmpty)
        XCTAssertEqual(run([], filters: SpottingFilterState()).count, 0)
    }

    func testMissingCatalogMetadataDoesNotInventAManufacturer() {
        let dreamliner = boeing789()
        var filters = SpottingFilterState()
        filters.insert(.reference(.manufacturer, .catalog(id: "mfr:boeing", label: "Boeing")))
        XCTAssertTrue(run([dreamliner], filters: filters).isEmpty)
        filters = SpottingFilterState()
        filters.insert(.reference(.manufacturer, .absent))
        XCTAssertEqual(run([dreamliner], filters: filters).map(\.id), ["b789"])
    }

    func testVerifiedManufacturerLinkIsUsedWhenSavedManufacturerIsAbsent() {
        let linked = boeing788()
        var filters = SpottingFilterState()
        filters.insert(.reference(.manufacturer, .catalog(id: "mfr:boeing", label: "Boeing")))
        XCTAssertEqual(run([linked], filters: filters).map(\.id), ["b788"])
        filters = SpottingFilterState()
        filters.insert(.reference(.manufacturer, .absent))
        XCTAssertTrue(run([linked], filters: filters).isEmpty)
    }

    func testSavedManufacturerIDWinsOverAircraftLink() {
        let entry = spotting(
            id: "override",
            airline: .absent,
            manufacturer: .catalog(id: "mfr:airbus", displayText: "Airbus"),
            aircraft: .catalog(id: "ac:b788", displayText: "Boeing 787-8", detail: "Model")
        )
        var filters = SpottingFilterState()
        filters.insert(.reference(.manufacturer, .catalog(id: "mfr:airbus", label: "Airbus")))
        XCTAssertEqual(run([entry], filters: filters).map(\.id), ["override"])
        filters = SpottingFilterState()
        filters.insert(.reference(.manufacturer, .catalog(id: "mfr:boeing", label: "Boeing")))
        XCTAssertTrue(run([entry], filters: filters).isEmpty)
    }

    func testMissingCatalogResourcesSkipRelationshipAndNameFallback() {
        let entries = [boeing789(), legacy(airline: "Qantas Airways")]
        var filters = SpottingFilterState()
        filters.insert(.aircraft(.family(id: "ac:b787", label: "Boeing 787")))
        XCTAssertTrue(run(entries, filters: filters, catalog: .unavailable).isEmpty)
        filters = SpottingFilterState()
        filters.insert(.reference(.operatorField, .catalog(id: "wikidata:Q32491", label: "Qantas Airways")))
        XCTAssertTrue(run(entries, filters: filters, catalog: .unavailable).isEmpty)
        filters = SpottingFilterState()
        filters.insert(.aircraft(.model(id: "ac:b789", label: "Boeing 787-9")))
        XCTAssertEqual(run(entries, filters: filters, catalog: .unavailable).map(\.id), ["b789"])
    }

    func testUnknownIsDistinctFromAbsentAndUnset() {
        let entries = [
            spotting(id: "unknown", airline: .unknown(), role: "unknown"),
            spotting(id: "absent", airline: .absent),
            spotting(id: "unset", airline: .catalog(id: "wikidata:Q32491", displayText: "Qantas Airways")),
            legacy(),
        ]
        var filters = SpottingFilterState()
        filters.insert(.reference(.operatorField, .unknown))
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["unknown"])
        filters = SpottingFilterState()
        filters.insert(.reference(.operatorField, .absent))
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["absent"])
        filters = SpottingFilterState()
        filters.insert(.role(.role("unknown")))
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["unknown"])
        filters = SpottingFilterState()
        filters.insert(.role(.role("civil")))
        XCTAssertTrue(run(entries, filters: filters).isEmpty)
    }

    func testOtherClassificationIsDistinctFromUnknown() {
        let entries = [
            spotting(id: "survey", role: "other", roleNote: "Survey", operation: "other", operationNote: "Banner tow"),
            spotting(id: "unknown-role", role: "unknown", operation: "unknown"),
            spotting(id: "unset"),
        ]
        var filters = SpottingFilterState()
        filters.insert(.role(.role("other")))
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["survey"])
        filters = SpottingFilterState()
        filters.insert(.role(.role("other", note: "Survey")))
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["survey"])
        filters.insert(.operation(.operation("other", note: "Banner tow")))
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["survey"])
        filters = SpottingFilterState()
        filters.insert(.role(.role("other", note: "Fire scan")))
        XCTAssertTrue(run(entries, filters: filters).isEmpty)
        filters = SpottingFilterState()
        filters.insert(.role(.role("unknown")))
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["unknown-role"])
    }

    func testLegacyEntriesRemainReachableByTheirOriginalText() {
        let entry = legacy(airline: "Local Charter Service", aircraftType: "Cessna 172", location: "Nearby park", registration: "VH-LEG")
        var filters = SpottingFilterState()
        filters.insert(.reference(.operatorField, .custom(text: "local charter service")))
        filters.insert(.reference(.location, .custom(text: "Nearby park")))
        filters.registrationQuery = "vh-leg"
        XCTAssertEqual(run([entry, qantas()], filters: filters).map(\.id), ["legacy"])
        XCTAssertNil(entry.reference.operatorField.catalogId)
        XCTAssertNil(entry.reference.classification.roleId)
    }

    func testUnambiguousLegacyNameMatchesCatalogFilterButCodeDoesNot() {
        let entries = [
            legacy(id: "full-name", airline: "Qantas Airways"),
            legacy(id: "code", airline: "QF"),
            qantas(),
            legacy(id: "twin", airline: "Air Twin"),
        ]
        var filters = SpottingFilterState()
        filters.insert(.reference(.operatorField, .catalog(id: "wikidata:Q32491", label: "Qantas Airways")))
        XCTAssertEqual(Set(run(entries, filters: filters).map(\.id)), ["full-name", "qantas"])
        filters = SpottingFilterState()
        filters.insert(.reference(.operatorField, .catalog(id: "op:twin-a", label: "Air Twin")))
        XCTAssertTrue(run(entries, filters: filters).isEmpty)
        let twinA = spotting(id: "twin-a", airline: .catalog(id: "op:twin-a", displayText: "Air Twin"))
        let twinB = spotting(id: "twin-b", airline: .catalog(id: "op:twin-b", displayText: "Air Twin"))
        filters = SpottingFilterState()
        filters.insert(.reference(.operatorField, .catalog(id: "op:twin-a", label: "Air Twin")))
        XCTAssertEqual(run([twinA, twinB, legacy(id: "twin", airline: "Air Twin")], filters: filters).map(\.id), ["twin-a"])
    }

    func testCatalogIDStillMatchesWhenTheRecordIsGone() {
        let entry = spotting(id: "old", airline: .catalog(id: "op:retired", displayText: "Retired Air"))
        var filters = SpottingFilterState()
        filters.insert(.reference(.operatorField, .catalog(id: "op:retired", label: "Retired Air")))
        XCTAssertEqual(run([entry], filters: filters).map(\.id), ["old"])
        XCTAssertNil(catalog.operatorName(id: "op:retired"))
    }

    func testCustomFilterDoesNotIncludeCatalogRecordsWithTheSameName() {
        var filters = SpottingFilterState()
        filters.insert(.reference(.operatorField, .custom(text: "Qantas Airways")))
        XCTAssertEqual(run([legacy(airline: "Qantas Airways"), qantas()], filters: filters).map(\.id), ["legacy"])
    }

    func testClearOneDimensionAndChipLabels() {
        var filters = SpottingFilterState()
        filters.insert(.role(.role("civil")))
        filters.insert(.operation(.operation("passenger")))
        filters.clear(.roles)
        XCTAssertTrue(filters.roles.isEmpty)
        XCTAssertEqual(filters.operationTypes.count, 1)
        filters.dateRange = FilterDateRange(
            start: FilterCalendarDay(year: 2024, month: 1, day: 2),
            end: FilterCalendarDay(year: 2024, month: 1, day: 3)
        )
        XCTAssertEqual(filters.chips().map(\.label).last, "Date: 2 Jan 2024 – 3 Jan 2024")
    }

    func testFilterSessionRetainsStateAcrossANavigationBoundary() {
        var session = SpottingFilterSession()
        session.filters.insert(.role(.role("civil")))
        session.sort = .registrationAZ
        let returned = leaveSearch(session)
        XCTAssertEqual(returned.filters.roles, [.role("civil")])
        XCTAssertEqual(returned.sort, .registrationAZ)
        XCTAssertEqual(returned.filters.activeConditionCount, 1)
    }

    func testA350CessnaAndC130Fixtures() {
        let entries = [airbus(), cessna(), c130(), customAircraft()]
        var filters = SpottingFilterState()
        filters.insert(.aircraft(.family(id: "ac:a350", label: "Airbus A350")))
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["a350"])
        filters = SpottingFilterState()
        filters.insert(.aircraft(.model(id: "ac:c172", label: "Cessna 172")))
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["c172"])
        filters = SpottingFilterState()
        filters.insert(.aircraft(.model(id: "ac:c130", label: "C-130")))
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["c130"])
        filters = SpottingFilterState()
        filters.insert(.reference(.manufacturer, .catalog(id: "mfr:cessna", label: "Cessna")))
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["c172"])
        filters = SpottingFilterState()
        filters.insert(.reference(.manufacturer, .catalog(id: "mfr:lockheed", label: "Lockheed Martin")))
        XCTAssertEqual(run(entries, filters: filters).map(\.id), ["c130"])
    }

    func testPerformanceAcrossCollectionSizes() {
        let smallCatalog = performanceCatalog(operatorCount: 10)
        let wideCatalog = performanceCatalog(operatorCount: 3000)
        let sizes = [100, 1_000, 10_000]
        var wideTimes: [Double] = []
        for size in sizes {
            let entries = performanceEntries(count: size)
            let single = measureFilter(entries: entries, catalog: wideCatalog, kind: .single)
            let multi = measureFilter(entries: entries, catalog: wideCatalog, kind: .multi)
            let text = measureFilter(entries: entries, catalog: wideCatalog, kind: .text)
            let family = measureFilter(entries: entries, catalog: wideCatalog, kind: .family)
            let reset = measureFilter(entries: entries, catalog: wideCatalog, kind: .reset)
            let sorted = measureFilter(entries: entries, catalog: wideCatalog, kind: .sorted)
            print(String(format: "FILTER_BENCH size=%d single=%.2f multi=%.2f text=%.2f family=%.2f reset=%.2f sort=%.2f", size, single, multi, text, family, reset, sorted))
            XCTAssertLessThan(multi, 5_000, "10k-class filtering should stay interactive in this fixture")
            if size == 10_000 {
                wideTimes = [single, multi, text, family, reset, sorted]
                let narrow = measureFilter(entries: entries, catalog: smallCatalog, kind: .multi)
                let ratio = multi / max(narrow, 0.01)
                print(String(format: "FILTER_BENCH size=10000 catalogOperators narrow=10 wide=3000 narrowMs=%.2f wideMs=%.2f ratio=%.2f", narrow, multi, ratio))
                XCTAssertLessThan(ratio, 8, "Filtering should not scan the operator catalog for every sighting")
            }
        }
        XCTAssertEqual(wideTimes.count, 6)
    }

    private func leaveSearch(_ session: SpottingFilterSession) -> SpottingFilterSession {
        session
    }

    private func run(
        _ entries: [FilterableSpotting],
        searchText: String = "",
        filters: SpottingFilterState,
        catalog: PreparedSpottingFilterCatalog? = nil,
        sort: SpottingFilterSort = .dateNewest
    ) -> [FilterableSpotting] {
        filteredSpottingResults(
            entries: entries,
            searchText: searchText,
            filters: filters,
            catalog: catalog ?? self.catalog,
            sort: sort,
            calendar: calendar
        )
    }

    private func qantas(id: String = "qantas") -> FilterableSpotting {
        spotting(
            id: id,
            registration: "VH-OJA",
            airline: .catalog(id: "wikidata:Q32491", displayText: "Qantas Airways"),
            aircraft: .catalog(id: "ac:b789", displayText: "Boeing 787-9", detail: "Model"),
            location: .catalog(id: "apt:yssy", displayText: "Sydney Airport"),
            role: "civil",
            operation: "passenger"
        )
    }

    private func jetstar() -> FilterableSpotting {
        spotting(
            id: "jetstar",
            registration: "VH-VGR",
            airline: .catalog(id: "wikidata:Q26468", displayText: "Jetstar"),
            location: .catalog(id: "apt:yssy", displayText: "Sydney Airport"),
            role: "civil",
            operation: "passenger"
        )
    }

    private func jetstarCargo() -> FilterableSpotting {
        spotting(
            id: "jetstar-cargo",
            registration: "VH-JST",
            airline: .catalog(id: "wikidata:Q26468", displayText: "Jetstar"),
            role: "civil",
            operation: "cargo"
        )
    }

    private func military() -> FilterableSpotting {
        spotting(
            id: "military",
            registration: "A97-001",
            airline: .catalog(id: "op:raaf", displayText: "RAAF"),
            aircraft: .catalog(id: "ac:c130", displayText: "C-130", detail: "Model"),
            location: .custom(from: "Richmond") ?? .absent,
            role: "military",
            operation: "cargo"
        )
    }

    private func boeing789() -> FilterableSpotting {
        spotting(id: "b789", aircraft: .catalog(id: "ac:b789", displayText: "Boeing 787-9", detail: "Model"))
    }

    private func boeing788() -> FilterableSpotting {
        spotting(id: "b788", aircraft: .catalog(id: "ac:b788", displayText: "Boeing 787-8", detail: "Model"))
    }

    private func family787() -> FilterableSpotting {
        spotting(id: "family-787", aircraft: .catalog(id: "ac:b787", displayText: "Boeing 787", detail: "Family"))
    }

    private func airbus() -> FilterableSpotting {
        spotting(id: "a350", aircraft: .catalog(id: "ac:a359", displayText: "Airbus A350-900", detail: "Model"))
    }

    private func cessna() -> FilterableSpotting {
        spotting(id: "c172", aircraft: .catalog(id: "ac:c172", displayText: "Cessna 172", detail: "Model"))
    }

    private func c130() -> FilterableSpotting {
        spotting(id: "c130", aircraft: .catalog(id: "ac:c130", displayText: "C-130", detail: "Model"))
    }

    private func mystery() -> FilterableSpotting {
        spotting(id: "mystery", aircraft: .catalog(id: "ac:mystery", displayText: "Mystery Jet", detail: "Model"))
    }

    private func customAircraft() -> FilterableSpotting {
        spotting(id: "custom-aircraft", aircraft: .custom(from: "Homebuilt") ?? .absent)
    }

    private func legacyAircraft() -> FilterableSpotting {
        legacy(id: "legacy-aircraft", aircraftType: "Boeing 787-9")
    }

    private func sydney() -> FilterableSpotting {
        spotting(id: "sydney", location: .catalog(id: "apt:yssy", displayText: "Sydney Airport"))
    }

    private func nearbyPark() -> FilterableSpotting {
        spotting(id: "park", location: .custom(from: "Nearby park") ?? .absent)
    }

    private func legacy(
        id: String = "legacy",
        airline: String = "Local Charter Service",
        aircraftType: String? = "Light twin",
        location: String = "Nearby park",
        registration: String = "VH-OLD"
    ) -> FilterableSpotting {
        FilterableSpotting(
            id: id,
            registration: registration,
            timestamp: stamp,
            reference: .legacy(airline: airline, location: location, aircraftType: aircraftType)
        )
    }

    private func spotting(
        id: String,
        registration: String = "VH-TEST",
        timestamp: Date? = nil,
        airline: AviationSelection = .absent,
        manufacturer: AviationSelection = .absent,
        aircraft: AviationSelection = .absent,
        location: AviationSelection = .absent,
        role: String? = nil,
        roleNote: String? = nil,
        operation: String? = nil,
        operationNote: String? = nil
    ) -> FilterableSpotting {
        FilterableSpotting(
            id: id,
            registration: registration,
            timestamp: timestamp ?? stamp,
            reference: SpottingReferenceState(
                operatorField: airline,
                manufacturerField: manufacturer,
                aircraftField: aircraft,
                locationField: location,
                classification: ClassificationChoice(
                    roleId: role,
                    roleNote: roleNote,
                    operationTypeId: operation,
                    operationTypeNote: operationNote
                ).normalized()
            )
        )
    }
}

private enum BenchKind { case single, multi, text, family, reset, sorted }

private func measureFilter(
    entries: [FilterableSpotting],
    catalog: PreparedSpottingFilterCatalog,
    kind: BenchKind
) -> Double {
    let calendar = filterTestCalendar()
    let filters = benchmarkFilters(kind)
    let search = kind == .text ? "VH-1" : ""
    let sort: SpottingFilterSort = kind == .sorted ? .registrationAZ : .dateNewest
    _ = filteredSpottingResults(entries: entries, searchText: search, filters: filters, catalog: catalog, sort: sort, calendar: calendar)
    let elapsed = ContinuousClock().measure {
        _ = filteredSpottingResults(entries: entries, searchText: search, filters: filters, catalog: catalog, sort: sort, calendar: calendar)
    }
    return Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
}

private func benchmarkFilters(_ kind: BenchKind) -> SpottingFilterState {
    var filters = SpottingFilterState()
    switch kind {
    case .single:
        filters.insert(.reference(.operatorField, .catalog(id: "op:0", label: "Operator 0")))
    case .multi, .text, .sorted:
        filters.insert(.reference(.operatorField, .catalog(id: "op:0", label: "Operator 0")))
        filters.insert(.reference(.operatorField, .catalog(id: "op:1", label: "Operator 1")))
        filters.insert(.role(.role("civil")))
        filters.insert(.operation(.operation("passenger")))
        filters.registrationQuery = "VH-"
    case .family:
        filters.insert(.aircraft(.family(id: "ac:bench-family", label: "Bench Family")))
    case .reset:
        break
    }
    return filters
}

private func performanceEntries(count: Int) -> [FilterableSpotting] {
    let stamp = filterTestDate(year: 2020, month: 1, day: 1)
    return (0..<count).map { index in
        let operatorIndex = index % 10
        let aircraftID = index % 3 == 0 ? "ac:bench-child" : "ac:bench-other"
        return FilterableSpotting(
            id: "perf-\(index)",
            registration: "VH-\(index)",
            timestamp: stamp.addingTimeInterval(TimeInterval(index)),
            reference: SpottingReferenceState(
                operatorField: .catalog(id: "op:\(operatorIndex)", displayText: "Operator \(operatorIndex)"),
                manufacturerField: .absent,
                aircraftField: .catalog(id: aircraftID, displayText: "Bench \(aircraftID)", detail: "Model"),
                locationField: .custom(from: "Field \(index % 4)") ?? .absent,
                classification: ClassificationChoice(
                    roleId: index % 2 == 0 ? "civil" : "military",
                    operationTypeId: index % 2 == 0 ? "passenger" : "cargo"
                )
            )
        )
    }
}

private func performanceCatalog(operatorCount: Int) -> PreparedSpottingFilterCatalog {
    let operators = (0..<operatorCount).map { FilterCatalogOperator(id: "op:\($0)", name: "Operator \($0)") }
    let aircraft = [
        FilterCatalogAircraft(id: "ac:bench-child", displayName: "Bench Child", manufacturerId: "mfr:bench", familyId: "ac:bench-family", familyName: "Bench Family", entryKind: "model"),
        FilterCatalogAircraft(id: "ac:bench-other", displayName: "Bench Other", manufacturerId: nil, familyId: nil, familyName: nil, entryKind: "model"),
        FilterCatalogAircraft(id: "ac:bench-family", displayName: "Bench Family", manufacturerId: "mfr:bench", familyId: nil, familyName: nil, entryKind: "family"),
    ]
    return PreparedSpottingFilterCatalog(
        snapshot: FilterCatalogSnapshot(
            operators: operators,
            manufacturers: [FilterCatalogNamed(id: "mfr:bench", name: "Bench Works")],
            aircraft: aircraft,
            airports: []
        )
    )
}

private func sampleFilterCatalog() -> PreparedSpottingFilterCatalog {
    PreparedSpottingFilterCatalog(
        snapshot: FilterCatalogSnapshot(
            operators: [
                FilterCatalogOperator(id: "wikidata:Q32491", name: "Qantas Airways"),
                FilterCatalogOperator(id: "wikidata:Q26468", name: "Jetstar"),
                FilterCatalogOperator(id: "wikidata:QFREIGHT", name: "Qantas Freight"),
                FilterCatalogOperator(id: "op:raaf", name: "RAAF"),
                FilterCatalogOperator(id: "op:twin-a", name: "Air Twin"),
                FilterCatalogOperator(id: "op:twin-b", name: "Air Twin"),
            ],
            manufacturers: [
                FilterCatalogNamed(id: "mfr:boeing", name: "Boeing"),
                FilterCatalogNamed(id: "mfr:airbus", name: "Airbus"),
                FilterCatalogNamed(id: "mfr:cessna", name: "Cessna"),
                FilterCatalogNamed(id: "mfr:lockheed", name: "Lockheed Martin"),
            ],
            aircraft: [
                FilterCatalogAircraft(id: "ac:b789", displayName: "Boeing 787-9", manufacturerId: nil, familyId: "ac:b787", familyName: "Boeing 787", entryKind: "model"),
                FilterCatalogAircraft(id: "ac:b788", displayName: "Boeing 787-8", manufacturerId: "mfr:boeing", familyId: "ac:b787", familyName: "Boeing 787", entryKind: "model"),
                FilterCatalogAircraft(id: "ac:b787", displayName: "Boeing 787", manufacturerId: "mfr:boeing", familyId: nil, familyName: nil, entryKind: "family"),
                FilterCatalogAircraft(id: "ac:a359", displayName: "Airbus A350-900", manufacturerId: "mfr:airbus", familyId: "ac:a350", familyName: "Airbus A350", entryKind: "model"),
                FilterCatalogAircraft(id: "ac:a350", displayName: "Airbus A350", manufacturerId: "mfr:airbus", familyId: nil, familyName: nil, entryKind: "family"),
                FilterCatalogAircraft(id: "ac:c172", displayName: "Cessna 172", manufacturerId: "mfr:cessna", familyId: "ac:c172-family", familyName: "Cessna 172", entryKind: "model"),
                FilterCatalogAircraft(id: "ac:c172-family", displayName: "Cessna 172", manufacturerId: "mfr:cessna", familyId: nil, familyName: nil, entryKind: "family"),
                FilterCatalogAircraft(id: "ac:c130", displayName: "C-130", manufacturerId: "mfr:lockheed", familyId: nil, familyName: nil, entryKind: "model"),
                FilterCatalogAircraft(id: "ac:mystery", displayName: "Mystery Jet", manufacturerId: nil, familyId: nil, familyName: nil, entryKind: "model"),
            ],
            airports: [
                FilterCatalogNamed(id: "apt:yssy", name: "Sydney Airport"),
                FilterCatalogNamed(id: "apt:ymml", name: "Melbourne Airport"),
            ]
        )
    )
}

private func filterTestCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar
}

private func filterTestDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int = 12,
    minute: Int = 0,
    second: Int = 0
) -> Date {
    var components = DateComponents()
    components.calendar = filterTestCalendar()
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    return components.date ?? Date(timeIntervalSince1970: 0)
}
