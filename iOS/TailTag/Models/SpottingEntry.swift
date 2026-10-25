import Foundation
import SmartEntry

struct SpottingEntry: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var photos: [Data]
    var registration: String
    var airline: String
    var location: String
    var aircraftType: String?
    var notes: String?
    var timestamp: Date
    var reference: SpottingReferenceState

    var photo: Data {
        photos.first ?? Data()
    }

    init(
        id: UUID = UUID(),
        photos: [Data],
        registration: String,
        airline: String,
        location: String,
        aircraftType: String? = nil,
        notes: String? = nil,
        timestamp: Date = Date(),
        reference: SpottingReferenceState? = nil
    ) {
        self.id = id
        self.photos = photos.isEmpty ? [Data()] : photos
        self.registration = registration
        self.notes = notes
        self.timestamp = timestamp
        let resolved = reference ?? SpottingReferenceState.legacy(
            airline: airline,
            location: location,
            aircraftType: aircraftType
        )
        let stored = resolved.forStorage().restored()
        self.reference = stored
        self.airline = stored.storedOperatorText
        self.location = stored.storedLocationText
        self.aircraftType = stored.storedAircraftText
    }

    init(
        id: UUID = UUID(),
        photo: Data,
        registration: String,
        airline: String,
        location: String,
        aircraftType: String? = nil,
        notes: String? = nil,
        timestamp: Date = Date(),
        reference: SpottingReferenceState? = nil
    ) {
        self.init(
            id: id,
            photos: [photo],
            registration: registration,
            airline: airline,
            location: location,
            aircraftType: aircraftType,
            notes: notes,
            timestamp: timestamp,
            reference: reference
        )
    }

    func replacingReference(_ reference: SpottingReferenceState) -> SpottingEntry {
        var copy = self
        let stored = reference.forStorage().restored()
        copy.reference = stored
        copy.airline = stored.storedOperatorText
        copy.location = stored.storedLocationText
        copy.aircraftType = stored.storedAircraftText
        return copy
    }
}

extension SpottingEntry {
    private enum CodingKeys: String, CodingKey {
        case id
        case photos
        case registration
        case airline
        case location
        case aircraftType
        case notes
        case timestamp
        case operatorCatalogId
        case operatorSelectionKind
        case manufacturerName
        case manufacturerCatalogId
        case manufacturerSelectionKind
        case aircraftCatalogId
        case aircraftSelectionKind
        case aircraftEntryKind
        case airportCatalogId
        case locationSelectionKind
        case aircraftRoleId
        case aircraftRoleNote
        case operationTypeId
        case operationTypeNote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let airline = try container.decode(String.self, forKey: .airline)
        let location = try container.decode(String.self, forKey: .location)
        let aircraftType = try container.decodeIfPresent(String.self, forKey: .aircraftType)
        let persisted = PersistedSpottingReference(
            operatorField: PersistedAviationField(
                kind: try container.decodeIfPresent(String.self, forKey: .operatorSelectionKind),
                catalogId: try container.decodeIfPresent(String.self, forKey: .operatorCatalogId),
                text: airline
            ),
            manufacturerField: PersistedAviationField(
                kind: try container.decodeIfPresent(String.self, forKey: .manufacturerSelectionKind),
                catalogId: try container.decodeIfPresent(String.self, forKey: .manufacturerCatalogId),
                text: try container.decodeIfPresent(String.self, forKey: .manufacturerName) ?? ""
            ),
            aircraftField: PersistedAviationField(
                kind: try container.decodeIfPresent(String.self, forKey: .aircraftSelectionKind),
                catalogId: try container.decodeIfPresent(String.self, forKey: .aircraftCatalogId),
                text: aircraftType ?? "",
                detail: try container.decodeIfPresent(String.self, forKey: .aircraftEntryKind)
            ),
            locationField: PersistedAviationField(
                kind: try container.decodeIfPresent(String.self, forKey: .locationSelectionKind),
                catalogId: try container.decodeIfPresent(String.self, forKey: .airportCatalogId),
                text: location
            ),
            classification: ClassificationChoice(
                roleId: try container.decodeIfPresent(String.self, forKey: .aircraftRoleId),
                roleNote: try container.decodeIfPresent(String.self, forKey: .aircraftRoleNote),
                operationTypeId: try container.decodeIfPresent(String.self, forKey: .operationTypeId),
                operationTypeNote: try container.decodeIfPresent(String.self, forKey: .operationTypeNote)
            )
        )
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            photos: try container.decodeIfPresent([Data].self, forKey: .photos) ?? [],
            registration: try container.decode(String.self, forKey: .registration),
            airline: airline,
            location: location,
            aircraftType: aircraftType,
            notes: try container.decodeIfPresent(String.self, forKey: .notes),
            timestamp: try container.decode(Date.self, forKey: .timestamp),
            reference: persisted.restored()
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(photos, forKey: .photos)
        try container.encode(registration, forKey: .registration)
        try container.encode(airline, forKey: .airline)
        try container.encode(location, forKey: .location)
        try container.encodeIfPresent(aircraftType, forKey: .aircraftType)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(timestamp, forKey: .timestamp)
        let stored = reference.forStorage()
        try container.encodeIfPresent(stored.operatorField.kind, forKey: .operatorSelectionKind)
        try container.encodeIfPresent(stored.operatorField.catalogId, forKey: .operatorCatalogId)
        let manufacturer = stored.manufacturerField.text
        if !manufacturer.isEmpty {
            try container.encode(manufacturer, forKey: .manufacturerName)
        }
        try container.encodeIfPresent(stored.manufacturerField.kind, forKey: .manufacturerSelectionKind)
        try container.encodeIfPresent(stored.manufacturerField.catalogId, forKey: .manufacturerCatalogId)
        try container.encodeIfPresent(stored.aircraftField.kind, forKey: .aircraftSelectionKind)
        try container.encodeIfPresent(stored.aircraftField.catalogId, forKey: .aircraftCatalogId)
        try container.encodeIfPresent(stored.aircraftField.detail, forKey: .aircraftEntryKind)
        try container.encodeIfPresent(stored.locationField.kind, forKey: .locationSelectionKind)
        try container.encodeIfPresent(stored.locationField.catalogId, forKey: .airportCatalogId)
        try container.encodeIfPresent(stored.classification.roleId, forKey: .aircraftRoleId)
        try container.encodeIfPresent(stored.classification.roleNote, forKey: .aircraftRoleNote)
        try container.encodeIfPresent(stored.classification.operationTypeId, forKey: .operationTypeId)
        try container.encodeIfPresent(stored.classification.operationTypeNote, forKey: .operationTypeNote)
    }
}
