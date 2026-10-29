import Foundation

public struct FilterableSpotting: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var registration: String
    public var timestamp: Date
    public var reference: SpottingReferenceState

    public init(id: String, registration: String, timestamp: Date, reference: SpottingReferenceState) {
        self.id = id
        self.registration = registration
        self.timestamp = timestamp
        self.reference = reference
    }
}

public struct FilterAircraftFacts: Equatable, Hashable, Sendable {
    public var displayName: String
    public var manufacturerId: String?
    public var familyId: String?
    public var familyName: String?
    public var entryKind: String

    public init(
        displayName: String,
        manufacturerId: String?,
        familyId: String?,
        familyName: String?,
        entryKind: String
    ) {
        self.displayName = displayName
        self.manufacturerId = manufacturerId
        self.familyId = familyId
        self.familyName = familyName
        self.entryKind = entryKind
    }
}

public struct FilterCatalogOperator: Equatable, Hashable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct FilterCatalogNamed: Equatable, Hashable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct FilterCatalogAircraft: Equatable, Hashable, Sendable {
    public var id: String
    public var displayName: String
    public var manufacturerId: String?
    public var familyId: String?
    public var familyName: String?
    public var entryKind: String

    public init(
        id: String,
        displayName: String,
        manufacturerId: String?,
        familyId: String?,
        familyName: String?,
        entryKind: String
    ) {
        self.id = id
        self.displayName = displayName
        self.manufacturerId = cleanedIdentifier(manufacturerId)
        self.familyId = cleanedIdentifier(familyId)
        self.familyName = cleanedIdentifier(familyName)
        self.entryKind = entryKind
    }
}

public struct FilterCatalogSnapshot: Equatable, Sendable {
    public var operators: [FilterCatalogOperator]
    public var manufacturers: [FilterCatalogNamed]
    public var aircraft: [FilterCatalogAircraft]
    public var airports: [FilterCatalogNamed]

    public init(
        operators: [FilterCatalogOperator] = [],
        manufacturers: [FilterCatalogNamed] = [],
        aircraft: [FilterCatalogAircraft] = [],
        airports: [FilterCatalogNamed] = []
    ) {
        self.operators = operators
        self.manufacturers = manufacturers
        self.aircraft = aircraft
        self.airports = airports
    }
}

public protocol SpottingFilterCatalog: Sendable {
    var isAvailable: Bool { get }
    func aircraft(id: String) -> FilterAircraftFacts?
    func manufacturerName(id: String) -> String?
    func operatorName(id: String) -> String?
    func airportName(id: String) -> String?
    /// Nil means the catalog cannot be consulted. Zero means the name was looked up and is absent.
    func operatorDisplayNameCount(_ normalizedName: String) -> Int?
    func manufacturerDisplayNameCount(_ normalizedName: String) -> Int?
    func aircraftDisplayNameCount(_ normalizedName: String) -> Int?
    func familyDisplayNameCount(_ normalizedName: String) -> Int?
    func airportDisplayNameCount(_ normalizedName: String) -> Int?
}

public struct PreparedSpottingFilterCatalog: SpottingFilterCatalog, Sendable {
    public let isAvailable: Bool
    private let aircraftByID: [String: FilterAircraftFacts]
    private let manufacturerNames: [String: String]
    private let operatorNames: [String: String]
    private let airportNames: [String: String]
    private let operatorNameCounts: [String: Int]
    private let manufacturerNameCounts: [String: Int]
    private let aircraftNameCounts: [String: Int]
    private let familyNameCounts: [String: Int]
    private let airportNameCounts: [String: Int]

    public static let unavailable = PreparedSpottingFilterCatalog(loaded: nil)

    public init(snapshot: FilterCatalogSnapshot) {
        self.init(loaded: snapshot)
    }

    private init(loaded snapshot: FilterCatalogSnapshot?) {
        guard let snapshot else {
            isAvailable = false
            aircraftByID = [:]
            manufacturerNames = [:]
            operatorNames = [:]
            airportNames = [:]
            operatorNameCounts = [:]
            manufacturerNameCounts = [:]
            aircraftNameCounts = [:]
            familyNameCounts = [:]
            airportNameCounts = [:]
            return
        }
        isAvailable = true
        var aircraft: [String: FilterAircraftFacts] = [:]
        aircraft.reserveCapacity(snapshot.aircraft.count)
        var aircraftCounts: [String: Int] = [:]
        var familyCounts: [String: Int] = [:]
        for record in snapshot.aircraft {
            aircraft[record.id] = FilterAircraftFacts(
                displayName: record.displayName,
                manufacturerId: record.manufacturerId,
                familyId: record.familyId,
                familyName: record.familyName,
                entryKind: record.entryKind
            )
            countName(record.displayName, into: &aircraftCounts)
            if record.entryKind == "family" {
                countName(record.displayName, into: &familyCounts)
            }
        }
        aircraftByID = aircraft
        aircraftNameCounts = aircraftCounts
        familyNameCounts = familyCounts
        (manufacturerNames, manufacturerNameCounts) = nameIndex(snapshot.manufacturers)
        (operatorNames, operatorNameCounts) = nameIndex(snapshot.operators.map { FilterCatalogNamed(id: $0.id, name: $0.name) })
        (airportNames, airportNameCounts) = nameIndex(snapshot.airports)
    }

    public func aircraft(id: String) -> FilterAircraftFacts? {
        guard isAvailable else { return nil }
        return aircraftByID[id]
    }

    public func manufacturerName(id: String) -> String? {
        guard isAvailable else { return nil }
        return manufacturerNames[id]
    }

    public func operatorName(id: String) -> String? {
        guard isAvailable else { return nil }
        return operatorNames[id]
    }

    public func airportName(id: String) -> String? {
        guard isAvailable else { return nil }
        return airportNames[id]
    }

    public func operatorDisplayNameCount(_ normalizedName: String) -> Int? {
        guard isAvailable else { return nil }
        return operatorNameCounts[normalizedName] ?? 0
    }

    public func manufacturerDisplayNameCount(_ normalizedName: String) -> Int? {
        guard isAvailable else { return nil }
        return manufacturerNameCounts[normalizedName] ?? 0
    }

    public func aircraftDisplayNameCount(_ normalizedName: String) -> Int? {
        guard isAvailable else { return nil }
        return aircraftNameCounts[normalizedName] ?? 0
    }

    public func familyDisplayNameCount(_ normalizedName: String) -> Int? {
        guard isAvailable else { return nil }
        return familyNameCounts[normalizedName] ?? 0
    }

    public func airportDisplayNameCount(_ normalizedName: String) -> Int? {
        guard isAvailable else { return nil }
        return airportNameCounts[normalizedName] ?? 0
    }
}

public struct FilterChoice: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var token: FilterToken

    public init(id: String, title: String, detail: String, token: FilterToken) {
        self.id = id
        self.title = title
        self.detail = detail
        self.token = token
    }
}

public struct CollectionFilterChoices: Equatable, Sendable {
    public var operators: [FilterChoice]
    public var manufacturers: [FilterChoice]
    public var aircraft: [FilterChoice]
    public var roles: [FilterChoice]
    public var operationTypes: [FilterChoice]
    public var locations: [FilterChoice]

    public init(
        operators: [FilterChoice],
        manufacturers: [FilterChoice],
        aircraft: [FilterChoice],
        roles: [FilterChoice],
        operationTypes: [FilterChoice],
        locations: [FilterChoice]
    ) {
        self.operators = operators
        self.manufacturers = manufacturers
        self.aircraft = aircraft
        self.roles = roles
        self.operationTypes = operationTypes
        self.locations = locations
    }
}

public func filteredSpottingResults(
    entries: [FilterableSpotting],
    searchText: String,
    filters: SpottingFilterState,
    catalog: any SpottingFilterCatalog,
    sort: SpottingFilterSort,
    calendar: Calendar
) -> [FilterableSpotting] {
    let indexed = entries.enumerated().filter { _, entry in
        matchesFreeText(entry, searchText: searchText) && matchesFilters(entry, filters: filters, catalog: catalog, calendar: calendar)
    }
    let ordered = indexed.sorted { lhs, rhs in
        let comparison = compareForSort(lhs.element, rhs.element, sort: sort)
        if comparison == .orderedSame {
            return lhs.offset < rhs.offset
        }
        return comparison == .orderedAscending
    }
    return ordered.map(\.element)
}

public func collectionFilterChoices(
    entries: [FilterableSpotting],
    catalog: any SpottingFilterCatalog
) -> CollectionFilterChoices {
    CollectionFilterChoices(
        operators: referenceChoices(entries, dimension: .operatorField, catalog: catalog, absentTitle: "No operator specified"),
        manufacturers: manufacturerChoices(entries, catalog: catalog),
        aircraft: aircraftChoices(entries, catalog: catalog),
        roles: classificationChoices(entries, order: ClassificationCopy.roleOrder, labels: ClassificationCopy.roleLabels, dimension: "role"),
        operationTypes: classificationChoices(entries, order: ClassificationCopy.operationOrder, labels: ClassificationCopy.operationLabels, dimension: "operation"),
        locations: referenceChoices(entries, dimension: .location, catalog: catalog, absentTitle: "No location specified")
    )
}

func matchesFreeText(_ entry: FilterableSpotting, searchText: String) -> Bool {
    if searchText.isEmpty { return true }
    let query = normalizeFilterName(searchText)
    if query.isEmpty { return true }
    let classification = entry.reference.classification
    let fields = [
        entry.registration,
        entry.reference.storedOperatorText,
        entry.reference.storedLocationText,
        entry.reference.storedAircraftText ?? "",
        entry.reference.storedManufacturerText ?? "",
        classification.roleNote ?? "",
        classification.operationTypeNote ?? "",
        ClassificationCopy.roleLabel(classification.roleId ?? ""),
        ClassificationCopy.operationLabel(classification.operationTypeId ?? ""),
    ]
    return fields.contains { normalizeFilterName($0).contains(query) }
}

func matchesFilters(
    _ entry: FilterableSpotting,
    filters: SpottingFilterState,
    catalog: any SpottingFilterCatalog,
    calendar: Calendar
) -> Bool {
    if !matchesReference(entry.reference.operatorField, filters.operators, nameCount: catalog.operatorDisplayNameCount) {
        return false
    }
    let manufacturer = resolvedManufacturerSelection(entry.reference, catalog: catalog)
    if !matchesReference(manufacturer, filters.manufacturers, nameCount: catalog.manufacturerDisplayNameCount) {
        return false
    }
    if !matchesAircraft(entry.reference.aircraftField, filters.aircraft, catalog: catalog) {
        return false
    }
    if !matchesClassification(entry.reference.classification.roleId, note: entry.reference.classification.roleNote, filters.roles) {
        return false
    }
    if !matchesClassification(entry.reference.classification.operationTypeId, note: entry.reference.classification.operationTypeNote, filters.operationTypes) {
        return false
    }
    if !matchesReference(entry.reference.locationField, filters.locations, nameCount: catalog.airportDisplayNameCount) {
        return false
    }
    if !registrationMatches(entry.registration, query: filters.registrationQuery) {
        return false
    }
    if !dateMatches(entry.timestamp, range: filters.dateRange, calendar: calendar) {
        return false
    }
    return true
}

/// Saved manufacturer identity wins. A verified aircraft manufacturer id is used only
/// when the saved manufacturer is absent and the catalog aircraft actually has one.
/// A missing manufacturer id is not filled in from the aircraft name.
func resolvedManufacturerSelection(
    _ reference: SpottingReferenceState,
    catalog: any SpottingFilterCatalog
) -> AviationSelection {
    let field = reference.manufacturerField
    if field.kind == .catalog, let id = cleanedIdentifier(field.catalogId) {
        return AviationSelection.catalog(id: id, displayText: field.displayText, detail: field.detail)
    }
    if field.kind == .unknown {
        return .unknown()
    }
    if field.kind == .custom, !normalizeFilterName(field.displayText).isEmpty {
        return field
    }
    if reference.aircraftField.kind == .catalog,
       let aircraftID = cleanedIdentifier(reference.aircraftField.catalogId),
       let facts = catalog.aircraft(id: aircraftID),
       let manufacturerID = cleanedIdentifier(facts.manufacturerId) {
        let name = catalog.manufacturerName(id: manufacturerID) ?? ""
        return .catalog(id: manufacturerID, displayText: name)
    }
    return .absent
}

private func matchesReference(
    _ selection: AviationSelection,
    _ filters: [ReferenceFilter],
    nameCount: (String) -> Int?
) -> Bool {
    if filters.isEmpty { return true }
    return filters.contains { filter in
        switch filter {
        case let .catalog(id, label):
            if selection.kind == .catalog, cleanedIdentifier(selection.catalogId) == id {
                return true
            }
            guard selection.kind == .custom else { return false }
            let recordName = normalizeFilterName(selection.displayText)
            let filterName = normalizeFilterName(label)
            guard !recordName.isEmpty, recordName == filterName else { return false }
            guard let count = nameCount(filterName), count == 1 else { return false }
            return true
        case let .custom(text):
            guard selection.kind == .custom else { return false }
            return normalizeFilterName(selection.displayText) == normalizeFilterName(text)
        case .unknown:
            return selection.kind == .unknown
        case .absent:
            return selection.kind == .absent
        }
    }
}

private func matchesAircraft(
    _ selection: AviationSelection,
    _ filters: [AircraftFilter],
    catalog: any SpottingFilterCatalog
) -> Bool {
    if filters.isEmpty { return true }
    return filters.contains { filter in
        switch filter {
        case let .model(id, label):
            if selection.kind == .catalog, cleanedIdentifier(selection.catalogId) == id {
                return true
            }
            guard selection.kind == .custom else { return false }
            return unambiguousText(selection.displayText, label: label, count: catalog.aircraftDisplayNameCount)
        case let .family(id, label):
            if selection.kind == .catalog, let recordID = cleanedIdentifier(selection.catalogId) {
                if recordID == id { return true }
                guard let facts = catalog.aircraft(id: recordID) else { return false }
                return facts.familyId == id
            }
            guard selection.kind == .custom else { return false }
            return unambiguousText(selection.displayText, label: label, count: catalog.familyDisplayNameCount)
        case let .custom(text):
            guard selection.kind == .custom else { return false }
            return normalizeFilterName(selection.displayText) == normalizeFilterName(text)
        case .unknown:
            return selection.kind == .unknown
        case .absent:
            return selection.kind == .absent
        }
    }
}

private func matchesClassification(_ id: String?, note: String?, _ filters: [ClassificationFilter]) -> Bool {
    if filters.isEmpty { return true }
    guard let id = cleanedIdentifier(id) else { return false }
    return filters.contains { filter in
        switch filter {
        case let .standard(filterID):
            return id == filterID
        case let .other(filterNote):
            guard id == "other" else { return false }
            guard let filterNote, !normalizeFilterName(filterNote).isEmpty else { return true }
            return normalizeFilterName(note ?? "") == normalizeFilterName(filterNote)
        }
    }
}

private func registrationMatches(_ registration: String, query: String) -> Bool {
    let normalizedQuery = normalizeRegistration(query)
    if normalizedQuery.isEmpty { return true }
    return normalizeRegistration(registration).hasPrefix(normalizedQuery)
}

private func dateMatches(_ timestamp: Date, range: FilterDateRange, calendar: Calendar) -> Bool {
    guard range.isActive else { return true }
    guard range.isValid else { return false }
    let day = filterCalendarDay(from: timestamp, calendar: calendar)
    if let start = range.start, day < start { return false }
    if let end = range.end, day > end { return false }
    return true
}

private func unambiguousText(_ recordText: String, label: String, count: (String) -> Int?) -> Bool {
    let recordName = normalizeFilterName(recordText)
    let filterName = normalizeFilterName(label)
    guard !recordName.isEmpty, recordName == filterName else { return false }
    guard let matches = count(filterName), matches == 1 else { return false }
    return true
}

private func compareForSort(
    _ lhs: FilterableSpotting,
    _ rhs: FilterableSpotting,
    sort: SpottingFilterSort
) -> ComparisonResult {
    switch sort {
    case .dateNewest:
        return compareDates(lhs.timestamp, rhs.timestamp, newestFirst: true)
    case .dateOldest:
        return compareDates(lhs.timestamp, rhs.timestamp, newestFirst: false)
    case .aircraftTypeAZ:
        return compareText(lhs.reference.storedAircraftText ?? "", rhs.reference.storedAircraftText ?? "", ascending: true)
    case .aircraftTypeZA:
        return compareText(lhs.reference.storedAircraftText ?? "", rhs.reference.storedAircraftText ?? "", ascending: false)
    case .airlineAZ:
        return compareText(lhs.reference.storedOperatorText, rhs.reference.storedOperatorText, ascending: true)
    case .airlineZA:
        return compareText(lhs.reference.storedOperatorText, rhs.reference.storedOperatorText, ascending: false)
    case .registrationAZ:
        return compareText(lhs.registration, rhs.registration, ascending: true)
    case .registrationZA:
        return compareText(lhs.registration, rhs.registration, ascending: false)
    }
}

private func compareDates(_ lhs: Date, _ rhs: Date, newestFirst: Bool) -> ComparisonResult {
    if lhs == rhs { return .orderedSame }
    let lhsFirst = newestFirst ? lhs > rhs : lhs < rhs
    return lhsFirst ? .orderedAscending : .orderedDescending
}

private func compareText(_ lhs: String, _ rhs: String, ascending: Bool) -> ComparisonResult {
    let left = normalizeFilterName(lhs)
    let right = normalizeFilterName(rhs)
    if left == right { return .orderedSame }
    let lhsFirst = ascending ? left < right : left > right
    return lhsFirst ? .orderedAscending : .orderedDescending
}

private func nameIndex(_ records: [FilterCatalogNamed]) -> (names: [String: String], counts: [String: Int]) {
    var names: [String: String] = [:]
    var counts: [String: Int] = [:]
    names.reserveCapacity(records.count)
    for record in records {
        if names[record.id] == nil {
            names[record.id] = record.name
        }
        countName(record.name, into: &counts)
    }
    return (names, counts)
}

private func countName(_ name: String, into counts: inout [String: Int]) {
    let normalized = normalizeFilterName(name)
    guard !normalized.isEmpty else { return }
    counts[normalized, default: 0] += 1
}

private struct ChoiceDraft {
    var token: FilterToken
    var title: String
    var kind: String
    var count: Int
}

private func referenceChoices(
    _ entries: [FilterableSpotting],
    dimension: ReferenceDimension,
    catalog: any SpottingFilterCatalog,
    absentTitle: String
) -> [FilterChoice] {
    var drafts: [String: ChoiceDraft] = [:]
    for entry in entries {
        let selection = selection(for: dimension, entry)
        let (token, title, kind) = referenceToken(selection, dimension: dimension, catalog: catalog, absentTitle: absentTitle)
        accumulate(&drafts, token: token, title: title, kind: kind)
    }
    ensure(&drafts, token: .reference(dimension, .unknown), title: "Unknown", kind: "Marked unknown")
    ensure(&drafts, token: .reference(dimension, .absent), title: absentTitle, kind: "Not specified")
    return finish(drafts)
}

private func manufacturerChoices(_ entries: [FilterableSpotting], catalog: any SpottingFilterCatalog) -> [FilterChoice] {
    var drafts: [String: ChoiceDraft] = [:]
    for entry in entries {
        let selection = resolvedManufacturerSelection(entry.reference, catalog: catalog)
        let (token, title, kind) = referenceToken(selection, dimension: .manufacturer, catalog: catalog, absentTitle: "No manufacturer specified")
        accumulate(&drafts, token: token, title: title, kind: kind)
    }
    ensure(&drafts, token: .reference(.manufacturer, .unknown), title: "Unknown", kind: "Marked unknown")
    ensure(&drafts, token: .reference(.manufacturer, .absent), title: "No manufacturer specified", kind: "Not specified")
    return finish(drafts)
}

private func aircraftChoices(_ entries: [FilterableSpotting], catalog: any SpottingFilterCatalog) -> [FilterChoice] {
    var drafts: [String: ChoiceDraft] = [:]
    for entry in entries {
        let selection = entry.reference.aircraftField
        switch selection.kind {
        case .catalog:
            guard let id = cleanedIdentifier(selection.catalogId) else { break }
            let facts = catalog.aircraft(id: id)
            if facts?.entryKind == "family" {
                let title = preferred(facts?.displayName, fallback: selection.displayText, id: id)
                accumulate(&drafts, token: .aircraft(.family(id: id, label: title)), title: title, kind: "Family")
            } else {
                let title = preferred(facts?.displayName, fallback: selection.displayText, id: id)
                let kind = facts == nil ? "Saved identity" : "Model"
                accumulate(&drafts, token: .aircraft(.model(id: id, label: title)), title: title, kind: kind)
                if let familyID = facts?.familyId {
                    let familyTitle = preferred(catalog.aircraft(id: familyID)?.displayName, fallback: facts?.familyName, id: familyID)
                    accumulate(&drafts, token: .aircraft(.family(id: familyID, label: familyTitle)), title: familyTitle, kind: "Family")
                }
            }
        case .custom:
            let title = selection.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
            accumulate(&drafts, token: .aircraft(.custom(text: selection.displayText)), title: title, kind: selection.isLegacy ? "Saved text" : "Custom")
        case .unknown:
            accumulate(&drafts, token: .aircraft(.unknown), title: "Unknown", kind: "Marked unknown")
        case .absent:
            accumulate(&drafts, token: .aircraft(.absent), title: "No aircraft specified", kind: "Not specified")
        }
    }
    ensure(&drafts, token: .aircraft(.unknown), title: "Unknown", kind: "Marked unknown")
    ensure(&drafts, token: .aircraft(.absent), title: "No aircraft specified", kind: "Not specified")
    return finish(drafts)
}

private func classificationChoices(
    _ entries: [FilterableSpotting],
    order: [String],
    labels: [String: String],
    dimension: String
) -> [FilterChoice] {
    var counts: [String: Int] = [:]
    var noteCounts: [String: Int] = [:]
    var noteTitles: [String: String] = [:]
    for entry in entries {
        let choice = dimension == "role"
            ? (entry.reference.classification.roleId, entry.reference.classification.roleNote)
            : (entry.reference.classification.operationTypeId, entry.reference.classification.operationTypeNote)
        guard let id = cleanedIdentifier(choice.0) else { continue }
        counts[id, default: 0] += 1
        if id == "other", let note = cleanedNote(choice.1) {
            let key = normalizeFilterName(note)
            noteCounts[key, default: 0] += 1
            if noteTitles[key] == nil {
                noteTitles[key] = note
            }
        }
    }
    var choices: [FilterChoice] = []
    for id in order {
        let filter = ClassificationFilter.role(id)
        let token: FilterToken = dimension == "role" ? .role(filter) : .operation(filter)
        choices.append(
            FilterChoice(
                id: chipID(for: token),
                title: labels[id] ?? id,
                detail: "Classification · \(counts[id] ?? 0)",
                token: token
            )
        )
    }
    for key in noteCounts.keys.sorted() {
        let note = noteTitles[key] ?? key
        let filter = ClassificationFilter.other(note: note)
        let token: FilterToken = dimension == "role" ? .role(filter) : .operation(filter)
        choices.append(
            FilterChoice(
                id: chipID(for: token),
                title: "Other: \(note)",
                detail: "Custom description · \(noteCounts[key] ?? 0)",
                token: token
            )
        )
    }
    return choices
}

private func selection(for dimension: ReferenceDimension, _ entry: FilterableSpotting) -> AviationSelection {
    switch dimension {
    case .operatorField:
        return entry.reference.operatorField
    case .manufacturer:
        return entry.reference.manufacturerField
    case .location:
        return entry.reference.locationField
    }
}

private func referenceToken(
    _ selection: AviationSelection,
    dimension: ReferenceDimension,
    catalog: any SpottingFilterCatalog,
    absentTitle: String
) -> (FilterToken, String, String) {
    switch selection.kind {
    case .catalog:
        let id = cleanedIdentifier(selection.catalogId) ?? ""
        let catalogName: String?
        switch dimension {
        case .operatorField:
            catalogName = catalog.operatorName(id: id)
        case .manufacturer:
            catalogName = catalog.manufacturerName(id: id)
        case .location:
            catalogName = catalog.airportName(id: id)
        }
        let title = preferred(catalogName, fallback: selection.displayText, id: id)
        let kind = catalogName == nil && catalog.isAvailable ? "Saved identity" : "Catalog"
        return (.reference(dimension, .catalog(id: id, label: title)), title, kind)
    case .custom:
        let title = selection.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (.reference(dimension, .custom(text: selection.displayText)), title, selection.isLegacy ? "Saved text" : "Custom")
    case .unknown:
        return (.reference(dimension, .unknown), "Unknown", "Marked unknown")
    case .absent:
        return (.reference(dimension, .absent), absentTitle, "Not specified")
    }
}

private func preferred(_ primary: String?, fallback: String?, id: String) -> String {
    if let primary, !normalizeFilterName(primary).isEmpty { return primary }
    if let fallback, !normalizeFilterName(fallback).isEmpty { return fallback }
    return id
}

private func accumulate(_ drafts: inout [String: ChoiceDraft], token: FilterToken, title: String, kind: String) {
    let id = chipID(for: token)
    if var existing = drafts[id] {
        existing.count += 1
        drafts[id] = existing
    } else {
        drafts[id] = ChoiceDraft(token: token, title: title, kind: kind, count: 1)
    }
}

private func ensure(_ drafts: inout [String: ChoiceDraft], token: FilterToken, title: String, kind: String) {
    let id = chipID(for: token)
    if drafts[id] == nil {
        drafts[id] = ChoiceDraft(token: token, title: title, kind: kind, count: 0)
    }
}

private func finish(_ drafts: [String: ChoiceDraft]) -> [FilterChoice] {
    let choices = drafts.map { id, draft in
        FilterChoice(
            id: id,
            title: draft.title,
            detail: "\(draft.kind) · \(draft.count)",
            token: draft.token
        )
    }
    return choices.sorted { lhs, rhs in
        let leftCount = count(in: lhs.detail)
        let rightCount = count(in: rhs.detail)
        if leftCount != rightCount { return leftCount > rightCount }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}

private func count(in detail: String) -> Int {
    Int(detail.split(separator: "·").last?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
}
