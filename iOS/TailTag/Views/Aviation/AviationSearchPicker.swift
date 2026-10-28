import SmartEntry
import SwiftUI

enum AviationPickerChoice<Record> {
    case record(Record)
    case custom(String)
    case unknown
    case absent
}

struct AviationSearchPicker<Record: Identifiable & Equatable, Header: View, Row: View>: View {
    let title: String
    let searchPrompt: String
    let currentSummary: String
    let allowsUnknown: Bool
    let absentTitle: String?
    let ambiguousMessage: String?
    let emptyMessage: String
    let results: [Record]
    let query: String
    let guidance: CatalogQueryGuidance
    let isLoadingCatalog: Bool
    let isSearching: Bool
    let errorMessage: String?
    let canLoadMore: Bool
    let accent: Color
    let onQuery: (String) -> Void
    let onLoadMore: () -> Void
    let onRetry: () -> Void
    let onConfirm: (AviationPickerChoice<Record>) -> Void
    let onCancel: () -> Void
    @ViewBuilder var header: () -> Header
    @ViewBuilder var row: (Record) -> Row

    @FocusState private var searchFocused: Bool
    @State private var draft: Draft?

    var body: some View {
        VStack(spacing: 0) {
                searchHeader
                List {
                    Section {
                        header()
                        if let custom = AviationSelection.custom(from: query) {
                            choiceRow(
                                title: "Use \"\(custom.displayText)\"",
                                subtitle: "Save this text without a catalog record",
                                systemImage: "square.and.pencil",
                                selected: draft == .custom
                            ) {
                                draft = .custom
                            }
                        }
                        if allowsUnknown {
                            choiceRow(
                                title: "Unknown",
                                subtitle: "Mark this as not known",
                                systemImage: "questionmark.circle",
                                selected: draft == .unknown
                            ) {
                                draft = .unknown
                            }
                        }
                        if let absentTitle {
                            choiceRow(
                                title: absentTitle,
                                subtitle: "Leave this blank",
                                systemImage: "minus.circle",
                                selected: draft == .absent
                            ) {
                                draft = .absent
                            }
                        }
                    }

                    Section {
                        catalogContent
                    } header: {
                        Text("Catalog")
                    }
                }
                .listStyle(.insetGrouped)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .tint(accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") { confirm() }
                        .fontWeight(.semibold)
                        .disabled(draft == nil)
                        .accessibilityIdentifier("confirm-selection")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSearching {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Searching")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                }
            }
            .onAppear { searchFocused = true }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(currentSummary)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField(searchPrompt, text: Binding(get: { query }, set: onQuery))
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
                .accessibilityLabel(searchPrompt)
                .accessibilityIdentifier("catalog-search")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var catalogContent: some View {
        switch guidance {
        case .prompt:
            statusText("Search by name, alias, or code.")
        case .tooShort:
            statusText("Enter at least two characters.")
        case .ready:
            readyContent
        }
    }

    @ViewBuilder
    private var readyContent: some View {
        if let errorMessage, results.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(errorMessage)
                    .foregroundStyle(.primary)
                Button("Try again", action: onRetry)
                    .foregroundStyle(accent)
            }
            .accessibilityElement(children: .combine)
        } else if isLoadingCatalog && results.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading the aviation catalog")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else if results.isEmpty && !isSearching {
            statusText(emptyMessage)
        } else {
            if let ambiguousMessage {
                Text(ambiguousMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(results) { record in
                Button {
                    draft = .record(record)
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        row(record)
                        Spacer(minLength: 8)
                        if draft == .record(record) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(accent)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("catalog-result-\(record.id)")
                .accessibilityAddTraits(.isButton)
            }
            if canLoadMore {
                Button("Show more results", action: onLoadMore)
                    .foregroundStyle(accent)
            }
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func choiceRow(
        title: String,
        subtitle: String,
        systemImage: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(accent)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }

    private func confirm() {
        guard let draft else { return }
        switch draft {
        case .record(let record):
            onConfirm(.record(record))
        case .custom:
            if let custom = AviationSelection.custom(from: query) {
                onConfirm(.custom(custom.displayText))
            }
        case .unknown:
            onConfirm(.unknown)
        case .absent:
            onConfirm(.absent)
        }
    }

    private enum Draft: Equatable {
        case record(Record)
        case custom
        case unknown
        case absent
    }
}

struct CatalogBadge: View {
    let text: String
    var prominent = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(prominent ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(.primary)
            .accessibilityLabel(text)
    }
}

struct CatalogResultLabel: View {
    let title: String
    let subtitle: String
    var badges: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                ForEach(badges, id: \.self) { badge in
                    CatalogBadge(text: badge, prominent: badge == "Historical" || badge == "Closed")
                }
            }
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
