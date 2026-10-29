package com.josh.tailtag.filters

import com.josh.tailtag.aviation.entry.AviationSelection
import com.josh.tailtag.aviation.entry.AviationSelectionKind
import com.josh.tailtag.aviation.entry.ClassificationChoice
import com.josh.tailtag.aviation.entry.ClassificationCopy
import com.josh.tailtag.aviation.entry.SpottingReferenceState
import com.josh.tailtag.aviation.entry.cleanedIdentifier
import com.josh.tailtag.aviation.entry.cleanedNote
import com.josh.tailtag.aviation.entry.referenceState
import com.josh.tailtag.model.SortOption
import com.josh.tailtag.model.SpottingEntry
import java.util.Calendar
import java.util.Locale

private const val UNIT = "\u001f"

data class FilterCalendarDay(val year: Int, val month: Int, val day: Int) : Comparable<FilterCalendarDay> {
    override fun compareTo(other: FilterCalendarDay): Int {
        if (year != other.year) return year.compareTo(other.year)
        if (month != other.month) return month.compareTo(other.month)
        return day.compareTo(other.day)
    }
}

data class FilterDateRange(
    val start: FilterCalendarDay? = null,
    val end: FilterCalendarDay? = null,
) {
    val isActive: Boolean get() = start != null || end != null
    val isValid: Boolean get() = start == null || end == null || start <= end
}

enum class ReferenceDimension(val wire: String) {
    OPERATOR("operator"),
    MANUFACTURER("manufacturer"),
    LOCATION("location"),
}

sealed class ReferenceFilter {
    abstract val label: String

    class Catalog(val id: String, override val label: String) : ReferenceFilter() {
        override fun equals(other: Any?) = other is Catalog && other.id == id
        override fun hashCode() = id.hashCode()
    }

    class Custom(val text: String) : ReferenceFilter() {
        override val label: String get() = text.trim()
        override fun equals(other: Any?) = other is Custom && normalizeFilterName(text) == normalizeFilterName(other.text)
        override fun hashCode() = normalizeFilterName(text).hashCode()
    }

    data object Unknown : ReferenceFilter() {
        override val label = "Unknown"
    }

    data object Absent : ReferenceFilter() {
        override val label = "Not specified"
    }
}

sealed class AircraftFilter {
    class Model(val id: String, val label: String) : AircraftFilter() {
        override fun equals(other: Any?) = other is Model && other.id == id
        override fun hashCode() = id.hashCode()
    }

    class Family(val id: String, val label: String) : AircraftFilter() {
        override fun equals(other: Any?) = other is Family && other.id == id
        override fun hashCode() = id.hashCode()
    }

    class Custom(val text: String) : AircraftFilter() {
        override fun equals(other: Any?) = other is Custom && normalizeFilterName(text) == normalizeFilterName(other.text)
        override fun hashCode() = normalizeFilterName(text).hashCode()
    }

    data object Unknown : AircraftFilter()
    data object Absent : AircraftFilter()
}

sealed class ClassificationFilter {
    class Standard(val id: String) : ClassificationFilter() {
        override fun equals(other: Any?) = other is Standard && other.id == id
        override fun hashCode() = id.hashCode()
    }

    class Other(val note: String?) : ClassificationFilter() {
        override fun equals(other: Any?) = other is Other && normalizeFilterName(note.orEmpty()) == normalizeFilterName(other.note.orEmpty())
        override fun hashCode() = normalizeFilterName(note.orEmpty()).hashCode()
    }

    companion object {
        fun role(id: String, note: String? = null): ClassificationFilter {
            return if (id == "other") Other(cleanedNote(note)) else Standard(id)
        }

        fun operation(id: String, note: String? = null) = role(id, note)
    }
}

sealed class FilterToken {
    data class Reference(val dimension: ReferenceDimension, val value: ReferenceFilter) : FilterToken()
    data class Aircraft(val value: AircraftFilter) : FilterToken()
    data class Role(val value: ClassificationFilter) : FilterToken()
    data class Operation(val value: ClassificationFilter) : FilterToken()
    data object Registration : FilterToken()
    data object DateRange : FilterToken()
}

data class SpottingFilterChip(
    val id: String,
    val label: String,
    val accessibilityLabel: String,
    val token: FilterToken,
)

enum class SpottingFilterSort {
    DATE_NEWEST,
    DATE_OLDEST,
    AIRCRAFT_TYPE_AZ,
    AIRCRAFT_TYPE_ZA,
    AIRLINE_AZ,
    AIRLINE_ZA,
    REGISTRATION_AZ,
    REGISTRATION_ZA,
}

fun SortOption.toFilterSort(): SpottingFilterSort = when (this) {
    SortOption.DATE_NEWEST -> SpottingFilterSort.DATE_NEWEST
    SortOption.DATE_OLDEST -> SpottingFilterSort.DATE_OLDEST
    SortOption.AIRCRAFT_TYPE_AZ -> SpottingFilterSort.AIRCRAFT_TYPE_AZ
    SortOption.AIRCRAFT_TYPE_ZA -> SpottingFilterSort.AIRCRAFT_TYPE_ZA
    SortOption.AIRLINE_AZ -> SpottingFilterSort.AIRLINE_AZ
    SortOption.AIRLINE_ZA -> SpottingFilterSort.AIRLINE_ZA
    SortOption.REGISTRATION_AZ -> SpottingFilterSort.REGISTRATION_AZ
    SortOption.REGISTRATION_ZA -> SpottingFilterSort.REGISTRATION_ZA
}

enum class FilterDimension {
    OPERATORS,
    MANUFACTURERS,
    AIRCRAFT,
    ROLES,
    OPERATION_TYPES,
    LOCATIONS,
    REGISTRATION,
    DATE_RANGE,
}

data class SpottingFilterState(
    val operators: List<ReferenceFilter> = emptyList(),
    val manufacturers: List<ReferenceFilter> = emptyList(),
    val aircraft: List<AircraftFilter> = emptyList(),
    val roles: List<ClassificationFilter> = emptyList(),
    val operationTypes: List<ClassificationFilter> = emptyList(),
    val locations: List<ReferenceFilter> = emptyList(),
    val registrationQuery: String = "",
    val dateRange: FilterDateRange = FilterDateRange(),
) {
    val registrationIsActive: Boolean get() = normalizeRegistration(registrationQuery).isNotEmpty()
    val activeConditionCount: Int
        get() = operators.size + manufacturers.size + aircraft.size + roles.size +
            operationTypes.size + locations.size +
            (if (registrationIsActive) 1 else 0) +
            (if (dateRange.isActive) 1 else 0)
    val isActive: Boolean get() = activeConditionCount > 0

    fun insert(token: FilterToken): SpottingFilterState = when (token) {
        is FilterToken.Reference -> when (token.dimension) {
            ReferenceDimension.OPERATOR -> copy(operators = operators.insertUnique(token.value))
            ReferenceDimension.MANUFACTURER -> copy(manufacturers = manufacturers.insertUnique(token.value))
            ReferenceDimension.LOCATION -> copy(locations = locations.insertUnique(token.value))
        }
        is FilterToken.Aircraft -> copy(aircraft = aircraft.insertUnique(token.value))
        is FilterToken.Role -> copy(roles = roles.insertUnique(token.value))
        is FilterToken.Operation -> copy(operationTypes = operationTypes.insertUnique(token.value))
        FilterToken.Registration, FilterToken.DateRange -> this
    }

    fun remove(token: FilterToken): SpottingFilterState = when (token) {
        is FilterToken.Reference -> when (token.dimension) {
            ReferenceDimension.OPERATOR -> copy(operators = operators.filterNot { it == token.value })
            ReferenceDimension.MANUFACTURER -> copy(manufacturers = manufacturers.filterNot { it == token.value })
            ReferenceDimension.LOCATION -> copy(locations = locations.filterNot { it == token.value })
        }
        is FilterToken.Aircraft -> copy(aircraft = aircraft.filterNot { it == token.value })
        is FilterToken.Role -> copy(roles = roles.filterNot { it == token.value })
        is FilterToken.Operation -> copy(operationTypes = operationTypes.filterNot { it == token.value })
        FilterToken.Registration -> copy(registrationQuery = "")
        FilterToken.DateRange -> copy(dateRange = FilterDateRange())
    }

    fun toggle(token: FilterToken): SpottingFilterState = if (contains(token)) remove(token) else insert(token)

    fun contains(token: FilterToken): Boolean = when (token) {
        is FilterToken.Reference -> when (token.dimension) {
            ReferenceDimension.OPERATOR -> operators.contains(token.value)
            ReferenceDimension.MANUFACTURER -> manufacturers.contains(token.value)
            ReferenceDimension.LOCATION -> locations.contains(token.value)
        }
        is FilterToken.Aircraft -> aircraft.contains(token.value)
        is FilterToken.Role -> roles.contains(token.value)
        is FilterToken.Operation -> operationTypes.contains(token.value)
        FilterToken.Registration -> registrationIsActive
        FilterToken.DateRange -> dateRange.isActive
    }

    fun clear(dimension: FilterDimension): SpottingFilterState = when (dimension) {
        FilterDimension.OPERATORS -> copy(operators = emptyList())
        FilterDimension.MANUFACTURERS -> copy(manufacturers = emptyList())
        FilterDimension.AIRCRAFT -> copy(aircraft = emptyList())
        FilterDimension.ROLES -> copy(roles = emptyList())
        FilterDimension.OPERATION_TYPES -> copy(operationTypes = emptyList())
        FilterDimension.LOCATIONS -> copy(locations = emptyList())
        FilterDimension.REGISTRATION -> copy(registrationQuery = "")
        FilterDimension.DATE_RANGE -> copy(dateRange = FilterDateRange())
    }

    fun reset() = SpottingFilterState()

    fun removeChip(id: String): SpottingFilterState {
        val token = tokenForChipId(id) ?: return this
        return remove(token)
    }

    fun chips(): List<SpottingFilterChip> = buildList {
        operators.forEach { add(referenceChip("Operator", it, "No operator specified", ReferenceDimension.OPERATOR)) }
        manufacturers.forEach { add(referenceChip("Manufacturer", it, "No manufacturer specified", ReferenceDimension.MANUFACTURER)) }
        aircraft.forEach { add(aircraftChip(it)) }
        roles.forEach { add(classificationChip("Role", it, ClassificationCopy.roleLabels, isRole = true)) }
        operationTypes.forEach { add(classificationChip("Operation", it, ClassificationCopy.operationLabels, isRole = false)) }
        locations.forEach { add(referenceChip("Location", it, "No location specified", ReferenceDimension.LOCATION)) }
        if (registrationIsActive) {
            val shown = normalizeRegistration(registrationQuery)
            add(chip("Registration: $shown", FilterToken.Registration))
        }
        if (dateRange.isActive) add(chip("Date: ${dateRangeLabel(dateRange)}", FilterToken.DateRange))
    }
}

data class SpottingFilterSession(
    val filters: SpottingFilterState = SpottingFilterState(),
    val sort: SpottingFilterSort = SpottingFilterSort.DATE_NEWEST,
)

fun normalizeFilterName(value: String): String =
    value.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ").lowercase(Locale.ROOT)

fun normalizeRegistration(value: String): String =
    value.uppercase(Locale.ROOT).filterNot { it.isWhitespace() }

fun filterCalendarDay(millis: Long, calendar: Calendar): FilterCalendarDay {
    val copy = calendar.clone() as Calendar
    copy.timeInMillis = millis
    return FilterCalendarDay(copy.get(Calendar.YEAR), copy.get(Calendar.MONTH) + 1, copy.get(Calendar.DAY_OF_MONTH))
}

fun formatFilterDay(day: FilterCalendarDay): String {
    val months = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
    if (day.month !in 1..12) return "${day.year}-${day.month}-${day.day}"
    return "${day.day} ${months[day.month - 1]} ${day.year}"
}

fun chipId(token: FilterToken): String = when (token) {
    is FilterToken.Reference -> "${token.dimension.wire}$UNIT${referenceSuffix(token.value)}"
    is FilterToken.Aircraft -> "aircraft$UNIT${aircraftSuffix(token.value)}"
    is FilterToken.Role -> "role$UNIT${classificationSuffix(token.value)}"
    is FilterToken.Operation -> "operation$UNIT${classificationSuffix(token.value)}"
    FilterToken.Registration -> "registration"
    FilterToken.DateRange -> "date"
}

private fun <T> List<T>.insertUnique(value: T): List<T> = if (contains(value)) this else this + value

private fun referenceChip(dimension: String, value: ReferenceFilter, absent: String, owner: ReferenceDimension): SpottingFilterChip {
    val text = when (value) {
        is ReferenceFilter.Absent -> absent
        is ReferenceFilter.Unknown -> "Unknown"
        is ReferenceFilter.Catalog -> value.label.ifBlank { "Catalog record" }
        is ReferenceFilter.Custom -> value.text.trim()
    }
    return chip("$dimension: $text", FilterToken.Reference(owner, value))
}

private fun aircraftChip(value: AircraftFilter): SpottingFilterChip {
    val text = when (value) {
        is AircraftFilter.Model -> "Aircraft: ${value.label.ifBlank { "Catalog record" }}"
        is AircraftFilter.Family -> "Family: ${value.label.ifBlank { "Catalog record" }}"
        is AircraftFilter.Custom -> "Aircraft: ${value.text.trim()}"
        AircraftFilter.Unknown -> "Aircraft: Unknown"
        AircraftFilter.Absent -> "Aircraft: No aircraft specified"
    }
    return chip(text, FilterToken.Aircraft(value))
}

private fun classificationChip(
    dimension: String,
    value: ClassificationFilter,
    labels: Map<String, String>,
    isRole: Boolean,
): SpottingFilterChip {
    val text = when (value) {
        is ClassificationFilter.Standard -> "$dimension: ${labels[value.id] ?: value.id}"
        is ClassificationFilter.Other -> {
            val note = value.note?.trim().orEmpty()
            if (normalizeFilterName(note).isEmpty()) "$dimension: Other" else "$dimension: Other: $note"
        }
    }
    val token = if (isRole) FilterToken.Role(value) else FilterToken.Operation(value)
    return chip(text, token)
}

private fun chip(label: String, token: FilterToken) = SpottingFilterChip(
    id = chipId(token),
    label = label,
    accessibilityLabel = "Remove $label",
    token = token,
)

private fun dateRangeLabel(range: FilterDateRange): String {
    if (!range.isValid) return "End is before start"
    val start = range.start
    val end = range.end
    return when {
        start != null && end != null -> "${formatFilterDay(start)} – ${formatFilterDay(end)}"
        start != null -> "From ${formatFilterDay(start)}"
        end != null -> "Until ${formatFilterDay(end)}"
        else -> "Any date"
    }
}

private fun referenceSuffix(value: ReferenceFilter): String = when (value) {
    is ReferenceFilter.Catalog -> "catalog$UNIT${value.id}"
    is ReferenceFilter.Custom -> "custom$UNIT${normalizeFilterName(value.text)}"
    ReferenceFilter.Unknown -> "unknown"
    ReferenceFilter.Absent -> "absent"
}

private fun aircraftSuffix(value: AircraftFilter): String = when (value) {
    is AircraftFilter.Model -> "model$UNIT${value.id}"
    is AircraftFilter.Family -> "family$UNIT${value.id}"
    is AircraftFilter.Custom -> "custom$UNIT${normalizeFilterName(value.text)}"
    AircraftFilter.Unknown -> "unknown"
    AircraftFilter.Absent -> "absent"
}

private fun classificationSuffix(value: ClassificationFilter): String = when (value) {
    is ClassificationFilter.Standard -> value.id
    is ClassificationFilter.Other -> {
        val note = normalizeFilterName(value.note.orEmpty())
        if (note.isEmpty()) "other" else "other$UNIT$note"
    }
}

private fun tokenForChipId(id: String): FilterToken? {
    if (id == "registration") return FilterToken.Registration
    if (id == "date") return FilterToken.DateRange
    val parts = id.split(UNIT)
    if (parts.size < 2) return null
    return when (parts[0]) {
        ReferenceDimension.OPERATOR.wire -> referenceToken(ReferenceDimension.OPERATOR, parts.drop(1))
        ReferenceDimension.MANUFACTURER.wire -> referenceToken(ReferenceDimension.MANUFACTURER, parts.drop(1))
        ReferenceDimension.LOCATION.wire -> referenceToken(ReferenceDimension.LOCATION, parts.drop(1))
        "aircraft" -> aircraftFilter(parts)?.let { FilterToken.Aircraft(it) }
        "role" -> classificationFilter(parts)?.let { FilterToken.Role(it) }
        "operation" -> classificationFilter(parts)?.let { FilterToken.Operation(it) }
        else -> null
    }
}

private fun referenceToken(dimension: ReferenceDimension, parts: List<String>): FilterToken? {
    val value = referenceFilter(parts) ?: return null
    return FilterToken.Reference(dimension, value)
}

private fun referenceFilter(parts: List<String>): ReferenceFilter? {
    val kind = parts.firstOrNull() ?: return null
    return when (kind) {
        "catalog" -> parts.drop(1).takeIf { it.isNotEmpty() }?.joinToString(UNIT)?.let { ReferenceFilter.Catalog(it, "") }
        "custom" -> parts.drop(1).takeIf { it.isNotEmpty() }?.joinToString(UNIT)?.let { ReferenceFilter.Custom(it) }
        "unknown" -> ReferenceFilter.Unknown
        "absent" -> ReferenceFilter.Absent
        else -> null
    }
}

private fun aircraftFilter(parts: List<String>): AircraftFilter? {
    if (parts.size < 2) return null
    return when (parts[1]) {
        "model" -> parts.drop(2).takeIf { it.isNotEmpty() }?.joinToString(UNIT)?.let { AircraftFilter.Model(it, "") }
        "family" -> parts.drop(2).takeIf { it.isNotEmpty() }?.joinToString(UNIT)?.let { AircraftFilter.Family(it, "") }
        "custom" -> parts.drop(2).takeIf { it.isNotEmpty() }?.joinToString(UNIT)?.let { AircraftFilter.Custom(it) }
        "unknown" -> AircraftFilter.Unknown
        "absent" -> AircraftFilter.Absent
        else -> null
    }
}

private fun classificationFilter(parts: List<String>): ClassificationFilter? {
    if (parts.size < 2) return null
    if (parts[1] == "other") {
        val note = parts.drop(2).joinToString(UNIT)
        return ClassificationFilter.Other(note.ifEmpty { null })
    }
    return ClassificationFilter.Standard(parts.drop(1).joinToString(UNIT))
}
