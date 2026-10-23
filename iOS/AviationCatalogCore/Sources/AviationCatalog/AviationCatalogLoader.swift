import CryptoKit
import Foundation

public enum AviationCatalogLoader {
    public static let supportedSchemaVersion = 1
    private static let fileNames = [
        "operators.json",
        "manufacturers.json",
        "aircraft.json",
        "airports.json",
        "classifications.json",
    ]

    public static func load() throws -> AviationCatalog {
        try load(bundle: .module)
    }

    static func load(bundle: Bundle) throws -> AviationCatalog {
        let manifestData = try data(named: "catalog-manifest.json", bundle: bundle)
        let manifest = try object(manifestData, name: "catalog-manifest.json")
        let schemaVersion = try int(manifest, "schemaVersion", file: "catalog-manifest.json")
        if schemaVersion != supportedSchemaVersion {
            throw AviationCatalogError.unsupportedSchema(schemaVersion)
        }
        guard let catalogVersion = string(manifest, "catalogVersion"), !catalogVersion.isEmpty else {
            throw AviationCatalogError.manifestMismatch("catalogVersion")
        }
        guard let files = manifest["files"] as? [String: Any] else {
            throw AviationCatalogError.manifestMismatch("files")
        }
        var raw: [String: Data] = [:]
        for name in fileNames {
            let fileData = try data(named: name, bundle: bundle)
            raw[name] = fileData
            guard let listed = files[name] as? [String: Any], let expected = listed["sha256"] as? String else {
                throw AviationCatalogError.manifestMismatch(name)
            }
            let digest = SHA256.hash(data: fileData).map { String(format: "%02x", $0) }.joined()
            if digest != expected {
                throw AviationCatalogError.manifestMismatch(name)
            }
        }
        let operators = try records(raw["operators.json"]!, name: "operators.json").map(operatorRecord)
        let manufacturers = try records(raw["manufacturers.json"]!, name: "manufacturers.json").map(manufacturerRecord)
        let aircraft = try records(raw["aircraft.json"]!, name: "aircraft.json").map(aircraftRecord)
        let airports = try records(raw["airports.json"]!, name: "airports.json").map(airportRecord)
        let classifications = try classificationDimensions(raw["classifications.json"]!)
        if operators.isEmpty || manufacturers.isEmpty || aircraft.isEmpty || airports.isEmpty || classifications.isEmpty {
            throw AviationCatalogError.manifestMismatch("empty dataset")
        }
        return AviationCatalog(
            schemaVersion: schemaVersion,
            catalogVersion: catalogVersion,
            operators: operators,
            manufacturers: manufacturers,
            aircraft: aircraft,
            airports: airports,
            classifications: classifications
        )
    }

    static func data(named name: String, bundle: Bundle) throws -> Data {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        let url = bundle.url(forResource: base, withExtension: ext)
            ?? bundle.url(forResource: base, withExtension: ext, subdirectory: "Resources")
        guard let url else { throw AviationCatalogError.resourceMissing(name) }
        return try Data(contentsOf: url)
    }
}

func object(_ data: Data, name: String) throws -> [String: Any] {
    let parsed: Any
    do {
        parsed = try JSONSerialization.jsonObject(with: data)
    } catch {
        throw AviationCatalogError.invalidJSON(name)
    }
    guard let object = parsed as? [String: Any] else {
        throw AviationCatalogError.invalidJSON(name)
    }
    return object
}

func records(_ data: Data, name: String) throws -> [[String: Any]] {
    let document = try object(data, name: name)
    let schema = try int(document, "schemaVersion", file: name)
    if schema != AviationCatalogLoader.supportedSchemaVersion {
        throw AviationCatalogError.unsupportedSchema(schema)
    }
    guard let records = document["records"] as? [[String: Any]] else {
        throw AviationCatalogError.invalidJSON(name)
    }
    return records
}

func operatorRecord(_ json: [String: Any]) throws -> AviationOperator {
    AviationOperator(
        id: try required(json, "id", "operator"),
        name: try required(json, "name", "operator"),
        aliases: strings(json, "aliases"),
        iataCodes: strings(json, "iataCodes"),
        icaoCodes: strings(json, "icaoCodes"),
        callsigns: strings(json, "callsigns"),
        countryCode: string(json, "countryCode"),
        tags: strings(json, "tags"),
        historical: json["historical"] as? Bool ?? false,
        dissolvedOn: string(json, "dissolvedOn"),
        sourceId: try required(json, "sourceId", "operator")
    )
}

func manufacturerRecord(_ json: [String: Any]) throws -> AviationManufacturer {
    AviationManufacturer(
        id: try required(json, "id", "manufacturer"),
        name: try required(json, "name", "manufacturer"),
        aliases: strings(json, "aliases"),
        countryCode: string(json, "countryCode"),
        sourceId: try required(json, "sourceId", "manufacturer")
    )
}

func aircraftRecord(_ json: [String: Any]) throws -> AircraftModel {
    let manufacturerNames = strings(json, "manufacturerNames")
    return AircraftModel(
        id: try required(json, "id", "aircraft"),
        manufacturerId: string(json, "manufacturerId"),
        manufacturer: string(json, "manufacturer"),
        manufacturerNames: manufacturerNames,
        familyId: string(json, "familyId"),
        family: string(json, "family"),
        model: try required(json, "model", "aircraft"),
        displayName: try required(json, "displayName", "aircraft"),
        entryKind: try required(json, "entryKind", "aircraft"),
        icaoTypeDesignators: strings(json, "icaoTypeDesignators"),
        iataEquipmentCodes: strings(json, "iataEquipmentCodes"),
        aliases: strings(json, "aliases"),
        sourceId: try required(json, "sourceId", "aircraft")
    )
}

func airportRecord(_ json: [String: Any]) throws -> AviationAirport {
    guard let latitude = number(json, "latitude"),
          let longitude = number(json, "longitude"),
          let scheduled = json["scheduledService"] as? Bool else {
        throw AviationCatalogError.invalidRecord("airport \(json["id"] ?? "")")
    }
    return AviationAirport(
        id: try required(json, "id", "airport"),
        ident: try required(json, "ident", "airport"),
        name: try required(json, "name", "airport"),
        iataCode: string(json, "iataCode"),
        icaoCode: string(json, "icaoCode"),
        gpsCode: string(json, "gpsCode"),
        localCode: string(json, "localCode"),
        countryCode: string(json, "countryCode"),
        municipality: string(json, "municipality"),
        type: try required(json, "type", "airport"),
        latitude: latitude,
        longitude: longitude,
        scheduledService: scheduled,
        aliases: strings(json, "aliases"),
        sourceId: try required(json, "sourceId", "airport")
    )
}

func classificationDimensions(_ data: Data) throws -> [AviationClassificationDimension] {
    let document = try object(data, name: "classifications.json")
    let schema = try int(document, "schemaVersion", file: "classifications.json")
    if schema != AviationCatalogLoader.supportedSchemaVersion {
        throw AviationCatalogError.unsupportedSchema(schema)
    }
    guard let dimensions = document["dimensions"] as? [[String: Any]] else {
        throw AviationCatalogError.invalidJSON("classifications.json")
    }
    return try dimensions.map { dimension in
        let values = (dimension["values"] as? [[String: Any]] ?? []).map { value in
            AviationClassificationValue(
                id: (value["id"] as? String) ?? "",
                label: (value["label"] as? String) ?? ""
            )
        }
        return AviationClassificationDimension(
            id: try required(dimension, "id", "classification"),
            label: try required(dimension, "label", "classification"),
            values: values
        )
    }
}

func required(_ json: [String: Any], _ key: String, _ dataset: String) throws -> String {
    guard let value = json[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw AviationCatalogError.invalidRecord("\(dataset).\(key)")
    }
    return value
}

func string(_ json: [String: Any], _ key: String) -> String? {
    guard let value = json[key] as? String, !value.isEmpty else { return nil }
    return value
}

func strings(_ json: [String: Any], _ key: String) -> [String] {
    (json[key] as? [String]) ?? []
}

func number(_ json: [String: Any], _ key: String) -> Double? {
    if let value = json[key] as? Double { return value }
    if let value = json[key] as? Int { return Double(value) }
    if let value = json[key] as? NSNumber { return value.doubleValue }
    return nil
}

func int(_ json: [String: Any], _ key: String, file: String) throws -> Int {
    if let value = json[key] as? Int { return value }
    throw AviationCatalogError.invalidJSON(file)
}

public actor AviationCatalogRepository {
    private var cached: AviationCatalog?
    private let load: @Sendable () throws -> AviationCatalog

    public init(load: @escaping @Sendable () throws -> AviationCatalog = { try AviationCatalogLoader.load() }) {
        self.load = load
    }

    public func catalog() async throws -> AviationCatalog {
        if let cached { return cached }
        let loaded = try load()
        cached = loaded
        return loaded
    }
}
