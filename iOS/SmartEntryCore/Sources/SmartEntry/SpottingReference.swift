import Foundation

public struct ClassificationChoice: Equatable, Hashable, Sendable, Codable {
    public var roleId: String?
    public var roleNote: String?
    public var operationTypeId: String?
    public var operationTypeNote: String?

    public init(
        roleId: String? = nil,
        roleNote: String? = nil,
        operationTypeId: String? = nil,
        operationTypeNote: String? = nil
    ) {
        self.roleId = roleId
        self.roleNote = roleNote
        self.operationTypeId = operationTypeId
        self.operationTypeNote = operationTypeNote
    }

    public static let unset = ClassificationChoice()

    /// Drops a custom note when the matching dimension is no longer "other".
    /// Does not invent a role or operation from any other field.
    public func normalized() -> ClassificationChoice {
        var copy = self
        copy.roleId = cleanedIdentifier(roleId)
        copy.operationTypeId = cleanedIdentifier(operationTypeId)
        copy.roleNote = copy.roleId == "other" ? cleanedNote(roleNote) : nil
        copy.operationTypeNote = copy.operationTypeId == "other" ? cleanedNote(operationTypeNote) : nil
        return copy
    }
}

public struct SpottingReferenceState: Equatable, Hashable, Sendable, Codable {
    public var operatorField: AviationSelection
    public var manufacturerField: AviationSelection
    public var aircraftField: AviationSelection
    public var locationField: AviationSelection
    public var classification: ClassificationChoice

    public init(
        operatorField: AviationSelection = .absent,
        manufacturerField: AviationSelection = .absent,
        aircraftField: AviationSelection = .absent,
        locationField: AviationSelection = .absent,
        classification: ClassificationChoice = .unset
    ) {
        self.operatorField = operatorField
        self.manufacturerField = manufacturerField
        self.aircraftField = aircraftField
        self.locationField = locationField
        self.classification = classification
    }

    public static func legacy(
        airline: String,
        location: String,
        aircraftType: String?,
        manufacturer: String? = nil
    ) -> SpottingReferenceState {
        SpottingReferenceState(
            operatorField: .legacy(text: airline),
            manufacturerField: .legacy(text: manufacturer ?? ""),
            aircraftField: .legacy(text: aircraftType ?? ""),
            locationField: .legacy(text: location),
            classification: .unset
        )
    }

    public var storedOperatorText: String {
        PersistedAviationField(selection: operatorField).text
    }

    public var storedLocationText: String {
        PersistedAviationField(selection: locationField).text
    }

    public var storedAircraftText: String? {
        let text = PersistedAviationField(selection: aircraftField).text
        return text.isEmpty ? nil : text
    }

    public var storedManufacturerText: String? {
        let text = PersistedAviationField(selection: manufacturerField).text
        return text.isEmpty ? nil : text
    }

    public func forStorage() -> PersistedSpottingReference {
        PersistedSpottingReference(
            operatorField: PersistedAviationField(selection: operatorField),
            manufacturerField: PersistedAviationField(selection: manufacturerField),
            aircraftField: PersistedAviationField(selection: aircraftField),
            locationField: PersistedAviationField(selection: locationField),
            classification: classification.normalized()
        )
    }
}

public struct PersistedSpottingReference: Equatable, Hashable, Sendable, Codable {
    public var operatorField: PersistedAviationField
    public var manufacturerField: PersistedAviationField
    public var aircraftField: PersistedAviationField
    public var locationField: PersistedAviationField
    public var classification: ClassificationChoice

    public init(
        operatorField: PersistedAviationField,
        manufacturerField: PersistedAviationField,
        aircraftField: PersistedAviationField,
        locationField: PersistedAviationField,
        classification: ClassificationChoice
    ) {
        self.operatorField = operatorField
        self.manufacturerField = manufacturerField
        self.aircraftField = aircraftField
        self.locationField = locationField
        self.classification = classification
    }

    public func restored() -> SpottingReferenceState {
        SpottingReferenceState(
            operatorField: operatorField.selection(),
            manufacturerField: manufacturerField.selection(),
            aircraftField: aircraftField.selection(),
            locationField: locationField.selection(),
            classification: classification
        )
    }
}

public func classificationSummary(id: String?, note: String?, labels: [String: String]) -> String? {
    guard let id = cleanedIdentifier(id) else { return nil }
    let label = labels[id] ?? id
    if id == "other", let note = cleanedNote(note) {
        return "\(label): \(note)"
    }
    return label
}

func cleanedIdentifier(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

func cleanedNote(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
