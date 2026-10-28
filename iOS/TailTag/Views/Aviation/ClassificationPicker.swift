import SmartEntry
import SwiftUI

struct ClassificationPicker: View {
    let title: String
    let description: String
    let options: [String]
    let labels: [String: String]
    let descriptions: [String: String]
    let selectedID: String?
    let note: String?
    let accent: Color
    let onConfirm: (String?, String?) -> Void
    let onCancel: () -> Void

    @State private var draftID: String?
    @State private var draftNote: String
    @State private var didChoose = false

    init(
        title: String,
        description: String,
        options: [String],
        labels: [String: String],
        descriptions: [String: String],
        selectedID: String?,
        note: String?,
        accent: Color,
        onConfirm: @escaping (String?, String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.description = description
        self.options = options
        self.labels = labels
        self.descriptions = descriptions
        self.selectedID = selectedID
        self.note = note
        self.accent = accent
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _draftID = State(initialValue: selectedID)
        _draftNote = State(initialValue: note ?? "")
        _didChoose = State(initialValue: selectedID != nil)
    }

    var body: some View {
        List {
                Section {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(options, id: \.self) { id in
                        Button {
                            draftID = id
                            didChoose = true
                            if id != "other" {
                                draftNote = ""
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(labels[id] ?? ClassificationCopy.roleLabel(id, catalogLabels: labels))
                                        .foregroundStyle(.primary)
                                    if let detail = descriptions[id] {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                Spacer()
                                if draftID == id && didChoose {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(accent)
                                }
                            }
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(labels[id] ?? id)
                        .accessibilityIdentifier("classification-\(id)")
                        .accessibilityHint(descriptions[id] ?? "Selects \(labels[id] ?? id)")
                    }
                    Button("Clear selection") {
                        draftID = nil
                        draftNote = ""
                        didChoose = true
                    }
                    .foregroundStyle(accent)
                }
                if draftID == "other" {
                    Section("Description") {
                        TextField("Describe it", text: $draftNote, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .tint(accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        onConfirm(draftID, draftNote)
                    }
                    .fontWeight(.semibold)
                    .disabled(!didChoose)
                    .accessibilityIdentifier("confirm-selection")
                }
            }
    }
}

struct SelectionValueRow: View {
    let title: String
    let selection: AviationSelection
    let placeholder: String
    let accent: Color

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(selectionSummary(selection, emptyPlaceholder: placeholder))
                    .font(.body)
                    .foregroundStyle(selection.kind == .absent ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                if let caption = selectionCaption(selection) {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens choices for \(title)")
    }
}
