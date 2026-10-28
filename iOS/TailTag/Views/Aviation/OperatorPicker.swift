import AviationCatalog
import SmartEntry
import SwiftUI

struct OperatorPicker: View {
    @ObservedObject var model: CatalogQueryModel<AviationOperator>
    let current: AviationSelection
    let isLoadingCatalog: Bool
    let errorMessage: String?
    let accent: Color
    let onConfirm: (AviationPickerChoice<AviationOperator>) -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void

    var body: some View {
        AviationSearchPicker(
            title: "Airline / Operator",
            searchPrompt: "Name, alias, IATA, ICAO, or callsign",
            currentSummary: selectionSummary(current, emptyPlaceholder: "No operator"),
            allowsUnknown: true,
            absentTitle: "No operator",
            ambiguousMessage: model.ambiguous ? "Several operators share this code. Choose the specific one." : nil,
            emptyMessage: model.unmatched ? "No catalog operators match. You can use the text above as a custom entry." : "No catalog operators match.",
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
            row: { record in
                CatalogResultLabel(
                    title: record.name,
                    subtitle: CatalogPresentation.operatorCodeSummary(record),
                    badges: record.historical ? ["Historical"] : []
                )
                .accessibilityLabel(CatalogPresentation.operatorAccessibilityLabel(record))
            }
        )
    }
}

struct ManufacturerPicker: View {
    @ObservedObject var model: CatalogQueryModel<AviationManufacturer>
    let current: AviationSelection
    let isLoadingCatalog: Bool
    let errorMessage: String?
    let accent: Color
    let onConfirm: (AviationPickerChoice<AviationManufacturer>) -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void

    var body: some View {
        AviationSearchPicker(
            title: "Manufacturer",
            searchPrompt: "Manufacturer name",
            currentSummary: selectionSummary(current, emptyPlaceholder: "No manufacturer"),
            allowsUnknown: true,
            absentTitle: "No manufacturer",
            ambiguousMessage: nil,
            emptyMessage: "No manufacturers match. You can use custom text instead.",
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
            row: { record in
                CatalogResultLabel(
                    title: record.name,
                    subtitle: CatalogPresentation.manufacturerSubtitle(record)
                )
                .accessibilityLabel(record.name)
            }
        )
    }
}
