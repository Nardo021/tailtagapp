import SmartEntry
import SwiftUI

struct SearchView: View {
    @EnvironmentObject var spottingStore: SpottingStore
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var catalogService: AviationCatalogUIService
    @Binding private var searchText: String
    @Binding private var filters: SpottingFilterState
    private let usesLocalSearchField: Bool
    @State private var selectedSortOption: SortOption = .dateNewest
    @State private var showingFilters = false

    init(searchText: Binding<String>, filters: Binding<SpottingFilterState>, usesLocalSearchField: Bool = true) {
        _searchText = searchText
        _filters = filters
        self.usesLocalSearchField = usesLocalSearchField
    }

    private var snapshots: [FilterableSpotting] {
        spottingStore.entries.map { $0.filterableSpotting() }
    }

    private var visibleEntries: [SpottingEntry] {
        searchSpottingEntries(
            spottingStore.entries,
            searchText: searchText,
            filters: filters,
            sort: selectedSortOption,
            catalog: catalogService.filterCatalog
        )
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                filterSortBar
                if spottingStore.entries.isEmpty {
                    EmptyStateView()
                } else if visibleEntries.isEmpty {
                    noResults
                } else {
                    results
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(SearchableIfNeeded(isEnabled: usesLocalSearchField, searchText: $searchText))
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showingFilters) {
            AdvancedFilterSheet(
                applied: filters,
                entries: snapshots,
                searchText: searchText,
                catalog: catalogService.filterCatalog,
                catalogPhase: catalogService.phase,
                accent: appSettings.accentColor,
                onCancel: { showingFilters = false },
                onApply: { updated in
                    filters = updated
                    showingFilters = false
                }
            )
            .environmentObject(catalogService)
            .environmentObject(appSettings)
        }
    }

    private var filterSortBar: some View {
        HStack(spacing: 12) {
            Button {
                showingFilters = true
            } label: {
                Label(
                    filters.isActive ? "Filters (\(filters.activeConditionCount))" : "Filters",
                    systemImage: filters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
                )
                .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(appSettings.accentColor)
            .accessibilityLabel(filters.isActive ? "Filters, \(filters.activeConditionCount) active" : "Filters")
            .accessibilityIdentifier("filters-button")

            Spacer()

            Menu {
                Picker("Sort", selection: $selectedSortOption) {
                    ForEach(SortOption.allCases) { option in
                        Label(option.rawValue, systemImage: option.icon)
                            .tag(option)
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(appSettings.accentColor)
            .accessibilityLabel("Sort")
            .accessibilityIdentifier("sort-button")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var results: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                summary
                ForEach(visibleEntries) { entry in
                    SpottingCardView(entry: entry)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            if filters.isActive {
                FilterChipBar(
                    chips: filters.chips(),
                    accent: appSettings.accentColor,
                    onRemove: { chip in
                        filters.removeChip(chip.id)
                    },
                    onClearAll: { filters.reset() }
                )
            }
            if !catalogService.filterCatalog.isAvailable && filters.isActive && catalogService.phase != .loading {
                Text("Some catalog details are unavailable, so family and manufacturer links may not resolve.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("search-catalog-unavailable")
            }
            HStack {
                Text(summaryTitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(visibleEntries.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("result-count")
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var summaryTitle: String {
        let visible = visibleEntries.count
        let total = spottingStore.entries.count
        if filters.isActive || !searchText.isEmpty {
            return "\(visible) of \(total) sightings"
        }
        return total == 1 ? "1 sighting" : "\(total) sightings"
    }

    private var noResults: some View {
        VStack(spacing: 16) {
            if filters.isActive {
                FilterChipBar(
                    chips: filters.chips(),
                    accent: appSettings.accentColor,
                    onRemove: { filters.removeChip($0.id) },
                    onClearAll: { filters.reset() }
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            Spacer()
            Image(systemName: filters.isActive ? "line.3.horizontal.decrease.circle" : "magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text(filters.isActive ? "No matching sightings" : "No Results")
                .font(.title2)
                .fontWeight(.semibold)
            Text(emptyMessage)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if filters.isActive {
                Button("Clear filters") { filters.reset() }
                    .buttonStyle(.borderedProminent)
                    .tint(appSettings.accentColor)
                    .accessibilityIdentifier("clear-filters-empty")
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var emptyMessage: String {
        if filters.isActive && !searchText.isEmpty {
            return "No saved sightings match these filters and \"\(searchText)\"."
        }
        if filters.isActive {
            return "The collection still has sightings, but none match the current filters."
        }
        return "No spottings match \"\(searchText)\""
    }
}

private struct SearchableIfNeeded: ViewModifier {
    let isEnabled: Bool
    @Binding var searchText: String

    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(text: $searchText, prompt: "Search aircraft, airlines, places...")
        } else {
            content
        }
    }
}
