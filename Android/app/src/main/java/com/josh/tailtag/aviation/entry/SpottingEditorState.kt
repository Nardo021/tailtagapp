package com.josh.tailtag.aviation.entry

import com.josh.tailtag.model.SpottingEntry

data class SpottingEditorState(
    val registration: String = "",
    val reference: SpottingReferenceState = SpottingReferenceState(),
    val notes: String = "",
    val registrationEdited: Boolean = false,
    val operatorEdited: Boolean = false,
    val registrationFromPhoto: Boolean = false,
) {
    fun canSave(photoCount: Int) = EntryRules.canSave(registration, photoCount, reference)

    fun editRegistration(value: String) = copy(
        registration = value,
        registrationEdited = true,
        registrationFromPhoto = false,
    )

    fun commitOperator(selection: AviationSelection) = copy(
        reference = reference.copy(operatorField = selection),
        operatorEdited = true,
    )

    fun commitAircraft(aircraft: AviationSelection, linkedManufacturer: AviationSelection?) : SpottingEditorState {
        val (nextAircraft, nextManufacturer) = AircraftRules.applyingAircraft(
            aircraft,
            reference.manufacturerField,
            linkedManufacturer,
        )
        return copy(reference = reference.copy(aircraftField = nextAircraft, manufacturerField = nextManufacturer))
    }

    fun proposeManufacturer(
        proposed: AviationSelection,
        aircraftManufacturerId: String?,
        aircraftManufacturerName: String?,
    ): Pair<SpottingEditorState, ManufacturerChange> {
        val change = AircraftRules.proposeManufacturerChange(
            aircraft = reference.aircraftField,
            aircraftManufacturerId = aircraftManufacturerId,
            aircraftManufacturerName = aircraftManufacturerName,
            currentManufacturer = reference.manufacturerField,
            proposed = proposed,
        )
        val updated = when (change) {
            is ManufacturerChange.Apply -> copy(reference = reference.copy(manufacturerField = change.selection))
            is ManufacturerChange.Confirm -> this
        }
        return updated to change
    }

    fun resolvePendingManufacturer(keepAircraft: Boolean, proposed: AviationSelection, restore: AviationSelection): SpottingEditorState {
        val (aircraft, manufacturer) = AircraftRules.resolveConflict(keepAircraft, proposed, restore)
        return copy(
            reference = reference.copy(
                aircraftField = aircraft ?: reference.aircraftField,
                manufacturerField = manufacturer,
            ),
        )
    }

    fun commitLocation(selection: AviationSelection) = copy(reference = reference.copy(locationField = selection))

    fun commitRole(id: String?, note: String?) = copy(
        reference = reference.copy(
            classification = reference.classification.copy(roleId = id, roleNote = note).normalized(),
        ),
    )

    fun commitOperation(id: String?, note: String?) = copy(
        reference = reference.copy(
            classification = reference.classification.copy(operationTypeId = id, operationTypeNote = note).normalized(),
        ),
    )

    fun applyPhotoDetection(registration: String?, airline: String?, confidence: Double): SpottingEditorState {
        val suggestion = PhotoTextSuggestion(registration, airline, confidence)
        val nextRegistration = PhotoSuggestions.applyRegistration(this.registration, registrationEdited, suggestion)
        val operator = PhotoSuggestions.applyOperator(
            OperatorFieldState(reference.operatorField, operatorEdited),
            suggestion,
        )
        return copy(
            registration = nextRegistration,
            registrationFromPhoto = nextRegistration != this.registration || registrationFromPhoto,
            reference = reference.copy(operatorField = operator.selection),
            operatorEdited = operator.userEdited,
        )
    }

    fun toEntry(id: String, timestamp: Long, photos: List<String>): SpottingEntry {
        val stored = reference.forStorage()
        return SpottingEntry(
            id = id,
            photos = photos,
            registration = EntryRules.trimmedRegistration(registration),
            airline = stored.operatorField.text,
            location = stored.locationField.text,
            aircraftType = stored.aircraftField.text.ifEmpty { null },
            notes = EntryRules.optionalNote(notes),
            timestamp = timestamp,
            operatorCatalogId = stored.operatorField.catalogId,
            operatorSelectionKind = stored.operatorField.kind,
            manufacturerName = stored.manufacturerField.text.ifEmpty { null },
            manufacturerCatalogId = stored.manufacturerField.catalogId,
            manufacturerSelectionKind = stored.manufacturerField.kind,
            aircraftCatalogId = stored.aircraftField.catalogId,
            aircraftSelectionKind = stored.aircraftField.kind,
            aircraftEntryKind = stored.aircraftField.detail,
            airportCatalogId = stored.locationField.catalogId,
            locationSelectionKind = stored.locationField.kind,
            aircraftRoleId = stored.classification.roleId,
            aircraftRoleNote = stored.classification.roleNote,
            operationTypeId = stored.classification.operationTypeId,
            operationTypeNote = stored.classification.operationTypeNote,
        )
    }

    companion object {
        fun from(entry: SpottingEntry?): SpottingEditorState {
            if (entry == null) return SpottingEditorState()
            val reference = entry.referenceState()
            return SpottingEditorState(
                registration = entry.registration,
                reference = reference,
                notes = entry.notes.orEmpty(),
                registrationEdited = true,
                operatorEdited = reference.operatorField.kind != AviationSelectionKind.ABSENT,
            )
        }
    }
}
