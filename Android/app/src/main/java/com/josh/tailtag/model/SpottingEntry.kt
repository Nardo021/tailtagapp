package com.josh.tailtag.model

import java.util.UUID

data class SpottingEntry(
    val id: String = UUID.randomUUID().toString(),
    val photos: List<String> = emptyList(),
    val registration: String,
    val airline: String,
    val location: String,
    val aircraftType: String? = null,
    val notes: String? = null,
    val timestamp: Long = System.currentTimeMillis(),
    val operatorCatalogId: String? = null,
    val operatorSelectionKind: String? = null,
    val manufacturerName: String? = null,
    val manufacturerCatalogId: String? = null,
    val manufacturerSelectionKind: String? = null,
    val aircraftCatalogId: String? = null,
    val aircraftSelectionKind: String? = null,
    val aircraftEntryKind: String? = null,
    val airportCatalogId: String? = null,
    val locationSelectionKind: String? = null,
    val aircraftRoleId: String? = null,
    val aircraftRoleNote: String? = null,
    val operationTypeId: String? = null,
    val operationTypeNote: String? = null,
)

enum class SortOption(val label: String) {
    DATE_NEWEST("Date (newest)"),
    DATE_OLDEST("Date (oldest)"),
    AIRCRAFT_TYPE_AZ("Aircraft type (A–Z)"),
    AIRCRAFT_TYPE_ZA("Aircraft type (Z–A)"),
    AIRLINE_AZ("Airline (A–Z)"),
    AIRLINE_ZA("Airline (Z–A)"),
    REGISTRATION_AZ("Registration (A–Z)"),
    REGISTRATION_ZA("Registration (Z–A)"),
}

fun List<SpottingEntry>.sortedByOption(option: SortOption): List<SpottingEntry> = when (option) {
    SortOption.DATE_NEWEST -> sortedByDescending { it.timestamp }
    SortOption.DATE_OLDEST -> sortedBy { it.timestamp }
    SortOption.AIRCRAFT_TYPE_AZ -> sortedBy { it.aircraftType.orEmpty().lowercase() }
    SortOption.AIRCRAFT_TYPE_ZA -> sortedByDescending { it.aircraftType.orEmpty().lowercase() }
    SortOption.AIRLINE_AZ -> sortedBy { it.airline.lowercase() }
    SortOption.AIRLINE_ZA -> sortedByDescending { it.airline.lowercase() }
    SortOption.REGISTRATION_AZ -> sortedBy { it.registration.lowercase() }
    SortOption.REGISTRATION_ZA -> sortedByDescending { it.registration.lowercase() }
}
