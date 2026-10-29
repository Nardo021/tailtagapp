import Combine
import CoreData
import Foundation
import SmartEntry
import SwiftData
import SwiftUI

@MainActor
class SpottingStore: ObservableObject {
    @Published var entries: [SpottingEntry] = []
    @Published var lastCloudKitSync: Date? = nil

    private var loadTask: Task<Void, Never>?
    private var needsReload = false

    private var modelContext: ModelContext {
        ModelContainer.tailTag.mainContext
    }

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestReset") {
            do {
                try modelContext.delete(model: SpottingRecord.self)
                try modelContext.save()
            } catch {
                print("UI test reset failed: \(error.localizedDescription)")
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-UITestSeedFilters") {
            seedFilterUITestEntries()
        }
        #endif
        loadEntries()

        // Refresh when CloudKit delivers remote store changes (low-level)
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loadEntries()
            }
        }

        // Observe SwiftData/NSPersistentCloudKitContainer sync events for status + refresh
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

    #if DEBUG
    private func seedFilterUITestEntries() {
        let samples: [(registration: String, reference: SpottingReferenceState)] = [
            (
                "VH-QFA",
                SpottingReferenceState(
                    operatorField: .catalog(id: "op:qantas", displayText: "Qantas Airways"),
                    aircraftField: .catalog(id: "ac:b789", displayText: "Boeing 787-9", detail: "Model"),
                    locationField: .catalog(id: "apt:yssy", displayText: "Sydney Airport"),
                    classification: ClassificationChoice(roleId: "civil", operationTypeId: "passenger")
                )
            ),
            (
                "VH-JST",
                SpottingReferenceState(
                    operatorField: .catalog(id: "op:jetstar", displayText: "Jetstar"),
                    aircraftField: .catalog(id: "ac:a320", displayText: "Airbus A320", detail: "Model"),
                    locationField: .catalog(id: "apt:yssy", displayText: "Sydney Airport"),
                    classification: ClassificationChoice(roleId: "civil", operationTypeId: "passenger")
                )
            ),
            (
                "VH-MIL",
                SpottingReferenceState(
                    operatorField: .catalog(id: "op:raaf", displayText: "RAAF"),
                    aircraftField: .catalog(id: "ac:c130", displayText: "C-130", detail: "Model"),
                    locationField: .custom(from: "Richmond") ?? .absent,
                    classification: ClassificationChoice(roleId: "military", operationTypeId: "cargo")
                )
            ),
        ]
        for (index, sample) in samples.enumerated() {
            let record = SpottingRecord(
                registration: sample.registration,
                timestamp: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index))
            )
            modelContext.insert(record)
            record.applyReference(sample.reference)
        }
        do {
            try modelContext.save()
        } catch {
            print("UI test filter seed failed: \(error.localizedDescription)")
        }
    }
    #endif

    // MARK: - Load

    func loadEntries() {
        needsReload = true
        guard loadTask == nil else { return }

        let container = ModelContainer.tailTag
        loadTask = Task { [weak self] in
            guard let self else { return }
            defer { loadTask = nil }

            while needsReload {
                needsReload = false
                do {
                    let loadedEntries = try await Task.detached(priority: .userInitiated) {
                        // Keep the context, models, and external photo reads off the main actor.
                        // A fresh context also sees the latest saved and imported changes.
                        let context = ModelContext(container)
                        context.autosaveEnabled = false
                        let descriptor = FetchDescriptor<SpottingRecord>(
                            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                        )
                        let records = try context.fetch(descriptor)
                        // Keep entries whose photos haven't arrived from CloudKit yet.
                        return records.map { $0.asEntry }
                    }.value

                    // A save or sync during the fetch requires a fresh snapshot.
                    if !needsReload {
                        entries = loadedEntries
                    }
                } catch {
                    // Preserve the last successful snapshot if a refresh fails.
                    print("Error loading entries: \(error.localizedDescription)")
                }
            }
        }
    }

    private func saveContext() {
        do {
            try modelContext.save()
            loadEntries()
        } catch {
            print("Error saving context: \(error.localizedDescription)")
        }
    }

    // MARK: - Image Compression

    static func compressImageData(_ data: Data, maxSizeKB: Int = 800) -> Data {
        guard let image = UIImage(data: data) else { return data }

        var compression: CGFloat = 0.8
        var imageData = image.jpegData(compressionQuality: compression)
        let maxBytes = maxSizeKB * 1024

        while let d = imageData, d.count > maxBytes && compression > 0.1 {
            compression -= 0.1
            imageData = image.jpegData(compressionQuality: compression)
        }

        if let d = imageData, d.count > maxBytes {
            let scale = sqrt(Double(maxBytes) / Double(d.count))
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            imageData = resizedImage?.jpegData(compressionQuality: 0.7)
        }

        return imageData ?? data
    }

    // MARK: - CRUD

    func addEntry(_ entry: SpottingEntry) {
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
        record.applyReference(entry.reference)

        for (index, photoData) in entry.photos.enumerated() {
            let photo = PhotoRecord(data: SpottingStore.compressImageData(photoData), index: index)
            record.photoRecords.append(photo)
            modelContext.insert(photo)
        }

        saveContext()
        Task {
            await TailTagSpotlightIndexer.index(entry)
        }
    }

    func deleteEntry(_ entry: SpottingEntry) {
        let id = entry.id
        let descriptor = FetchDescriptor<SpottingRecord>(
            predicate: #Predicate { $0.id == id }
        )
        do {
            if let record = try modelContext.fetch(descriptor).first {
                modelContext.delete(record)
                saveContext()
                Task {
                    await TailTagSpotlightIndexer.deleteSpotting(with: entry.id)
                }
            }
        } catch {
            print("Error deleting entry: \(error.localizedDescription)")
        }
    }

    func deleteSpotting(_ spotting: SpottingEntry) {
        deleteEntry(spotting)
    }

    func updateSpotting(_ updatedSpotting: SpottingEntry) {
        let id = updatedSpotting.id
        let descriptor = FetchDescriptor<SpottingRecord>(
            predicate: #Predicate { $0.id == id }
        )
        do {
            if let record = try modelContext.fetch(descriptor).first {
                record.registration = updatedSpotting.registration
                record.notes = updatedSpotting.notes
                record.timestamp = updatedSpotting.timestamp
                record.applyReference(updatedSpotting.reference)

                // Replace photos
                for photo in record.photoRecords {
                    modelContext.delete(photo)
                }
                record.photoRecords.removeAll()

                for (index, photoData) in updatedSpotting.photos.enumerated() {
                    let photo = PhotoRecord(
                        data: SpottingStore.compressImageData(photoData),
                        index: index
                    )
                    record.photoRecords.append(photo)
                    modelContext.insert(photo)
                }

                saveContext()
                Task {
                    await TailTagSpotlightIndexer.index(updatedSpotting)
                }
            }
        } catch {
            print("Error updating entry: \(error.localizedDescription)")
        }
    }

    func clearAllEntries() {
        do {
            try modelContext.delete(model: SpottingRecord.self)
            try modelContext.save()
            loadEntries()
            Task {
                await TailTagSpotlightIndexer.deleteAllSpottingEntries()
            }
        } catch {
            print("Error clearing entries: \(error.localizedDescription)")
        }
    }

    // MARK: - Filtering / Sorting

    func filteredEntries(searchText: String) -> [SpottingEntry] {
        guard !searchText.isEmpty else { return entries }
        return entries.filter { entry in
            entry.registration.localizedCaseInsensitiveContains(searchText) ||
            entry.airline.localizedCaseInsensitiveContains(searchText) ||
            entry.location.localizedCaseInsensitiveContains(searchText) ||
            (entry.aircraftType?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (entry.reference.storedManufacturerText?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (entry.reference.classification.roleNote?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (entry.reference.classification.operationTypeNote?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            classificationMatches(entry.reference.classification, searchText: searchText)
        }
    }

    private func classificationMatches(_ classification: ClassificationChoice, searchText: String) -> Bool {
        let role = classification.roleId ?? ""
        let operation = classification.operationTypeId ?? ""
        return ClassificationCopy.roleLabel(role).localizedCaseInsensitiveContains(searchText) ||
            ClassificationCopy.operationLabel(operation).localizedCaseInsensitiveContains(searchText)
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
