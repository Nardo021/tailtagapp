package com.josh.tailtag.filters

import com.josh.tailtag.aviation.entry.AviationSelection
import com.josh.tailtag.aviation.entry.AviationSelectionKind
import com.josh.tailtag.aviation.entry.ClassificationCopy
import com.josh.tailtag.aviation.entry.SpottingReferenceState
import com.josh.tailtag.aviation.entry.cleanedIdentifier
import com.josh.tailtag.aviation.entry.cleanedNote
import com.josh.tailtag.aviation.entry.referenceState
import com.josh.tailtag.model.SpottingEntry
import java.util.Calendar

data class FilterableSpotting(
    val id: String,
    val registration: String,
    val timestamp: Long,
    val reference: SpottingReferenceState,
)

data class FilterAircraftFacts(
    val displayName: String,
    val manufacturerId: String?,
    val familyId: String?,
    val familyName: String?,
    val entryKind: String,
)

data class FilterCatalogOperator(val id: String, val name: String)
data class FilterCatalogNamed(val id: String, val name: String)
data class FilterCatalogAircraft(
    val id: String,
    val displayName: String,
    val manufacturerId: String?,
    val familyId: String?,
    val familyName: String?,
    val entryKind: String,
) {
    val cleanedManufacturerId = cleanedIdentifier(manufacturerId)
    val cleanedFamilyId = cleanedIdentifier(familyId)
    val cleanedFamilyName = cleanedIdentifier(familyName)
}

data class FilterCatalogSnapshot(
    val operators: List<FilterCatalogOperator> = emptyList(),
    val manufacturers: List<FilterCatalogNamed> = emptyList(),
    val aircraft: List<FilterCatalogAircraft> = emptyList(),
    val airports: List<FilterCatalogNamed> = emptyList(),
)

interface SpottingFilterCatalog {
    val isAvailable: Boolean
    fun aircraft(id: String): FilterAircraftFacts?
    fun manufacturerName(id: String): String?
    fun operatorName(id: String): String?
    fun airportName(id: String): String?
    fun operatorDisplayNameCount(normalizedName: String): Int?
    fun manufacturerDisplayNameCount(normalizedName: String): Int?
    fun aircraftDisplayNameCount(normalizedName: String): Int?
    fun familyDisplayNameCount(normalizedName: String): Int?
    fun airportDisplayNameCount(normalizedName: String): Int?
}

class PreparedSpottingFilterCatalog private constructor(
    override val isAvailable: Boolean,
    private val aircraftById: Map<String, FilterAircraftFacts>,
    private val manufacturerNames: Map<String, String>,
    private val operatorNames: Map<String, String>,
    private val airportNames: Map<String, String>,
    private val operatorNameCounts: Map<String, Int>,
    private val manufacturerNameCounts: Map<String, Int>,
    private val aircraftNameCounts: Map<String, Int>,
    private val familyNameCounts: Map<String, Int>,
    private val airportNameCounts: Map<String, Int>,
) : SpottingFilterCatalog {
    constructor(snapshot: FilterCatalogSnapshot) : this(
        isAvailable = true,
        aircraftById = snapshot.aircraft.associate { record ->
            record.id to FilterAircraftFacts(
                displayName = record.displayName,
                manufacturerId = record.cleanedManufacturerId,
                familyId = record.cleanedFamilyId,
                familyName = record.cleanedFamilyName,
                entryKind = record.entryKind,
            )
        },
        manufacturerNames = firstNames(snapshot.manufacturers),
        operatorNames = firstNames(snapshot.operators.map { FilterCatalogNamed(it.id, it.name) }),
        airportNames = firstNames(snapshot.airports),
        operatorNameCounts = nameCounts(snapshot.operators.map { it.name }),
        manufacturerNameCounts = nameCounts(snapshot.manufacturers.map { it.name }),
        aircraftNameCounts = nameCounts(snapshot.aircraft.map { it.displayName }),
        familyNameCounts = nameCounts(snapshot.aircraft.filter { it.entryKind == "family" }.map { it.displayName }),
        airportNameCounts = nameCounts(snapshot.airports.map { it.name }),
    )

    override fun aircraft(id: String) = if (isAvailable) aircraftById[id] else null
    override fun manufacturerName(id: String) = if (isAvailable) manufacturerNames[id] else null
    override fun operatorName(id: String) = if (isAvailable) operatorNames[id] else null
    override fun airportName(id: String) = if (isAvailable) airportNames[id] else null
    override fun operatorDisplayNameCount(normalizedName: String) = count(operatorNameCounts, normalizedName)
    override fun manufacturerDisplayNameCount(normalizedName: String) = count(manufacturerNameCounts, normalizedName)
    override fun aircraftDisplayNameCount(normalizedName: String) = count(aircraftNameCounts, normalizedName)
    override fun familyDisplayNameCount(normalizedName: String) = count(familyNameCounts, normalizedName)
    override fun airportDisplayNameCount(normalizedName: String) = count(airportNameCounts, normalizedName)

    private fun count(counts: Map<String, Int>, name: String): Int? = if (isAvailable) counts[name] ?: 0 else null

    companion object {
        val unavailable = PreparedSpottingFilterCatalog(
            isAvailable = false,
            aircraftById = emptyMap(),
            manufacturerNames = emptyMap(),
            operatorNames = emptyMap(),
            airportNames = emptyMap(),
            operatorNameCounts = emptyMap(),
            manufacturerNameCounts = emptyMap(),
            aircraftNameCounts = emptyMap(),
            familyNameCounts = emptyMap(),
            airportNameCounts = emptyMap(),
        )
    }
}

data class FilterChoice(
    val id: String,
    val title: String,
    val detail: String,
    val token: FilterToken,
)

data class CollectionFilterChoices(
    val operators: List<FilterChoice>,
    val manufacturers: List<FilterChoice>,
    val aircraft: List<FilterChoice>,
    val roles: List<FilterChoice>,
    val operationTypes: List<FilterChoice>,
    val locations: List<FilterChoice>,
)

fun SpottingEntry.toFilterable() = FilterableSpotting(
    id = id,
    registration = registration,
    timestamp = timestamp,
    reference = referenceState(),
)

fun filterSpottingEntries(
    entries: List<SpottingEntry>,
    searchText: String,
    filters: SpottingFilterState,
    catalog: SpottingFilterCatalog,
    sort: SpottingFilterSort,
    calendar: Calendar,
): List<SpottingEntry> {
    val ordered = filteredSpottingResults(entries.map { it.toFilterable() }, searchText, filters, catalog, sort, calendar)
    val byId = entries.associateBy { it.id }
    return ordered.mapNotNull { byId[it.id] }
}

fun filteredSpottingResults(
    entries: List<FilterableSpotting>,
    searchText: String,
    filters: SpottingFilterState,
    catalog: SpottingFilterCatalog,
    sort: SpottingFilterSort,
    calendar: Calendar,
): List<FilterableSpotting> {
    val indexed = entries.withIndex().filter { (_, entry) ->
        matchesFreeText(entry, searchText) && matchesFilters(entry, filters, catalog, calendar)
    }
    return indexed.sortedWith { lhs, rhs ->
        val comparison = compareForSort(lhs.value, rhs.value, sort)
        if (comparison == 0) lhs.index.compareTo(rhs.index) else comparison
    }.map { it.value }
}

fun collectionFilterChoices(entries: List<FilterableSpotting>, catalog: SpottingFilterCatalog) = CollectionFilterChoices(
    operators = referenceChoices(entries, ReferenceDimension.OPERATOR, catalog, "No operator specified"),
    manufacturers = manufacturerChoices(entries, catalog),
    aircraft = aircraftChoices(entries, catalog),
    roles = classificationChoices(entries, ClassificationCopy.roleOrder, ClassificationCopy.roleLabels, role = true),
    operationTypes = classificationChoices(entries, ClassificationCopy.operationOrder, ClassificationCopy.operationLabels, role = false),
    locations = referenceChoices(entries, ReferenceDimension.LOCATION, catalog, "No location specified"),
)

fun matchesFreeText(entry: FilterableSpotting, searchText: String): Boolean {
    if (searchText.isEmpty()) return true
    val query = normalizeFilterName(searchText)
    if (query.isEmpty()) return true
    val classification = entry.reference.classification
    val fields = listOf(
        entry.registration,
        entry.reference.storedOperatorText,
        entry.reference.storedLocationText,
        entry.reference.storedAircraftText.orEmpty(),
        entry.reference.storedManufacturerText.orEmpty(),
        classification.roleNote.orEmpty(),
        classification.operationTypeNote.orEmpty(),
        ClassificationCopy.roleLabel(classification.roleId.orEmpty()),
        ClassificationCopy.operationLabel(classification.operationTypeId.orEmpty()),
    )
    return fields.any { normalizeFilterName(it).contains(query) }
}

fun matchesFilters(
    entry: FilterableSpotting,
    filters: SpottingFilterState,
    catalog: SpottingFilterCatalog,
    calendar: Calendar,
): Boolean {
    if (!matchesReference(entry.reference.operatorField, filters.operators, catalog::operatorDisplayNameCount)) return false
    val manufacturer = resolvedManufacturerSelection(entry.reference, catalog)
    if (!matchesReference(manufacturer, filters.manufacturers, catalog::manufacturerDisplayNameCount)) return false
    if (!matchesAircraft(entry.reference.aircraftField, filters.aircraft, catalog)) return false
    if (!matchesClassification(entry.reference.classification.roleId, entry.reference.classification.roleNote, filters.roles)) return false
    if (!matchesClassification(entry.reference.classification.operationTypeId, entry.reference.classification.operationTypeNote, filters.operationTypes)) return false
    if (!matchesReference(entry.reference.locationField, filters.locations, catalog::airportDisplayNameCount)) return false
    if (!registrationMatches(entry.registration, filters.registrationQuery)) return false
    if (!dateMatches(entry.timestamp, filters.dateRange, calendar)) return false
    return true
}

fun resolvedManufacturerSelection(reference: SpottingReferenceState, catalog: SpottingFilterCatalog): AviationSelection {
    val field = reference.manufacturerField
    val savedId = cleanedIdentifier(field.catalogId)
    if (field.kind == AviationSelectionKind.CATALOG && savedId != null) {
        return AviationSelection.catalog(savedId, field.displayText, field.detail)
    }
    if (field.kind == AviationSelectionKind.UNKNOWN) return AviationSelection.unknown()
    if (field.kind == AviationSelectionKind.CUSTOM && normalizeFilterName(field.displayText).isNotEmpty()) return field
    val aircraftId = cleanedIdentifier(reference.aircraftField.catalogId)
    if (reference.aircraftField.kind == AviationSelectionKind.CATALOG && aircraftId != null) {
        val facts = catalog.aircraft(aircraftId)
        val manufacturerId = cleanedIdentifier(facts?.manufacturerId)
        if (facts != null && manufacturerId != null) {
            return AviationSelection.catalog(manufacturerId, catalog.manufacturerName(manufacturerId).orEmpty())
        }
    }
    return AviationSelection.absent
}

private fun matchesReference(
    selection: AviationSelection,
    filters: List<ReferenceFilter>,
    nameCount: (String) -> Int?,
): Boolean {
    if (filters.isEmpty()) return true
    return filters.any { filter ->
        when (filter) {
            is ReferenceFilter.Catalog -> {
                if (selection.kind == AviationSelectionKind.CATALOG && cleanedIdentifier(selection.catalogId) == filter.id) {
                    true
                } else if (selection.kind != AviationSelectionKind.CUSTOM) {
                    false
                } else {
                    val recordName = normalizeFilterName(selection.displayText)
                    val filterName = normalizeFilterName(filter.label)
                    recordName.isNotEmpty() && recordName == filterName && nameCount(filterName) == 1
                }
            }
            is ReferenceFilter.Custom -> selection.kind == AviationSelectionKind.CUSTOM &&
                normalizeFilterName(selection.displayText) == normalizeFilterName(filter.text)
            ReferenceFilter.Unknown -> selection.kind == AviationSelectionKind.UNKNOWN
            ReferenceFilter.Absent -> selection.kind == AviationSelectionKind.ABSENT
        }
    }
}

private fun matchesAircraft(
    selection: AviationSelection,
    filters: List<AircraftFilter>,
    catalog: SpottingFilterCatalog,
): Boolean {
    if (filters.isEmpty()) return true
    return filters.any { filter ->
        when (filter) {
            is AircraftFilter.Model -> {
                if (selection.kind == AviationSelectionKind.CATALOG && cleanedIdentifier(selection.catalogId) == filter.id) {
                    true
                } else if (selection.kind == AviationSelectionKind.CUSTOM) {
                    unambiguousText(selection.displayText, filter.label, catalog::aircraftDisplayNameCount)
                } else {
                    false
                }
            }
            is AircraftFilter.Family -> {
                val recordId = cleanedIdentifier(selection.catalogId)
                if (selection.kind == AviationSelectionKind.CATALOG && recordId != null) {
                    if (recordId == filter.id) {
                        true
                    } else {
                        catalog.aircraft(recordId)?.familyId == filter.id
                    }
                } else if (selection.kind == AviationSelectionKind.CUSTOM) {
                    unambiguousText(selection.displayText, filter.label, catalog::familyDisplayNameCount)
                } else {
                    false
                }
            }
            is AircraftFilter.Custom -> selection.kind == AviationSelectionKind.CUSTOM &&
                normalizeFilterName(selection.displayText) == normalizeFilterName(filter.text)
            AircraftFilter.Unknown -> selection.kind == AviationSelectionKind.UNKNOWN
            AircraftFilter.Absent -> selection.kind == AviationSelectionKind.ABSENT
        }
    }
}

private fun matchesClassification(id: String?, note: String?, filters: List<ClassificationFilter>): Boolean {
    if (filters.isEmpty()) return true
    val cleaned = cleanedIdentifier(id) ?: return false
    return filters.any { filter ->
        when (filter) {
            is ClassificationFilter.Standard -> cleaned == filter.id
            is ClassificationFilter.Other -> {
                if (cleaned != "other") {
                    false
                } else if (filter.note == null || normalizeFilterName(filter.note).isEmpty()) {
                    true
                } else {
                    normalizeFilterName(note.orEmpty()) == normalizeFilterName(filter.note)
                }
            }
        }
    }
}

private fun registrationMatches(registration: String, query: String): Boolean {
    val normalized = normalizeRegistration(query)
    if (normalized.isEmpty()) return true
    return normalizeRegistration(registration).startsWith(normalized)
}

private fun dateMatches(timestamp: Long, range: FilterDateRange, calendar: Calendar): Boolean {
    if (!range.isActive) return true
    if (!range.isValid) return false
    val day = filterCalendarDay(timestamp, calendar)
    if (range.start != null && day < range.start) return false
    if (range.end != null && day > range.end) return false
    return true
}

private fun unambiguousText(recordText: String, label: String, count: (String) -> Int?): Boolean {
    val recordName = normalizeFilterName(recordText)
    val filterName = normalizeFilterName(label)
    if (recordName.isEmpty() || recordName != filterName) return false
    return count(filterName) == 1
}

private fun compareForSort(lhs: FilterableSpotting, rhs: FilterableSpotting, sort: SpottingFilterSort): Int = when (sort) {
    SpottingFilterSort.DATE_NEWEST -> rhs.timestamp.compareTo(lhs.timestamp)
    SpottingFilterSort.DATE_OLDEST -> lhs.timestamp.compareTo(rhs.timestamp)
    SpottingFilterSort.AIRCRAFT_TYPE_AZ -> compareText(lhs.reference.storedAircraftText.orEmpty(), rhs.reference.storedAircraftText.orEmpty(), true)
    SpottingFilterSort.AIRCRAFT_TYPE_ZA -> compareText(lhs.reference.storedAircraftText.orEmpty(), rhs.reference.storedAircraftText.orEmpty(), false)
    SpottingFilterSort.AIRLINE_AZ -> compareText(lhs.reference.storedOperatorText, rhs.reference.storedOperatorText, true)
    SpottingFilterSort.AIRLINE_ZA -> compareText(lhs.reference.storedOperatorText, rhs.reference.storedOperatorText, false)
    SpottingFilterSort.REGISTRATION_AZ -> compareText(lhs.registration, rhs.registration, true)
    SpottingFilterSort.REGISTRATION_ZA -> compareText(lhs.registration, rhs.registration, false)
}

private fun compareText(lhs: String, rhs: String, ascending: Boolean): Int {
    val compared = normalizeFilterName(lhs).compareTo(normalizeFilterName(rhs))
    return if (ascending) compared else -compared
}

private fun firstNames(records: List<FilterCatalogNamed>): Map<String, String> {
    val names = LinkedHashMap<String, String>()
    records.forEach { record -> if (!names.containsKey(record.id)) names[record.id] = record.name }
    return names
}

private fun nameCounts(names: List<String>): Map<String, Int> {
    val counts = HashMap<String, Int>()
    names.forEach { name ->
        val normalized = normalizeFilterName(name)
        if (normalized.isNotEmpty()) counts[normalized] = (counts[normalized] ?: 0) + 1
    }
    return counts
}

private data class ChoiceDraft(val token: FilterToken, val title: String, val kind: String, var count: Int)

private fun referenceChoices(
    entries: List<FilterableSpotting>,
    dimension: ReferenceDimension,
    catalog: SpottingFilterCatalog,
    absentTitle: String,
): List<FilterChoice> {
    val drafts = linkedMapOf<String, ChoiceDraft>()
    entries.forEach { entry ->
        val selection = when (dimension) {
            ReferenceDimension.OPERATOR -> entry.reference.operatorField
            ReferenceDimension.MANUFACTURER -> entry.reference.manufacturerField
            ReferenceDimension.LOCATION -> entry.reference.locationField
        }
        val (token, title, kind) = referenceToken(selection, dimension, catalog, absentTitle)
        accumulate(drafts, token, title, kind)
    }
    ensure(drafts, FilterToken.Reference(dimension, ReferenceFilter.Unknown), "Unknown", "Marked unknown")
    ensure(drafts, FilterToken.Reference(dimension, ReferenceFilter.Absent), absentTitle, "Not specified")
    return finish(drafts)
}

private fun manufacturerChoices(entries: List<FilterableSpotting>, catalog: SpottingFilterCatalog): List<FilterChoice> {
    val drafts = linkedMapOf<String, ChoiceDraft>()
    entries.forEach { entry ->
        val selection = resolvedManufacturerSelection(entry.reference, catalog)
        val (token, title, kind) = referenceToken(selection, ReferenceDimension.MANUFACTURER, catalog, "No manufacturer specified")
        accumulate(drafts, token, title, kind)
    }
    ensure(drafts, FilterToken.Reference(ReferenceDimension.MANUFACTURER, ReferenceFilter.Unknown), "Unknown", "Marked unknown")
    ensure(drafts, FilterToken.Reference(ReferenceDimension.MANUFACTURER, ReferenceFilter.Absent), "No manufacturer specified", "Not specified")
    return finish(drafts)
}

private fun aircraftChoices(entries: List<FilterableSpotting>, catalog: SpottingFilterCatalog): List<FilterChoice> {
    val drafts = linkedMapOf<String, ChoiceDraft>()
    entries.forEach { entry ->
        val selection = entry.reference.aircraftField
        when (selection.kind) {
            AviationSelectionKind.CATALOG -> {
                val id = cleanedIdentifier(selection.catalogId) ?: return@forEach
                val facts = catalog.aircraft(id)
                if (facts?.entryKind == "family") {
                    val title = preferred(facts.displayName, selection.displayText, id)
                    accumulate(drafts, FilterToken.Aircraft(AircraftFilter.Family(id, title)), title, "Family")
                } else {
                    val title = preferred(facts?.displayName, selection.displayText, id)
                    accumulate(drafts, FilterToken.Aircraft(AircraftFilter.Model(id, title)), title, if (facts == null) "Saved identity" else "Model")
                    val familyId = facts?.familyId
                    if (familyId != null) {
                        val familyTitle = preferred(catalog.aircraft(familyId)?.displayName, facts.familyName, familyId)
                        accumulate(drafts, FilterToken.Aircraft(AircraftFilter.Family(familyId, familyTitle)), familyTitle, "Family")
                    }
                }
            }
            AviationSelectionKind.CUSTOM -> {
                val title = selection.displayText.trim()
                accumulate(drafts, FilterToken.Aircraft(AircraftFilter.Custom(selection.displayText)), title, if (selection.isLegacy) "Saved text" else "Custom")
            }
            AviationSelectionKind.UNKNOWN -> accumulate(drafts, FilterToken.Aircraft(AircraftFilter.Unknown), "Unknown", "Marked unknown")
            AviationSelectionKind.ABSENT -> accumulate(drafts, FilterToken.Aircraft(AircraftFilter.Absent), "No aircraft specified", "Not specified")
        }
    }
    ensure(drafts, FilterToken.Aircraft(AircraftFilter.Unknown), "Unknown", "Marked unknown")
    ensure(drafts, FilterToken.Aircraft(AircraftFilter.Absent), "No aircraft specified", "Not specified")
    return finish(drafts)
}

private fun classificationChoices(
    entries: List<FilterableSpotting>,
    order: List<String>,
    labels: Map<String, String>,
    role: Boolean,
): List<FilterChoice> {
    val counts = HashMap<String, Int>()
    val noteCounts = HashMap<String, Int>()
    val noteTitles = HashMap<String, String>()
    entries.forEach { entry ->
        val choice = if (role) {
            entry.reference.classification.roleId to entry.reference.classification.roleNote
        } else {
            entry.reference.classification.operationTypeId to entry.reference.classification.operationTypeNote
        }
        val id = cleanedIdentifier(choice.first) ?: return@forEach
        counts[id] = (counts[id] ?: 0) + 1
        if (id == "other") {
            val note = cleanedNote(choice.second)
            if (note != null) {
                val key = normalizeFilterName(note)
                noteCounts[key] = (noteCounts[key] ?: 0) + 1
                noteTitles.putIfAbsent(key, note)
            }
        }
    }
    val choices = order.map { id ->
        val filter = ClassificationFilter.role(id)
        val token = if (role) FilterToken.Role(filter) else FilterToken.Operation(filter)
        FilterChoice(chipId(token), labels[id] ?: id, "Classification · ${counts[id] ?: 0}", token)
    }.toMutableList()
    noteCounts.keys.sorted().forEach { key ->
        val note = noteTitles[key] ?: key
        val filter = ClassificationFilter.Other(note)
        val token = if (role) FilterToken.Role(filter) else FilterToken.Operation(filter)
        choices += FilterChoice(chipId(token), "Other: $note", "Custom description · ${noteCounts[key] ?: 0}", token)
    }
    return choices
}

private fun referenceToken(
    selection: AviationSelection,
    dimension: ReferenceDimension,
    catalog: SpottingFilterCatalog,
    absentTitle: String,
): Triple<FilterToken, String, String> = when (selection.kind) {
    AviationSelectionKind.CATALOG -> {
        val id = cleanedIdentifier(selection.catalogId).orEmpty()
        val catalogName = when (dimension) {
            ReferenceDimension.OPERATOR -> catalog.operatorName(id)
            ReferenceDimension.MANUFACTURER -> catalog.manufacturerName(id)
            ReferenceDimension.LOCATION -> catalog.airportName(id)
        }
        val title = preferred(catalogName, selection.displayText, id)
        val kind = if (catalogName == null && catalog.isAvailable) "Saved identity" else "Catalog"
        Triple(FilterToken.Reference(dimension, ReferenceFilter.Catalog(id, title)), title, kind)
    }
    AviationSelectionKind.CUSTOM -> Triple(
        FilterToken.Reference(dimension, ReferenceFilter.Custom(selection.displayText)),
        selection.displayText.trim(),
        if (selection.isLegacy) "Saved text" else "Custom",
    )
    AviationSelectionKind.UNKNOWN -> Triple(FilterToken.Reference(dimension, ReferenceFilter.Unknown), "Unknown", "Marked unknown")
    AviationSelectionKind.ABSENT -> Triple(FilterToken.Reference(dimension, ReferenceFilter.Absent), absentTitle, "Not specified")
}

private fun preferred(primary: String?, fallback: String?, id: String): String {
    if (primary != null && normalizeFilterName(primary).isNotEmpty()) return primary
    if (fallback != null && normalizeFilterName(fallback).isNotEmpty()) return fallback
    return id
}

private fun accumulate(drafts: MutableMap<String, ChoiceDraft>, token: FilterToken, title: String, kind: String) {
    val id = chipId(token)
    val existing = drafts[id]
    if (existing == null) drafts[id] = ChoiceDraft(token, title, kind, 1) else existing.count += 1
}

private fun ensure(drafts: MutableMap<String, ChoiceDraft>, token: FilterToken, title: String, kind: String) {
    val id = chipId(token)
    if (!drafts.containsKey(id)) drafts[id] = ChoiceDraft(token, title, kind, 0)
}

private fun finish(drafts: Map<String, ChoiceDraft>): List<FilterChoice> = drafts.map { (id, draft) ->
    FilterChoice(id, draft.title, "${draft.kind} · ${draft.count}", draft.token)
}.sortedWith(compareByDescending<FilterChoice> { countIn(it.detail) }.thenBy { it.title.lowercase(java.util.Locale.ROOT) })

private fun countIn(detail: String): Int = detail.substringAfterLast("·").trim().toIntOrNull() ?: 0
