import SmartEntry
import SwiftUI

struct FilterFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? 0
        let rows = rows(maxWidth: width, subviews: subviews)
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var y = bounds.minY
        for row in rows(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indexes {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(maxWidth: CGFloat, subviews: Subviews) -> [FlowRow] {
        var result: [FlowRow] = []
        var current = FlowRow()
        var x: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                result.append(current)
                current = FlowRow()
                x = 0
            }
            current.indexes.append(index)
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.indexes.isEmpty {
            result.append(current)
        }
        return result
    }

    private struct FlowRow {
        var indexes: [Int] = []
        var height: CGFloat = 0
    }
}

struct FilterChipBar: View {
    let chips: [SpottingFilterChip]
    let accent: Color
    let onRemove: (SpottingFilterChip) -> Void
    let onClearAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FilterFlowLayout(spacing: 8) {
                ForEach(chips) { chip in
                    Button {
                        onRemove(chip)
                    } label: {
                        HStack(spacing: 6) {
                            Text(chip.label)
                                .font(.footnote)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .foregroundStyle(accent)
                        .background(accent.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(chip.accessibilityLabel)
                    .accessibilityIdentifier(filterAccessibilityID("filter-chip", chip.id))
                }
            }
            Button("Clear all", action: onClearAll)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(accent)
                .accessibilityIdentifier("clear-filters")
        }
    }
}

struct FilterChoiceButtons: View {
    let choices: [FilterChoice]
    let isSelected: (FilterToken) -> Bool
    let accent: Color
    let onToggle: (FilterToken) -> Void

    var body: some View {
        FilterFlowLayout(spacing: 8) {
            ForEach(choices) { choice in
                let selected = isSelected(choice.token)
                Button {
                    onToggle(choice.token)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(choice.title)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.leading)
                        Text(choice.detail)
                            .font(.caption2)
                            .foregroundStyle(selected ? Color.white.opacity(0.85) : .secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .background(selected ? accent : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(choice.title), \(choice.detail)")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier(filterAccessibilityID("filter-choice", choice.id))
            }
        }
    }
}

func filterAccessibilityID(_ prefix: String, _ chipID: String) -> String {
    let sanitized = chipID.replacingOccurrences(of: "\u{1f}", with: "-")
    return "\(prefix)-\(sanitized)"
}
