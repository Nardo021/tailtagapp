import AviationCatalog
import Foundation

public enum EntryFieldIssue: Equatable, Sendable {
    case registration
    case photos
    case `operator`
    case location
    case manufacturer
    case aircraft
}

public enum EntryRules {
    public static func registrationIsValid(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func trimmedRegistration(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func optionalNote(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func operatorIsValid(_ selection: AviationSelection) -> Bool {
        switch selection.kind {
        case .catalog:
            return selection.hasCatalogIdentity
        case .custom:
            return !selection.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .unknown, .absent:
            return true
        }
    }

    public static func locationIsValid(_ selection: AviationSelection) -> Bool {
        switch selection.kind {
        case .catalog:
            return selection.hasCatalogIdentity
                && !selection.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .custom:
            return !selection.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .unknown:
            return true
        case .absent:
            return false
        }
    }

    public static func optionalSelectionIsValid(_ selection: AviationSelection) -> Bool {
        switch selection.kind {
        case .catalog:
            return selection.hasCatalogIdentity
        case .custom:
            return !selection.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .unknown, .absent:
            return true
        }
    }

    public static func canSave(
        registration: String,
        photoCount: Int,
        reference: SpottingReferenceState
    ) -> Bool {
        issues(registration: registration, photoCount: photoCount, reference: reference).isEmpty
    }

    public static func issues(
        registration: String,
        photoCount: Int,
        reference: SpottingReferenceState
    ) -> [EntryFieldIssue] {
        var issues: [EntryFieldIssue] = []
        if !registrationIsValid(registration) {
            issues.append(.registration)
        }
        if photoCount < 1 {
            issues.append(.photos)
        }
        if !operatorIsValid(reference.operatorField) {
            issues.append(.operator)
        }
        if !locationIsValid(reference.locationField) {
            issues.append(.location)
        }
        if !optionalSelectionIsValid(reference.manufacturerField) {
            issues.append(.manufacturer)
        }
        if !optionalSelectionIsValid(reference.aircraftField) {
            issues.append(.aircraft)
        }
        return issues
    }
}

public struct ManufacturerConflict: Equatable, Sendable {
    public var aircraftId: String
    public var aircraftManufacturerId: String
    public var proposedManufacturerId: String?

    public init(aircraftId: String, aircraftManufacturerId: String, proposedManufacturerId: String?) {
        self.aircraftId = aircraftId
        self.aircraftManufacturerId = aircraftManufacturerId
        self.proposedManufacturerId = proposedManufacturerId
    }
}

public enum ManufacturerChange: Equatable, Sendable {
    case apply(AviationSelection)
    case confirm(ManufacturerConflict, proposed: AviationSelection, restore: AviationSelection)
}

public enum EntryRulesAircraft {
    /// Selecting an aircraft with a verified manufacturer updates the manufacturer field.
    /// An aircraft with no manufacturer id leaves the manufacturer field as it was.
    public static func applyingAircraft(
        _ aircraft: AviationSelection,
        currentManufacturer: AviationSelection,
        linkedManufacturer: AviationSelection?
    ) -> (aircraft: AviationSelection, manufacturer: AviationSelection) {
        guard aircraft.kind == .catalog, let linkedManufacturer, linkedManufacturer.hasCatalogIdentity else {
            return (aircraft, currentManufacturer)
        }
        return (aircraft, linkedManufacturer)
    }

    public static func proposeManufacturerChange(
        aircraft: AviationSelection,
        aircraftManufacturerId: String?,
        aircraftManufacturerName: String?,
        currentManufacturer: AviationSelection,
        proposed: AviationSelection
    ) -> ManufacturerChange {
        guard aircraft.kind == .catalog,
              let aircraftId = aircraft.catalogId,
              !aircraftId.isEmpty,
              let known = cleanedIdentifier(aircraftManufacturerId) else {
            return .apply(proposed)
        }
        let proposedId = proposed.kind == .catalog ? cleanedIdentifier(proposed.catalogId) : nil
        if proposed.kind == .catalog && proposedId == known {
            return .apply(proposed)
        }
        let conflict = ManufacturerConflict(
            aircraftId: aircraftId,
            aircraftManufacturerId: known,
            proposedManufacturerId: proposedId
        )
        let restoreName = currentManufacturer.kind == .catalog && currentManufacturer.catalogId == known
            ? currentManufacturer.displayText
            : (cleanedIdentifier(aircraftManufacturerName) ?? known)
        let restore = AviationSelection.catalog(id: known, displayText: restoreName)
        return .confirm(conflict, proposed: proposed, restore: restore)
    }

    public static func resolveConflict(
        keepAircraft: Bool,
        proposed: AviationSelection,
        restore: AviationSelection
    ) -> (aircraft: AviationSelection?, manufacturer: AviationSelection) {
        if keepAircraft {
            return (nil, restore)
        }
        return (.absent, proposed)
    }
}

public struct PhotoTextSuggestion: Equatable, Sendable {
    public var registration: String?
    public var operatorText: String?
    public var confidence: Double

    public init(registration: String?, operatorText: String?, confidence: Double) {
        self.registration = registration
        self.operatorText = operatorText
        self.confidence = confidence
    }
}

public struct OperatorFieldState: Equatable, Sendable {
    public var selection: AviationSelection
    public var userEdited: Bool

    public init(selection: AviationSelection, userEdited: Bool) {
        self.selection = selection
        self.userEdited = userEdited
    }
}

public enum PhotoSuggestions {
    public static let minimumConfidence = 0.6

    public static func applyRegistration(
        current: String,
        userEdited: Bool,
        suggestion: PhotoTextSuggestion
    ) -> String {
        guard !userEdited,
              suggestion.confidence > minimumConfidence,
              let detected = suggestion.registration?.trimmingCharacters(in: .whitespacesAndNewlines),
              !detected.isEmpty,
              current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return current
        }
        return detected
    }

    /// Photo text can fill an empty operator field. It never selects a catalog id,
    /// and it does not replace a value the user or a previous save already set.
    public static func applyOperator(
        field: OperatorFieldState,
        suggestion: PhotoTextSuggestion
    ) -> OperatorFieldState {
        guard suggestion.confidence > minimumConfidence,
              let detected = suggestion.operatorText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !detected.isEmpty,
              !field.userEdited,
              field.selection.kind == .absent else {
            return field
        }
        var selection = AviationSelection(kind: .custom, displayText: detected, suggestedFromPhoto: true)
        selection.suggestedFromPhoto = true
        return OperatorFieldState(selection: selection, userEdited: false)
    }
}

public func aircraftKindLabel(_ entryKind: String) -> String {
    switch entryKind {
    case "model":
        return "Model"
    case "family":
        return "Family"
    case "unspecified":
        return "Unspecified"
    default:
        return entryKind
    }
}

public func officialDesignatorText(_ codes: [String]) -> String? {
    let cleaned = codes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    guard !cleaned.isEmpty else { return nil }
    return cleaned.joined(separator: ", ")
}

public func aircraftSelection(from model: AircraftModel) -> AviationSelection {
    AviationSelection.catalog(
        id: model.id,
        displayText: model.displayName,
        detail: aircraftKindLabel(model.entryKind)
    )
}

public func linkedManufacturerSelection(from model: AircraftModel) -> AviationSelection? {
    guard let id = cleanedIdentifier(model.manufacturerId) else { return nil }
    let name = cleanedIdentifier(model.manufacturer) ?? model.manufacturerNames.first { cleanedIdentifier($0) != nil }
    guard let name, let cleanedName = cleanedIdentifier(name) else { return nil }
    return .catalog(id: id, displayText: cleanedName)
}

public func classificationUnchanged(
    byAircraftSelection classification: ClassificationChoice
) -> ClassificationChoice {
    classification
}
