import SwiftUI
import Foundation

struct SpottingEntry: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var photos: [Data]
    var registration: String
    var airline: String
    var location: String
    var aircraftType: String?
    var notes: String?
    var timestamp: Date
    
    // Computed property for backward compatibility
    var photo: Data {
        photos.first ?? Data()
    }
    
    init(id: UUID = UUID(), photos: [Data], registration: String, airline: String, location: String, aircraftType: String? = nil, notes: String? = nil, timestamp: Date = Date()) {
        self.id = id
        // Empty bytes are not photos. Callers that have no image yet keep an empty list.
        self.photos = photos.filter { !$0.isEmpty }
        self.registration = registration
        self.airline = airline
        self.location = location
        self.aircraftType = aircraftType
        self.notes = notes
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let decodedPhotos = try container.decodeIfPresent([Data].self, forKey: .photos) ?? []
        photos = decodedPhotos.filter { !$0.isEmpty }
        registration = try container.decode(String.self, forKey: .registration)
        airline = try container.decode(String.self, forKey: .airline)
        location = try container.decode(String.self, forKey: .location)
        aircraftType = try container.decodeIfPresent(String.self, forKey: .aircraftType)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
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
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case photos
        case registration
        case airline
        case location
        case aircraftType
        case notes
        case timestamp
    }
    
    // Convenience initializer for single photo (backward compatibility)
    init(id: UUID = UUID(), photo: Data, registration: String, airline: String, location: String, aircraftType: String? = nil, notes: String? = nil, timestamp: Date = Date()) {
        self.init(id: id, photos: [photo], registration: registration, airline: airline, location: location, aircraftType: aircraftType, notes: notes, timestamp: timestamp)
    }
}


