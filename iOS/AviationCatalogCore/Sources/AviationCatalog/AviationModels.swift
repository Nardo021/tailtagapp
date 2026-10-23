import Foundation

public enum AviationReference<ID: Hashable & Sendable>: Equatable, Sendable {
    /// A record that exists in the catalog.
    case catalog(ID)
    /// The user explicitly does not know the value. This is not a catalog record.
    case unknown
    /// Text the user entered that did not resolve to a catalog record.
    case custom(String)
    /// No value was supplied.
    case absent
}

public enum AviationCatalogError: Error, Equatable, Sendable {
    case resourceMissing(String)
    case invalidJSON(String)
    case unsupportedSchema(Int)
    case manifestMismatch(String)
    case invalidLimit
    case invalidRecord(String)
}

public struct AviationOperator: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let aliases: [String]
    public let iataCodes: [String]
    public let icaoCodes: [String]
    public let callsigns: [String]
    public let countryCode: String?
    public let tags: [String]
    public let historical: Bool
    public let dissolvedOn: String?
    public let sourceId: String
}

public struct AircraftModel: Equatable, Identifiable, Sendable {
    public let id: String
    public let manufacturerId: String?
    public let manufacturer: String?
    public let manufacturerNames: [String]
    public let familyId: String?
    public let family: String?
    public let model: String
    public let displayName: String
    public let entryKind: String
    public let icaoTypeDesignators: [String]
    public let iataEquipmentCodes: [String]
    public let aliases: [String]
    public let sourceId: String
}

public struct AviationAirport: Equatable, Identifiable, Sendable {
    public let id: String
    public let ident: String
    public let name: String
    public let iataCode: String?
    public let icaoCode: String?
    public let gpsCode: String?
    public let localCode: String?
    public let countryCode: String?
    public let municipality: String?
    public let type: String
    public let latitude: Double
    public let longitude: Double
    public let scheduledService: Bool
    public let aliases: [String]
    public let sourceId: String
}

public struct AviationManufacturer: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let aliases: [String]
    public let countryCode: String?
    public let sourceId: String
}

public struct AviationClassificationValue: Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
}

public struct AviationClassificationDimension: Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let values: [AviationClassificationValue]
}

public struct AviationCatalog: Sendable {
    public let schemaVersion: Int
    public let catalogVersion: String
    public let operators: [AviationOperator]
    public let manufacturers: [AviationManufacturer]
    public let aircraft: [AircraftModel]
    public let airports: [AviationAirport]
    public let classifications: [AviationClassificationDimension]
    let operatorIndex: AviationSearchIndex<AviationOperator>
    let aircraftIndex: AviationSearchIndex<AircraftModel>
    let airportIndex: AviationSearchIndex<AviationAirport>
    let manufacturerIndex: AviationSearchIndex<AviationManufacturer>
    private let operatorsById: [String: AviationOperator]
    private let aircraftById: [String: AircraftModel]
    private let airportsById: [String: AviationAirport]
    private let manufacturersById: [String: AviationManufacturer]

    init(
        schemaVersion: Int,
        catalogVersion: String,
        operators: [AviationOperator],
        manufacturers: [AviationManufacturer],
        aircraft: [AircraftModel],
        airports: [AviationAirport],
        classifications: [AviationClassificationDimension]
    ) {
        self.schemaVersion = schemaVersion
        self.catalogVersion = catalogVersion
        self.operators = operators
        self.manufacturers = manufacturers
        self.aircraft = aircraft
        self.airports = airports
        self.classifications = classifications
        operatorIndex = AviationSearchIndex(
            records: operators,
            id: { $0.id },
            codes: { $0.iataCodes + $0.icaoCodes + $0.callsigns + [$0.id] },
            names: { [$0.name] + $0.aliases }
        )
        manufacturerIndex = AviationSearchIndex(
            records: manufacturers,
            id: { $0.id },
            codes: { [$0.id] },
            names: { [$0.name] + $0.aliases }
        )
        aircraftIndex = AviationSearchIndex(
            records: aircraft,
            id: { $0.id },
            codes: { $0.icaoTypeDesignators + $0.iataEquipmentCodes + [$0.id] },
            names: {
                var names = $0.manufacturerNames
                if let manufacturer = $0.manufacturer { names.append(manufacturer) }
                if let family = $0.family { names.append(family) }
                names.append($0.model)
                names.append($0.displayName)
                names.append(contentsOf: $0.aliases)
                return names
            }
        )
        airportIndex = AviationSearchIndex(
            records: airports,
            id: { $0.id },
            codes: { [$0.iataCode, $0.icaoCode, $0.ident, $0.gpsCode, $0.localCode, $0.id].compactMap { $0 } },
            names: { [$0.name, $0.municipality].compactMap { $0 } + $0.aliases }
        )
        operatorsById = Dictionary(uniqueKeysWithValues: operators.map { ($0.id, $0) })
        aircraftById = Dictionary(uniqueKeysWithValues: aircraft.map { ($0.id, $0) })
        airportsById = Dictionary(uniqueKeysWithValues: airports.map { ($0.id, $0) })
        manufacturersById = Dictionary(uniqueKeysWithValues: manufacturers.map { ($0.id, $0) })
    }

    public func searchOperators(query: String, limit: Int = 20) throws -> [AviationOperator] {
        try operatorIndex.search(query: query, limit: limit)
    }

    public func searchAircraft(query: String, limit: Int = 20) throws -> [AircraftModel] {
        try aircraftIndex.search(query: query, limit: limit)
    }

    public func searchAirports(query: String, limit: Int = 20) throws -> [AviationAirport] {
        try airportIndex.search(query: query, limit: limit)
    }

    public func searchManufacturers(query: String, limit: Int = 20) throws -> [AviationManufacturer] {
        try manufacturerIndex.search(query: query, limit: limit)
    }

    public func operatorById(_ id: String) -> AviationOperator? { operatorsById[id] }
    public func aircraftById(_ id: String) -> AircraftModel? { aircraftById[id] }
    public func airportById(_ id: String) -> AviationAirport? { airportsById[id] }
    public func manufacturerById(_ id: String) -> AviationManufacturer? { manufacturersById[id] }

    public func resolveOperators(query: String, limit: Int = 20) throws -> AviationQueryResolution<AviationOperator> {
        let matches = try searchOperators(query: query, limit: limit)
        return resolveAviationQuery(query, matches: matches, exactCodeCount: operatorIndex.exactCodeCount(query: query))
    }

    public func resolveAircraft(query: String, limit: Int = 20) throws -> AviationQueryResolution<AircraftModel> {
        let matches = try searchAircraft(query: query, limit: limit)
        return resolveAviationQuery(query, matches: matches, exactCodeCount: aircraftIndex.exactCodeCount(query: query))
    }

    public func resolveAirports(query: String, limit: Int = 20) throws -> AviationQueryResolution<AviationAirport> {
        let matches = try searchAirports(query: query, limit: limit)
        return resolveAviationQuery(query, matches: matches, exactCodeCount: airportIndex.exactCodeCount(query: query))
    }
}

extension AviationCatalog: Equatable {
    public static func == (lhs: AviationCatalog, rhs: AviationCatalog) -> Bool {
        lhs.schemaVersion == rhs.schemaVersion
            && lhs.catalogVersion == rhs.catalogVersion
            && lhs.operators == rhs.operators
            && lhs.manufacturers == rhs.manufacturers
            && lhs.aircraft == rhs.aircraft
            && lhs.airports == rhs.airports
            && lhs.classifications == rhs.classifications
    }
}
