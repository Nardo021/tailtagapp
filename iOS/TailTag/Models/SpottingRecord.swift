import SwiftData
import Foundation

@Model
final class SpottingRecord {
    var id: UUID = UUID()
    var registration: String = ""
    var airline: String = ""
    var location: String = ""
    var aircraftType: String? = nil
    var notes: String? = nil
    var timestamp: Date = Date()

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
            timestamp: timestamp
        )
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
