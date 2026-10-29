import AviationCatalog
import Foundation
import SmartEntry

extension SpottingEntry {
    func filterableSpotting() -> FilterableSpotting {
        FilterableSpotting(
            id: id.uuidString,
            registration: registration,
            timestamp: timestamp,
            reference: reference
        )
    }
}

extension SortOption {
    var filterSort: SpottingFilterSort {
        switch self {
        case .dateNewest:
            return .dateNewest
        case .dateOldest:
            return .dateOldest
        case .aircraftTypeAZ:
            return .aircraftTypeAZ
        case .aircraftTypeZA:
            return .aircraftTypeZA
        case .airlineAZ:
            return .airlineAZ
        case .airlineZA:
            return .airlineZA
        case .registrationAZ:
            return .registrationAZ
        case .registrationZA:
            return .registrationZA
        }
    }
}

func searchSpottingEntries(
    _ entries: [SpottingEntry],
    searchText: String,
    filters: SpottingFilterState,
    sort: SortOption,
    catalog: any SpottingFilterCatalog,
    calendar: Calendar = .current
) -> [SpottingEntry] {
    let snapshots = entries.map { $0.filterableSpotting() }
    let matched = filteredSpottingResults(
        entries: snapshots,
        searchText: searchText,
        filters: filters,
        catalog: catalog,
        sort: sort.filterSort,
        calendar: calendar
    )
    let lookup = Dictionary(uniqueKeysWithValues: entries.map { ($0.id.uuidString, $0) })
    return matched.compactMap { lookup[$0.id] }
}

enum FilterCatalogBrowse: Hashable {
    case operators
    case manufacturers
    case aircraft
    case locations
}

struct FilterCatalogHit: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var subtitle: String
    var token: FilterToken
}

struct FilterCatalogSearchResult: Equatable, Sendable {
    var hits: [FilterCatalogHit]
    var ambiguous: Bool
    var unmatched: Bool

    static let unavailable = FilterCatalogSearchResult(hits: [], ambiguous: false, unmatched: false)
}

nonisolated func makeFilterCatalog(from catalog: AviationCatalog) -> PreparedSpottingFilterCatalog {
    PreparedSpottingFilterCatalog(
        snapshot: FilterCatalogSnapshot(
            operators: catalog.operators.map { FilterCatalogOperator(id: $0.id, name: $0.name) },
            manufacturers: catalog.manufacturers.map { FilterCatalogNamed(id: $0.id, name: $0.name) },
            aircraft: catalog.aircraft.map {
                FilterCatalogAircraft(
                    id: $0.id,
                    displayName: $0.displayName,
                    manufacturerId: $0.manufacturerId,
                    familyId: $0.familyId,
                    familyName: $0.family,
                    entryKind: $0.entryKind
                )
            },
            airports: catalog.airports.map { FilterCatalogNamed(id: $0.id, name: $0.name) }
        )
    )
}
