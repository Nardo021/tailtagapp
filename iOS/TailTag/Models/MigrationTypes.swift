import Foundation

/// Outcomes of reading the legacy Core Data store.
/// A missing file is not the same thing as a file that exists but cannot be read.
enum LegacyReadResult: Equatable {
    case absent
    case loaded([SourceSnapshot])
    case unreadable
    case readFailed
}

/// One legacy or local-store record before it is validated.
struct SourceSnapshot: Equatable, Sendable {
    var id: UUID?
    var registration: String?
    var airline: String?
    var location: String?
    var aircraftType: String?
    var notes: String?
    var timestamp: Date?
    var photos: [Data]

    init(
        id: UUID? = nil,
        registration: String? = nil,
        airline: String? = nil,
        location: String? = nil,
        aircraftType: String? = nil,
        notes: String? = nil,
        timestamp: Date? = nil,
        photos: [Data] = []
    ) {
        self.id = id
        self.registration = registration
        self.airline = airline
        self.location = location
        self.aircraftType = aircraftType
        self.notes = notes
        self.timestamp = timestamp
        self.photos = photos
    }
}

struct ValidatedSource: Equatable, Sendable {
    var id: UUID
    var registration: String
    var airline: String
    var location: String
    var aircraftType: String?
    var notes: String?
    var timestamp: Date
    var photos: [Data]
}

struct DestinationPhoto: Equatable, Sendable {
    var index: Int
    var data: Data
}

struct DestinationSnapshot: Equatable, Sendable {
    var id: UUID
    var registration: String
    var airline: String
    var location: String
    var aircraftType: String?
    var notes: String?
    var timestamp: Date
    var photos: [DestinationPhoto]

    init(
        id: UUID,
        registration: String,
        airline: String,
        location: String,
        aircraftType: String? = nil,
        notes: String? = nil,
        timestamp: Date,
        photos: [DestinationPhoto]
    ) {
        self.id = id
        self.registration = registration
        self.airline = airline
        self.location = location
        self.aircraftType = aircraftType
        self.notes = notes
        self.timestamp = timestamp
        self.photos = photos
    }

    init(source: ValidatedSource) {
        id = source.id
        registration = source.registration
        airline = source.airline
        location = source.location
        aircraftType = source.aircraftType
        notes = source.notes
        timestamp = source.timestamp
        photos = source.photos.enumerated().map { DestinationPhoto(index: $0.offset, data: $0.element) }
    }
}

enum MergePlan: Equatable, Sendable {
    case invalid
    case insert(ValidatedSource)
    case unchanged
    case addPhotos(id: UUID, photos: [DestinationPhoto])
    /// Destination is left untouched. `fields` names the conflicting parts and never includes values.
    case conflict(id: UUID, fields: [String])
}

struct MigrationPlanResult: Equatable, Sendable {
    var plans: [MergePlan]
    var shouldMarkComplete: Bool
    var conflictIDs: [UUID]
    var invalidCount: Int
    var duplicateDestinationIDs: [UUID]
}

enum CloudMigrationEligibility: Equatable, Sendable {
    case preferenceDisabled
    case localFallback
    case sameStore
    case sourceAbsent
    case sourceUnreadable
    case ready
}

struct CloudSourceInput: Equatable, Sendable {
    var exists: Bool
    var sameAsActive: Bool
    var openFailed: Bool
    var snapshots: [SourceSnapshot]
}

struct RecordedConflict: Codable, Equatable, Sendable {
    var id: String
    var fields: [String]
}

enum MigrationOutcome: Equatable, Sendable {
    case alreadyComplete
    case completed
    case incomplete(notice: String)
}

nonisolated protocol MigrationFlagStore: AnyObject {
    func bool(forKey key: String) -> Bool
    func set(_ value: Bool, forKey key: String)
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
}

nonisolated final class UserDefaultsMigrationFlags: MigrationFlagStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func bool(forKey key: String) -> Bool {
        defaults.bool(forKey: key)
    }

    func set(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    func set(_ value: String?, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}

nonisolated final class MemoryMigrationFlags: MigrationFlagStore {
    var bools: [String: Bool] = [:]
    var strings: [String: String] = [:]

    func bool(forKey key: String) -> Bool {
        bools[key] ?? false
    }

    func set(_ value: Bool, forKey key: String) {
        bools[key] = value
    }

    func string(forKey key: String) -> String? {
        strings[key]
    }

    func set(_ value: String?, forKey key: String) {
        if let value {
            strings[key] = value
        } else {
            strings.removeValue(forKey: key)
        }
    }
}

enum LegacyStoreFiles {
    static func sqliteURL(in directory: URL, name: String = "SpottingModel") -> URL {
        directory.appendingPathComponent("\(name).sqlite")
    }

    /// True when a store file or its SQLite sidecar is already on disk.
    /// Callers must use this before opening Core Data, because opening a missing store creates an empty one.
    static func exists(_ sqliteURL: URL, fileManager: FileManager = .default) -> Bool {
        let path = sqliteURL.path
        if fileManager.fileExists(atPath: path) {
            return true
        }
        if fileManager.fileExists(atPath: path + "-wal") {
            return true
        }
        return fileManager.fileExists(atPath: path + "-shm")
    }
}

enum MigrationPlanning {
    static func planMerge(source: SourceSnapshot, destination: DestinationSnapshot?) -> MergePlan {
        guard let id = source.id,
              let registration = source.registration,
              let airline = source.airline,
              let location = source.location,
              let timestamp = source.timestamp else {
            return .invalid
        }

        let photos = source.photos.filter { !$0.isEmpty }
        let validated = ValidatedSource(
            id: id,
            registration: registration,
            airline: airline,
            location: location,
            aircraftType: source.aircraftType,
            notes: source.notes,
            timestamp: timestamp,
            photos: photos
        )

        guard let destination else {
            return .insert(validated)
        }

        let metadataConflicts = conflictingMetadataFields(source: validated, destination: destination)
        if !metadataConflicts.isEmpty {
            return .conflict(id: id, fields: metadataConflicts)
        }

        switch planPhotos(source: photos, destination: destination.photos) {
        case .identical:
            return .unchanged
        case .pending:
            // Destination owns photo rows whose bytes have not arrived. Do not add a second copy.
            return .conflict(id: id, fields: ["photosPending"])
        case .different:
            return .conflict(id: id, fields: ["photos"])
        case .append(let photosToAdd):
            return .addPhotos(id: id, photos: photosToAdd)
        }
    }

    /// Plans a whole migration against a mutable destination index so a repeated UUID is not inserted twice.
    static func planMigration(
        sources: [SourceSnapshot],
        destinations: [DestinationSnapshot]
    ) -> MigrationPlanResult {
        var byID: [UUID: DestinationSnapshot] = [:]
        var duplicateDestinationIDs: [UUID] = []
        for destination in destinations {
            if byID[destination.id] != nil {
                duplicateDestinationIDs.append(destination.id)
            } else {
                byID[destination.id] = destination
            }
        }

        var plans: [MergePlan] = []
        for source in sources {
            let existing = source.id.flatMap { byID[$0] }
            let plan = planMerge(source: source, destination: existing)
            plans.append(plan)
            switch plan {
            case .insert(let validated):
                byID[validated.id] = DestinationSnapshot(source: validated)
            case .addPhotos(let id, let photos):
                if var current = byID[id] {
                    current.photos.append(contentsOf: photos)
                    byID[id] = current
                }
            case .invalid, .unchanged, .conflict:
                break
            }
        }

        let invalidCount = plans.reduce(into: 0) { count, plan in
            if case .invalid = plan {
                count += 1
            }
        }
        let conflictIDs = plans.compactMap { plan -> UUID? in
            if case .conflict(let id, _) = plan {
                return id
            }
            return nil
        }
        let uniqueConflicts = Array(Set(conflictIDs)).sorted { $0.uuidString < $1.uuidString }
        let shouldMarkComplete = invalidCount == 0 && uniqueConflicts.isEmpty && duplicateDestinationIDs.isEmpty
        return MigrationPlanResult(
            plans: plans,
            shouldMarkComplete: shouldMarkComplete,
            conflictIDs: uniqueConflicts,
            invalidCount: invalidCount,
            duplicateDestinationIDs: duplicateDestinationIDs
        )
    }

    static func cloudEligibility(
        preferenceEnabled: Bool,
        activeIsCloudBacked: Bool,
        sourceFileExists: Bool,
        sourceURLMatchesActive: Bool,
        sourceOpenFailed: Bool
    ) -> CloudMigrationEligibility {
        if !preferenceEnabled {
            return .preferenceDisabled
        }
        if !activeIsCloudBacked {
            return .localFallback
        }
        if sourceURLMatchesActive {
            return .sameStore
        }
        if sourceOpenFailed {
            return .sourceUnreadable
        }
        if !sourceFileExists {
            return .sourceAbsent
        }
        return .ready
    }

    static func conflicts(from plans: [MergePlan]) -> [RecordedConflict] {
        plans.compactMap { plan in
            guard case .conflict(let id, let fields) = plan else { return nil }
            return RecordedConflict(id: id.uuidString, fields: fields)
        }
    }

    static func encodeConflicts(_ conflicts: [RecordedConflict]) -> String? {
        guard !conflicts.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(conflicts)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func conflictingMetadataFields(
        source: ValidatedSource,
        destination: DestinationSnapshot
    ) -> [String] {
        var fields: [String] = []
        if destination.registration != source.registration {
            fields.append("registration")
        }
        if destination.airline != source.airline {
            fields.append("airline")
        }
        if destination.location != source.location {
            fields.append("location")
        }
        if (destination.aircraftType ?? "") != (source.aircraftType ?? "") {
            fields.append("aircraftType")
        }
        if (destination.notes ?? "") != (source.notes ?? "") {
            fields.append("notes")
        }
        if destination.timestamp != source.timestamp {
            fields.append("timestamp")
        }
        return fields.sorted()
    }

    private enum PhotoPlan {
        case identical
        case pending
        case different
        case append([DestinationPhoto])
    }

    private static func planPhotos(source: [Data], destination: [DestinationPhoto]) -> PhotoPlan {
        if source.isEmpty {
            return .identical
        }
        if destination.isEmpty {
            return .append(source.enumerated().map { DestinationPhoto(index: $0.offset, data: $0.element) })
        }
        if destination.contains(where: { $0.data.isEmpty }) {
            return .pending
        }

        let destinationByIndex = Dictionary(destination.map { ($0.index, $0.data) }, uniquingKeysWith: { first, _ in first })
        var toAdd: [DestinationPhoto] = []
        for (index, data) in source.enumerated() {
            if let existing = destinationByIndex[index] {
                if existing != data {
                    return .different
                }
            } else {
                toAdd.append(DestinationPhoto(index: index, data: data))
            }
        }
        if toAdd.isEmpty {
            return .identical
        }
        return .append(toAdd)
    }
}
