import AviationCatalog
import Combine
import Foundation
import SmartEntry

struct AviationSearchOutcome<Record: Sendable>: Sendable {
    var records: [Record]
    var ambiguous: Bool
    var unmatched: Bool
}

@MainActor
final class AviationCatalogUIService: ObservableObject {
    @Published private(set) var phase: CatalogLoadPhase = .idle
    @Published private(set) var errorMessage: String?

    private let repository: AviationCatalogRepository
    private var catalog: AviationCatalog?
    private var loadState = CatalogLoadState()
    private var loadTask: Task<Void, Never>?

    init(repository: AviationCatalogRepository = AviationCatalogRepository()) {
        self.repository = repository
    }

    func prepare() {
        guard loadState.begin() else { return }
        startLoad()
    }

    func retry() {
        guard loadState.retry() else { return }
        startLoad()
    }

    func operatorExists(_ id: String?) -> Bool? { exists(id, lookup: { catalog?.operatorById($0) }) }
    func manufacturerExists(_ id: String?) -> Bool? { exists(id, lookup: { catalog?.manufacturerById($0) }) }
    func aircraftExists(_ id: String?) -> Bool? { exists(id, lookup: { catalog?.aircraftById($0) }) }
    func airportExists(_ id: String?) -> Bool? { exists(id, lookup: { catalog?.airportById($0) }) }

    func aircraftManufacturerLink(for aircraftId: String?) -> (id: String, name: String)? {
        guard phase == .ready, let aircraftId, let model = catalog?.aircraftById(aircraftId) else { return nil }
        guard let linked = linkedManufacturerSelection(from: model), let id = linked.catalogId else { return nil }
        return (id, linked.displayText)
    }

    func classificationLabels() -> (roles: [String: String], operations: [String: String]) {
        guard let catalog else { return ([:], [:]) }
        return (
            labels(in: catalog, dimension: "aircraft-role"),
            labels(in: catalog, dimension: "operation-type")
        )
    }

    func searchOperators(query: String, limit: Int) async -> AviationSearchOutcome<AviationOperator>? {
        guard let catalog else { return nil }
        return try? await Task.detached(priority: .userInitiated) {
            try searchOutcome(catalog.resolveOperators(query: query, limit: limit))
        }.value
    }

    func searchManufacturers(query: String, limit: Int) async -> AviationSearchOutcome<AviationManufacturer>? {
        guard let catalog else { return nil }
        return try? await Task.detached(priority: .userInitiated) {
            let records = try catalog.searchManufacturers(query: query, limit: limit)
            let unmatched = records.isEmpty && catalogQueryGuidance(query) == .ready
            return AviationSearchOutcome(records: records, ambiguous: false, unmatched: unmatched)
        }.value
    }

    func searchAirports(query: String, limit: Int) async -> AviationSearchOutcome<AviationAirport>? {
        guard let catalog else { return nil }
        return try? await Task.detached(priority: .userInitiated) {
            try searchOutcome(catalog.resolveAirports(query: query, limit: limit))
        }.value
    }

    func searchAircraft(
        query: String,
        limit: Int,
        manufacturerId: String?
    ) async -> AviationSearchOutcome<AircraftModel>? {
        guard let catalog else { return nil }
        return try? await Task.detached(priority: .userInitiated) {
            if let manufacturerId {
                let records = try catalog.searchAircraft(query: query, limit: limit, manufacturerId: manufacturerId)
                return AviationSearchOutcome(
                    records: records,
                    ambiguous: false,
                    unmatched: records.isEmpty && catalogQueryGuidance(query) == .ready
                )
            }
            return try searchOutcome(catalog.resolveAircraft(query: query, limit: limit))
        }.value
    }

    private func startLoad() {
        phase = .loading
        errorMessage = nil
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.loadCatalog()
        }
    }

    private func loadCatalog() async {
        do {
            let loaded = try await repository.catalog()
            if Task.isCancelled { return }
            catalog = loaded
            loadState.succeed()
            phase = loadState.phase
            errorMessage = nil
        } catch {
            if Task.isCancelled { return }
            loadState.fail()
            phase = loadState.phase
            errorMessage = "The aviation catalog could not be loaded."
        }
    }

    private func exists<T>(_ id: String?, lookup: (String) -> T?) -> Bool? {
        guard phase == .ready, let id, !id.isEmpty else { return nil }
        return lookup(id) != nil
    }

    private func labels(in catalog: AviationCatalog, dimension: String) -> [String: String] {
        guard let values = catalog.classifications.first(where: { $0.id == dimension })?.values else { return [:] }
        return Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0.label) })
    }

}

private func searchOutcome<Record: Sendable>(
    _ resolution: AviationQueryResolution<Record>
) -> AviationSearchOutcome<Record> {
    switch resolution {
    case .blank:
        return AviationSearchOutcome(records: [], ambiguous: false, unmatched: false)
    case .matches(let records):
        return AviationSearchOutcome(records: records, ambiguous: false, unmatched: false)
    case .ambiguous(let records):
        return AviationSearchOutcome(records: records, ambiguous: true, unmatched: false)
    case .unmatched:
        return AviationSearchOutcome(records: [], ambiguous: false, unmatched: true)
    }
}

@MainActor
final class CatalogQueryModel<Record: Identifiable & Sendable>: ObservableObject {
    @Published var query = ""
    @Published var records: [Record] = []
    @Published var ambiguous = false
    @Published var unmatched = false
    @Published var searching = false
    @Published private(set) var limit = 20

    private let gate = LatestQueryGate()
    private var task: Task<Void, Never>?
    private let search: @MainActor (String, Int) async -> AviationSearchOutcome<Record>?

    init(search: @escaping @MainActor (String, Int) async -> AviationSearchOutcome<Record>?) {
        self.search = search
    }

    var canLoadMore: Bool {
        catalogQueryGuidance(query) == .ready && records.count >= limit && limit < 100 && !searching
    }

    func setQuery(_ query: String) {
        self.query = query
        limit = 20
        schedule()
    }

    func loadMore() {
        guard canLoadMore else { return }
        limit += 20
        schedule()
    }

    func cancel() {
        task?.cancel()
        searching = false
    }

    private func schedule() {
        task?.cancel()
        let query = query
        let limit = limit
        guard catalogQueryGuidance(query) == .ready else {
            records = []
            ambiguous = false
            unmatched = false
            searching = false
            return
        }
        searching = true
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self, !Task.isCancelled else { return }
            let token = await self.gate.issue()
            let outcome = await self.search(query, limit)
            guard !Task.isCancelled, await self.gate.isCurrent(token) else { return }
            self.searching = false
            self.records = outcome?.records ?? []
            self.ambiguous = outcome?.ambiguous ?? false
            self.unmatched = outcome?.unmatched ?? false
        }
    }
}
