import Foundation

/// One calendar day in the calendar used to display sighting dates.
public struct FilterCalendarDay: Equatable, Hashable, Sendable, Comparable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (lhs: FilterCalendarDay, rhs: FilterCalendarDay) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}

public struct FilterDateRange: Equatable, Hashable, Sendable {
    public var start: FilterCalendarDay?
    public var end: FilterCalendarDay?

    public init(start: FilterCalendarDay? = nil, end: FilterCalendarDay? = nil) {
        self.start = start
        self.end = end
    }

    public var isActive: Bool { start != nil || end != nil }

    /// An end day earlier than the start day is invalid. Callers show that state
    /// and do not swap the two days.
    public var isValid: Bool {
        guard let start, let end else { return true }
        return start <= end
    }
}

public enum ReferenceDimension: String, Equatable, Hashable, Sendable, CaseIterable {
    case operatorField = "operator"
    case manufacturer
    case location
}

/// A catalog id, explicit custom text, unknown, or absent value.
/// Catalog identity is the id. The label is display text and is not part of equality.
public enum ReferenceFilter: Sendable {
    case catalog(id: String, label: String)
    case custom(text: String)
    case unknown
    case absent
}

extension ReferenceFilter: Hashable {
    public static func == (lhs: ReferenceFilter, rhs: ReferenceFilter) -> Bool {
        switch (lhs, rhs) {
        case let (.catalog(lhsID, _), .catalog(rhsID, _)):
            return lhsID == rhsID
        case let (.custom(lhsText), .custom(rhsText)):
            return normalizeFilterName(lhsText) == normalizeFilterName(rhsText)
        case (.unknown, .unknown):
            return true
        case (.absent, .absent):
            return true
        case (.catalog, .custom), (.catalog, .unknown), (.catalog, .absent),
             (.custom, .catalog), (.custom, .unknown), (.custom, .absent),
             (.unknown, .catalog), (.unknown, .custom), (.unknown, .absent),
             (.absent, .catalog), (.absent, .custom), (.absent, .unknown):
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .catalog(id, _):
            hasher.combine("catalog")
            hasher.combine(id)
        case let .custom(text):
            hasher.combine("custom")
            hasher.combine(normalizeFilterName(text))
        case .unknown:
            hasher.combine("unknown")
        case .absent:
            hasher.combine("absent")
        }
    }

    public var label: String {
        switch self {
        case let .catalog(_, label):
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Catalog record" : trimmed
        case let .custom(text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .unknown:
            return "Unknown"
        case .absent:
            return "Not specified"
        }
    }
}

/// Exact model and aircraft family are different filters.
public enum AircraftFilter: Sendable {
    case model(id: String, label: String)
    case family(id: String, label: String)
    case custom(text: String)
    case unknown
    case absent
}

extension AircraftFilter: Hashable {
    public static func == (lhs: AircraftFilter, rhs: AircraftFilter) -> Bool {
        switch (lhs, rhs) {
        case let (.model(lhsID, _), .model(rhsID, _)):
            return lhsID == rhsID
        case let (.family(lhsID, _), .family(rhsID, _)):
            return lhsID == rhsID
        case let (.custom(lhsText), .custom(rhsText)):
            return normalizeFilterName(lhsText) == normalizeFilterName(rhsText)
        case (.unknown, .unknown), (.absent, .absent):
            return true
        case (.model, .family), (.model, .custom), (.model, .unknown), (.model, .absent),
             (.family, .model), (.family, .custom), (.family, .unknown), (.family, .absent),
             (.custom, .model), (.custom, .family), (.custom, .unknown), (.custom, .absent),
             (.unknown, .model), (.unknown, .family), (.unknown, .custom), (.unknown, .absent),
             (.absent, .model), (.absent, .family), (.absent, .custom), (.absent, .unknown):
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .model(id, _):
            hasher.combine("model")
            hasher.combine(id)
        case let .family(id, _):
            hasher.combine("family")
            hasher.combine(id)
        case let .custom(text):
            hasher.combine("custom")
            hasher.combine(normalizeFilterName(text))
        case .unknown:
            hasher.combine("unknown")
        case .absent:
            hasher.combine("absent")
        }
    }
}

public enum ClassificationFilter: Sendable {
    /// A vocabulary id other than `other`.
    case standard(id: String)
    /// `note == nil` matches every Other value. A note matches that description only.
    case other(note: String?)
}

extension ClassificationFilter: Hashable {
    public static func role(_ id: String, note: String? = nil) -> ClassificationFilter {
        if id == "other" {
            return .other(note: cleanedNote(note))
        }
        return .standard(id: id)
    }

    public static func operation(_ id: String, note: String? = nil) -> ClassificationFilter {
        role(id, note: note)
    }

    public static func == (lhs: ClassificationFilter, rhs: ClassificationFilter) -> Bool {
        switch (lhs, rhs) {
        case let (.standard(lhsID), .standard(rhsID)):
            return lhsID == rhsID
        case let (.other(lhsNote), .other(rhsNote)):
            return normalizeFilterName(lhsNote ?? "") == normalizeFilterName(rhsNote ?? "")
        case (.standard, .other), (.other, .standard):
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .standard(id):
            hasher.combine("standard")
            hasher.combine(id)
        case let .other(note):
            hasher.combine("other")
            hasher.combine(normalizeFilterName(note ?? ""))
        }
    }
}

public enum FilterToken: Equatable, Hashable, Sendable {
    case reference(ReferenceDimension, ReferenceFilter)
    case aircraft(AircraftFilter)
    case role(ClassificationFilter)
    case operation(ClassificationFilter)
    case registration
    case dateRange
}

public struct SpottingFilterChip: Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var accessibilityLabel: String
    public var token: FilterToken

    public init(id: String, label: String, accessibilityLabel: String, token: FilterToken) {
        self.id = id
        self.label = label
        self.accessibilityLabel = accessibilityLabel
        self.token = token
    }
}

public enum SpottingFilterSort: String, Equatable, Hashable, Sendable, CaseIterable {
    case dateNewest
    case dateOldest
    case aircraftTypeAZ
    case aircraftTypeZA
    case airlineAZ
    case airlineZA
    case registrationAZ
    case registrationZA
}

/// Ephemeral search filters. This value is not written into a spotting record.
public struct SpottingFilterState: Equatable, Hashable, Sendable {
    public var operators: [ReferenceFilter]
    public var manufacturers: [ReferenceFilter]
    public var aircraft: [AircraftFilter]
    public var roles: [ClassificationFilter]
    public var operationTypes: [ClassificationFilter]
    public var locations: [ReferenceFilter]
    public var registrationQuery: String
    public var dateRange: FilterDateRange

    public init(
        operators: [ReferenceFilter] = [],
        manufacturers: [ReferenceFilter] = [],
        aircraft: [AircraftFilter] = [],
        roles: [ClassificationFilter] = [],
        operationTypes: [ClassificationFilter] = [],
        locations: [ReferenceFilter] = [],
        registrationQuery: String = "",
        dateRange: FilterDateRange = FilterDateRange()
    ) {
        self.operators = operators
        self.manufacturers = manufacturers
        self.aircraft = aircraft
        self.roles = roles
        self.operationTypes = operationTypes
        self.locations = locations
        self.registrationQuery = registrationQuery
        self.dateRange = dateRange
    }

    public var isActive: Bool { activeConditionCount > 0 }

    public var activeConditionCount: Int {
        operators.count
            + manufacturers.count
            + aircraft.count
            + roles.count
            + operationTypes.count
            + locations.count
            + (registrationIsActive ? 1 : 0)
            + (dateRange.isActive ? 1 : 0)
    }

    public var registrationIsActive: Bool {
        !normalizeRegistration(registrationQuery).isEmpty
    }

    public mutating func insert(_ token: FilterToken) {
        switch token {
        case let .reference(dimension, value):
            switch dimension {
            case .operatorField:
                insertUnique(&operators, value)
            case .manufacturer:
                insertUnique(&manufacturers, value)
            case .location:
                insertUnique(&locations, value)
            }
        case let .aircraft(value):
            insertUnique(&aircraft, value)
        case let .role(value):
            insertUnique(&roles, value)
        case let .operation(value):
            insertUnique(&operationTypes, value)
        case .registration, .dateRange:
            break
        }
    }

    public mutating func remove(_ token: FilterToken) {
        switch token {
        case let .reference(dimension, value):
            switch dimension {
            case .operatorField:
                operators.removeAll { $0 == value }
            case .manufacturer:
                manufacturers.removeAll { $0 == value }
            case .location:
                locations.removeAll { $0 == value }
            }
        case let .aircraft(value):
            aircraft.removeAll { $0 == value }
        case let .role(value):
            roles.removeAll { $0 == value }
        case let .operation(value):
            operationTypes.removeAll { $0 == value }
        case .registration:
            registrationQuery = ""
        case .dateRange:
            dateRange = FilterDateRange()
        }
    }

    public mutating func toggle(_ token: FilterToken) {
        if contains(token) {
            remove(token)
        } else {
            insert(token)
        }
    }

    public func contains(_ token: FilterToken) -> Bool {
        switch token {
        case let .reference(dimension, value):
            switch dimension {
            case .operatorField:
                return operators.contains(value)
            case .manufacturer:
                return manufacturers.contains(value)
            case .location:
                return locations.contains(value)
            }
        case let .aircraft(value):
            return aircraft.contains(value)
        case let .role(value):
            return roles.contains(value)
        case let .operation(value):
            return operationTypes.contains(value)
        case .registration:
            return registrationIsActive
        case .dateRange:
            return dateRange.isActive
        }
    }

    public mutating func clear(_ dimension: FilterDimension) {
        switch dimension {
        case .operators:
            operators = []
        case .manufacturers:
            manufacturers = []
        case .aircraft:
            aircraft = []
        case .roles:
            roles = []
        case .operationTypes:
            operationTypes = []
        case .locations:
            locations = []
        case .registration:
            registrationQuery = ""
        case .dateRange:
            dateRange = FilterDateRange()
        }
    }

    public mutating func reset() {
        self = SpottingFilterState()
    }

    public mutating func removeChip(_ id: String) {
        guard let token = tokenForChipID(id) else { return }
        remove(token)
    }

    public func chips() -> [SpottingFilterChip] {
        var chips: [SpottingFilterChip] = []
        chips.append(contentsOf: operators.map { chip(dimension: "Operator", value: referenceLabel($0, absent: "No operator specified"), token: .reference(.operatorField, $0)) })
        chips.append(contentsOf: manufacturers.map { chip(dimension: "Manufacturer", value: referenceLabel($0, absent: "No manufacturer specified"), token: .reference(.manufacturer, $0)) })
        chips.append(contentsOf: aircraft.map { aircraftChip($0) })
        chips.append(contentsOf: roles.map { classificationChip("Role", $0, labels: ClassificationCopy.roleLabels) })
        chips.append(contentsOf: operationTypes.map { classificationChip("Operation", $0, labels: ClassificationCopy.operationLabels) })
        chips.append(contentsOf: locations.map { chip(dimension: "Location", value: referenceLabel($0, absent: "No location specified"), token: .reference(.location, $0)) })
        if registrationIsActive {
            let shown = normalizeRegistration(registrationQuery)
            chips.append(chip(dimension: "Registration", value: shown, token: .registration))
        }
        if dateRange.isActive {
            chips.append(chip(dimension: "Date", value: dateRangeLabel(dateRange), token: .dateRange))
        }
        return chips
    }
}

public enum FilterDimension: Equatable, Hashable, Sendable, CaseIterable {
    case operators
    case manufacturers
    case aircraft
    case roles
    case operationTypes
    case locations
    case registration
    case dateRange
}

/// In-memory holder used by the search screen. Filtering never clears this on its own.
public struct SpottingFilterSession: Equatable, Sendable {
    public var filters: SpottingFilterState
    public var sort: SpottingFilterSort

    public init(filters: SpottingFilterState = SpottingFilterState(), sort: SpottingFilterSort = .dateNewest) {
        self.filters = filters
        self.sort = sort
    }
}

func normalizeFilterName(_ value: String) -> String {
    let collapsed = value
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    return collapsed.lowercased(with: Locale(identifier: "en_US_POSIX"))
}

func normalizeRegistration(_ value: String) -> String {
    let uppercased = value.uppercased(with: Locale(identifier: "en_US_POSIX"))
    return uppercased.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.map(String.init).joined()
}

public func filterCalendarDay(from date: Date, calendar: Calendar) -> FilterCalendarDay {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return FilterCalendarDay(year: parts.year ?? 1, month: parts.month ?? 1, day: parts.day ?? 1)
}

func chipID(for token: FilterToken) -> String {
    switch token {
    case let .reference(dimension, value):
        return "\(dimension.rawValue)\u{1f}\(referenceChipSuffix(value))"
    case let .aircraft(value):
        return "aircraft\u{1f}\(aircraftChipSuffix(value))"
    case let .role(value):
        return "role\u{1f}\(classificationChipSuffix(value))"
    case let .operation(value):
        return "operation\u{1f}\(classificationChipSuffix(value))"
    case .registration:
        return "registration"
    case .dateRange:
        return "date"
    }
}

private func tokenForChipID(_ id: String) -> FilterToken? {
    if id == "registration" { return .registration }
    if id == "date" { return .dateRange }
    let parts = id.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
    guard parts.count >= 2 else { return nil }
    switch parts[0] {
    case ReferenceDimension.operatorField.rawValue:
        return referenceToken(.operatorField, parts)
    case ReferenceDimension.manufacturer.rawValue:
        return referenceToken(.manufacturer, parts)
    case ReferenceDimension.location.rawValue:
        return referenceToken(.location, parts)
    case "aircraft":
        guard let value = aircraftFilter(from: parts) else { return nil }
        return .aircraft(value)
    case "role":
        guard let value = classificationFilter(from: parts) else { return nil }
        return .role(value)
    case "operation":
        guard let value = classificationFilter(from: parts) else { return nil }
        return .operation(value)
    default:
        return nil
    }
}

private func referenceToken(_ dimension: ReferenceDimension, _ parts: [String]) -> FilterToken? {
    guard let value = referenceFilter(from: Array(parts.dropFirst())) else { return nil }
    return .reference(dimension, value)
}

private func referenceFilter(from parts: [String]) -> ReferenceFilter? {
    guard let kind = parts.first else { return nil }
    switch kind {
    case "catalog":
        guard parts.count >= 2 else { return nil }
        return .catalog(id: parts.dropFirst().joined(separator: "\u{1f}"), label: "")
    case "custom":
        guard parts.count >= 2 else { return nil }
        return .custom(text: parts.dropFirst().joined(separator: "\u{1f}"))
    case "unknown":
        return .unknown
    case "absent":
        return .absent
    default:
        return nil
    }
}

private func aircraftFilter(from parts: [String]) -> AircraftFilter? {
    guard parts.count >= 2 else { return nil }
    switch parts[1] {
    case "model":
        guard parts.count >= 3 else { return nil }
        return .model(id: parts.dropFirst(2).joined(separator: "\u{1f}"), label: "")
    case "family":
        guard parts.count >= 3 else { return nil }
        return .family(id: parts.dropFirst(2).joined(separator: "\u{1f}"), label: "")
    case "custom":
        guard parts.count >= 3 else { return nil }
        return .custom(text: parts.dropFirst(2).joined(separator: "\u{1f}"))
    case "unknown":
        return .unknown
    case "absent":
        return .absent
    default:
        return nil
    }
}

private func classificationFilter(from parts: [String]) -> ClassificationFilter? {
    guard parts.count >= 2 else { return nil }
    if parts[1] == "other" {
        let note = parts.count >= 3 ? parts.dropFirst(2).joined(separator: "\u{1f}") : ""
        return .other(note: note.isEmpty ? nil : note)
    }
    return .standard(id: parts.dropFirst().joined(separator: "\u{1f}"))
}

private func referenceChipSuffix(_ value: ReferenceFilter) -> String {
    switch value {
    case let .catalog(id, _):
        return "catalog\u{1f}\(id)"
    case let .custom(text):
        return "custom\u{1f}\(normalizeFilterName(text))"
    case .unknown:
        return "unknown"
    case .absent:
        return "absent"
    }
}

private func aircraftChipSuffix(_ value: AircraftFilter) -> String {
    switch value {
    case let .model(id, _):
        return "model\u{1f}\(id)"
    case let .family(id, _):
        return "family\u{1f}\(id)"
    case let .custom(text):
        return "custom\u{1f}\(normalizeFilterName(text))"
    case .unknown:
        return "unknown"
    case .absent:
        return "absent"
    }
}

private func classificationChipSuffix(_ value: ClassificationFilter) -> String {
    switch value {
    case let .standard(id):
        return id
    case let .other(note):
        let normalized = normalizeFilterName(note ?? "")
        return normalized.isEmpty ? "other" : "other\u{1f}\(normalized)"
    }
}

private func insertUnique<Value: Equatable>(_ values: inout [Value], _ value: Value) {
    if !values.contains(value) {
        values.append(value)
    }
}

private func chip(dimension: String, value: String, token: FilterToken) -> SpottingFilterChip {
    let label = "\(dimension): \(value)"
    return SpottingFilterChip(
        id: chipID(for: token),
        label: label,
        accessibilityLabel: "Remove \(label)",
        token: token
    )
}

private func referenceLabel(_ value: ReferenceFilter, absent: String) -> String {
    switch value {
    case .absent:
        return absent
    case .unknown:
        return "Unknown"
    case let .catalog(_, label):
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Catalog record" : trimmed
    case let .custom(text):
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func aircraftChip(_ value: AircraftFilter) -> SpottingFilterChip {
    let text: String
    switch value {
    case let .model(_, label):
        text = "Aircraft: \(shown(label))"
    case let .family(_, label):
        text = "Family: \(shown(label))"
    case let .custom(textValue):
        text = "Aircraft: \(textValue.trimmingCharacters(in: .whitespacesAndNewlines))"
    case .unknown:
        text = "Aircraft: Unknown"
    case .absent:
        text = "Aircraft: No aircraft specified"
    }
    return SpottingFilterChip(id: chipID(for: .aircraft(value)), label: text, accessibilityLabel: "Remove \(text)", token: .aircraft(value))
}

private func classificationChip(_ dimension: String, _ value: ClassificationFilter, labels: [String: String]) -> SpottingFilterChip {
    let text: String
    switch value {
    case let .standard(id):
        text = "\(dimension): \(labels[id] ?? id)"
    case let .other(note):
        if let note, !normalizeFilterName(note).isEmpty {
            text = "\(dimension): Other: \(note.trimmingCharacters(in: .whitespacesAndNewlines))"
        } else {
            text = "\(dimension): Other"
        }
    }
    let token: FilterToken = dimension == "Role" ? .role(value) : .operation(value)
    return SpottingFilterChip(id: chipID(for: token), label: text, accessibilityLabel: "Remove \(text)", token: token)
}

private func shown(_ label: String) -> String {
    let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Catalog record" : trimmed
}

private func dateRangeLabel(_ range: FilterDateRange) -> String {
    guard range.isValid else { return "End is before start" }
    switch (range.start, range.end) {
    case let (start?, end?):
        return "\(formatFilterDay(start)) – \(formatFilterDay(end))"
    case let (start?, nil):
        return "From \(formatFilterDay(start))"
    case let (nil, end?):
        return "Until \(formatFilterDay(end))"
    case (nil, nil):
        return "Any date"
    }
}

func formatFilterDay(_ day: FilterCalendarDay) -> String {
    let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    guard day.month >= 1, day.month <= 12 else {
        return "\(day.year)-\(day.month)-\(day.day)"
    }
    return "\(day.day) \(months[day.month - 1]) \(day.year)"
}
