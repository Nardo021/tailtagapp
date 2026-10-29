import CoreData
import Foundation
import SmartEntry
import SwiftData
import XCTest
@testable import TailTag

@MainActor
final class DataIntegrityTests: XCTestCase {
    private let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    private var containers: [ModelContainer] = []

    func testAbsentLegacyStoreMarksMigrationCompleteWithoutCreatingData() throws {
        let context = try makeContext()
        let flags = MemoryMigrationFlags()
        let outcome = SpottingMigrator.migrateLegacySnapshots(read: .absent, into: context, flags: flags)
        XCTAssertEqual(outcome, .completed)
        XCTAssertTrue(flags.bool(forKey: SpottingMigrator.migrationKey))
        XCTAssertTrue(try fetchRecords(context).isEmpty)
    }

    func testUnreadableLegacyStoreDoesNotMarkMigrationComplete() throws {
        let context = try makeContext()
        let flags = MemoryMigrationFlags()
        flags.set(true, forKey: SpottingMigrator.migrationKey)
        let outcome = SpottingMigrator.migrateLegacySnapshots(read: .unreadable, into: context, flags: flags)
        guard case .incomplete = outcome else {
            return XCTFail("Expected incomplete migration")
        }
        XCTAssertFalse(flags.bool(forKey: SpottingMigrator.migrationKey))
        XCTAssertTrue(try fetchRecords(context).isEmpty)
    }

    func testMissingLegacyFileIsAbsentAndDoesNotCreateAStore() throws {
        let directory = try makeTemporaryDirectory()
        let sqlite = LegacyStoreFiles.sqliteURL(in: directory)
        XCTAssertFalse(LegacyStoreFiles.exists(sqlite))
        let read = SpottingMigrator.readLegacyStore(directory: directory)
        XCTAssertEqual(read, .absent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sqlite.path))
        let walOnly = try makeTemporaryDirectory()
        let wal = LegacyStoreFiles.sqliteURL(in: walOnly).path + "-wal"
        FileManager.default.createFile(atPath: wal, contents: Data("wal".utf8))
        XCTAssertTrue(LegacyStoreFiles.exists(LegacyStoreFiles.sqliteURL(in: walOnly)))
        XCTAssertEqual(SpottingMigrator.readLegacyStore(directory: walOnly), .unreadable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: LegacyStoreFiles.sqliteURL(in: walOnly).path))
    }

    func testCorruptLegacyFileStaysRetryable() throws {
        let directory = try makeTemporaryDirectory()
        let sqlite = LegacyStoreFiles.sqliteURL(in: directory)
        try Data("this is not a sqlite database".utf8).write(to: sqlite)
        let read = SpottingMigrator.readLegacyStore(directory: directory)
        XCTAssertEqual(read, .unreadable)
        let flags = MemoryMigrationFlags()
        _ = SpottingMigrator.migrateLegacySnapshots(read: read, into: try makeContext(), flags: flags)
        XCTAssertFalse(flags.bool(forKey: SpottingMigrator.migrationKey))
        XCTAssertEqual(try Data(contentsOf: sqlite), Data("this is not a sqlite database".utf8))
    }

    func testLegacyRecordsKeepIdentityPhotoOrderAndSurviveASecondRun() throws {
        let context = try makeContext()
        let flags = MemoryMigrationFlags()
        let id = UUID()
        let photos = [Data("first".utf8), Data("second".utf8), Data("third".utf8)]
        let first = SpottingMigrator.migrateLegacySnapshots(
            read: .loaded([snapshot(id: id, photos: photos)]),
            into: context,
            flags: flags
        )
        XCTAssertEqual(first, .completed)
        XCTAssertTrue(flags.bool(forKey: SpottingMigrator.migrationKey))
        assertPhotos(try fetchRecords(context), id: id, photos: photos)

        let second = SpottingMigrator.migrateLegacySnapshots(
            read: .loaded([snapshot(id: id, photos: photos)]),
            into: context,
            flags: flags
        )
        XCTAssertEqual(second, .completed)
        XCTAssertEqual(try fetchRecords(context).count, 1)
        assertPhotos(try fetchRecords(context), id: id, photos: photos)
    }

    func testInvalidLegacyRecordBlocksCompletionButKeepsValidRecords() throws {
        let context = try makeContext()
        let flags = MemoryMigrationFlags()
        let validID = UUID()
        var invalid = snapshot(id: UUID(), photos: [Data("photo".utf8)])
        invalid.registration = nil
        let outcome = SpottingMigrator.migrateLegacySnapshots(
            read: .loaded([invalid, snapshot(id: validID, photos: [Data("ok".utf8)])]),
            into: context,
            flags: flags
        )
        guard case .incomplete = outcome else {
            return XCTFail("Expected incomplete migration")
        }
        XCTAssertFalse(flags.bool(forKey: SpottingMigrator.migrationKey))
        let records = try fetchRecords(context)
        XCTAssertEqual(records.map(\.id), [validID])

        let retry = SpottingMigrator.migrateLegacySnapshots(
            read: .loaded([invalid, snapshot(id: validID, photos: [Data("ok".utf8)])]),
            into: context,
            flags: flags
        )
        guard case .incomplete = retry else {
            return XCTFail("Retry should stay incomplete")
        }
        XCTAssertEqual(try fetchRecords(context).count, 1)
        XCTAssertEqual(try fetchRecords(context).first?.photoRecords.count, 1)
    }

    func testFailedSaveDoesNotMarkMigrationCompleteAndCanBeRetried() throws {
        let context = try makeContext()
        let flags = MemoryMigrationFlags()
        let id = UUID()
        let failed = SpottingMigrator.migrateLegacySnapshots(
            read: .loaded([snapshot(id: id, photos: [Data("photo".utf8)])]),
            into: context,
            flags: flags,
            persist: { _ in throw TestSaveError.failed }
        )
        guard case .incomplete = failed else {
            return XCTFail("Expected save failure")
        }
        XCTAssertFalse(flags.bool(forKey: SpottingMigrator.migrationKey))
        XCTAssertTrue(try fetchRecords(context).isEmpty)

        let retried = SpottingMigrator.migrateLegacySnapshots(
            read: .loaded([snapshot(id: id, photos: [Data("photo".utf8)])]),
            into: context,
            flags: flags
        )
        XCTAssertEqual(retried, .completed)
        XCTAssertEqual(try fetchRecords(context).map(\.id), [id])
    }

    func testEmptyPhotoBytesAreNotStoredAsAttachments() throws {
        let context = try makeContext()
        let flags = MemoryMigrationFlags()
        let id = UUID()
        _ = SpottingMigrator.migrateLegacySnapshots(
            read: .loaded([snapshot(id: id, photos: [Data(), Data("real".utf8), Data()])]),
            into: context,
            flags: flags
        )
        let record = try XCTUnwrap(fetchRecords(context).first)
        XCTAssertEqual(record.photoRecords.map(\.data), [Data("real".utf8)])
        XCTAssertTrue(record.asEntry.photos.allSatisfy { !$0.isEmpty })
    }

    func testExistingDestinationDoesNotBlockUniqueRecordsOrOverwriteConflicts() throws {
        let context = try makeContext()
        let existingID = UUID()
        let freshID = UUID()
        let existing = SpottingRecord(
            id: existingID,
            registration: "KEEP-ME",
            airline: "Kept",
            location: "YMML",
            timestamp: timestamp
        )
        context.insert(existing)
        try context.save()

        let flags = MemoryMigrationFlags()
        var conflict = snapshot(id: existingID, registration: "SECRET-REG", photos: [Data("other".utf8)])
        conflict.airline = "Other"
        let outcome = SpottingMigrator.migrateCloudSources(
            preferenceEnabled: true,
            activeIsCloudBacked: true,
            sources: [CloudSourceInput(exists: true, sameAsActive: false, openFailed: false, snapshots: [
                conflict,
                snapshot(id: freshID, photos: [Data("new".utf8)]),
            ])],
            into: context,
            flags: flags
        )
        guard case .incomplete = outcome else {
            return XCTFail("Conflicts should leave migration incomplete")
        }
        XCTAssertFalse(flags.bool(forKey: SpottingMigrator.cloudKitMigrationKey))
        let records = try fetchRecords(context)
        XCTAssertEqual(Set(records.map(\.id)), Set([existingID, freshID]))
        let kept = try XCTUnwrap(records.first { $0.id == existingID })
        XCTAssertEqual(kept.registration, "KEEP-ME")
        XCTAssertTrue(kept.photoRecords.isEmpty)
        let storedConflicts = flags.string(forKey: SpottingMigrator.cloudConflictKey) ?? ""
        XCTAssertTrue(storedConflicts.contains(existingID.uuidString))
        XCTAssertFalse(storedConflicts.contains("SECRET-REG"))
    }

    func testLocalFallbackDoesNotMarkCloudMigrationComplete() throws {
        let context = try makeContext()
        let flags = MemoryMigrationFlags()
        let id = UUID()
        let outcome = SpottingMigrator.migrateCloudSources(
            preferenceEnabled: true,
            activeIsCloudBacked: false,
            sources: [CloudSourceInput(exists: true, sameAsActive: false, openFailed: false, snapshots: [
                snapshot(id: id, photos: [Data("local".utf8)]),
            ])],
            into: context,
            flags: flags
        )
        guard case .incomplete = outcome else {
            return XCTFail("Fallback must not look complete")
        }
        XCTAssertFalse(flags.bool(forKey: SpottingMigrator.cloudKitMigrationKey))
        XCTAssertTrue(try fetchRecords(context).isEmpty)
    }

    func testSameStoreIsNotCopiedOntoItself() throws {
        let context = try makeContext()
        let flags = MemoryMigrationFlags()
        let outcome = SpottingMigrator.migrateCloudSources(
            preferenceEnabled: true,
            activeIsCloudBacked: true,
            sources: [CloudSourceInput(exists: true, sameAsActive: true, openFailed: false, snapshots: [
                snapshot(id: UUID(), photos: [Data("loop".utf8)]),
            ])],
            into: context,
            flags: flags
        )
        guard case .incomplete = outcome else {
            return XCTFail("Same-store copy must stay incomplete")
        }
        XCTAssertFalse(flags.bool(forKey: SpottingMigrator.cloudKitMigrationKey))
        XCTAssertTrue(try fetchRecords(context).isEmpty)
    }

    func testStaleCloudKitFlagStillCopiesMissingLocalRecords() throws {
        let context = try makeContext()
        let flags = MemoryMigrationFlags()
        flags.set(true, forKey: SpottingMigrator.cloudKitMigrationKey)

        let presentID = UUID()
        let missingID = UUID()
        let present = SpottingRecord(
            id: presentID,
            registration: "VH-TST",
            airline: "Test Air",
            location: "YMML",
            aircraftType: "B738",
            notes: "note",
            timestamp: timestamp
        )
        context.insert(present)
        try context.save()

        let localPhotos = [Data("only-local".utf8)]
        let sources = [CloudSourceInput(
            exists: true,
            sameAsActive: false,
            openFailed: false,
            snapshots: [
                snapshot(id: presentID, photos: []),
                snapshot(id: missingID, photos: localPhotos),
            ]
        )]
        let outcome = SpottingMigrator.migrateCloudSources(
            preferenceEnabled: true,
            activeIsCloudBacked: true,
            sources: sources,
            into: context,
            flags: flags
        )
        XCTAssertEqual(outcome, .completed)
        let records = try fetchRecords(context)
        XCTAssertEqual(Set(records.map(\.id)), Set([presentID, missingID]))
        XCTAssertEqual(records.filter { $0.id == presentID }.count, 1)
        assertPhotos(records, id: missingID, photos: localPhotos)

        let second = SpottingMigrator.migrateCloudSources(
            preferenceEnabled: true,
            activeIsCloudBacked: true,
            sources: sources,
            into: context,
            flags: flags
        )
        XCTAssertEqual(second, .completed)
        XCTAssertEqual(try fetchRecords(context).count, 2)
        XCTAssertTrue(flags.bool(forKey: SpottingMigrator.cloudKitMigrationKey))
    }

    func testDisabledSyncDoesNotMigrateOrSetTheCloudFlag() throws {
        let context = try makeContext()
        let flags = MemoryMigrationFlags()
        let outcome = SpottingMigrator.migrateCloudSources(
            preferenceEnabled: false,
            activeIsCloudBacked: false,
            sources: [CloudSourceInput(exists: true, sameAsActive: false, openFailed: false, snapshots: [
                snapshot(id: UUID(), photos: [Data("local".utf8)]),
            ])],
            into: context,
            flags: flags
        )
        XCTAssertEqual(outcome, .alreadyComplete)
        XCTAssertFalse(flags.bool(forKey: SpottingMigrator.cloudKitMigrationKey))
        XCTAssertTrue(try fetchRecords(context).isEmpty)
    }

    func testCloudEligibilityDoesNotTreatAccountPreferenceAsAnActiveCloudStore() {
        XCTAssertEqual(
            MigrationPlanning.cloudEligibility(
                preferenceEnabled: true,
                activeIsCloudBacked: false,
                sourceFileExists: true,
                sourceURLMatchesActive: false,
                sourceOpenFailed: false
            ),
            .localFallback
        )
        XCTAssertEqual(
            MigrationPlanning.cloudEligibility(
                preferenceEnabled: true,
                activeIsCloudBacked: true,
                sourceFileExists: true,
                sourceURLMatchesActive: true,
                sourceOpenFailed: false
            ),
            .sameStore
        )
        XCTAssertEqual(
            MigrationPlanning.cloudEligibility(
                preferenceEnabled: false,
                activeIsCloudBacked: true,
                sourceFileExists: true,
                sourceURLMatchesActive: false,
                sourceOpenFailed: false
            ),
            .preferenceDisabled
        )
    }

    func testAsEntryDoesNotInventAPhotoAndKeepsTheRecord() throws {
        let context = try makeContext()
        let record = SpottingRecord(
            id: UUID(),
            registration: "VH-EMPTY",
            airline: "Test",
            location: "YMML",
            timestamp: timestamp
        )
        let pending = PhotoRecord(data: Data(), index: 0)
        record.photoRecords.append(pending)
        context.insert(record)
        context.insert(pending)
        try context.save()

        XCTAssertTrue(record.asEntry.photos.isEmpty)
        XCTAssertEqual(try fetchRecords(context).count, 1)

        let decoded = try JSONDecoder().decode(
            SpottingEntry.self,
            from: JSONEncoder().encode(SpottingEntry(photos: [Data(), Data("real".utf8)], registration: "VH-X", airline: "Q", location: "Y"))
        )
        XCTAssertEqual(decoded.photos, [Data("real".utf8)])
        XCTAssertTrue(SpottingEntry(photos: [], registration: "VH-X", airline: "Q", location: "Y").photos.isEmpty)
    }

    func testFailedSaveRollsBackAndSkipsSpotlight() async throws {
        let context = try makeContext()
        let indexer = RecordingIndexer()
        let store = SpottingStore(modelContext: context, spotlight: indexer, entryLoader: EmptyEntryLoader())
        store.persistImplementation = { _ in throw TestSaveError.failed }
        let entry = sampleEntry()

        do {
            try store.addEntry(entry)
            XCTFail("Save should fail")
        } catch {
            XCTAssertTrue(error is SpottingPersistenceError)
        }
        XCTAssertTrue(try fetchRecords(context).isEmpty)
        XCTAssertNil(store.lastIndexTask)
        await store.waitUntilIdle()
        XCTAssertFalse(store.entries.contains { $0.id == entry.id })
    }

    func testSuccessfulSaveIndexesOnlyAfterPersistence() async throws {
        let context = try makeContext()
        let indexer = RecordingIndexer()
        let store = SpottingStore(modelContext: context, spotlight: indexer, entryLoader: EmptyEntryLoader())
        let entry = sampleEntry()
        try store.addEntry(entry)
        await store.lastIndexTask?.value
        XCTAssertEqual(indexer.indexed, [entry.id])
        XCTAssertEqual(try fetchRecords(context).map(\.id), [entry.id])

        store.persistImplementation = { _ in throw TestSaveError.failed }
        do {
            try store.deleteEntry(entry)
            XCTFail("Delete should fail")
        } catch {
            XCTAssertTrue(error is SpottingPersistenceError)
        }
        XCTAssertEqual(try fetchRecords(context).map(\.id), [entry.id])
        XCTAssertTrue(indexer.deleted.isEmpty)

        do {
            try store.clearAllEntries()
            XCTFail("Reset should fail")
        } catch {
            XCTAssertTrue(error is SpottingPersistenceError)
        }
        XCTAssertFalse(indexer.deletedAll)
        XCTAssertEqual(try fetchRecords(context).count, 1)
    }

    func testStaleLoadCannotReplaceANewerSnapshot() async throws {
        let context = try makeContext()
        let loader = ScriptedEntryLoader()
        let older = sampleEntry(registration: "OLD")
        let newer = sampleEntry(registration: "NEW")
        loader.pages = [[older], [newer]]
        let store = SpottingStore(modelContext: context, spotlight: RecordingIndexer(), entryLoader: loader)
        await loader.waitUntilPaused()
        for _ in 0..<8 {
            store.loadEntries()
        }
        loader.resume()
        await store.waitUntilIdle()
        XCTAssertEqual(loader.fetchCount, 2)
        XCTAssertEqual(store.entries.map(\.registration), ["NEW"])
    }

    func testFailedReloadKeepsTheLastSnapshot() async throws {
        let context = try makeContext()
        let loader = ScriptedEntryLoader()
        let kept = sampleEntry(registration: "KEPT")
        loader.pages = [[kept]]
        loader.pauseFirstFetch = false
        let store = SpottingStore(modelContext: context, spotlight: RecordingIndexer(), entryLoader: loader)
        await store.waitUntilIdle()
        XCTAssertEqual(store.entries.map(\.registration), ["KEPT"])
        loader.failNext = true
        store.loadEntries()
        await store.waitUntilIdle()
        XCTAssertEqual(store.entries.map(\.registration), ["KEPT"])
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: SpottingRecord.self, PhotoRecord.self, configurations: configuration)
        container.mainContext.autosaveEnabled = false
        containers.append(container)
        return container.mainContext
    }

    private func fetchRecords(_ context: ModelContext) throws -> [SpottingRecord] {
        try context.fetch(FetchDescriptor<SpottingRecord>())
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func snapshot(
        id: UUID,
        registration: String = "VH-TST",
        photos: [Data]
    ) -> SourceSnapshot {
        SourceSnapshot(
            id: id,
            registration: registration,
            airline: "Test Air",
            location: "YMML",
            aircraftType: "B738",
            notes: "note",
            timestamp: timestamp,
            photos: photos
        )
    }

    private func assertPhotos(_ records: [SpottingRecord], id: UUID, photos: [Data]) {
        let record = records.first { $0.id == id }
        let stored = record?.photoRecords.sorted { $0.index < $1.index }.map(\.data)
        XCTAssertEqual(stored, photos)
    }

    func testStructuredMetadataSurvivesSaveReloadEditAndAFailedSave() throws {
        let context = try makeContext()
        let store = SpottingStore(
            modelContext: context,
            spotlight: RecordingIndexer(),
            entryLoader: ModelContainerEntryLoader(container: context.container)
        )
        let entry = SpottingEntry(
            photos: [Data("picture".utf8)],
            registration: "VH-NEW",
            airline: "Qantas Airways",
            location: "Nearby park",
            timestamp: timestamp,
            reference: SpottingReferenceState(
                operatorField: .catalog(id: "wikidata:Q32491", displayText: "Qantas Airways"),
                locationField: .custom(from: "Nearby park") ?? .absent,
                classification: ClassificationChoice(roleId: "civil", operationTypeId: "passenger")
            )
        )
        try store.addEntry(entry)
        let saved = try XCTUnwrap(fetchRecords(context).first)
        XCTAssertEqual(saved.operatorCatalogId, "wikidata:Q32491")
        XCTAssertEqual(saved.operatorSelectionKind, "catalog")
        XCTAssertEqual(saved.locationSelectionKind, "custom")
        XCTAssertEqual(saved.aircraftRoleId, "civil")
        XCTAssertEqual(saved.operationTypeId, "passenger")

        let edited = entry.replacingReference(
            SpottingReferenceState(
                operatorField: .catalog(id: "wikidata:Q32491", displayText: "Qantas Airways"),
                aircraftField: .catalog(id: "ac:b789", displayText: "Boeing 787-9", detail: "Model"),
                locationField: .custom(from: "Nearby park") ?? .absent,
                classification: ClassificationChoice(roleId: "civil", operationTypeId: "cargo")
            )
        )
        try store.updateSpotting(edited)
        let reloaded = try XCTUnwrap(fetchRecords(context).first)
        XCTAssertEqual(reloaded.aircraftCatalogId, "ac:b789")
        XCTAssertEqual(reloaded.operationTypeId, "cargo")
        XCTAssertEqual(reloaded.operatorCatalogId, "wikidata:Q32491")

        store.persistImplementation = { _ in throw TestSaveError.failed }
        var failedEdit = edited
        failedEdit.registration = "VH-LOST"
        XCTAssertThrowsError(try store.updateSpotting(failedEdit))
        XCTAssertEqual(try XCTUnwrap(fetchRecords(context).first).registration, "VH-NEW")
        XCTAssertEqual(try XCTUnwrap(fetchRecords(context).first).aircraftCatalogId, "ac:b789")
    }

    func testMigrationKeepsCatalogMetadataAndDoesNotDuplicateIds() throws {
        let context = try makeContext()
        let flags = MemoryMigrationFlags()
        let id = UUID()
        var source = snapshot(id: id, photos: [Data("picture".utf8)])
        source.reference = MigratedReference(
            operatorCatalogId: "wikidata:Q32491",
            operatorSelectionKind: "catalog",
            locationSelectionKind: "custom"
        )
        let first = SpottingMigrator.migrateLegacySnapshots(read: .loaded([source]), into: context, flags: flags)
        XCTAssertEqual(first, .completed)
        let saved = try XCTUnwrap(fetchRecords(context).first)
        XCTAssertEqual(saved.operatorCatalogId, "wikidata:Q32491")
        XCTAssertEqual(saved.locationSelectionKind, "custom")
        XCTAssertEqual(try fetchRecords(context).count, 1)

        let second = SpottingMigrator.migrateLegacySnapshots(read: .loaded([source]), into: context, flags: flags)
        XCTAssertEqual(second, .completed)
        XCTAssertEqual(try fetchRecords(context).count, 1)
        XCTAssertEqual(try XCTUnwrap(fetchRecords(context).first).operatorCatalogId, "wikidata:Q32491")

        let existingID = UUID()
        let existing = SpottingRecord(
            id: existingID,
            registration: "VH-TST",
            airline: "Test Air",
            location: "YMML",
            aircraftType: "B738",
            notes: "note",
            timestamp: timestamp
        )
        let photo = PhotoRecord(data: Data("picture".utf8), index: 0)
        existing.photoRecords = [photo]
        context.insert(existing)
        context.insert(photo)
        try context.save()
        var gap = snapshot(id: existingID, photos: [Data("picture".utf8)])
        gap.reference = MigratedReference(
            operatorCatalogId: "op:custom-air",
            operatorSelectionKind: "custom",
            locationSelectionKind: "custom"
        )
        let filled = SpottingMigrator.migrateLegacySnapshots(read: .loaded([gap]), into: context, flags: MemoryMigrationFlags())
        XCTAssertEqual(filled, .completed)
        let updated = try XCTUnwrap(fetchRecords(context).first { $0.id == existingID })
        XCTAssertEqual(updated.operatorCatalogId, "op:custom-air")
        XCTAssertEqual(updated.operatorSelectionKind, "custom")
        XCTAssertEqual(updated.registration, "VH-TST")
        XCTAssertEqual(updated.photoRecords.map(\.data), [Data("picture".utf8)])

        var filters = SpottingFilterState()
        filters.insert(.reference(.operatorField, .catalog(id: "wikidata:Q32491", label: "Qantas Airways")))
        let visible = searchSpottingEntries(
            [saved.asEntry],
            searchText: "VH-",
            filters: filters,
            sort: .registrationAZ,
            catalog: PreparedSpottingFilterCatalog.unavailable
        )
        XCTAssertEqual(visible.map { $0.registration }, ["VH-TST"])
    }

    private func sampleEntry(registration: String = "VH-NEW") -> SpottingEntry {
        SpottingEntry(
            photos: [Data("picture".utf8)],
            registration: registration,
            airline: "Test Air",
            location: "YMML",
            timestamp: timestamp
        )
    }
}

private enum TestSaveError: Error {
    case failed
}

private struct EmptyEntryLoader: EntryLoading {
    func fetchEntries() async throws -> [SpottingEntry] { [] }
}

@MainActor
private final class RecordingIndexer: SpottingIndexing {
    var indexed: [UUID] = []
    var deleted: [UUID] = []
    var deletedAll = false

    func index(_ entry: SpottingEntry) async {
        indexed.append(entry.id)
    }

    func delete(id: UUID) async {
        deleted.append(id)
    }

    func deleteAll() async {
        deletedAll = true
    }
}

@MainActor
private final class ScriptedEntryLoader: EntryLoading {
    var pages: [[SpottingEntry]] = []
    var pauseFirstFetch = true
    var failNext = false
    private(set) var fetchCount = 0
    private var paused = false
    private var resumed = false
    private var waiter: CheckedContinuation<Void, Never>?

    func fetchEntries() async throws -> [SpottingEntry] {
        let index = fetchCount
        fetchCount += 1
        if failNext {
            failNext = false
            throw TestSaveError.failed
        }
        if index == 0 && pauseFirstFetch {
            paused = true
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if resumed {
                    continuation.resume()
                } else {
                    waiter = continuation
                }
            }
        }
        if pages.isEmpty { return [] }
        return pages[min(index, pages.count - 1)]
    }

    func waitUntilPaused() async {
        while !paused {
            await Task.yield()
        }
    }

    func resume() {
        resumed = true
        waiter?.resume()
        waiter = nil
    }
}
