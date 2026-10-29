import Foundation
import SmartEntry
import SwiftData

@Model
final class SpottingRecord {
    var id: UUID = UUID()
    var registration: String = ""
    var airline: String = ""
    var location: String = ""
    var aircraftType: String? = nil
    var notes: String? = nil
    var timestamp: Date = Date()
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

    @Relationship(deleteRule: .cascade)
    var photoRecords: [PhotoRecord] = []

    init(
        id: UUID = UUID(),
        registration: String = "",
        airline: String = "",
        location: String = "",
        aircraftType: String? = nil,
        notes: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.registration = registration
        self.airline = airline
        self.location = location
        self.aircraftType = aircraftType
        self.notes = notes
        self.timestamp = timestamp
    }

    var photos: [Data] {
        photoRecords.sorted { $0.index < $1.index }.compactMap {
            $0.data.isEmpty ? nil : $0.data
        }
    }

    var asEntry: SpottingEntry {
        // Missing photo bytes stay missing. A placeholder Data value would count as a real photo
        // and can hide records whose CloudKit attachments have not been downloaded yet.
        SpottingEntry(
            id: id,
            photos: photos,
            registration: registration,
            airline: airline,
            location: location,
            aircraftType: aircraftType,
            notes: notes,
            timestamp: timestamp,
            reference: referenceState()
        )
    }

    func referenceState() -> SpottingReferenceState {
        PersistedSpottingReference(
            operatorField: PersistedAviationField(
                kind: operatorSelectionKind,
                catalogId: operatorCatalogId,
                text: airline
            ),
            manufacturerField: PersistedAviationField(
                kind: manufacturerSelectionKind,
                catalogId: manufacturerCatalogId,
                text: manufacturerName ?? ""
            ),
            aircraftField: PersistedAviationField(
                kind: aircraftSelectionKind,
                catalogId: aircraftCatalogId,
                text: aircraftType ?? "",
                detail: aircraftEntryKind
            ),
            locationField: PersistedAviationField(
                kind: locationSelectionKind,
                catalogId: airportCatalogId,
                text: location
            ),
            classification: ClassificationChoice(
                roleId: aircraftRoleId,
                roleNote: aircraftRoleNote,
                operationTypeId: operationTypeId,
                operationTypeNote: operationTypeNote
            )
        ).restored()
    }

    func applyReference(_ reference: SpottingReferenceState) {
        let stored = reference.forStorage()
        airline = stored.operatorField.text
        operatorSelectionKind = stored.operatorField.kind
        operatorCatalogId = stored.operatorField.catalogId
        manufacturerName = stored.manufacturerField.text.isEmpty ? nil : stored.manufacturerField.text
        manufacturerSelectionKind = stored.manufacturerField.kind
        manufacturerCatalogId = stored.manufacturerField.catalogId
        aircraftType = stored.aircraftField.text.isEmpty ? nil : stored.aircraftField.text
        aircraftSelectionKind = stored.aircraftField.kind
        aircraftCatalogId = stored.aircraftField.catalogId
        aircraftEntryKind = stored.aircraftField.detail
        location = stored.locationField.text
        locationSelectionKind = stored.locationField.kind
        airportCatalogId = stored.locationField.catalogId
        aircraftRoleId = stored.classification.roleId
        aircraftRoleNote = stored.classification.roleNote
        operationTypeId = stored.classification.operationTypeId
        operationTypeNote = stored.classification.operationTypeNote
    }

    func migratedReference() -> MigratedReference {
        MigratedReference(
            operatorCatalogId: operatorCatalogId,
            operatorSelectionKind: operatorSelectionKind,
            manufacturerName: manufacturerName,
            manufacturerCatalogId: manufacturerCatalogId,
            manufacturerSelectionKind: manufacturerSelectionKind,
            aircraftCatalogId: aircraftCatalogId,
            aircraftSelectionKind: aircraftSelectionKind,
            aircraftEntryKind: aircraftEntryKind,
            airportCatalogId: airportCatalogId,
            locationSelectionKind: locationSelectionKind,
            aircraftRoleId: aircraftRoleId,
            aircraftRoleNote: aircraftRoleNote,
            operationTypeId: operationTypeId,
            operationTypeNote: operationTypeNote
        )
    }

    func applyMigratedReference(_ reference: MigratedReference) {
        operatorCatalogId = reference.operatorCatalogId
        operatorSelectionKind = reference.operatorSelectionKind
        manufacturerName = reference.manufacturerName
        manufacturerCatalogId = reference.manufacturerCatalogId
        manufacturerSelectionKind = reference.manufacturerSelectionKind
        aircraftCatalogId = reference.aircraftCatalogId
        aircraftSelectionKind = reference.aircraftSelectionKind
        aircraftEntryKind = reference.aircraftEntryKind
        airportCatalogId = reference.airportCatalogId
        locationSelectionKind = reference.locationSelectionKind
        aircraftRoleId = reference.aircraftRoleId
        aircraftRoleNote = reference.aircraftRoleNote
        operationTypeId = reference.operationTypeId
        operationTypeNote = reference.operationTypeNote
    }

    func fillMigratedReference(_ reference: MigratedReference) -> Bool {
        var changed = false
        func fill(_ current: inout String?, _ incoming: String?) {
            let trimmed = incoming?.trimmingCharacters(in: .whitespacesAndNewlines)
            let currentBlank = current?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
            guard currentBlank, let trimmed, !trimmed.isEmpty else { return }
            current = trimmed
            changed = true
        }
        fill(&operatorCatalogId, reference.operatorCatalogId)
        fill(&operatorSelectionKind, reference.operatorSelectionKind)
        fill(&manufacturerName, reference.manufacturerName)
        fill(&manufacturerCatalogId, reference.manufacturerCatalogId)
        fill(&manufacturerSelectionKind, reference.manufacturerSelectionKind)
        fill(&aircraftCatalogId, reference.aircraftCatalogId)
        fill(&aircraftSelectionKind, reference.aircraftSelectionKind)
        fill(&aircraftEntryKind, reference.aircraftEntryKind)
        fill(&airportCatalogId, reference.airportCatalogId)
        fill(&locationSelectionKind, reference.locationSelectionKind)
        fill(&aircraftRoleId, reference.aircraftRoleId)
        fill(&aircraftRoleNote, reference.aircraftRoleNote)
        fill(&operationTypeId, reference.operationTypeId)
        fill(&operationTypeNote, reference.operationTypeNote)
        return changed
    }

    func copyCatalogFields(from other: SpottingRecord) {
        operatorCatalogId = other.operatorCatalogId
        operatorSelectionKind = other.operatorSelectionKind
        manufacturerName = other.manufacturerName
        manufacturerCatalogId = other.manufacturerCatalogId
        manufacturerSelectionKind = other.manufacturerSelectionKind
        aircraftCatalogId = other.aircraftCatalogId
        aircraftSelectionKind = other.aircraftSelectionKind
        aircraftEntryKind = other.aircraftEntryKind
        airportCatalogId = other.airportCatalogId
        locationSelectionKind = other.locationSelectionKind
        aircraftRoleId = other.aircraftRoleId
        aircraftRoleNote = other.aircraftRoleNote
        operationTypeId = other.operationTypeId
        operationTypeNote = other.operationTypeNote
    }
}

@Model
final class PhotoRecord {
    @Attribute(.externalStorage) var data: Data = Data()
    var index: Int = 0
    var spotting: SpottingRecord? = nil

    init(data: Data = Data(), index: Int = 0) {
        self.data = data
        self.index = index
    }
}
