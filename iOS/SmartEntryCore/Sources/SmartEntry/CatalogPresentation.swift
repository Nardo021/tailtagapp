import AviationCatalog
import Foundation

public struct LabeledCode: Equatable, Sendable {
    public var title: String
    public var code: String

    public init(title: String, code: String) {
        self.title = title
        self.code = code
    }
}

public enum CatalogPresentation {
    public static func operatorCodeSummary(_ record: AviationOperator) -> String {
        var parts: [String] = []
        if !record.iataCodes.isEmpty {
            parts.append("IATA \(record.iataCodes.joined(separator: ", "))")
        }
        if !record.icaoCodes.isEmpty {
            parts.append("ICAO \(record.icaoCodes.joined(separator: ", "))")
        }
        if !record.callsigns.isEmpty {
            parts.append(record.callsigns.joined(separator: ", "))
        }
        if let country = cleanedIdentifier(record.countryCode) {
            parts.append(country)
        }
        return parts.joined(separator: " · ")
    }

    public static func operatorAccessibilityLabel(_ record: AviationOperator) -> String {
        var pieces = [record.name, operatorCodeSummary(record)].filter { !$0.isEmpty }
        if record.historical {
            pieces.append("Historical")
            if let dissolved = cleanedIdentifier(record.dissolvedOn) {
                pieces.append("dissolved \(dissolved)")
            }
        }
        return pieces.joined(separator: ", ")
    }

    public static func primaryAirportCode(_ airport: AviationAirport) -> LabeledCode? {
        if let iata = cleanedIdentifier(airport.iataCode) {
            return LabeledCode(title: "IATA", code: iata)
        }
        if let icao = cleanedIdentifier(airport.icaoCode) {
            return LabeledCode(title: "ICAO", code: icao)
        }
        if let ident = cleanedIdentifier(airport.ident) {
            return LabeledCode(title: "Ident", code: ident)
        }
        return nil
    }

    public static func airportTypeLabel(_ type: String) -> String {
        switch type {
        case "closed":
            return "Closed"
        case "heliport":
            return "Heliport"
        case "small_airport":
            return "Small airport"
        case "medium_airport":
            return "Medium airport"
        case "large_airport":
            return "Large airport"
        case "seaplane_base":
            return "Seaplane base"
        case "balloonport":
            return "Balloonport"
        default:
            let words = type.replacingOccurrences(of: "_", with: " ")
            return words.prefix(1).uppercased() + words.dropFirst()
        }
    }

    public static func isClosedAirport(_ airport: AviationAirport) -> Bool {
        airport.type == "closed"
    }

    public static func airportSubtitle(_ airport: AviationAirport) -> String {
        var parts: [String] = []
        if let code = primaryAirportCode(airport) {
            parts.append("\(code.title) \(code.code)")
        }
        if let municipality = cleanedIdentifier(airport.municipality) {
            parts.append(municipality)
        }
        if let country = cleanedIdentifier(airport.countryCode) {
            parts.append(country)
        }
        if !airport.type.isEmpty {
            parts.append(airportTypeLabel(airport.type))
        }
        return parts.joined(separator: " · ")
    }

    public static func airportSnapshot(_ airport: AviationAirport) -> String {
        guard let code = primaryAirportCode(airport) else { return airport.name }
        if code.title == "Ident" {
            return "\(airport.name) (ident \(code.code))"
        }
        return "\(airport.name) (\(code.code))"
    }

    public static func airportAccessibilityLabel(_ airport: AviationAirport) -> String {
        var pieces = [airport.name, airportSubtitle(airport)].filter { !$0.isEmpty }
        if isClosedAirport(airport) {
            pieces.append("Closed")
        }
        return pieces.joined(separator: ", ")
    }

    public static func aircraftSubtitle(_ model: AircraftModel) -> String {
        var parts: [String] = [aircraftKindLabel(model.entryKind)]
        if let manufacturer = cleanedIdentifier(model.manufacturer) {
            parts.append(manufacturer)
        }
        if let family = cleanedIdentifier(model.family), family != model.displayName, family != model.model {
            parts.append(family)
        }
        if let designators = officialDesignatorText(model.icaoTypeDesignators) {
            parts.append("ICAO \(designators)")
        }
        return parts.joined(separator: " · ")
    }

    public static func aircraftAccessibilityLabel(_ model: AircraftModel) -> String {
        "\(model.displayName), \(aircraftSubtitle(model))"
    }

    public static func manufacturerSubtitle(_ record: AviationManufacturer) -> String {
        cleanedIdentifier(record.countryCode) ?? ""
    }
}

public enum ClassificationCopy {
    public static let roleLabels: [String: String] = [
        "civil": "Civil",
        "military": "Military",
        "unknown": "Unknown",
        "other": "Other",
    ]

    public static let operationLabels: [String: String] = [
        "passenger": "Passenger",
        "cargo": "Cargo",
        "private": "Private",
        "general-aviation": "General aviation",
        "government": "Government",
        "training": "Training",
        "emergency-services": "Emergency services",
        "mixed": "Mixed",
        "unknown": "Unknown",
        "other": "Other",
    ]

    public static let roleDescriptions: [String: String] = [
        "civil": "Civil aircraft, including airline, private, and other non-military flying.",
        "military": "Military or armed-forces aircraft.",
        "unknown": "The role is not known.",
        "other": "A role that is not listed.",
    ]

    public static let operationDescriptions: [String: String] = [
        "passenger": "Carrying passengers.",
        "cargo": "Carrying freight.",
        "private": "Private or personal flying.",
        "general-aviation": "General aviation that is not a scheduled airline service.",
        "government": "Government flying that is not necessarily military.",
        "training": "Training or instructional flying.",
        "emergency-services": "Emergency, medical, or rescue flying.",
        "mixed": "More than one kind of operation.",
        "unknown": "The operation is not known.",
        "other": "An operation that is not listed.",
    ]

    public static let roleOrder = ["civil", "military", "unknown", "other"]
    public static let operationOrder = [
        "passenger", "cargo", "private", "general-aviation", "government",
        "training", "emergency-services", "mixed", "unknown", "other",
    ]

    public static func roleLabel(_ id: String, catalogLabels: [String: String] = [:]) -> String {
        catalogLabels[id] ?? roleLabels[id] ?? id
    }

    public static func operationLabel(_ id: String, catalogLabels: [String: String] = [:]) -> String {
        catalogLabels[id] ?? operationLabels[id] ?? id
    }
}
