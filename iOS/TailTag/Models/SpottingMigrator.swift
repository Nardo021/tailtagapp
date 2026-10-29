import CoreData
import Foundation
import SwiftData

private enum MigrationApplyError: Error {
    case missingDestination
}

enum SpottingMigrator {
    static let migrationKey = "HasMigratedToSwiftData"
    static let cloudKitMigrationKey = "HasMigratedToCloudKitStore"
    static let legacyConflictKey = "LegacyMigrationConflicts"
    static let cloudConflictKey = "CloudKitMigrationConflicts"

    private static let legacyIncompleteNotice = "Some existing aircraft records could not be merged safely. They were left in the original store and were not overwritten."
    private static let unreadableNotice = "Existing aircraft records are still in the original store, but they could not be read. They were not replaced."
    private static let saveFailedNotice = "Aircraft records could not be saved. Migration was not marked complete."

    // MARK: - App entry points

    @MainActor
    static func migrateIfNeeded(store: SpottingStore, flags: MigrationFlagStore? = nil) async {
        let flags = flags ?? UserDefaultsMigrationFlags()
        let directory = NSPersistentContainer.defaultDirectoryURL()
        let read = readLegacyStore(directory: directory)

        let destination = store.modelContextForMigration
        let outcome = migrateLegacySnapshots(read: read, into: destination, flags: flags)
        store.loadEntries()
        publish(outcome, on: store, signature: "legacy")
    }

    /// Copies unique local SwiftData records into the active store only when that store is actually CloudKit-backed.
    /// A local fallback never sets the CloudKit migration flag and never copies a store onto itself.
    @MainActor
    static func migrateToCloudKitIfNeeded(store: SpottingStore, flags: MigrationFlagStore? = nil) async {
        let flags = flags ?? UserDefaultsMigrationFlags()
        let preferenceEnabled = UserDefaults.standard.bool(forKey: PersistenceController.iCloudSyncKey)
        let active = ModelContainer.activeIdentity
        let activeIsCloudBacked: Bool
        let activeURL: URL?
        switch active {
        case .cloudKit(let url):
            activeIsCloudBacked = true
            activeURL = url
        case .local:
            activeIsCloudBacked = false
            activeURL = nil
        }

        let sources = cloudSources(activeURL: activeURL, activeIsCloudBacked: activeIsCloudBacked)
        let outcome = migrateCloudSources(
            preferenceEnabled: preferenceEnabled,
            activeIsCloudBacked: activeIsCloudBacked,
            sources: sources,
            into: store.modelContextForMigration,
            flags: flags
        )
        if preferenceEnabled {
            store.loadEntries()
        }
        publish(outcome, on: store, signature: "cloud")
    }

    // MARK: - Testable migration

    @MainActor
    static func migrateLegacySnapshots(
        read: LegacyReadResult,
        into context: ModelContext,
        flags: MigrationFlagStore,
        persist: (ModelContext) throws -> Void = { try $0.save() }
    ) -> MigrationOutcome {
        switch read {
        case .absent:
            flags.set(true, forKey: migrationKey)
            flags.set(nil, forKey: legacyConflictKey)
            return .completed
        case .unreadable, .readFailed:
            flags.set(false, forKey: migrationKey)
            return .incomplete(notice: unreadableNotice)
        case .loaded(let snapshots):
            // Keep original photo bytes. Recompressing on every retry can make identical photos look different.
            return apply(
                sources: snapshots,
                into: context,
                flags: flags,
                completionKey: migrationKey,
                conflictKey: legacyConflictKey,
                persist: persist
            )
        }
    }

    @MainActor
    static func migrateCloudSources(
        preferenceEnabled: Bool,
        activeIsCloudBacked: Bool,
        sources: [CloudSourceInput],
        into context: ModelContext,
        flags: MigrationFlagStore,
        persist: (ModelContext) throws -> Void = { try $0.save() }
    ) -> MigrationOutcome {
        // Older builds set HasMigratedToCloudKitStore without copying unique local UUIDs.
        // The flag is not an early return. A later launch still merges those records.
        if !preferenceEnabled {
            return .alreadyComplete
        }
        if !activeIsCloudBacked {
            flags.set(false, forKey: cloudKitMigrationKey)
            return .incomplete(notice: "iCloud sync is turned on, but this launch is using on-device storage. Records were not marked as migrated.")
        }

        var sawSameStore = false
        var sawUnreadable = false
        var snapshots: [SourceSnapshot] = []
        for source in sources {
            let eligibility = MigrationPlanning.cloudEligibility(
                preferenceEnabled: true,
                activeIsCloudBacked: true,
                sourceFileExists: source.exists,
                sourceURLMatchesActive: source.sameAsActive,
                sourceOpenFailed: source.openFailed
            )
            switch eligibility {
            case .preferenceDisabled, .localFallback:
                flags.set(false, forKey: cloudKitMigrationKey)
                return .incomplete(notice: saveFailedNotice)
            case .sameStore:
                sawSameStore = true
            case .sourceUnreadable:
                sawUnreadable = true
            case .sourceAbsent:
                break
            case .ready:
                snapshots.append(contentsOf: source.snapshots)
            }
        }

        let outcome = apply(
            sources: snapshots,
            into: context,
            flags: flags,
            completionKey: cloudKitMigrationKey,
            conflictKey: cloudConflictKey,
            persist: persist
        )
        guard !sawSameStore, !sawUnreadable else {
            flags.set(false, forKey: cloudKitMigrationKey)
            if sawUnreadable {
                return .incomplete(notice: unreadableNotice)
            }
            return .incomplete(notice: "Local records were not copied into the same on-device store.")
        }
        return outcome
    }

    // MARK: - Applying plans

    @MainActor
    private static func apply(
        sources: [SourceSnapshot],
        into context: ModelContext,
        flags: MigrationFlagStore,
        completionKey: String,
        conflictKey: String,
        persist: (ModelContext) throws -> Void
    ) -> MigrationOutcome {
        let destinations: [DestinationSnapshot]
        do {
            destinations = try fetchDestinations(in: context)
        } catch {
            flags.set(false, forKey: completionKey)
            return .incomplete(notice: unreadableNotice)
        }

        let plan = MigrationPlanning.planMigration(sources: sources, destinations: destinations)
        flags.set(MigrationPlanning.encodeConflicts(MigrationPlanning.conflicts(from: plan.plans)), forKey: conflictKey)

        var wrote = false
        for step in plan.plans {
            switch step {
            case .invalid, .unchanged, .conflict:
                break
            case .insert(let source):
                insert(source, into: context)
                wrote = true
            case .addPhotos(let id, let photos):
                do {
                    if try append(photos, to: id, in: context) {
                        wrote = true
                    }
                } catch {
                    context.rollback()
                    flags.set(false, forKey: completionKey)
                    return .incomplete(notice: saveFailedNotice)
                }
            }
        }

        for (source, step) in zip(sources, plan.plans) {
            switch step {
            case .unchanged, .addPhotos:
                break
            case .invalid, .insert, .conflict:
                continue
            }
            guard let id = source.id, !source.reference.isEmpty else { continue }
            do {
                if try fillReference(source.reference, id: id, in: context) {
                    wrote = true
                }
            } catch {
                context.rollback()
                flags.set(false, forKey: completionKey)
                return .incomplete(notice: saveFailedNotice)
            }
        }

        if wrote {
            do {
                try persist(context)
            } catch {
                context.rollback()
                flags.set(false, forKey: completionKey)
                return .incomplete(notice: saveFailedNotice)
            }
        }

        if plan.shouldMarkComplete {
            flags.set(true, forKey: completionKey)
            return .completed
        }

        flags.set(false, forKey: completionKey)
        return .incomplete(notice: legacyIncompleteNotice)
    }

    @MainActor
    private static func fetchDestinations(in context: ModelContext) throws -> [DestinationSnapshot] {
        let records = try context.fetch(FetchDescriptor<SpottingRecord>())
        return records.map { record in
            DestinationSnapshot(
                id: record.id,
                registration: record.registration,
                airline: record.airline,
                location: record.location,
                aircraftType: record.aircraftType,
                notes: record.notes,
                timestamp: record.timestamp,
                photos: record.photoRecords.map { DestinationPhoto(index: $0.index, data: $0.data) },
                reference: record.migratedReference()
            )
        }
    }

    @MainActor
    private static func insert(_ source: ValidatedSource, into context: ModelContext) {
        let record = SpottingRecord(
            id: source.id,
            registration: source.registration,
            airline: source.airline,
            location: source.location,
            aircraftType: source.aircraftType,
            notes: source.notes,
            timestamp: source.timestamp
        )
        context.insert(record)
        record.applyMigratedReference(source.reference)
        for (index, data) in source.photos.enumerated() where !data.isEmpty {
            let photo = PhotoRecord(data: data, index: index)
            record.photoRecords.append(photo)
            context.insert(photo)
        }
    }

    @MainActor
    private static func append(_ photos: [DestinationPhoto], to id: UUID, in context: ModelContext) throws -> Bool {
        let descriptor = FetchDescriptor<SpottingRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else {
            throw MigrationApplyError.missingDestination
        }
        var appended = false
        let existingIndexes = Set(record.photoRecords.map(\.index))
        for photo in photos where !photo.data.isEmpty && !existingIndexes.contains(photo.index) {
            let stored = PhotoRecord(data: photo.data, index: photo.index)
            record.photoRecords.append(stored)
            context.insert(stored)
            appended = true
        }
        return appended
    }

    @MainActor
    private static func fillReference(_ reference: MigratedReference, id: UUID, in context: ModelContext) throws -> Bool {
        let descriptor = FetchDescriptor<SpottingRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else { return false }
        return record.fillMigratedReference(reference)
    }

    // MARK: - Legacy store reading

    @MainActor
    static func readLegacyStore(directory: URL) -> LegacyReadResult {
        let sqliteURL = LegacyStoreFiles.sqliteURL(in: directory)
        guard LegacyStoreFiles.exists(sqliteURL) else { return .absent }
        // A sidecar without the main file is not an empty database. Opening it can create a new store.
        guard FileManager.default.fileExists(atPath: sqliteURL.path) else { return .unreadable }

        let container = NSPersistentContainer(name: "SpottingModel")
        let description = NSPersistentStoreDescription(url: sqliteURL)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if loadError != nil {
            return .unreadable
        }

        let request = NSFetchRequest<NSManagedObject>(entityName: "SpottingEntryEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        do {
            let objects = try container.viewContext.fetch(request)
            return .loaded(objects.map(snapshot(from:)))
        } catch {
            return .readFailed
        }
    }

    static func snapshot(from object: NSManagedObject) -> SourceSnapshot {
        SourceSnapshot(
            id: object.value(forKey: "id") as? UUID,
            registration: object.value(forKey: "registration") as? String,
            airline: object.value(forKey: "airline") as? String,
            location: object.value(forKey: "location") as? String,
            aircraftType: object.value(forKey: "aircraftType") as? String,
            notes: object.value(forKey: "notes") as? String,
            timestamp: object.value(forKey: "timestamp") as? Date,
            photos: photoData(from: object)
        )
    }

    private static func photoData(from object: NSManagedObject) -> [Data] {
        var ordered: [Data] = []
        let rawPhotos = object.value(forKey: "photos")
        if let photos = rawPhotos as? [Data] {
            ordered = photos
        } else if let photos = rawPhotos as? NSArray {
            ordered = photos.compactMap { $0 as? Data }
        }
        if ordered.isEmpty, let single = object.value(forKey: "photo") as? Data {
            ordered = [single]
        }
        return ordered.filter { !$0.isEmpty }
    }

    // MARK: - Local SwiftData sources

    @MainActor
    private static func cloudSources(activeURL: URL?, activeIsCloudBacked: Bool) -> [CloudSourceInput] {
        guard activeIsCloudBacked else {
            return [CloudSourceInput(exists: true, sameAsActive: false, openFailed: false, snapshots: [])]
        }

        let schema = Schema([SpottingRecord.self, PhotoRecord.self])
        let configurations = [
            ModelConfiguration("TailTagLocal", schema: schema, cloudKitDatabase: .none),
            ModelConfiguration(schema: schema, cloudKitDatabase: .none),
        ]

        return configurations.map { configuration in
            let sourceURL = configuration.url
            let sameAsActive = activeURL.map { urlsMatch($0, sourceURL) } ?? false
            let exists = LegacyStoreFiles.exists(sourceURL)
            if !exists || sameAsActive {
                return CloudSourceInput(exists: exists, sameAsActive: sameAsActive, openFailed: false, snapshots: [])
            }
            do {
                let container = try ModelContainer(for: schema, configurations: [configuration])
                let records = try container.mainContext.fetch(FetchDescriptor<SpottingRecord>())
                let snapshots = records.map { record in
                    SourceSnapshot(
                        id: record.id,
                        registration: record.registration,
                        airline: record.airline,
                        location: record.location,
                        aircraftType: record.aircraftType,
                        notes: record.notes,
                        timestamp: record.timestamp,
                        photos: record.photoRecords
                            .sorted { $0.index < $1.index }
                            .map(\.data)
                            .filter { !$0.isEmpty },
                        reference: record.migratedReference()
                    )
                }
                return CloudSourceInput(exists: true, sameAsActive: false, openFailed: false, snapshots: snapshots)
            } catch {
                return CloudSourceInput(exists: true, sameAsActive: false, openFailed: true, snapshots: [])
            }
        }
    }

    private static func urlsMatch(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    @MainActor
    private static func publish(_ outcome: MigrationOutcome, on store: SpottingStore, signature: String) {
        guard case .incomplete(let notice) = outcome else { return }
        store.presentNotice(notice, signature: signature + ":" + notice)
    }
}
