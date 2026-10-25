import CoreData
import SwiftData
import Foundation

enum SpottingMigrator {
    static let migrationKey = "HasMigratedToSwiftData"
    static let cloudKitMigrationKey = "HasMigratedToCloudKitStore"

    // MARK: - CoreData → SwiftData (local store)

    @MainActor
    static func migrateIfNeeded(store: SpottingStore) async {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let oldContainer = NSPersistentContainer(name: "SpottingModel")
        var loadError: Error?
        oldContainer.loadPersistentStores { _, error in
            loadError = error
        }

        guard loadError == nil else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        let context = oldContainer.viewContext
        let fetchRequest: NSFetchRequest<SpottingEntryEntity> = SpottingEntryEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \SpottingEntryEntity.timestamp, ascending: true)]

        do {
            let entities = try context.fetch(fetchRequest)
            guard !entities.isEmpty else {
                UserDefaults.standard.set(true, forKey: migrationKey)
                return
            }

            let modelContext = ModelContainer.tailTag.mainContext

            for entity in entities {
                guard let id = entity.id,
                      let registration = entity.registration,
                      let airline = entity.airline,
                      let location = entity.location,
                      let timestamp = entity.timestamp else { continue }

                let record = SpottingRecord(
                    id: id,
                    registration: registration,
                    airline: airline,
                    location: location,
                    aircraftType: entity.aircraftType,
                    notes: entity.notes,
                    timestamp: timestamp
                )
                modelContext.insert(record)

                let photosData: [Data] = (entity.photos as? [Data]) ?? entity.photo.map { [$0] } ?? []
                for (index, photoData) in photosData.enumerated() {
                    let photo = PhotoRecord(
                        data: SpottingStore.compressImageData(photoData),
                        index: index
                    )
                    record.photoRecords.append(photo)
                    modelContext.insert(photo)
                }
            }

            try modelContext.save()
            UserDefaults.standard.set(true, forKey: migrationKey)
            print("Migrated \(entities.count) entries to SwiftData")
            store.loadEntries()
        } catch {
            print("SwiftData migration failed: \(error)")
        }
    }

    // MARK: - Local SwiftData store → CloudKit store

    /// Called when iCloud sync is enabled. Copies entries from the local "TailTagLocal"
    /// store (or the legacy unnamed default store) into the active CloudKit store.
    @MainActor
    static func migrateToCloudKitIfNeeded(store: SpottingStore) async {
        guard UserDefaults.standard.bool(forKey: PersistenceController.iCloudSyncKey) else { return }
        guard !UserDefaults.standard.bool(forKey: cloudKitMigrationKey) else { return }

        let schema = Schema([SpottingRecord.self, PhotoRecord.self])
        let cloudContext = ModelContainer.tailTag.mainContext

        // Check CloudKit store already has data (e.g. other device already synced)
        if let existingCount = try? cloudContext.fetchCount(FetchDescriptor<SpottingRecord>()),
           existingCount > 0 {
            UserDefaults.standard.set(true, forKey: cloudKitMigrationKey)
            return
        }

        // Try the named local store first, then fall back to the unnamed default store.
        let storeConfigs: [ModelConfiguration] = [
            ModelConfiguration("TailTagLocal", schema: schema, cloudKitDatabase: .none),
            ModelConfiguration(schema: schema, cloudKitDatabase: .none)   // legacy unnamed store
        ]

        for localConfig in storeConfigs {
            guard let localContainer = try? ModelContainer(for: schema, configurations: [localConfig]) else {
                continue
            }

            let localContext = localContainer.mainContext
            guard let localRecords = try? localContext.fetch(FetchDescriptor<SpottingRecord>()),
                  !localRecords.isEmpty else {
                continue
            }

            for record in localRecords {
                let sorted = record.photoRecords.sorted { $0.index < $1.index }
                let newRecord = SpottingRecord(
                    id: record.id,
                    registration: record.registration,
                    airline: record.airline,
                    location: record.location,
                    aircraftType: record.aircraftType,
                    notes: record.notes,
                    timestamp: record.timestamp
                )
                cloudContext.insert(newRecord)
                newRecord.copyCatalogFields(from: record)

                for photo in sorted {
                    let newPhoto = PhotoRecord(data: photo.data, index: photo.index)
                    newRecord.photoRecords.append(newPhoto)
                    cloudContext.insert(newPhoto)
                }
            }

            try? cloudContext.save()
            print("[TailTag] Copied \(localRecords.count) entries from local store to CloudKit store")
            break
        }

        UserDefaults.standard.set(true, forKey: cloudKitMigrationKey)
        store.loadEntries()
    }
}
