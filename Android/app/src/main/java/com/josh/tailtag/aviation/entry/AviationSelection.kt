package com.josh.tailtag.aviation.entry

enum class AviationSelectionKind(val wire: String) {
    CATALOG("catalog"),
    CUSTOM("custom"),
    UNKNOWN("unknown"),
    ABSENT("absent");

    companion object {
        fun fromWire(value: String?): AviationSelectionKind? = entries.firstOrNull { it.wire == value }
    }
}

data class AviationSelection(
    val kind: AviationSelectionKind,
    val catalogId: String? = null,
    val displayText: String = "",
    val detail: String? = null,
    val unavailableInCatalog: Boolean = false,
    val isLegacy: Boolean = false,
    val suggestedFromPhoto: Boolean = false,
) {
    val hasCatalogIdentity: Boolean
        get() = kind == AviationSelectionKind.CATALOG && !catalogId.isNullOrBlank()

    companion object {
        val absent = AviationSelection(AviationSelectionKind.ABSENT)

        fun unknown() = AviationSelection(AviationSelectionKind.UNKNOWN, displayText = "Unknown")

        fun catalog(id: String, displayText: String, detail: String? = null) = AviationSelection(
            kind = AviationSelectionKind.CATALOG,
            catalogId = id,
            displayText = displayText,
            detail = detail,
        )

        fun custom(raw: String): AviationSelection? {
            val trimmed = raw.trim()
            if (trimmed.isEmpty()) return null
            return AviationSelection(AviationSelectionKind.CUSTOM, displayText = trimmed)
        }

        fun legacy(text: String): AviationSelection {
            if (text.isBlank()) return absent
            return AviationSelection(AviationSelectionKind.CUSTOM, displayText = text, isLegacy = true)
        }
    }

    fun reconciled(existsInCatalog: Boolean?): AviationSelection {
        if (kind != AviationSelectionKind.CATALOG || !hasCatalogIdentity || existsInCatalog == null) return this
        return copy(unavailableInCatalog = !existsInCatalog)
    }
}

data class PersistedAviationField(
    val kind: String? = null,
    val catalogId: String? = null,
    val text: String = "",
    val detail: String? = null,
) {
    constructor(selection: AviationSelection) : this(
        kind = if (selection.isLegacy) null else selection.kind.wire,
        catalogId = if (selection.isLegacy) null else if (selection.kind == AviationSelectionKind.CATALOG) selection.catalogId else null,
        text = when {
            selection.isLegacy -> selection.displayText
            selection.kind == AviationSelectionKind.CUSTOM -> selection.displayText.trim()
            selection.kind == AviationSelectionKind.UNKNOWN -> "Unknown"
            selection.kind == AviationSelectionKind.ABSENT -> ""
            else -> selection.displayText
        },
        detail = if (selection.isLegacy || selection.kind != AviationSelectionKind.CATALOG) null else selection.detail,
    )

    fun selection(): AviationSelection {
        val parsed = AviationSelectionKind.fromWire(kind) ?: return AviationSelection.legacy(text)
        return when (parsed) {
            AviationSelectionKind.CATALOG -> AviationSelection.catalog(catalogId.orEmpty(), text, detail)
            AviationSelectionKind.CUSTOM -> if (text.isBlank()) AviationSelection.legacy(text) else AviationSelection(
                AviationSelectionKind.CUSTOM,
                displayText = text,
            )
            AviationSelectionKind.UNKNOWN -> AviationSelection.unknown()
            AviationSelectionKind.ABSENT -> AviationSelection.absent
        }
    }
}

object AmbiguityPolicy {
    fun automaticCatalogId(matchCount: Int, exactCodeCount: Int): String? {
        return null
    }

    fun isAmbiguousExactCode(exactCodeCount: Int) = exactCodeCount > 1
}

data class PickerSession<T>(val committed: T, val draft: T? = null) {
    fun cancel() = committed
    fun confirm() = draft ?: committed
    val hasDraft: Boolean get() = draft != null
}

enum class CatalogLoadPhase { IDLE, LOADING, READY, FAILED }

data class CatalogLoadState(
    val phase: CatalogLoadPhase = CatalogLoadPhase.IDLE,
    val failureCount: Int = 0,
) {
    fun begin(): CatalogLoadState = when (phase) {
        CatalogLoadPhase.IDLE, CatalogLoadPhase.FAILED -> copy(phase = CatalogLoadPhase.LOADING)
        CatalogLoadPhase.LOADING, CatalogLoadPhase.READY -> this
    }

    val beginAccepted: Boolean
        get() = phase == CatalogLoadPhase.IDLE || phase == CatalogLoadPhase.FAILED

    fun succeed() = copy(phase = CatalogLoadPhase.READY)

    fun fail() = copy(phase = CatalogLoadPhase.FAILED, failureCount = failureCount + 1)

    fun retry(): CatalogLoadState? = if (phase == CatalogLoadPhase.FAILED) copy(phase = CatalogLoadPhase.LOADING) else null
}

enum class CatalogQueryGuidance { PROMPT, TOO_SHORT, READY }

private val queryIgnored = setOf('-', '‐', '‑', '‒', '–', '—', '_', '/', '\\')

fun catalogQueryGuidance(query: String): CatalogQueryGuidance {
    val trimmed = query.trim()
    if (trimmed.isEmpty()) return CatalogQueryGuidance.PROMPT
    val compact = trimmed.filter { !it.isWhitespace() && it !in queryIgnored }
    return if (compact.length < 2) CatalogQueryGuidance.TOO_SHORT else CatalogQueryGuidance.READY
}

fun selectionSummary(selection: AviationSelection, emptyPlaceholder: String): String = when (selection.kind) {
    AviationSelectionKind.ABSENT -> emptyPlaceholder
    AviationSelectionKind.UNKNOWN -> "Unknown"
    AviationSelectionKind.CATALOG, AviationSelectionKind.CUSTOM ->
        if (selection.displayText.isBlank()) emptyPlaceholder else selection.displayText
}

fun selectionCaption(selection: AviationSelection): String? {
    if (selection.unavailableInCatalog) return "No longer in the current catalog"
    if (selection.suggestedFromPhoto) return "Suggested from photo. Search the catalog to confirm."
    if (selection.isLegacy) return "Saved text"
    return when (selection.kind) {
        AviationSelectionKind.CATALOG -> selection.detail?.trim()?.takeIf { it.isNotEmpty() }
        AviationSelectionKind.CUSTOM -> "Custom"
        AviationSelectionKind.UNKNOWN -> "Marked unknown"
        AviationSelectionKind.ABSENT -> null
    }
}

class LatestQueryGate {
    private val lock = Any()
    private var generation = 0

    fun issue(): Int = synchronized(lock) { ++generation }

    fun isCurrent(token: Int): Boolean = synchronized(lock) { token == generation }

    fun <T> accept(token: Int, value: T): T? = synchronized(lock) {
        if (token == generation) value else null
    }
}
