import Combine
import CoreData
import Foundation
import SwiftData
import SwiftUI

enum SpottingPersistenceError: LocalizedError {
    case saveFailed
    case recordNotFound

    var errorDescription: String? {
        switch self {
        case .saveFailed:
            return "The spotting could not be saved. Nothing was changed."
        case .recordNotFound:
            return "That spotting is no longer in the saved log."
        }
    }
}

protocol SpottingIndexing {
    func index(_ entry: SpottingEntry) async
    func delete(id: UUID) async
    func deleteAll() async
}

struct LiveSpottingIndexer: SpottingIndexing {
    func index(_ entry: SpottingEntry) async {
        await TailTagSpotlightIndexer.index(entry)
    }

    func delete(id: UUID) async {
        await TailTagSpotlightIndexer.deleteSpotting(with: id)
    }

    func deleteAll() async {
        await TailTagSpotlightIndexer.deleteAllSpottingEntries()
    }
}

protocol EntryLoading {
    func fetchEntries() async throws -> [SpottingEntry]
}

struct ModelContainerEntryLoader: EntryLoading {
    let container: ModelContainer

    func fetchEntries() async throws -> [SpottingEntry] {
        let reader = SpottingRecordReader(modelContainer: container)
        return try await reader.fetchEntries()
    }
}

@ModelActor
actor SpottingRecordReader {
    func fetchEntries() throws -> [SpottingEntry] {
        modelContext.autosaveEnabled = false
        let descriptor = FetchDescriptor<SpottingRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let records = try modelContext.fetch(descriptor)
        return records.map(\.asEntry)
    }
}

@MainActor
class SpottingStore: ObservableObject {
    @Published var entries: [SpottingEntry] = []
    @Published var lastCloudKitSync: Date? = nil
    @Published var userNotice: String?

    private var loadTask: Task<Void, Never>?
    private var needsReload = false
    private var loadGeneration = 0
    private var noticeSignatures: Set<String> = []

    let modelContext: ModelContext
    private let spotlight: any SpottingIndexing
    private let entryLoader: any EntryLoading
    /// Test hook. Production saves go through `ModelContext.save()`.
    var persistImplementation: ((ModelContext) throws -> Void)?
    var lastIndexTask: Task<Void, Never>?

    var modelContextForMigration: ModelContext { modelContext }

    init(
        modelContext: ModelContext? = nil,
        spotlight: (any SpottingIndexing)? = nil,
        entryLoader: (any EntryLoading)? = nil
    ) {
        let resolvedContext = modelContext ?? ModelContainer.tailTag.mainContext
        resolvedContext.autosaveEnabled = false
        self.modelContext = resolvedContext
        self.spotlight = spotlight ?? LiveSpottingIndexer()
        self.entryLoader = entryLoader ?? ModelContainerEntryLoader(container: resolvedContext.container)
        loadEntries()

        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loadEntries()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if event.type == .import && event.endDate != nil {
                    self.lastCloudKitSync = event.endDate
                    self.loadEntries()
                }
            }
        }
    }

    func presentNotice(_ message: String, signature: String) {
        guard noticeSignatures.insert(signature).inserted else { return }
        userNotice = message
    }

    // MARK: - Load

    func loadEntries() {
        loadGeneration += 1
        needsReload = true
        guard loadTask == nil else { return }

        loadTask = Task { [weak self] in
            guard let self else { return }
            defer { self.loadTask = nil }

            while self.needsReload {
                self.needsReload = false
                let generation = self.loadGeneration
                do {
                    let loadedEntries = try await self.entryLoader.fetchEntries()
                    // An older fetch must not replace a snapshot requested after it started.
                    if !self.needsReload && generation == self.loadGeneration {
                        self.entries = loadedEntries
                    }
                } catch {
                    // Keep the last successful snapshot. A failed refresh is not an empty log.
                }
            }
        }
    }

    private func persist() throws {
        do {
            if let persistImplementation {
                try persistImplementation(modelContext)
            } else {
                try modelContext.save()
            }
        } catch {
            modelContext.rollback()
            throw SpottingPersistenceError.saveFailed
        }
    }

    // MARK: - Image Compression

    nonisolated static func compressImageData(_ data: Data, maxSizeKB: Int = 800) -> Data {
        PhotoByteCompressor.compress(data, maxSizeKB: maxSizeKB)
    }

    // MARK: - CRUD

    func addEntry(_ entry: SpottingEntry) throws {
        let record = SpottingRecord(
            id: entry.id,
            registration: entry.registration,
            airline: entry.airline,
            location: entry.location,
            aircraftType: entry.aircraftType,
            notes: entry.notes,
            timestamp: entry.timestamp
        )
        modelContext.insert(record)

        for (index, photoData) in entry.photos.enumerated() where !photoData.isEmpty {
            let photo = PhotoRecord(data: SpottingStore.compressImageData(photoData), index: index)
            record.photoRecords.append(photo)
            modelContext.insert(photo)
        }

        try persist()
        loadEntries()
        let saved = entry
        lastIndexTask = Task {
            await spotlight.index(saved)
        }
    }

    func deleteEntry(_ entry: SpottingEntry) throws {
        let id = entry.id
        let descriptor = FetchDescriptor<SpottingRecord>(
            predicate: #Predicate { $0.id == id }
        )
        let matches = try modelContext.fetch(descriptor)
        guard let record = matches.first else {
            throw SpottingPersistenceError.recordNotFound
        }
        // External photo bytes stay as future backing data until read. Rollback after a
        // failed delete snapshots that placeholder and aborts.
        for photo in record.photoRecords {
            _ = photo.data
        }
        modelContext.delete(record)
        try persist()
        loadEntries()
        lastIndexTask = Task {
            await spotlight.delete(id: id)
        }
    }

    func deleteSpotting(_ spotting: SpottingEntry) throws {
        try deleteEntry(spotting)
    }

    func updateSpotting(_ updatedSpotting: SpottingEntry) throws {
        let id = updatedSpotting.id
        let descriptor = FetchDescriptor<SpottingRecord>(
            predicate: #Predicate { $0.id == id }
        )
        let matches = try modelContext.fetch(descriptor)
        guard let record = matches.first else {
            throw SpottingPersistenceError.recordNotFound
        }
        record.registration = updatedSpotting.registration
        record.airline = updatedSpotting.airline
        record.location = updatedSpotting.location
        record.aircraftType = updatedSpotting.aircraftType
        record.notes = updatedSpotting.notes
        record.timestamp = updatedSpotting.timestamp

        for photo in record.photoRecords {
            _ = photo.data
            modelContext.delete(photo)
        }
        record.photoRecords.removeAll()

        for (index, photoData) in updatedSpotting.photos.enumerated() where !photoData.isEmpty {
            let photo = PhotoRecord(
                data: SpottingStore.compressImageData(photoData),
                index: index
            )
            record.photoRecords.append(photo)
            modelContext.insert(photo)
        }

        try persist()
        loadEntries()
        let saved = updatedSpotting
        lastIndexTask = Task {
            await spotlight.index(saved)
        }
    }

    func clearAllEntries() throws {
        let records = try modelContext.fetch(FetchDescriptor<SpottingRecord>())
        for record in records {
            for photo in record.photoRecords {
                _ = photo.data
            }
            modelContext.delete(record)
        }
        try persist()
        loadEntries()
        lastIndexTask = Task {
            await spotlight.deleteAll()
        }
    }

    func waitUntilIdle() async {
        while loadTask != nil {
            await Task.yield()
        }
    }

    // MARK: - Filtering / Sorting

    func filteredEntries(searchText: String) -> [SpottingEntry] {
        guard !searchText.isEmpty else { return entries }
        return entries.filter { entry in
            entry.registration.localizedCaseInsensitiveContains(searchText) ||
            entry.airline.localizedCaseInsensitiveContains(searchText) ||
            entry.location.localizedCaseInsensitiveContains(searchText) ||
            (entry.aircraftType?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var mostRecentEntries: [SpottingEntry] {
        entries.sorted { $0.timestamp > $1.timestamp }
    }

    func sortedEntries(by sortOption: SortOption) -> [SpottingEntry] {
        sortEntries(entries, by: sortOption)
    }

    func filteredAndSortedEntries(searchText: String, sortOption: SortOption) -> [SpottingEntry] {
        sortEntries(filteredEntries(searchText: searchText), by: sortOption)
    }

    private func sortEntries(_ entries: [SpottingEntry], by sortOption: SortOption) -> [SpottingEntry] {
        switch sortOption {
        case .dateNewest:
            return entries.sorted { $0.timestamp > $1.timestamp }
        case .dateOldest:
            return entries.sorted { $0.timestamp < $1.timestamp }
        case .aircraftTypeAZ:
            return entries.sorted {
                ($0.aircraftType?.lowercased() ?? "") < ($1.aircraftType?.lowercased() ?? "")
            }
        case .aircraftTypeZA:
            return entries.sorted {
                ($0.aircraftType?.lowercased() ?? "") > ($1.aircraftType?.lowercased() ?? "")
            }
        case .airlineAZ:
            return entries.sorted { $0.airline.lowercased() < $1.airline.lowercased() }
        case .airlineZA:
            return entries.sorted { $0.airline.lowercased() > $1.airline.lowercased() }
        case .registrationAZ:
            return entries.sorted { $0.registration.lowercased() < $1.registration.lowercased() }
        case .registrationZA:
            return entries.sorted { $0.registration.lowercased() > $1.registration.lowercased() }
        }
    }
}
