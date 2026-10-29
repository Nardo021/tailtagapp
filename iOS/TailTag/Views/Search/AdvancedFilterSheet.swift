import SmartEntry
import SwiftUI

struct AdvancedFilterSheet: View {
    let entries: [FilterableSpotting]
    let searchText: String
    let catalog: PreparedSpottingFilterCatalog
    let catalogPhase: CatalogLoadPhase
    let accent: Color
    let onCancel: () -> Void
    let onApply: (SpottingFilterState) -> Void

    @State private var draft: SpottingFilterState
    @State private var browse: FilterCatalogBrowse?
    @State private var startEnabled: Bool
    @State private var endEnabled: Bool
    @State private var startDate: Date
    @State private var endDate: Date

    init(
        applied: SpottingFilterState,
        entries: [FilterableSpotting],
        searchText: String,
        catalog: PreparedSpottingFilterCatalog,
        catalogPhase: CatalogLoadPhase,
        accent: Color,
        onCancel: @escaping () -> Void,
        onApply: @escaping (SpottingFilterState) -> Void
    ) {
        self.entries = entries
        self.searchText = searchText
        self.catalog = catalog
        self.catalogPhase = catalogPhase
        self.accent = accent
        self.onCancel = onCancel
        self.onApply = onApply
        _draft = State(initialValue: applied)
        _startEnabled = State(initialValue: applied.dateRange.start != nil)
        _endEnabled = State(initialValue: applied.dateRange.end != nil)
        _startDate = State(initialValue: Self.date(from: applied.dateRange.start) ?? Date())
        _endDate = State(initialValue: Self.date(from: applied.dateRange.end) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Group {
                if let browse {
                    FilterCatalogSearchPage(
                        browse: browse,
                        accent: accent,
                        phase: catalogPhase,
                        onSelect: { token in
                            draft.insert(token)
                            self.browse = nil
                        },
                        onClose: { self.browse = nil }
                    )
                } else {
                    filterForm
                }
            }
        }
    }

    private var filterForm: some View {
        let choices = collectionFilterChoices(entries: entries, catalog: catalog)
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                catalogNotice
                Text(matchSummary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("filter-match-count")
                choiceSection("Operator", choices: choices.operators, dimension: .operators, browse: .operators)
                choiceSection("Manufacturer", choices: choices.manufacturers, dimension: .manufacturers, browse: .manufacturers)
                choiceSection("Aircraft", choices: choices.aircraft, dimension: .aircraft, browse: .aircraft)
                choiceSection("Aircraft role", choices: choices.roles, dimension: .roles, browse: nil)
                choiceSection("Operation type", choices: choices.operationTypes, dimension: .operationTypes, browse: nil)
                choiceSection("Airport / location", choices: choices.locations, dimension: .locations, browse: .locations)
                registrationSection
                dateSection
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Filters")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
                    .accessibilityIdentifier("cancel-filters")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Apply") {
                    onApply(draft)
                }
                .fontWeight(.semibold)
                .disabled(!draft.dateRange.isValid)
                .accessibilityIdentifier("apply-filters")
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Reset all") {
                    draft.reset()
                    startEnabled = false
                    endEnabled = false
                }
                .accessibilityIdentifier("reset-filters")
            }
        }
    }

    private var matchSummary: String {
        let count = filteredSpottingResults(
            entries: entries,
            searchText: searchText,
            filters: draft,
            catalog: catalog,
            sort: .dateNewest,
            calendar: .current
        ).count
        let noun = count == 1 ? "sighting" : "sightings"
        return "\(count) \(noun) match"
    }

    @ViewBuilder
    private var catalogNotice: some View {
        switch catalogPhase {
        case .idle, .loading:
            notice("The aviation catalog is still loading. Saved identities can be selected now.", icon: "clock")
        case .failed:
            notice("Some catalog details are unavailable. Saved identities still match, but family and manufacturer links cannot be resolved.", icon: "exclamationmark.triangle")
        case .ready:
            EmptyView()
        }
    }

    private func notice(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("catalog-filter-notice")
    }

    private func choiceSection(
        _ title: String,
        choices: [FilterChoice],
        dimension: FilterDimension,
        browse: FilterCatalogBrowse?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if dimensionHasSelection(dimension) {
                    Button("Clear") { draft.clear(dimension) }
                        .font(.subheadline)
                        .foregroundStyle(accent)
                }
            }
            if choices.isEmpty {
                Text("No saved values in this collection.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                FilterChoiceButtons(
                    choices: choices,
                    isSelected: { draft.contains($0) },
                    accent: accent,
                    onToggle: { draft.toggle($0) }
                )
            }
            if let browse {
                Button {
                    self.browse = browse
                } label: {
                    Label("Search catalog", systemImage: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(accent)
                .accessibilityIdentifier("search-catalog-\(browseIdentifier(browse))")
            }
        }
    }

    private var registrationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Registration")
                    .font(.headline)
                Spacer()
                if draft.registrationIsActive {
                    Button("Clear") { draft.clear(.registration) }
                        .font(.subheadline)
                        .foregroundStyle(accent)
                }
            }
            TextField("VH-, N123, G-", text: $draft.registrationQuery)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("registration-filter")
            Text("Matches the start of a registration. This stays separate from the main search.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sighting date")
                    .font(.headline)
                Spacer()
                if draft.dateRange.isActive {
                    Button("Clear") {
                        draft.clear(.dateRange)
                        startEnabled = false
                        endEnabled = false
                    }
                    .font(.subheadline)
                    .foregroundStyle(accent)
                }
            }
            Toggle("Start date", isOn: $startEnabled)
                .onChange(of: startEnabled) { _, enabled in
                    updateDateRange(startOn: enabled, endOn: endEnabled)
                }
            if startEnabled {
                DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    .labelsHidden()
                    .onChange(of: startDate) { _, _ in
                        updateDateRange(startOn: true, endOn: endEnabled)
                    }
                    .accessibilityIdentifier("filter-start-date")
            }
            Toggle("End date", isOn: $endEnabled)
                .onChange(of: endEnabled) { _, enabled in
                    updateDateRange(startOn: startEnabled, endOn: enabled)
                }
            if endEnabled {
                DatePicker("End date", selection: $endDate, displayedComponents: .date)
                    .labelsHidden()
                    .onChange(of: endDate) { _, _ in
                        updateDateRange(startOn: startEnabled, endOn: true)
                    }
                    .accessibilityIdentifier("filter-end-date")
            }
            if !draft.dateRange.isValid {
                Text("End date is before the start date. Choose an end date on or after the start date.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("filter-date-error")
            } else {
                Text("An end date includes sightings through that calendar day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func dimensionHasSelection(_ dimension: FilterDimension) -> Bool {
        switch dimension {
        case .operators:
            return !draft.operators.isEmpty
        case .manufacturers:
            return !draft.manufacturers.isEmpty
        case .aircraft:
            return !draft.aircraft.isEmpty
        case .roles:
            return !draft.roles.isEmpty
        case .operationTypes:
            return !draft.operationTypes.isEmpty
        case .locations:
            return !draft.locations.isEmpty
        case .registration:
            return draft.registrationIsActive
        case .dateRange:
            return draft.dateRange.isActive
        }
    }

    private func updateDateRange(startOn: Bool, endOn: Bool) {
        draft.dateRange = FilterDateRange(
            start: startOn ? filterCalendarDay(from: startDate, calendar: .current) : nil,
            end: endOn ? filterCalendarDay(from: endDate, calendar: .current) : nil
        )
    }

    private static func date(from day: FilterCalendarDay?) -> Date? {
        guard let day else { return nil }
        var components = DateComponents()
        components.calendar = .current
        components.year = day.year
        components.month = day.month
        components.day = day.day
        return Calendar.current.date(from: components)
    }

    private func browseIdentifier(_ browse: FilterCatalogBrowse) -> String {
        switch browse {
        case .operators:
            return "operators"
        case .manufacturers:
            return "manufacturers"
        case .aircraft:
            return "aircraft"
        case .locations:
            return "locations"
        }
    }
}

private struct FilterCatalogSearchPage: View {
    @EnvironmentObject private var catalogService: AviationCatalogUIService
    let browse: FilterCatalogBrowse
    let accent: Color
    let phase: CatalogLoadPhase
    let onSelect: (FilterToken) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var hits: [FilterCatalogHit] = []
    @State private var ambiguous = false
    @State private var unmatched = false
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        List {
            if phase == .failed {
                Text("The aviation catalog could not be loaded. Saved collection values are still available on the previous screen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                TextField(promptText, text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("filter-catalog-search")
                    .onChange(of: query) { _, newValue in
                        scheduleSearch(newValue)
                    }
            }
            if ambiguous {
                Section {
                    Text(ambiguousMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                if searching {
                    ProgressView()
                }
                ForEach(hits) { hit in
                    Button {
                        onSelect(hit.token)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(hit.title)
                                .foregroundStyle(.primary)
                            if !hit.subtitle.isEmpty {
                                Text(hit.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("filter-catalog-hit-\(hit.id)")
                }
                if unmatched {
                    Text("No catalog records match.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let custom = customToken {
                    Button(customTitle) {
                        onSelect(custom)
                    }
                    .accessibilityIdentifier("filter-catalog-custom")
                }
            }
        }
        .tint(accent)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back", action: onClose)
                    .accessibilityIdentifier("filter-catalog-back")
            }
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private func scheduleSearch(_ query: String) {
        searchTask?.cancel()
        guard catalogQueryGuidance(query) == .ready else {
            hits = []
            ambiguous = false
            unmatched = false
            searching = false
            return
        }
        searching = true
        let browse = browse
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            let result = await catalogService.searchFilterCatalog(browse, query: query, limit: 20)
            guard !Task.isCancelled else { return }
            hits = result.hits
            ambiguous = result.ambiguous
            unmatched = result.unmatched
            searching = false
        }
    }

    private var title: String {
        switch browse {
        case .operators:
            return "Operator"
        case .manufacturers:
            return "Manufacturer"
        case .aircraft:
            return "Aircraft"
        case .locations:
            return "Location"
        }
    }

    private var promptText: String {
        switch browse {
        case .operators:
            return "Name or code"
        case .manufacturers:
            return "Manufacturer"
        case .aircraft:
            return "Model or family"
        case .locations:
            return "Airport or place"
        }
    }

    private var ambiguousMessage: String {
        switch browse {
        case .operators:
            return "Several operators share this code. Choose the specific one."
        case .aircraft:
            return "Several aircraft match this code. Choose the specific one."
        case .locations:
            return "Several airports share this code. Choose the specific one."
        case .manufacturers:
            return "Choose the specific manufacturer."
        }
    }

    private var customToken: FilterToken? {
        guard catalogQueryGuidance(query) == .ready else { return nil }
        guard let text = AviationSelection.custom(from: query)?.displayText else { return nil }
        switch browse {
        case .operators:
            return .reference(.operatorField, .custom(text: text))
        case .manufacturers:
            return .reference(.manufacturer, .custom(text: text))
        case .aircraft:
            return .aircraft(.custom(text: text))
        case .locations:
            return .reference(.location, .custom(text: text))
        }
    }

    private var customTitle: String {
        let text = AviationSelection.custom(from: query)?.displayText ?? query
        return "Use \"\(text)\" as custom text"
    }
}
