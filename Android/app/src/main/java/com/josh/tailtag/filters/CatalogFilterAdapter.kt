package com.josh.tailtag.filters

import com.josh.tailtag.aviation.AircraftModel
import com.josh.tailtag.aviation.AviationAirport
import com.josh.tailtag.aviation.AviationCatalog
import com.josh.tailtag.aviation.AviationManufacturer
import com.josh.tailtag.aviation.AviationOperator

fun AviationCatalog.toFilterSnapshot() = FilterCatalogSnapshot(
    operators = operators.map { FilterCatalogOperator(it.id, it.name) },
    manufacturers = manufacturers.map { FilterCatalogNamed(it.id, it.name) },
    aircraft = aircraft.map { it.toFilterAircraft() },
    airports = airports.map { FilterCatalogNamed(it.id, it.name) },
)

private fun AircraftModel.toFilterAircraft() = FilterCatalogAircraft(
    id = id,
    displayName = displayName,
    manufacturerId = manufacturerId,
    familyId = familyId,
    familyName = family,
    entryKind = entryKind,
)

fun AviationOperator.filterLabel() = name
fun AviationManufacturer.filterLabel() = name
fun AviationAirport.filterLabel() = name
