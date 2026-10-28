import Foundation

/// How a spotting field relates to the offline catalog.
///
/// `catalog` stores a stable catalog id plus the display text captured at selection time.
/// `custom` is text the user entered. `unknown` is an explicit "not known" choice.
/// `absent` means the user supplied no value. These are not catalog records.
public enum AviationSelectionKind: String, Codable, Sendable, Equatable, CaseIterable {
    case catalog
    case custom
    case unknown
    case absent
}

public struct AviationSelection: Equatable, Hashable, Sendable, Codable {
    public var kind: AviationSelectionKind
    public var catalogId: String?
    public var displayText: String
    /// Snapshot that is not an identity, such as "Model" or "Family".
    public var detail: String?
    /// Set when a saved id was checked and is missing. This is not stored.
    public var unavailableInCatalog: Bool
    /// The source record had display text and no selection kind.
    public var isLegacy: Bool
    /// OCR or another detector suggested the text. This is not a catalog identity.
    public var suggestedFromPhoto: Bool

    public init(
        kind: AviationSelectionKind,
        catalogId: String? = nil,
        displayText: String = "",
        detail: String? = nil,
        unavailableInCatalog: Bool = false,
        isLegacy: Bool = false,
        suggestedFromPhoto: Bool = false
    ) {
        self.kind = kind
        self.catalogId = catalogId
        self.displayText = displayText
        self.detail = detail
        self.unavailableInCatalog = unavailableInCatalog
        self.isLegacy = isLegacy
        self.suggestedFromPhoto = suggestedFromPhoto
    }

    public static let absent = AviationSelection(kind: .absent)

    public static func unknown() -> AviationSelection {
        AviationSelection(kind: .unknown, displayText: "Unknown")
    }

    public static func catalog(id: String, displayText: String, detail: String? = nil) -> AviationSelection {
        AviationSelection(
            kind: .catalog,
            catalogId: id,
            displayText: displayText,
            detail: detail
        )
    }

    /// Explicit custom text. Blank and whitespace-only input is rejected.
    public static func custom(from raw: String) -> AviationSelection? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return AviationSelection(kind: .custom, displayText: trimmed)
    }

    /// Text already stored on a spotting that never recorded a selection kind.
    /// The original characters are kept, including surrounding spaces.
    public static func legacy(text: String) -> AviationSelection {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .absent
        }
        return AviationSelection(kind: .custom, displayText: text, isLegacy: true)
    }

    public var hasCatalogIdentity: Bool {
        guard kind == .catalog, let catalogId else { return false }
        return !catalogId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct PersistedAviationField: Equatable, Hashable, Sendable, Codable {
    public var kind: String?
    public var catalogId: String?
    public var text: String
    public var detail: String?

    public init(kind: String? = nil, catalogId: String? = nil, text: String = "", detail: String? = nil) {
        self.kind = kind
        self.catalogId = catalogId
        self.text = text
        self.detail = detail
    }

    public init(selection: AviationSelection) {
        if selection.isLegacy {
            kind = nil
            catalogId = nil
            text = selection.displayText
            detail = nil
            return
        }
        switch selection.kind {
        case .catalog:
            kind = AviationSelectionKind.catalog.rawValue
            catalogId = selection.catalogId
            text = selection.displayText
            detail = selection.detail
        case .custom:
            kind = AviationSelectionKind.custom.rawValue
            catalogId = nil
            text = selection.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
            detail = nil
        case .unknown:
            kind = AviationSelectionKind.unknown.rawValue
            catalogId = nil
            text = "Unknown"
            detail = nil
        case .absent:
            kind = AviationSelectionKind.absent.rawValue
            catalogId = nil
            text = ""
            detail = nil
        }
    }

    public func selection() -> AviationSelection {
        guard let kind else {
            return AviationSelection.legacy(text: text)
        }
        guard let parsed = AviationSelectionKind(rawValue: kind) else {
            return AviationSelection.legacy(text: text)
        }
        switch parsed {
        case .catalog:
            return AviationSelection.catalog(
                id: catalogId ?? "",
                displayText: text,
                detail: detail
            )
        case .custom:
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return AviationSelection.legacy(text: text)
            }
            return AviationSelection(kind: .custom, displayText: text)
        case .unknown:
            return .unknown()
        case .absent:
            return .absent
        }
    }
}

extension AviationSelection {
    /// Keeps the saved label when an id no longer resolves.
    /// A nil lookup means the catalog was not available, so the field is left unchanged.
    public func reconciled(existsInCatalog: Bool?) -> AviationSelection {
        guard kind == .catalog, hasCatalogIdentity, let existsInCatalog else { return self }
        var copy = self
        copy.unavailableInCatalog = !existsInCatalog
        return copy
    }
}

public enum AmbiguityPolicy {
    /// A code match never becomes a saved catalog identity on its own.
    /// `limit` does not change this, including when only one row was returned.
    public static func automaticCatalogID(matchCount: Int, exactCodeCount: Int) -> String? {
        _ = matchCount
        _ = exactCodeCount
        return nil
    }

    public static func isAmbiguousExactCode(exactCodeCount: Int) -> Bool {
        exactCodeCount > 1
    }
}

public struct PickerSession<Value: Equatable>: Equatable {
    public var committed: Value
    public var draft: Value?

    public init(committed: Value, draft: Value? = nil) {
        self.committed = committed
        self.draft = draft
    }

    public func cancel() -> Value {
        committed
    }

    public func confirm() -> Value {
        draft ?? committed
    }

    public var hasDraft: Bool {
        draft != nil
    }
}

public enum CatalogLoadPhase: String, Equatable, Sendable {
    case idle
    case loading
    case ready
    case failed
}

public struct CatalogLoadState: Equatable, Sendable {
    public private(set) var phase: CatalogLoadPhase
    public private(set) var failureCount: Int

    public init(phase: CatalogLoadPhase = .idle, failureCount: Int = 0) {
        self.phase = phase
        self.failureCount = failureCount
    }

    /// Starts a load from idle or failed. A load already in progress is left alone.
    public mutating func begin() -> Bool {
        switch phase {
        case .idle, .failed:
            phase = .loading
            return true
        case .loading, .ready:
            return false
        }
    }

    public mutating func succeed() {
        phase = .ready
    }

    public mutating func fail() {
        phase = .failed
        failureCount += 1
    }

    public mutating func retry() -> Bool {
        guard phase == .failed else { return false }
        phase = .loading
        return true
    }
}

public enum CatalogQueryGuidance: Equatable, Sendable {
    case prompt
    case tooShort
    case ready
}

public func catalogQueryGuidance(_ query: String) -> CatalogQueryGuidance {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return .prompt
    }
    let compact = trimmed.unicodeScalars.filter { scalar in
        !scalar.properties.isWhitespace && !catalogQueryIgnored.contains(scalar)
    }
    if compact.count < 2 {
        return .tooShort
    }
    return .ready
}

private let catalogQueryIgnored: Set<Unicode.Scalar> = ["-", "‐", "‑", "‒", "–", "—", "_", "/", "\\"]

public func selectionSummary(_ selection: AviationSelection, emptyPlaceholder: String) -> String {
    switch selection.kind {
    case .absent:
        return emptyPlaceholder
    case .unknown:
        return "Unknown"
    case .catalog, .custom:
        if selection.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return emptyPlaceholder
        }
        return selection.displayText
    }
}

public func selectionCaption(_ selection: AviationSelection) -> String? {
    if selection.unavailableInCatalog {
        return "No longer in the current catalog"
    }
    if selection.suggestedFromPhoto {
        return "Suggested from photo. Search the catalog to confirm."
    }
    if selection.isLegacy {
        return "Saved text"
    }
    switch selection.kind {
    case .catalog:
        guard let detail = selection.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty else {
            return nil
        }
        return detail
    case .custom:
        return "Custom"
    case .unknown:
        return "Marked unknown"
    case .absent:
        return nil
    }
}
