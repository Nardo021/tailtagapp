package com.josh.tailtag.aviation.entry

import com.josh.tailtag.aviation.AircraftModel
import com.josh.tailtag.aviation.AviationAirport
import com.josh.tailtag.aviation.AviationManufacturer
import com.josh.tailtag.aviation.AviationOperator

data class ClassificationChoice(
    val roleId: String? = null,
    val roleNote: String? = null,
    val operationTypeId: String? = null,
    val operationTypeNote: String? = null,
) {
    fun normalized(): ClassificationChoice {
        val role = cleanedIdentifier(roleId)
        val operation = cleanedIdentifier(operationTypeId)
        return copy(
            roleId = role,
            operationTypeId = operation,
            roleNote = if (role == "other") cleanedNote(roleNote) else null,
            operationTypeNote = if (operation == "other") cleanedNote(operationTypeNote) else null,
        )
    }

    companion object {
        val unset = ClassificationChoice()
    }
}

data class SpottingReferenceState(
    val operatorField: AviationSelection = AviationSelection.absent,
    val manufacturerField: AviationSelection = AviationSelection.absent,
    val aircraftField: AviationSelection = AviationSelection.absent,
    val locationField: AviationSelection = AviationSelection.absent,
    val classification: ClassificationChoice = ClassificationChoice.unset,
) {
    val storedOperatorText: String get() = PersistedAviationField(operatorField).text
    val storedLocationText: String get() = PersistedAviationField(locationField).text
    val storedAircraftText: String? get() = PersistedAviationField(aircraftField).text.ifEmpty { null }
    val storedManufacturerText: String? get() = PersistedAviationField(manufacturerField).text.ifEmpty { null }

    fun forStorage() = PersistedSpottingReference(
        operatorField = PersistedAviationField(operatorField),
        manufacturerField = PersistedAviationField(manufacturerField),
        aircraftField = PersistedAviationField(aircraftField),
        locationField = PersistedAviationField(locationField),
        classification = classification.normalized(),
    )

    companion object {
        fun legacy(airline: String, location: String, aircraftType: String?, manufacturer: String? = null) = SpottingReferenceState(
            operatorField = AviationSelection.legacy(airline),
            manufacturerField = AviationSelection.legacy(manufacturer.orEmpty()),
            aircraftField = AviationSelection.legacy(aircraftType.orEmpty()),
            locationField = AviationSelection.legacy(location),
        )
    }
}

data class PersistedSpottingReference(
    val operatorField: PersistedAviationField,
    val manufacturerField: PersistedAviationField,
    val aircraftField: PersistedAviationField,
    val locationField: PersistedAviationField,
    val classification: ClassificationChoice,
) {
    fun restored() = SpottingReferenceState(
        operatorField = operatorField.selection(),
        manufacturerField = manufacturerField.selection(),
        aircraftField = aircraftField.selection(),
        locationField = locationField.selection(),
        classification = classification,
    )
}

fun classificationSummary(id: String?, note: String?, labels: Map<String, String>): String? {
    val cleaned = cleanedIdentifier(id) ?: return null
    val label = labels[cleaned] ?: cleaned
    val custom = if (cleaned == "other") cleanedNote(note) else null
    return if (custom != null) "$label: $custom" else label
}

fun cleanedIdentifier(value: String?): String? = value?.trim()?.takeIf { it.isNotEmpty() }

fun cleanedNote(value: String?): String? = value?.trim()?.takeIf { it.isNotEmpty() }

fun com.josh.tailtag.model.SpottingEntry.referenceState(): SpottingReferenceState = PersistedSpottingReference(
    operatorField = PersistedAviationField(
        kind = operatorSelectionKind,
        catalogId = operatorCatalogId,
        text = airline,
    ),
    manufacturerField = PersistedAviationField(
        kind = manufacturerSelectionKind,
        catalogId = manufacturerCatalogId,
        text = manufacturerName.orEmpty(),
    ),
    aircraftField = PersistedAviationField(
        kind = aircraftSelectionKind,
        catalogId = aircraftCatalogId,
        text = aircraftType.orEmpty(),
        detail = aircraftEntryKind,
    ),
    locationField = PersistedAviationField(
        kind = locationSelectionKind,
        catalogId = airportCatalogId,
        text = location,
    ),
    classification = ClassificationChoice(
        roleId = aircraftRoleId,
        roleNote = aircraftRoleNote,
        operationTypeId = operationTypeId,
        operationTypeNote = operationTypeNote,
    ),
).restored()

enum class EntryFieldIssue { REGISTRATION, PHOTOS, OPERATOR, LOCATION, MANUFACTURER, AIRCRAFT }

object EntryRules {
    fun registrationIsValid(value: String) = value.isNotBlank()

    fun trimmedRegistration(value: String) = value.trim()

    fun optionalNote(value: String) = value.trim().takeIf { it.isNotEmpty() }

    fun operatorIsValid(selection: AviationSelection) = when (selection.kind) {
        AviationSelectionKind.CATALOG -> selection.hasCatalogIdentity
        AviationSelectionKind.CUSTOM -> selection.displayText.isNotBlank()
        AviationSelectionKind.UNKNOWN, AviationSelectionKind.ABSENT -> true
    }

    fun locationIsValid(selection: AviationSelection) = when (selection.kind) {
        AviationSelectionKind.CATALOG -> selection.hasCatalogIdentity && selection.displayText.isNotBlank()
        AviationSelectionKind.CUSTOM -> selection.displayText.isNotBlank()
        AviationSelectionKind.UNKNOWN -> true
        AviationSelectionKind.ABSENT -> false
    }

    fun optionalSelectionIsValid(selection: AviationSelection) = when (selection.kind) {
        AviationSelectionKind.CATALOG -> selection.hasCatalogIdentity
        AviationSelectionKind.CUSTOM -> selection.displayText.isNotBlank()
        AviationSelectionKind.UNKNOWN, AviationSelectionKind.ABSENT -> true
    }

    fun canSave(registration: String, photoCount: Int, reference: SpottingReferenceState) =
        issues(registration, photoCount, reference).isEmpty()

    fun issues(registration: String, photoCount: Int, reference: SpottingReferenceState): List<EntryFieldIssue> = buildList {
        if (!registrationIsValid(registration)) add(EntryFieldIssue.REGISTRATION)
        if (photoCount < 1) add(EntryFieldIssue.PHOTOS)
        if (!operatorIsValid(reference.operatorField)) add(EntryFieldIssue.OPERATOR)
        if (!locationIsValid(reference.locationField)) add(EntryFieldIssue.LOCATION)
        if (!optionalSelectionIsValid(reference.manufacturerField)) add(EntryFieldIssue.MANUFACTURER)
        if (!optionalSelectionIsValid(reference.aircraftField)) add(EntryFieldIssue.AIRCRAFT)
    }
}

data class ManufacturerConflict(
    val aircraftId: String,
    val aircraftManufacturerId: String,
    val proposedManufacturerId: String?,
)

sealed class ManufacturerChange {
    data class Apply(val selection: AviationSelection) : ManufacturerChange()
    data class Confirm(
        val conflict: ManufacturerConflict,
        val proposed: AviationSelection,
        val restore: AviationSelection,
    ) : ManufacturerChange()
}

object AircraftRules {
    fun applyingAircraft(
        aircraft: AviationSelection,
        currentManufacturer: AviationSelection,
        linkedManufacturer: AviationSelection?,
    ): Pair<AviationSelection, AviationSelection> {
        if (aircraft.kind == AviationSelectionKind.CATALOG && linkedManufacturer?.hasCatalogIdentity == true) {
            return aircraft to linkedManufacturer
        }
        return aircraft to currentManufacturer
    }

    fun proposeManufacturerChange(
        aircraft: AviationSelection,
        aircraftManufacturerId: String?,
        aircraftManufacturerName: String?,
        currentManufacturer: AviationSelection,
        proposed: AviationSelection,
    ): ManufacturerChange {
        val aircraftId = aircraft.catalogId
        val known = cleanedIdentifier(aircraftManufacturerId)
        if (aircraft.kind != AviationSelectionKind.CATALOG || aircraftId.isNullOrEmpty() || known == null) {
            return ManufacturerChange.Apply(proposed)
        }
        val proposedId = if (proposed.kind == AviationSelectionKind.CATALOG) cleanedIdentifier(proposed.catalogId) else null
        if (proposed.kind == AviationSelectionKind.CATALOG && proposedId == known) {
            return ManufacturerChange.Apply(proposed)
        }
        val restoreName = if (currentManufacturer.kind == AviationSelectionKind.CATALOG && currentManufacturer.catalogId == known) {
            currentManufacturer.displayText
        } else {
            cleanedIdentifier(aircraftManufacturerName) ?: known
        }
        return ManufacturerChange.Confirm(
            conflict = ManufacturerConflict(aircraftId, known, proposedId),
            proposed = proposed,
            restore = AviationSelection.catalog(known, restoreName),
        )
    }

    fun resolveConflict(
        keepAircraft: Boolean,
        proposed: AviationSelection,
        restore: AviationSelection,
    ): Pair<AviationSelection?, AviationSelection> {
        return if (keepAircraft) null to restore else AviationSelection.absent to proposed
    }
}

data class PhotoTextSuggestion(
    val registration: String?,
    val operatorText: String?,
    val confidence: Double,
)

data class OperatorFieldState(
    val selection: AviationSelection,
    val userEdited: Boolean,
)

object PhotoSuggestions {
    const val minimumConfidence = 0.6

    fun applyRegistration(current: String, userEdited: Boolean, suggestion: PhotoTextSuggestion): String {
        val detected = suggestion.registration?.trim()
        if (userEdited || suggestion.confidence <= minimumConfidence || detected.isNullOrEmpty() || current.isNotBlank()) {
            return current
        }
        return detected
    }

    fun applyOperator(field: OperatorFieldState, suggestion: PhotoTextSuggestion): OperatorFieldState {
        val detected = suggestion.operatorText?.trim()
        if (
            suggestion.confidence <= minimumConfidence ||
            detected.isNullOrEmpty() ||
            field.userEdited ||
            field.selection.kind != AviationSelectionKind.ABSENT
        ) {
            return field
        }
        return OperatorFieldState(
            AviationSelection(AviationSelectionKind.CUSTOM, displayText = detected, suggestedFromPhoto = true),
            userEdited = false,
        )
    }
}

fun aircraftKindLabel(entryKind: String) = when (entryKind) {
    "model" -> "Model"
    "family" -> "Family"
    "unspecified" -> "Unspecified"
    else -> entryKind
}

fun officialDesignatorText(codes: List<String>): String? {
    val cleaned = codes.map { it.trim() }.filter { it.isNotEmpty() }
    return cleaned.takeIf { it.isNotEmpty() }?.joinToString(", ")
}

fun aircraftSelection(model: AircraftModel) = AviationSelection.catalog(
    id = model.id,
    displayText = model.displayName,
    detail = aircraftKindLabel(model.entryKind),
)

fun linkedManufacturerSelection(model: AircraftModel): AviationSelection? {
    val id = cleanedIdentifier(model.manufacturerId) ?: return null
    val name = cleanedIdentifier(model.manufacturer) ?: model.manufacturerNames.firstOrNull { cleanedIdentifier(it) != null }
    val cleanedName = cleanedIdentifier(name) ?: return null
    return AviationSelection.catalog(id, cleanedName)
}

fun classificationUnchanged(classification: ClassificationChoice) = classification

data class LabeledCode(val title: String, val code: String)

object CatalogPresentation {
    fun operatorCodeSummary(record: AviationOperator): String {
        val parts = buildList {
            if (record.iataCodes.isNotEmpty()) add("IATA ${record.iataCodes.joinToString(", ")}")
            if (record.icaoCodes.isNotEmpty()) add("ICAO ${record.icaoCodes.joinToString(", ")}")
            if (record.callsigns.isNotEmpty()) add(record.callsigns.joinToString(", "))
            cleanedIdentifier(record.countryCode)?.let(::add)
        }
        return parts.joinToString(" · ")
    }

    fun operatorAccessibilityLabel(record: AviationOperator): String {
        val pieces = mutableListOf(record.name, operatorCodeSummary(record)).filter { it.isNotEmpty() }.toMutableList()
        if (record.historical) {
            pieces += "Historical"
            cleanedIdentifier(record.dissolvedOn)?.let { pieces += "dissolved $it" }
        }
        return pieces.joinToString(", ")
    }

    fun primaryAirportCode(airport: AviationAirport): LabeledCode? {
        cleanedIdentifier(airport.iataCode)?.let { return LabeledCode("IATA", it) }
        cleanedIdentifier(airport.icaoCode)?.let { return LabeledCode("ICAO", it) }
        cleanedIdentifier(airport.ident)?.let { return LabeledCode("Ident", it) }
        return null
    }

    fun airportTypeLabel(type: String) = when (type) {
        "closed" -> "Closed"
        "heliport" -> "Heliport"
        "small_airport" -> "Small airport"
        "medium_airport" -> "Medium airport"
        "large_airport" -> "Large airport"
        "seaplane_base" -> "Seaplane base"
        "balloonport" -> "Balloonport"
        else -> type.replace('_', ' ').replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
    }

    fun isClosedAirport(airport: AviationAirport) = airport.type == "closed"

    fun airportSubtitle(airport: AviationAirport): String = buildList {
        primaryAirportCode(airport)?.let { add("${it.title} ${it.code}") }
        cleanedIdentifier(airport.municipality)?.let(::add)
        cleanedIdentifier(airport.countryCode)?.let(::add)
        if (airport.type.isNotEmpty()) add(airportTypeLabel(airport.type))
    }.joinToString(" · ")

    fun airportSnapshot(airport: AviationAirport): String {
        val code = primaryAirportCode(airport) ?: return airport.name
        return if (code.title == "Ident") "${airport.name} (ident ${code.code})" else "${airport.name} (${code.code})"
    }

    fun airportAccessibilityLabel(airport: AviationAirport): String {
        val pieces = mutableListOf(airport.name, airportSubtitle(airport)).filter { it.isNotEmpty() }.toMutableList()
        if (isClosedAirport(airport)) pieces += "Closed"
        return pieces.joinToString(", ")
    }

    fun aircraftSubtitle(model: AircraftModel): String = buildList {
        add(aircraftKindLabel(model.entryKind))
        cleanedIdentifier(model.manufacturer)?.let(::add)
        val family = cleanedIdentifier(model.family)
        if (family != null && family != model.displayName && family != model.model) add(family)
        officialDesignatorText(model.icaoTypeDesignators)?.let { add("ICAO $it") }
    }.joinToString(" · ")

    fun manufacturerSubtitle(record: AviationManufacturer) = cleanedIdentifier(record.countryCode).orEmpty()
}

object ClassificationCopy {
    val roleLabels = mapOf(
        "civil" to "Civil",
        "military" to "Military",
        "unknown" to "Unknown",
        "other" to "Other",
    )
    val operationLabels = mapOf(
        "passenger" to "Passenger",
        "cargo" to "Cargo",
        "private" to "Private",
        "general-aviation" to "General aviation",
        "government" to "Government",
        "training" to "Training",
        "emergency-services" to "Emergency services",
        "mixed" to "Mixed",
        "unknown" to "Unknown",
        "other" to "Other",
    )
    val roleDescriptions = mapOf(
        "civil" to "Civil aircraft, including airline, private, and other non-military flying.",
        "military" to "Military or armed-forces aircraft.",
        "unknown" to "The role is not known.",
        "other" to "A role that is not listed.",
    )
    val operationDescriptions = mapOf(
        "passenger" to "Carrying passengers.",
        "cargo" to "Carrying freight.",
        "private" to "Private or personal flying.",
        "general-aviation" to "General aviation that is not a scheduled airline service.",
        "government" to "Government flying that is not necessarily military.",
        "training" to "Training or instructional flying.",
        "emergency-services" to "Emergency, medical, or rescue flying.",
        "mixed" to "More than one kind of operation.",
        "unknown" to "The operation is not known.",
        "other" to "An operation that is not listed.",
    )
    val roleOrder = listOf("civil", "military", "unknown", "other")
    val operationOrder = listOf(
        "passenger", "cargo", "private", "general-aviation", "government",
        "training", "emergency-services", "mixed", "unknown", "other",
    )

    fun roleLabel(id: String, catalogLabels: Map<String, String> = emptyMap()) = catalogLabels[id] ?: roleLabels[id] ?: id

    fun operationLabel(id: String, catalogLabels: Map<String, String> = emptyMap()) =
        catalogLabels[id] ?: operationLabels[id] ?: id
}
