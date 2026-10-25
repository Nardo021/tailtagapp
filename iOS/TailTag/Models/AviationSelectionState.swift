import Combine
import Foundation
import SmartEntry
import SwiftUI

/// Editor state shared by the add and edit screens.
@MainActor
final class SpottingEditorModel: ObservableObject {
    @Published var registration: String
    @Published var reference: SpottingReferenceState
    @Published var notes: String
    @Published var timestamp: Date
    @Published var registrationFromPhoto = false
    @Published var registrationEdited: Bool
    @Published var operatorEdited: Bool
    @Published var pendingManufacturer: PendingManufacturerChange?

    struct PendingManufacturerChange: Identifiable {
        let id = UUID()
        var proposed: AviationSelection
        var restore: AviationSelection
    }

    init(entry: SpottingEntry? = nil) {
        if let entry {
            registration = entry.registration
            reference = entry.reference
            notes = entry.notes ?? ""
            timestamp = entry.timestamp
            registrationEdited = true
            operatorEdited = entry.reference.operatorField.kind != .absent
        } else {
            registration = ""
            reference = SpottingReferenceState()
            notes = ""
            timestamp = Date()
            registrationEdited = false
            operatorEdited = false
        }
    }

    func canSave(photoCount: Int) -> Bool {
        EntryRules.canSave(registration: registration, photoCount: photoCount, reference: reference)
    }

    func entry(id: UUID, photos: [Data]) -> SpottingEntry {
        SpottingEntry(
            id: id,
            photos: photos,
            registration: EntryRules.trimmedRegistration(registration),
            airline: reference.storedOperatorText,
            location: reference.storedLocationText,
            aircraftType: reference.storedAircraftText,
            notes: EntryRules.optionalNote(notes),
            timestamp: timestamp,
            reference: reference
        )
    }

    func editRegistration(_ value: String) {
        registration = value
        registrationEdited = true
        registrationFromPhoto = false
    }

    func commitOperator(_ selection: AviationSelection) {
        reference.operatorField = selection
        operatorEdited = true
    }

    func commitAircraft(_ aircraft: AviationSelection, linkedManufacturer: AviationSelection?) {
        let applied = EntryRulesAircraft.applyingAircraft(
            aircraft,
            currentManufacturer: reference.manufacturerField,
            linkedManufacturer: linkedManufacturer
        )
        reference.aircraftField = applied.aircraft
        reference.manufacturerField = applied.manufacturer
    }

    func proposeManufacturer(
        _ proposed: AviationSelection,
        aircraftManufacturerId: String?,
        aircraftManufacturerName: String?
    ) {
        let change = EntryRulesAircraft.proposeManufacturerChange(
            aircraft: reference.aircraftField,
            aircraftManufacturerId: aircraftManufacturerId,
            aircraftManufacturerName: aircraftManufacturerName,
            currentManufacturer: reference.manufacturerField,
            proposed: proposed
        )
        switch change {
        case .apply(let selection):
            reference.manufacturerField = selection
            pendingManufacturer = nil
        case .confirm(_, let proposed, let restore):
            pendingManufacturer = PendingManufacturerChange(proposed: proposed, restore: restore)
        }
    }

    func resolvePendingManufacturer(keepAircraft: Bool) {
        guard let pending = pendingManufacturer else { return }
        let resolved = EntryRulesAircraft.resolveConflict(
            keepAircraft: keepAircraft,
            proposed: pending.proposed,
            restore: pending.restore
        )
        if let aircraft = resolved.aircraft {
            reference.aircraftField = aircraft
        }
        reference.manufacturerField = resolved.manufacturer
        pendingManufacturer = nil
    }

    func cancelPendingManufacturer() {
        pendingManufacturer = nil
    }

    func commitLocation(_ selection: AviationSelection) {
        reference.locationField = selection
    }

    func commitRole(_ id: String?, note: String?) {
        reference.classification.roleId = id
        reference.classification.roleNote = note
        reference.classification = reference.classification.normalized()
    }

    func commitOperation(_ id: String?, note: String?) {
        reference.classification.operationTypeId = id
        reference.classification.operationTypeNote = note
        reference.classification = reference.classification.normalized()
    }

    func applyPhotoDetection(registration detectedRegistration: String?, airline detectedAirline: String?, confidence: Double) {
        let suggestion = PhotoTextSuggestion(
            registration: detectedRegistration,
            operatorText: detectedAirline,
            confidence: confidence
        )
        let registrationBefore = registration
        registration = PhotoSuggestions.applyRegistration(
            current: registration,
            userEdited: registrationEdited,
            suggestion: suggestion
        )
        if registration != registrationBefore {
            registrationFromPhoto = true
        }
        let updated = PhotoSuggestions.applyOperator(
            field: OperatorFieldState(selection: reference.operatorField, userEdited: operatorEdited),
            suggestion: suggestion
        )
        reference.operatorField = updated.selection
        operatorEdited = updated.userEdited
    }

    func reconcile(with catalog: AviationCatalogUIService) {
        reference.operatorField = reference.operatorField.reconciled(
            existsInCatalog: catalog.operatorExists(reference.operatorField.catalogId)
        )
        reference.manufacturerField = reference.manufacturerField.reconciled(
            existsInCatalog: catalog.manufacturerExists(reference.manufacturerField.catalogId)
        )
        reference.aircraftField = reference.aircraftField.reconciled(
            existsInCatalog: catalog.aircraftExists(reference.aircraftField.catalogId)
        )
        reference.locationField = reference.locationField.reconciled(
            existsInCatalog: catalog.airportExists(reference.locationField.catalogId)
        )
    }
}
