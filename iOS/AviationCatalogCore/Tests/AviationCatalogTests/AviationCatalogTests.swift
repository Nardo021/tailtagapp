import XCTest
import Darwin
@testable import AviationCatalog

final class AviationCatalogTests: XCTestCase {
    func testNormalizationMatchesReference() throws {
        let payload = try fixture("normalization-cases.json")
        let cases = payload["cases"] as! [[String: String]]
        for sample in cases {
            let normalized = AviationText.normalize(sample["input"])
            XCTAssertEqual(normalized, sample["normalized"], sample["input"] ?? "")
            XCTAssertEqual(AviationText.compact(normalized), sample["compact"], sample["input"] ?? "")
        }
    }

    func testRankingMatchesReference() throws {
        let catalog = try fixture("ranking-catalog.json")
        let operators = try (catalog["operators"] as! [[String: Any]]).map(operatorRecord)
        let aircraft = try (catalog["aircraft"] as! [[String: Any]]).map(aircraftRecord)
        let airports = try (catalog["airports"] as! [[String: Any]]).map(airportRecord)
        let built = AviationCatalog(
            schemaVersion: 1,
            catalogVersion: "fixture",
            operators: operators,
            manufacturers: [],
            aircraft: aircraft,
            airports: airports,
            classifications: []
        )
        let cases = try fixture("ranking-cases.json")["cases"] as! [[String: Any]]
        for sample in cases {
            let dataset = sample["dataset"] as! String
            let query = sample["query"] as! String
            let limit = sample["limit"] as! Int
            let expected = sample["expectedIds"] as! [String]
            let ids: [String]
            let resolution: String
            switch dataset {
            case "operators":
                let matches = try built.searchOperators(query: query, limit: limit)
                ids = matches.map(\.id)
                resolution = try built.resolveOperators(query: query, limit: limit).kindName
            case "aircraft":
                let matches = try built.searchAircraft(query: query, limit: limit)
                ids = matches.map(\.id)
                resolution = try built.resolveAircraft(query: query, limit: limit).kindName
            case "airports":
                let matches = try built.searchAirports(query: query, limit: limit)
                ids = matches.map(\.id)
                resolution = try built.resolveAirports(query: query, limit: limit).kindName
            default:
                XCTFail("unexpected dataset \(dataset)")
                continue
            }
            XCTAssertEqual(ids, expected, "\(dataset) \(query)")
            XCTAssertEqual(resolution, sample["resolution"] as? String, query)
            if let text = sample["unmatchedText"] as? String, case .unmatched(let actual) = try built.resolveOperators(query: query, limit: limit), dataset == "operators" {
                XCTAssertEqual(actual, text)
            }
        }
        let qantas = try built.searchOperators(query: "QF", limit: 5)
        XCTAssertEqual(qantas.first?.id, "fixture:qantas")
        XCTAssertNotEqual(qantas.first?.id, "fixture:prefix-carrier")
        let shared = try built.searchAircraft(query: "A320", limit: 5).map(\.id)
        XCTAssertEqual(shared, ["fixture:a320-200", "fixture:a320-family"])
        let raaf = try XCTUnwrap(built.operatorById("fixture:raaf"))
        XCTAssertTrue(raaf.iataCodes.isEmpty)
        XCTAssertEqual(raaf.tags, ["military-operator"])
        let dragon = try XCTUnwrap(built.aircraftById("fixture:dragon"))
        XCTAssertTrue(dragon.icaoTypeDesignators.isEmpty)
        XCTAssertTrue(dragon.iataEquipmentCodes.isEmpty)
        let unknown = try built.resolveAirports(query: "zzzz-not-a-place", limit: 5)
        if case .unmatched(let text) = unknown {
            XCTAssertEqual(text, "zzzz-not-a-place")
        } else {
            XCTFail("unknown query was substituted")
        }
        XCTAssertThrowsError(try built.searchOperators(query: "QF", limit: -1))
    }

    func testUnmatchedTextIsNotReplacedByFirstResult() throws {
        let reference = AviationReference<String>.custom("Not A Real Airline")
        let unknown = AviationReference<String>.unknown
        let absent = AviationReference<String>.absent
        XCTAssertNotEqual(reference, .catalog("fixture:qantas"))
        XCTAssertNotEqual(unknown, .catalog("fixture:qantas"))
        XCTAssertEqual(absent, .absent)
    }

    func testFailedLoadDoesNotCacheEmptyCatalog() async {
        let repository = AviationCatalogRepository {
            throw AviationCatalogError.resourceMissing("operators.json")
        }
        do {
            _ = try await repository.catalog()
            XCTFail("expected load failure")
        } catch AviationCatalogError.resourceMissing {
        } catch {
            XCTFail("unexpected error \(error)")
        }
        do {
            _ = try await repository.catalog()
            XCTFail("failure was cached as a catalog")
        } catch AviationCatalogError.resourceMissing {
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testBundledCatalogWhenPresent() async throws {
        let started = Date()
        let catalog: AviationCatalog
        do {
            catalog = try AviationCatalogLoader.load()
        } catch AviationCatalogError.resourceMissing {
            throw XCTSkip("catalog resources have not been generated")
        }
        print(String(format: "catalog load %.3fs", Date().timeIntervalSince(started)))
        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertFalse(catalog.operators.isEmpty)
        XCTAssertFalse(catalog.airports.isEmpty)
        let heathrow = try XCTUnwrap(catalog.airportById("ourairports:2434"))
        XCTAssertEqual(heathrow.iataCode, "LHR")
        XCTAssertEqual(heathrow.icaoCode, "EGLL")
        let queryStarted = Date()
        let sydney = try catalog.searchAirports(query: "YSSY", limit: 3)
        let qantas = try catalog.searchOperators(query: "Qantas", limit: 5)
        let a350 = try catalog.searchAircraft(query: "A350", limit: 5)
        let heathrowMatches = try catalog.searchAirports(query: "Heathrow", limit: 5)
        print(String(format: "catalog search sample %.3fs", Date().timeIntervalSince(queryStarted)))
        print("catalog counts operators=\(catalog.operators.count) manufacturers=\(catalog.manufacturers.count) aircraft=\(catalog.aircraft.count) airports=\(catalog.airports.count)")
        XCTAssertEqual(sydney.first?.id, "ourairports:27145")
        XCTAssertFalse(qantas.isEmpty)
        XCTAssertFalse(a350.isEmpty)
        XCTAssertTrue(heathrowMatches.contains { $0.iataCode == "LHR" })
        XCTAssertTrue(catalog.aircraft.allSatisfy { $0.icaoTypeDesignators.isEmpty && $0.iataEquipmentCodes.isEmpty })
        XCTAssertEqual(try catalog.searchAirports(query: "zzzz-not-a-place", limit: 5).count, 0)
        let b789 = try catalog.searchAircraft(query: "B789", limit: 5)
        XCTAssertEqual(b789.first?.id, "wikidata:Q15111575")
        let qf = try catalog.resolveOperators(query: "QF", limit: 1)
        if case .ambiguous = qf {
        } else {
            XCTFail("QF exact-code collision was collapsed")
        }
        let historical = try XCTUnwrap(catalog.operatorById("wikidata:Q100268337"))
        XCTAssertTrue(historical.historical)
        XCTAssertNil(historical.dissolvedOn)
        XCTAssertEqual(try catalog.searchOperators(query: historical.name, limit: 5).first?.id, historical.id)
        let closed = try XCTUnwrap(catalog.airportById("ourairports:10002"))
        XCTAssertEqual(closed.type, "closed")
        XCTAssertEqual(try catalog.searchAirports(query: "Roto-Whirl", limit: 5).first?.id, closed.id)
        let battery = [
            ("airports", "YSSY"), ("operators", "Qantas"), ("aircraft", "A350"), ("airports", "Heathrow"),
            ("aircraft", "B789"), ("aircraft", "787-9"), ("aircraft", "A359"), ("operators", "QF"),
            ("operators", "QFA"), ("airports", "LHR"), ("airports", "EGLL"), ("airports", "Sydney"),
            ("aircraft", "A320"), ("aircraft", "Cessna 172"), ("aircraft", "C-130"),
        ]
        var firstPass: [String] = []
        var latencies: [Double] = []
        for pass in 0..<5 {
            for sample in battery {
                let started = Date()
                switch sample.0 {
                case "operators": _ = try catalog.searchOperators(query: sample.1, limit: 5)
                case "aircraft": _ = try catalog.searchAircraft(query: sample.1, limit: 5)
                case "airports": _ = try catalog.searchAirports(query: sample.1, limit: 5)
                default:
                    XCTFail(sample.0)
                }
                let elapsed = Date().timeIntervalSince(started)
                latencies.append(elapsed)
                if pass == 0 {
                    firstPass.append(String(format: "%@ %@ %.3fms", sample.0, sample.1, elapsed * 1000))
                }
            }
        }
        latencies.sort()
        let p50 = latencies[latencies.count / 2]
        let p95 = latencies[Int(Double(latencies.count - 1) * 0.95)]
        print("catalog query first pass " + firstPass.joined(separator: " | "))
        print(String(format: "catalog query p50 %.3fms p95 %.3fms n=%d", p50 * 1000, p95 * 1000, latencies.count))
        if let resident = residentMegabytes() {
            print(String(format: "catalog resident %.1f MB", resident))
        }
        let repository = AviationCatalogRepository()
        let coldStarted = Date()
        _ = try await repository.catalog()
        print(String(format: "catalog repository cold %.3fs", Date().timeIntervalSince(coldStarted)))
        let warmStarted = Date()
        _ = try await repository.catalog()
        print(String(format: "catalog repository warm %.3fs", Date().timeIntervalSince(warmStarted)))
        if let searchCases = try? fixture("search-cases.json")["cases"] as? [[String: Any]] {
            for sample in searchCases {
                let dataset = sample["dataset"] as! String
                let query = sample["query"] as! String
                let limit = sample["limit"] as! Int
                let expected = sample["expectedIds"] as! [String]
                let ids: [String]
                switch dataset {
                case "operators": ids = try catalog.searchOperators(query: query, limit: limit).map(\.id)
                case "aircraft": ids = try catalog.searchAircraft(query: query, limit: limit).map(\.id)
                case "airports": ids = try catalog.searchAirports(query: query, limit: limit).map(\.id)
                default: continue
                }
                XCTAssertEqual(ids, expected, "\(dataset) \(query)")
            }
        }
    }

    private func fixture(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: (name as NSString).deletingPathExtension, withExtension: "json"))
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private func residentMegabytes() -> Double? {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.stride / MemoryLayout<natural_t>.stride)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
        }
    }
    guard result == KERN_SUCCESS else { return nil }
    return Double(info.resident_size) / 1_048_576
}
