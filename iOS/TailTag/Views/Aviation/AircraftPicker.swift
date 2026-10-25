import AviationCatalog
import SmartEntry
import SwiftUI

struct AircraftPicker: View {
    @ObservedObject var model: CatalogQueryModel<AircraftModel>
    let current: AviationSelection
    let manufacturerName: String?
    @Binding var searchEntireCatalog: Bool
    let isLoadingCatalog: Bool
    let errorMessage: String?
    let accent: Color
    let onConfirm: (AviationPickerChoice<AircraftModel>) -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void

    var body: some View {
        AviationSearchPicker(
            title: "Aircraft Model / Family",
            searchPrompt: "Model, family, manufacturer, or alias",
            currentSummary: selectionSummary(current, emptyPlaceholder: "No aircraft selected"),
            allowsUnknown: true,
            absentTitle: "No aircraft type",
            ambiguousMessage: model.ambiguous ? "Several aircraft match this code. Choose the specific one." : nil,
            emptyMessage: emptyMessage,
            results: model.records,
            query: model.query,
            guidance: catalogQueryGuidance(model.query),
            isLoadingCatalog: isLoadingCatalog,
            isSearching: model.searching,
            errorMessage: errorMessage,
            canLoadMore: model.canLoadMore,
            accent: accent,
            onQuery: model.setQuery,
            onLoadMore: model.loadMore,
            onRetry: onRetry,
            onConfirm: onConfirm,
            onCancel: {
                model.cancel()
                onCancel()
            },
            header: {
                if manufacturerName != nil {
                    Toggle(isOn: $searchEntireCatalog) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Search all manufacturers")
                            Text(searchEntireCatalog ? "Results are from the full catalog." : "Results prefer \(manufacturerName ?? "the selected manufacturer").")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(accent)
                }
            },
            row: { record in
                let designator = officialDesignatorText(record.icaoTypeDesignators)
                CatalogResultLabel(
                    title: record.displayName,
                    subtitle: designator == nil
                        ? CatalogPresentation.aircraftSubtitle(record)
                        : CatalogPresentation.aircraftSubtitle(record),
                    badges: [aircraftKindLabel(record.entryKind)]
                )
                .accessibilityLabel(CatalogPresentation.aircraftAccessibilityLabel(record))
            }
        )
    }

    private var emptyMessage: String {
        if manufacturerName != nil && !searchEntireCatalog {
            return "No matches for this manufacturer. Search the full catalog, or use custom text."
        }
        return "No aircraft match. A family is not a specific model. You can use custom text."
    }
}

struct AirportPicker: View {
    @ObservedObject var model: CatalogQueryModel<AviationAirport>
    let current: AviationSelection
    let isLoadingCatalog: Bool
    let errorMessage: String?
    let accent: Color
    let onConfirm: (AviationPickerChoice<AviationAirport>) -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void

    var body: some View {
        AviationSearchPicker(
            title: "Location / Airport",
            searchPrompt: "Airport, city, ICAO, IATA, or ident",
            currentSummary: selectionSummary(current, emptyPlaceholder: "No location"),
            allowsUnknown: true,
            absentTitle: nil,
            ambiguousMessage: model.ambiguous ? "Several places match this code. Choose the specific one." : nil,
            emptyMessage: "No airports match. A street, park, or airshow can be saved as custom text.",
            results: model.records,
            query: model.query,
            guidance: catalogQueryGuidance(model.query),
            isLoadingCatalog: isLoadingCatalog,
            isSearching: model.searching,
            errorMessage: errorMessage,
            canLoadMore: model.canLoadMore,
            accent: accent,
            onQuery: model.setQuery,
            onLoadMore: model.loadMore,
            onRetry: onRetry,
            onConfirm: onConfirm,
            onCancel: {
                model.cancel()
                onCancel()
            },
            header: { EmptyView() },
            row: { airport in
                CatalogResultLabel(
                    title: airport.name,
                    subtitle: CatalogPresentation.airportSubtitle(airport),
                    badges: CatalogPresentation.isClosedAirport(airport) ? ["Closed"] : []
                )
                .accessibilityLabel(CatalogPresentation.airportAccessibilityLabel(airport))
            }
        )
    }
}
