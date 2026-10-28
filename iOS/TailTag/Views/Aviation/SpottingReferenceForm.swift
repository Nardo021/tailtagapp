import AviationCatalog
import SmartEntry
import SwiftUI

private final class AircraftSearchFilter {
    var entireCatalog = false
}

enum ReferenceSheet: String, Identifiable {
    case `operator`
    case manufacturer
    case aircraft
    case airport
    case role
    case operation

    var id: String { rawValue }
}

struct SpottingReferenceForm: View {
    @ObservedObject var editor: SpottingEditorModel
    @ObservedObject var catalog: AviationCatalogUIService
    let accent: Color

    @State private var sheet: ReferenceSheet?
    @State private var searchEntireCatalog = false
    @State private var didBindQueries = false
    @State private var aircraftFilter = AircraftSearchFilter()
    @State private var operatorQuery = CatalogQueryModel<AviationOperator> { _, _ in nil }
    @State private var manufacturerQuery = CatalogQueryModel<AviationManufacturer> { _, _ in nil }
    @State private var aircraftQuery = CatalogQueryModel<AircraftModel> { _, _ in nil }
    @State private var airportQuery = CatalogQueryModel<AviationAirport> { _, _ in nil }

    var body: some View {
        Group {
            Section("Aircraft") {
                Button { sheet = .operator } label: {
                    SelectionValueRow(
                        title: "Airline / Operator",
                        selection: editor.reference.operatorField,
                        placeholder: "No operator",
                        accent: accent
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("field-operator")

                Button { sheet = .manufacturer } label: {
                    SelectionValueRow(
                        title: "Manufacturer",
                        selection: editor.reference.manufacturerField,
                        placeholder: "Optional",
                        accent: accent
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("field-manufacturer")

                Button { sheet = .aircraft } label: {
                    SelectionValueRow(
                        title: "Aircraft Model / Family",
                        selection: editor.reference.aircraftField,
                        placeholder: "Optional",
                        accent: accent
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("field-aircraft")
            }

            Section("Location") {
                Button { sheet = .airport } label: {
                    SelectionValueRow(
                        title: "Location / Airport",
                        selection: editor.reference.locationField,
                        placeholder: "Airport or place",
                        accent: accent
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("field-location")
            }

            Section("Classification") {
                Button { sheet = .role } label: {
                    classificationRow(
                        title: "Aircraft role",
                        id: editor.reference.classification.roleId,
                        note: editor.reference.classification.roleNote,
                        labels: catalog.classificationLabels().roles,
                        fallback: ClassificationCopy.roleLabels
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("field-role")

                Button { sheet = .operation } label: {
                    classificationRow(
                        title: "Operation type",
                        id: editor.reference.classification.operationTypeId,
                        note: editor.reference.classification.operationTypeNote,
                        labels: catalog.classificationLabels().operations,
                        fallback: ClassificationCopy.operationLabels
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("field-operation")

                if catalog.phase == .loading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Catalog loading. Custom text can still be saved.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if catalog.phase == .failed {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(catalog.errorMessage ?? "The aviation catalog could not be loaded.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Try again") { catalog.retry() }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                }
            }
        }
        .onAppear {
            catalog.prepare()
            if !didBindQueries {
                bindQueries()
                didBindQueries = true
            }
            editor.reconcile(with: catalog)
        }
        .onChange(of: searchEntireCatalog) { _, entire in
            aircraftFilter.entireCatalog = entire
            aircraftQuery.setQuery(aircraftQuery.query)
        }
        .onChange(of: catalog.phase) { _, phase in
            editor.reconcile(with: catalog)
            if phase == .ready {
                operatorQuery.setQuery(operatorQuery.query)
                manufacturerQuery.setQuery(manufacturerQuery.query)
                aircraftQuery.setQuery(aircraftQuery.query)
                airportQuery.setQuery(airportQuery.query)
            }
        }
        .navigationDestination(item: $sheet) { sheet in
            picker(for: sheet)
        }
        .alert(
            "Manufacturer doesn't match",
            isPresented: Binding(
                get: { editor.pendingManufacturer != nil },
                set: { if !$0 { editor.cancelPendingManufacturer() } }
            )
        ) {
            Button("Keep aircraft") { editor.resolvePendingManufacturer(keepAircraft: true) }
            Button("Clear aircraft", role: .destructive) { editor.resolvePendingManufacturer(keepAircraft: false) }
            Button("Cancel", role: .cancel) { editor.cancelPendingManufacturer() }
        } message: {
            Text("The selected aircraft is linked to a different manufacturer. Keep the aircraft and its manufacturer, or clear the aircraft and use the manufacturer you chose.")
        }
    }

    @ViewBuilder
    private func picker(for sheet: ReferenceSheet) -> some View {
        switch sheet {
        case .operator:
            OperatorPicker(
                model: operatorQuery,
                current: editor.reference.operatorField,
                isLoadingCatalog: catalog.phase == .loading,
                errorMessage: catalog.phase == .failed ? catalog.errorMessage : nil,
                accent: accent,
                onConfirm: { choice in
                    editor.commitOperator(operatorSelection(choice))
                    self.sheet = nil
                },
                onCancel: { self.sheet = nil },
                onRetry: catalog.retry
            )
        case .manufacturer:
            ManufacturerPicker(
                model: manufacturerQuery,
                current: editor.reference.manufacturerField,
                isLoadingCatalog: catalog.phase == .loading,
                errorMessage: catalog.phase == .failed ? catalog.errorMessage : nil,
                accent: accent,
                onConfirm: { choice in
                    let link = catalog.aircraftManufacturerLink(for: editor.reference.aircraftField.catalogId)
                    editor.proposeManufacturer(
                        manufacturerSelection(choice),
                        aircraftManufacturerId: link?.id,
                        aircraftManufacturerName: link?.name
                    )
                    self.sheet = nil
                },
                onCancel: { self.sheet = nil },
                onRetry: catalog.retry
            )
        case .aircraft:
            AircraftPicker(
                model: aircraftQuery,
                current: editor.reference.aircraftField,
                manufacturerName: editor.reference.manufacturerField.kind == .catalog ? editor.reference.manufacturerField.displayText : nil,
                searchEntireCatalog: $searchEntireCatalog,
                isLoadingCatalog: catalog.phase == .loading,
                errorMessage: catalog.phase == .failed ? catalog.errorMessage : nil,
                accent: accent,
                onConfirm: { choice in
                    switch choice {
                    case .record(let model):
                        editor.commitAircraft(
                            aircraftSelection(from: model),
                            linkedManufacturer: linkedManufacturerSelection(from: model)
                        )
                    case .custom(let text):
                        editor.commitAircraft(.custom(from: text) ?? .absent, linkedManufacturer: nil)
                    case .unknown:
                        editor.commitAircraft(.unknown(), linkedManufacturer: nil)
                    case .absent:
                        editor.commitAircraft(.absent, linkedManufacturer: nil)
                    }
                    self.sheet = nil
                },
                onCancel: { self.sheet = nil },
                onRetry: catalog.retry
            )
        case .airport:
            AirportPicker(
                model: airportQuery,
                current: editor.reference.locationField,
                isLoadingCatalog: catalog.phase == .loading,
                errorMessage: catalog.phase == .failed ? catalog.errorMessage : nil,
                accent: accent,
                onConfirm: { choice in
                    editor.commitLocation(locationSelection(choice))
                    self.sheet = nil
                },
                onCancel: { self.sheet = nil },
                onRetry: catalog.retry
            )
        case .role:
            let labels = mergedLabels(ClassificationCopy.roleLabels, catalog.classificationLabels().roles)
            ClassificationPicker(
                title: "Aircraft role",
                description: "Role is separate from the kind of operation.",
                options: ClassificationCopy.roleOrder,
                labels: labels,
                descriptions: ClassificationCopy.roleDescriptions,
                selectedID: editor.reference.classification.roleId,
                note: editor.reference.classification.roleNote,
                accent: accent,
                onConfirm: { id, note in
                    editor.commitRole(id, note: note)
                    self.sheet = nil
                },
                onCancel: { self.sheet = nil }
            )
        case .operation:
            let labels = mergedLabels(ClassificationCopy.operationLabels, catalog.classificationLabels().operations)
            ClassificationPicker(
                title: "Operation type",
                description: "Operation is separate from civil or military role.",
                options: ClassificationCopy.operationOrder,
                labels: labels,
                descriptions: ClassificationCopy.operationDescriptions,
                selectedID: editor.reference.classification.operationTypeId,
                note: editor.reference.classification.operationTypeNote,
                accent: accent,
                onConfirm: { id, note in
                    editor.commitOperation(id, note: note)
                    self.sheet = nil
                },
                onCancel: { self.sheet = nil }
            )
        }
    }

    private func bindQueries() {
        let catalog = catalog
        let editor = editor
        let filter = aircraftFilter
        operatorQuery = CatalogQueryModel { query, limit in
            await catalog.searchOperators(query: query, limit: limit)
        }
        manufacturerQuery = CatalogQueryModel { query, limit in
            await catalog.searchManufacturers(query: query, limit: limit)
        }
        aircraftQuery = CatalogQueryModel { query, limit in
            let manufacturerId = filter.entireCatalog || editor.reference.manufacturerField.kind != .catalog
                ? nil
                : editor.reference.manufacturerField.catalogId
            return await catalog.searchAircraft(query: query, limit: limit, manufacturerId: manufacturerId)
        }
        airportQuery = CatalogQueryModel { query, limit in
            await catalog.searchAirports(query: query, limit: limit)
        }
    }

    private func operatorSelection(_ choice: AviationPickerChoice<AviationOperator>) -> AviationSelection {
        switch choice {
        case .record(let record):
            return .catalog(id: record.id, displayText: record.name, detail: nil)
        case .custom(let text):
            return .custom(from: text) ?? .absent
        case .unknown:
            return .unknown()
        case .absent:
            return .absent
        }
    }

    private func manufacturerSelection(_ choice: AviationPickerChoice<AviationManufacturer>) -> AviationSelection {
        switch choice {
        case .record(let record):
            return .catalog(id: record.id, displayText: record.name)
        case .custom(let text):
            return .custom(from: text) ?? .absent
        case .unknown:
            return .unknown()
        case .absent:
            return .absent
        }
    }

    private func locationSelection(_ choice: AviationPickerChoice<AviationAirport>) -> AviationSelection {
        switch choice {
        case .record(let airport):
            return .catalog(
                id: airport.id,
                displayText: CatalogPresentation.airportSnapshot(airport),
                detail: CatalogPresentation.isClosedAirport(airport) ? "Closed" : nil
            )
        case .custom(let text):
            return .custom(from: text) ?? .absent
        case .unknown:
            return .unknown()
        case .absent:
            return editor.reference.locationField
        }
    }

    private func classificationRow(
        title: String,
        id: String?,
        note: String?,
        labels: [String: String],
        fallback: [String: String]
    ) -> some View {
        let summary = classificationSummary(id: id, note: note, labels: mergedLabels(fallback, labels)) ?? "Optional"
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(summary)
                    .font(.body)
                    .foregroundStyle(id == nil ? .secondary : .primary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(title), \(summary)")
    }

    private func mergedLabels(_ fallback: [String: String], _ catalogLabels: [String: String]) -> [String: String] {
        fallback.merging(catalogLabels) { _, catalog in catalog }
    }
}
