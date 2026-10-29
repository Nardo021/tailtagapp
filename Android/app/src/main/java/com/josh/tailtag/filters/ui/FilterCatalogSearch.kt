package com.josh.tailtag.filters.ui

import com.josh.tailtag.TailTagViewModel
import com.josh.tailtag.aviation.entry.CatalogPresentation
import com.josh.tailtag.aviation.entry.aircraftKindLabel
import com.josh.tailtag.filters.AircraftFilter
import com.josh.tailtag.filters.FilterToken
import com.josh.tailtag.filters.ReferenceDimension
import com.josh.tailtag.filters.ReferenceFilter

enum class FilterCatalogBrowse {
    OPERATORS,
    MANUFACTURERS,
    AIRCRAFT,
    LOCATIONS,
}

data class FilterCatalogHit(
    val id: String,
    val title: String,
    val subtitle: String,
    val token: FilterToken,
)

data class FilterCatalogSearchResult(
    val hits: List<FilterCatalogHit> = emptyList(),
    val ambiguous: Boolean = false,
    val unmatched: Boolean = false,
)

suspend fun TailTagViewModel.searchFilterCatalog(browse: FilterCatalogBrowse, query: String): FilterCatalogSearchResult {
    return when (browse) {
        FilterCatalogBrowse.OPERATORS -> {
            val page = searchOperators(query, 20) ?: return FilterCatalogSearchResult()
            FilterCatalogSearchResult(
                hits = page.records.map { record ->
                    FilterCatalogHit(
                        id = record.id,
                        title = record.name,
                        subtitle = CatalogPresentation.operatorCodeSummary(record),
                        token = FilterToken.Reference(ReferenceDimension.OPERATOR, ReferenceFilter.Catalog(record.id, record.name)),
                    )
                },
                ambiguous = page.ambiguous,
                unmatched = page.unmatched,
            )
        }
        FilterCatalogBrowse.MANUFACTURERS -> {
            val page = searchManufacturers(query, 20) ?: return FilterCatalogSearchResult()
            FilterCatalogSearchResult(
                hits = page.records.map { record ->
                    FilterCatalogHit(
                        id = record.id,
                        title = record.name,
                        subtitle = CatalogPresentation.manufacturerSubtitle(record),
                        token = FilterToken.Reference(ReferenceDimension.MANUFACTURER, ReferenceFilter.Catalog(record.id, record.name)),
                    )
                },
                ambiguous = page.ambiguous,
                unmatched = page.unmatched,
            )
        }
        FilterCatalogBrowse.AIRCRAFT -> {
            val page = searchAircraft(query, 20, null) ?: return FilterCatalogSearchResult()
            FilterCatalogSearchResult(
                hits = page.records.map { record ->
                    val filter = if (record.entryKind == "family") {
                        AircraftFilter.Family(record.id, record.displayName)
                    } else {
                        AircraftFilter.Model(record.id, record.displayName)
                    }
                    FilterCatalogHit(
                        id = "${record.entryKind}-${record.id}",
                        title = record.displayName,
                        subtitle = aircraftKindLabel(record.entryKind),
                        token = FilterToken.Aircraft(filter),
                    )
                },
                ambiguous = page.ambiguous,
                unmatched = page.unmatched,
            )
        }
        FilterCatalogBrowse.LOCATIONS -> {
            val page = searchAirports(query, 20) ?: return FilterCatalogSearchResult()
            FilterCatalogSearchResult(
                hits = page.records.map { record ->
                    FilterCatalogHit(
                        id = record.id,
                        title = record.name,
                        subtitle = CatalogPresentation.airportSnapshot(record),
                        token = FilterToken.Reference(ReferenceDimension.LOCATION, ReferenceFilter.Catalog(record.id, record.name)),
                    )
                },
                ambiguous = page.ambiguous,
                unmatched = page.unmatched,
            )
        }
    }
}
