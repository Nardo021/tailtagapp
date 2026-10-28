import SmartEntry
import SwiftData
import XCTest

@testable import TailTag

@MainActor
final class SpottingRecordPersistenceTests: XCTestCase {
    func testLegacyEntryKeepsTextPhotosAndTimestamp() throws {
        let container = try makeContainer()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let id = UUID()
        let context = ModelContext(container)
        let record = SpottingRecord(
            id: id,
            registration: "VH-OLD",
            airline: "Some small charter company",
            location: "Nearby park",
            aircraftType: "Unknown aircraft",
            notes: "kept",
            timestamp: timestamp
        )
        record.applyReference(
            .legacy(airline: "Some small charter company", location: "Nearby park", aircraftType: "Unknown aircraft")
        )
        attachPhotos([Data([9, 8, 7, 6]), Data([5, 4, 3])], to: record, in: context)
        context.insert(record)
        try context.save()

        let loaded = try fetch(id, in: container)
        XCTAssertEqual(loaded.registration, "VH-OLD")
        XCTAssertEqual(loaded.airline, "Some small charter company")
        XCTAssertEqual(loaded.location, "Nearby park")
        XCTAssertEqual(loaded.aircraftType, "Unknown aircraft")
        XCTAssertEqual(loaded.notes, "kept")
        XCTAssertEqual(loaded.timestamp, timestamp)
        XCTAssertNil(loaded.operatorSelectionKind)
        XCTAssertNil(loaded.operatorCatalogId)
        XCTAssertNil(loaded.manufacturerCatalogId)
        XCTAssertNil(loaded.aircraftCatalogId)
        XCTAssertNil(loaded.airportCatalogId)
        XCTAssertNil(loaded.locationSelectionKind)
        XCTAssertNil(loaded.aircraftRoleId)
        XCTAssertNil(loaded.operationTypeId)
        XCTAssertEqual(loaded.photos.map { [UInt8]($0) }, [[9, 8, 7, 6], [5, 4, 3]])
        XCTAssertEqual(loaded.photoRecords.map(\.index).sorted(), [0, 1])
        XCTAssertTrue(loaded.referenceState().operatorField.isLegacy)
        XCTAssertEqual(loaded.asEntry.timestamp, timestamp)
        XCTAssertEqual(loaded.asEntry.photos.count, 2)
    }

    func testStructuredFieldsSaveReloadAndEdit() throws {
        let container = try makeContainer()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let id = UUID()
        let context = ModelContext(container)
        let record = SpottingRecord(
            id: id,
            registration: "VH-NEW",
            airline: "",
            location: "",
            notes: "original",
            timestamp: timestamp
        )
        record.applyReference(structuredReference())
        attachPhotos([Data([1, 2, 3]), Data([4, 5])], to: record, in: context)
        context.insert(record)
        try context.save()

        let loaded = try fetch(id, in: container)
        assertStructured(loaded)
        XCTAssertEqual(loaded.notes, "original")
        XCTAssertEqual(loaded.timestamp, timestamp)
        XCTAssertEqual(loaded.photos.map { [UInt8]($0) }, [[1, 2, 3], [4, 5]])

        loaded.notes = "Ramp note"
        let editedTime = Date(timeIntervalSince1970: 1_700_000_500)
        loaded.timestamp = editedTime
        loaded.photoRecords.first { $0.index == 0 }?.data = Data([7, 7, 7])
        var edited = structuredReference()
        edited.operatorField = .custom(from: "Local club")!
        edited.locationField = .custom(from: "Street corner")!
        loaded.applyReference(edited)
        try XCTUnwrap(loaded.modelContext).save()

        let reloaded = try fetch(id, in: container)
        XCTAssertEqual(reloaded.notes, "Ramp note")
        XCTAssertEqual(reloaded.timestamp, editedTime)
        XCTAssertEqual(reloaded.airline, "Local club")
        XCTAssertEqual(reloaded.operatorSelectionKind, "custom")
        XCTAssertNil(reloaded.operatorCatalogId)
        XCTAssertEqual(reloaded.location, "Street corner")
        XCTAssertEqual(reloaded.locationSelectionKind, "custom")
        XCTAssertNil(reloaded.airportCatalogId)
        XCTAssertEqual(reloaded.manufacturerCatalogId, "wikidata:Q66")
        XCTAssertEqual(reloaded.aircraftCatalogId, "wikidata:Q15111575")
        XCTAssertEqual(reloaded.aircraftEntryKind, "Model")
        XCTAssertEqual(reloaded.aircraftRoleId, "civil")
        XCTAssertEqual(reloaded.operationTypeId, "passenger")
        XCTAssertEqual(reloaded.photos.map { [UInt8]($0) }, [[7, 7, 7], [4, 5]])
        XCTAssertEqual(reloaded.asEntry.reference.operatorField.displayText, "Local club")
        XCTAssertEqual(reloaded.asEntry.registration, "VH-NEW")
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: SpottingRecord.self, PhotoRecord.self, configurations: configuration)
    }

    private func attachPhotos(_ bytes: [Data], to record: SpottingRecord, in context: ModelContext) {
        for (index, data) in bytes.enumerated() {
            let photo = PhotoRecord(data: data, index: index)
            record.photoRecords.append(photo)
            context.insert(photo)
        }
    }

    private func fetch(_ id: UUID, in container: ModelContainer) throws -> SpottingRecord {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<SpottingRecord>(predicate: #Predicate { $0.id == id })
        return try XCTUnwrap(context.fetch(descriptor).first)
    }

    private func structuredReference() -> SpottingReferenceState {
        SpottingReferenceState(
            operatorField: .catalog(id: "wikidata:Q32491", displayText: "Qantas Airways"),
            manufacturerField: .catalog(id: "wikidata:Q66", displayText: "Boeing"),
            aircraftField: .catalog(id: "wikidata:Q15111575", displayText: "Boeing 787-9", detail: "Model"),
            locationField: .custom(from: "Nearby park")!,
            classification: ClassificationChoice(roleId: "civil", operationTypeId: "passenger")
        )
    }

    private func assertStructured(_ record: SpottingRecord, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(record.airline, "Qantas Airways", file: file, line: line)
        XCTAssertEqual(record.operatorCatalogId, "wikidata:Q32491", file: file, line: line)
        XCTAssertEqual(record.operatorSelectionKind, "catalog", file: file, line: line)
        XCTAssertEqual(record.manufacturerName, "Boeing", file: file, line: line)
        XCTAssertEqual(record.manufacturerCatalogId, "wikidata:Q66", file: file, line: line)
        XCTAssertEqual(record.manufacturerSelectionKind, "catalog", file: file, line: line)
        XCTAssertEqual(record.aircraftType, "Boeing 787-9", file: file, line: line)
        XCTAssertEqual(record.aircraftCatalogId, "wikidata:Q15111575", file: file, line: line)
        XCTAssertEqual(record.aircraftSelectionKind, "catalog", file: file, line: line)
        XCTAssertEqual(record.aircraftEntryKind, "Model", file: file, line: line)
        XCTAssertEqual(record.location, "Nearby park", file: file, line: line)
        XCTAssertEqual(record.locationSelectionKind, "custom", file: file, line: line)
        XCTAssertNil(record.airportCatalogId, file: file, line: line)
        XCTAssertEqual(record.aircraftRoleId, "civil", file: file, line: line)
        XCTAssertEqual(record.operationTypeId, "passenger", file: file, line: line)
        XCTAssertNil(record.aircraftRoleNote, file: file, line: line)
        XCTAssertNil(record.operationTypeNote, file: file, line: line)
    }
}
