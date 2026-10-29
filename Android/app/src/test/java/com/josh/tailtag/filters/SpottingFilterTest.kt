package com.josh.tailtag.filters

import com.josh.tailtag.aviation.entry.AviationSelection
import com.josh.tailtag.aviation.entry.ClassificationChoice
import com.josh.tailtag.aviation.entry.SpottingReferenceState
import com.josh.tailtag.model.SpottingEntry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

class SpottingFilterTest {
    private val calendar = utcCalendar()
    private val catalog = sampleCatalog()
    private val stamp = utcMillis(2024, 6, 15, 9)

    @Test fun emptyFiltersReturnEveryEntryInInputOrder() {
        val entries = listOf(qantas(), jetstar(), legacy())
        assertEquals(entries.map { it.id }, run(entries, SpottingFilterState()).map { it.id })
    }

    @Test fun oneOperatorFilterUsesCatalogId() {
        val entries = listOf(qantas(), jetstar(), legacy(airline = "QF"))
        val filters = SpottingFilterState().insert(FilterToken.Reference(ReferenceDimension.OPERATOR, ReferenceFilter.Catalog("wikidata:Q32491", "Qantas Airways")))
        assertEquals(listOf("qantas"), run(entries, filters).map { it.id })
    }

    @Test fun operatorsCombineWithOr() {
        val filters = SpottingFilterState()
            .insert(FilterToken.Reference(ReferenceDimension.OPERATOR, ReferenceFilter.Catalog("wikidata:Q32491", "Qantas Airways")))
            .insert(FilterToken.Reference(ReferenceDimension.OPERATOR, ReferenceFilter.Catalog("wikidata:Q26468", "Jetstar")))
        assertEquals(setOf("qantas", "jetstar"), run(listOf(qantas(), jetstar(), military()), filters).map { it.id }.toSet())
    }

    @Test fun operatorAndRoleCombineWithAnd() {
        val filters = SpottingFilterState()
            .insert(FilterToken.Reference(ReferenceDimension.OPERATOR, ReferenceFilter.Catalog("wikidata:Q32491", "Qantas Airways")))
            .insert(FilterToken.Reference(ReferenceDimension.OPERATOR, ReferenceFilter.Catalog("wikidata:Q26468", "Jetstar")))
            .insert(FilterToken.Role(ClassificationFilter.role("civil")))
        assertEquals(listOf("qantas", "jetstar-cargo"), run(listOf(qantas(), jetstarCargo(), military()), filters).map { it.id })
    }

    @Test fun roleAndOperationCombineWithAnd() {
        val filters = SpottingFilterState()
            .insert(FilterToken.Role(ClassificationFilter.role("civil")))
            .insert(FilterToken.Operation(ClassificationFilter.operation("cargo")))
        assertEquals(listOf("jetstar-cargo"), run(listOf(qantas(), jetstarCargo(), military()), filters).map { it.id })
    }

    @Test fun manufacturerAndAircraftCombine() {
        val filters = SpottingFilterState()
            .insert(FilterToken.Reference(ReferenceDimension.MANUFACTURER, ReferenceFilter.Catalog("mfr:boeing", "Boeing")))
            .insert(FilterToken.Aircraft(AircraftFilter.Model("ac:b788", "Boeing 787-8")))
        assertEquals(listOf("b788"), run(listOf(boeing788(), airbus(), cessna()), filters).map { it.id })
    }

    @Test fun exactModelDoesNotIncludeSiblingModels() {
        val filters = SpottingFilterState().insert(FilterToken.Aircraft(AircraftFilter.Model("ac:b789", "Boeing 787-9")))
        assertEquals(listOf("b789"), run(listOf(boeing789(), boeing788(), family787()), filters).map { it.id })
    }

    @Test fun familyMatchesFamilyRecordAndVerifiedChildrenOnly() {
        val filters = SpottingFilterState().insert(FilterToken.Aircraft(AircraftFilter.Family("ac:b787", "Boeing 787")))
        val entries = listOf(boeing789(), boeing788(), family787(), airbus(), c130(), customAircraft(), legacyAircraft())
        assertEquals(setOf("b789", "b788", "family-787"), run(entries, filters).map { it.id }.toSet())
    }

    @Test fun modelWithoutFamilyIsNotAssignedToAnInventedFamily() {
        val entries = listOf(c130(), mystery(), boeing789())
        val boeing = SpottingFilterState().insert(FilterToken.Aircraft(AircraftFilter.Family("ac:b787", "Boeing 787")))
        assertEquals(listOf("b789"), run(entries, boeing).map { it.id })
        val invented = SpottingFilterState().insert(FilterToken.Aircraft(AircraftFilter.Family("ac:c130-family", "C-130")))
        assertTrue(run(entries, invented).isEmpty())
    }

    @Test fun legacyAircraftTextAndCustomTypesStaySearchable() {
        val entries = listOf(legacyAircraft(), customAircraft(), boeing789())
        val custom = SpottingFilterState().insert(FilterToken.Aircraft(AircraftFilter.Custom("Homebuilt")))
        assertEquals(listOf("custom-aircraft"), run(entries, custom).map { it.id })
        val text = SpottingFilterState().insert(FilterToken.Aircraft(AircraftFilter.Custom("boeing 787-9")))
        assertEquals(listOf("legacy-aircraft"), run(entries, text).map { it.id })
    }

    @Test fun missingAircraftCatalogIdDoesNotCrash() {
        val entries = listOf(legacyAircraft(), spotting("blank-aircraft", aircraft = AviationSelection.absent))
        val filters = SpottingFilterState().insert(FilterToken.Aircraft(AircraftFilter.Model("ac:missing", "Missing")))
        assertTrue(run(entries, filters).isEmpty())
        assertEquals(2, run(entries, SpottingFilterState()).size)
    }

    @Test fun filteringDoesNotWriteFamilyOrMutateEntries() {
        val entries = listOf(boeing789(), legacyAircraft(), qantas())
        val before = entries.toList()
        val filters = SpottingFilterState().insert(FilterToken.Aircraft(AircraftFilter.Family("ac:b787", "Boeing 787")))
        run(entries, filters)
        assertEquals(before, entries)
        assertEquals("ac:b789", entries[0].reference.aircraftField.catalogId)
        val stored = SpottingEntry(registration = "VH-KEEP", airline = "Qantas", location = "Sydney", aircraftType = "Boeing 787-9", photos = listOf("photo-a"))
        val filtered = filterSpottingEntries(listOf(stored), "", filters, catalog, SpottingFilterSort.DATE_NEWEST, calendar)
        assertEquals(listOf("photo-a"), stored.photos)
        assertNull(stored.aircraftCatalogId)
        assertTrue(filtered.isEmpty() || filtered[0].photos == stored.photos)
    }

    @Test fun airportDoesNotMatchADifferentCustomLocation() {
        val entries = listOf(sydney(), nearbyPark(), legacy(location = "SYD"))
        val airport = SpottingFilterState().insert(FilterToken.Reference(ReferenceDimension.LOCATION, ReferenceFilter.Catalog("apt:yssy", "Sydney Airport")))
        assertEquals(listOf("sydney"), run(entries, airport).map { it.id })
        val custom = SpottingFilterState().insert(FilterToken.Reference(ReferenceDimension.LOCATION, ReferenceFilter.Custom("Nearby park")))
        assertEquals(listOf("park"), run(entries, custom).map { it.id })
    }

    @Test fun registrationPrefixIsCaseInsensitive() {
        val entries = listOf(
            spotting("vh", registration = "vh-oja"),
            spotting("n", registration = "N12345"),
            spotting("g", registration = "G-EZTH"),
            spotting("other", registration = "NVH-OJA"),
        )
        assertEquals(setOf("vh"), run(entries, SpottingFilterState(registrationQuery = "vh-")).map { it.id }.toSet())
        assertEquals(listOf("n"), run(entries, SpottingFilterState(registrationQuery = "n123")).map { it.id })
        assertEquals(listOf("g"), run(entries, SpottingFilterState(registrationQuery = "g-")).map { it.id })
    }

    @Test fun dateRangeIncludesTheEndCalendarDay() {
        val entries = listOf(
            spotting("before", timestamp = utcMillis(2024, 1, 1, 23, 59, 59)),
            spotting("start", timestamp = utcMillis(2024, 1, 2, 0, 0, 0)),
            spotting("end", timestamp = utcMillis(2024, 1, 3, 23, 59, 59)),
            spotting("after", timestamp = utcMillis(2024, 1, 4, 0, 0, 0)),
        )
        val range = SpottingFilterState(dateRange = FilterDateRange(FilterCalendarDay(2024, 1, 2), FilterCalendarDay(2024, 1, 3)))
        assertEquals(listOf("start", "end"), run(entries, range, sort = SpottingFilterSort.DATE_OLDEST).map { it.id })
        assertEquals(listOf("after"), run(entries, SpottingFilterState(dateRange = FilterDateRange(start = FilterCalendarDay(2024, 1, 4)))).map { it.id })
        assertEquals(listOf("before"), run(entries, SpottingFilterState(dateRange = FilterDateRange(end = FilterCalendarDay(2024, 1, 1)))).map { it.id })
        val invalid = SpottingFilterState(dateRange = FilterDateRange(FilterCalendarDay(2024, 1, 3), FilterCalendarDay(2024, 1, 2)))
        assertFalse(invalid.dateRange.isValid)
        assertTrue(run(entries, invalid).isEmpty())
    }

    @Test fun freeTextAndFiltersCombineWithAnd() {
        val entries = listOf(qantas(), jetstar(), military())
        val civil = SpottingFilterState().insert(FilterToken.Role(ClassificationFilter.role("civil")))
        assertEquals(setOf("jetstar"), run(entries, civil, searchText = "jetstar").map { it.id }.toSet())
        val militaryOnly = SpottingFilterState().insert(FilterToken.Role(ClassificationFilter.role("military")))
        assertTrue(run(entries, militaryOnly, searchText = "jetstar").isEmpty())
    }

    @Test fun sortingHappensAfterFiltering() {
        val entries = listOf(
            spotting("b", registration = "VH-BBB", airline = AviationSelection.catalog("wikidata:Q32491", "Qantas Airways"), role = "civil"),
            spotting("a", registration = "VH-AAA", airline = AviationSelection.catalog("wikidata:Q32491", "Qantas Airways"), role = "civil"),
            spotting("c", registration = "VH-CCC", airline = AviationSelection.catalog("wikidata:Q26468", "Jetstar"), role = "civil"),
        )
        val filters = SpottingFilterState().insert(FilterToken.Reference(ReferenceDimension.OPERATOR, ReferenceFilter.Catalog("wikidata:Q32491", "Qantas Airways")))
        assertEquals(listOf("a", "b"), run(entries, filters, sort = SpottingFilterSort.REGISTRATION_AZ).map { it.id })
    }

    @Test fun resetClearsEveryDimension() {
        var filters = SpottingFilterState(registrationQuery = "VH-", dateRange = FilterDateRange(start = FilterCalendarDay(2024, 1, 1)))
            .insert(FilterToken.Role(ClassificationFilter.role("civil")))
        assertTrue(filters.isActive)
        filters = filters.reset()
        assertFalse(filters.isActive)
        assertEquals(0, filters.activeConditionCount)
        assertEquals(2, run(listOf(qantas(), military()), filters).size)
    }

    @Test fun removingOneChipLeavesTheOtherFilter() {
        var filters = SpottingFilterState()
            .insert(FilterToken.Reference(ReferenceDimension.OPERATOR, ReferenceFilter.Catalog("wikidata:Q32491", "Qantas Airways")))
            .insert(FilterToken.Reference(ReferenceDimension.OPERATOR, ReferenceFilter.Catalog("wikidata:Q26468", "Jetstar")))
        val removed = filters.chips().first { it.label.contains("Jetstar") }
        filters = filters.removeChip(removed.id)
        assertEquals(1, filters.operators.size)
        assertEquals(listOf("qantas"), run(listOf(qantas(), jetstar()), filters).map { it.id })
    }

    @Test fun duplicateSelectionsCountOnceAndMatchOnce() {
        val filters = SpottingFilterState()
            .insert(FilterToken.Reference(ReferenceDimension.OPERATOR, ReferenceFilter.Catalog("wikidata:Q32491", "Qantas Airways")))
            .insert(FilterToken.Reference(ReferenceDimension.OPERATOR, ReferenceFilter.Catalog("wikidata:Q32491", "QANTAS AIRWAYS")))
        assertEquals(1, filters.activeConditionCount)
        assertEquals(listOf("qantas", "qantas-2"), run(listOf(qantas(), qantas("qantas-2")), filters).map { it.id })
    }

    @Test fun noMatchingEntriesAndEmptyCollection() {
        val filters = SpottingFilterState().insert(FilterToken.Role(ClassificationFilter.role("military")))
        assertTrue(run(listOf(qantas()), filters).isEmpty())
        assertTrue(run(emptyList(), filters).isEmpty())
        assertEquals(0, run(emptyList(), SpottingFilterState()).size)
    }

    @Test fun missingCatalogMetadataDoesNotInventAManufacturer() {
        val dreamliner = boeing789()
        val boeing = SpottingFilterState().insert(FilterToken.Reference(ReferenceDimension.MANUFACTURER, ReferenceFilter.Catalog("mfr:boeing", "Boeing")))
        assertTrue(run(listOf(dreamliner), boeing).isEmpty())
        val absent = SpottingFilterState().insert(FilterToken.Reference(ReferenceDimension.MANUFACTURER, ReferenceFilter.Absent))
        assertEquals(listOf("b789"), run(listOf(dreamliner), absent).map { it.id })
    }

    @Test fun verifiedManufacturerLinkIsUsedWhenSavedManufacturerIsAbsent() {
        val linked = boeing788()
        val boeing = SpottingFilterState().insert(FilterToken.Reference(ReferenceDimension.MANUFACTURER, ReferenceFilter.Catalog("mfr:boeing", "Boeing")))
        assertEquals(listOf("b788"), run(listOf(linked), boeing).map { it.id })
        val absent = SpottingFilterState().insert(FilterToken.Reference(ReferenceDimension.MANUFACTURER, ReferenceFilter.Absent))
        assertTrue(run(listOf(linked), absent).isEmpty())
    }

    @Test fun savedManufacturerIdWinsOverAircraftLink() {
        val entry = spotting(
            "override",
            manufacturer = AviationSelection.catalog("mfr:airbus", "Airbus"),
            aircraft = AviationSelection.catalog("ac:b788", "Boeing 787-8", "Model"),
        )
        val airbus = SpottingFilterState().insert(FilterToken.Reference(ReferenceDimension.MANUFACTURER, ReferenceFilter.Catalog("mfr:airbus", "Airbus")))
        assertEquals(listOf("override"), run(listOf(entry), airbus).map { it.id })
        val boeing = SpottingFilterState().insert(FilterToken.Reference(ReferenceDimension.MANUFACTURER, ReferenceFilter.Catalog("mfr:boeing", "Boeing")))
        assertTrue(run(listOf(entry), boeing).isEmpty())
    }

    @Test fun missingCatalogResourcesSkipRelationshipAndNameFallback() {
        val entries = listOf(boeing789(), legacy(airline = "Qantas Airways"))
        val family = SpottingFilterState().insert(FilterToken.Aircraft(AircraftFilter.Family("ac:b787", "Boeing 787")))
        assertTrue(run(entries, family, catalog = PreparedSpottingFilterCatalog.unavailable).isEmpty())
        val qantas = SpottingFilterState().insert(FilterToken.Reference(ReferenceDimension.OPERATOR, ReferenceFilter.Catalog("wikidata:Q32491", "Qantas Airways")))
        assertTrue(run(entries, qantas, catalog = PreparedSpottingFilterCatalog.unavailable).isEmpty())
        val model = SpottingFilterState().insert(FilterToken.Aircraft(AircraftFilter.Model("ac:b789", "Boeing 787-9")))
        assertEquals(listOf("b789"), run(entries, model, catalog = PreparedSpottingFilterCatalog.unavailable).map { it.id })
    }

    @Test fun unknownIsDistinctFromAbsentAndUnset() {
        val entries = listOf(
            spotting("unknown", airline = AviationSelection.unknown(), role = "unknown"),
            spotting("absent", airline = AviationSelection.absent),
            spotting("unset", airline = AviationSelection.catalog("wikidata:Q32491", "Qantas Airways")),
            legacy(),
        )
        assertEquals(listOf("unknown"), run(entries, SpottingFilterState().insert(FilterToken.Reference(ReferenceDimension.OPERATOR, ReferenceFilter.Unknown))).map { it.id })
        assertEquals(listOf("absent"), run(entries, SpottingFilterState().insert(FilterToken.Reference(ReferenceDimension.OPERATOR, ReferenceFilter.Absent))).map { it.id })
        assertEquals(listOf("unknown"), run(entries, SpottingFilterState().insert(FilterToken.Role(ClassificationFilter.role("unknown")))).map { it.id })
        assertTrue(run(entries, SpottingFilterState().insert(FilterToken.Role(ClassificationFilter.role("civil")))).isEmpty())
    }

    @Test fun otherClassificationIsDistinctFromUnknown() {
        val entries = listOf(
            spotting("survey", role = "other", roleNote = "Survey", operation = "other", operationNote = "Banner tow"),
            spotting("unknown-role", role = "unknown", operation = "unknown"),
            spotting("unset"),
        )
        assertEquals(listOf("survey"), run(entries, SpottingFilterState().insert(FilterToken.Role(ClassificationFilter.role("other")))).map { it.id })
        val noted = SpottingFilterState()
            .insert(FilterToken.Role(ClassificationFilter.role("other", "Survey")))
            .insert(FilterToken.Operation(ClassificationFilter.operation("other", "Banner tow")))
        assertEquals(listOf("survey"), run(entries, noted).map { it.id })
        assertTrue(run(entries, SpottingFilterState().insert(FilterToken.Role(ClassificationFilter.role("other", "Fire scan")))).isEmpty())
        assertEquals(listOf("unknown-role"), run(entries, SpottingFilterState().insert(FilterToken.Role(ClassificationFilter.role("unknown")))).map { it.id })
    }

    @Test fun legacyEntriesRemainReachableByTheirOriginalText() {
        val entry = legacy(airline = "Local Charter Service", aircraftType = "Cessna 172", location = "Nearby park", registration = "VH-LEG")
        val filters = SpottingFilterState(registrationQuery = "vh-leg")
            .insert(FilterToken.Reference(ReferenceDimension.OPERATOR, ReferenceFilter.Custom("local charter service")))
            .insert(FilterToken.Reference(ReferenceDimension.LOCATION, ReferenceFilter.Custom("Nearby park")))
        assertEquals(listOf("legacy"), run(listOf(entry, qantas()), filters).map { it.id })
        assertNull(entry.reference.operatorField.catalogId)
        assertNull(entry.reference.classification.roleId)
    }

    @Test fun unambiguousLegacyNameMatchesCatalogFilterButCodeDoesNot() {
        val entries = listOf(legacy("full-name", airline = "Qantas Airways"), legacy("code", airline = "QF"), qantas(), legacy("twin", airline = "Air Twin"))
        val qantasFilter = SpottingFilterState().insert(FilterToken.Reference(ReferenceDimension.OPERATOR, ReferenceFilter.Catalog("wikidata:Q32491", "Qantas Airways")))
        assertEquals(setOf("full-name", "qantas"), run(entries, qantasFilter).map { it.id }.toSet())
        val ambiguous = SpottingFilterState().insert(FilterToken.Reference(ReferenceDimension.OPERATOR, ReferenceFilter.Catalog("op:twin-a", "Air Twin")))
        assertTrue(run(entries, ambiguous).isEmpty())
        val twins = listOf(
            spotting("twin-a", airline = AviationSelection.catalog("op:twin-a", "Air Twin")),
            spotting("twin-b", airline = AviationSelection.catalog("op:twin-b", "Air Twin")),
            legacy("twin", airline = "Air Twin"),
        )
        assertEquals(listOf("twin-a"), run(twins, ambiguous).map { it.id })
    }

    @Test fun catalogIdStillMatchesWhenTheRecordIsGone() {
        val entry = spotting("old", airline = AviationSelection.catalog("op:retired", "Retired Air"))
        val filters = SpottingFilterState().insert(FilterToken.Reference(ReferenceDimension.OPERATOR, ReferenceFilter.Catalog("op:retired", "Retired Air")))
        assertEquals(listOf("old"), run(listOf(entry), filters).map { it.id })
        assertNull(catalog.operatorName("op:retired"))
    }

    @Test fun customFilterDoesNotIncludeCatalogRecordsWithTheSameName() {
        val filters = SpottingFilterState().insert(FilterToken.Reference(ReferenceDimension.OPERATOR, ReferenceFilter.Custom("Qantas Airways")))
        assertEquals(listOf("legacy"), run(listOf(legacy(airline = "Qantas Airways"), qantas()), filters).map { it.id })
    }

    @Test fun clearOneDimensionAndChipLabels() {
        val filters = SpottingFilterState(dateRange = FilterDateRange(FilterCalendarDay(2024, 1, 2), FilterCalendarDay(2024, 1, 3)))
            .insert(FilterToken.Role(ClassificationFilter.role("civil")))
            .insert(FilterToken.Operation(ClassificationFilter.operation("passenger")))
            .clear(FilterDimension.ROLES)
        assertTrue(filters.roles.isEmpty())
        assertEquals(1, filters.operationTypes.size)
        assertEquals("Date: 2 Jan 2024 – 3 Jan 2024", filters.chips().last().label)
    }

    @Test fun filterSessionRetainsStateAcrossANavigationBoundary() {
        val session = SpottingFilterSession(
            filters = SpottingFilterState().insert(FilterToken.Role(ClassificationFilter.role("civil"))),
            sort = SpottingFilterSort.REGISTRATION_AZ,
        )
        val returned = session
        assertEquals(listOf(ClassificationFilter.role("civil")), returned.filters.roles)
        assertEquals(SpottingFilterSort.REGISTRATION_AZ, returned.sort)
        assertEquals(1, returned.filters.activeConditionCount)
    }

    @Test fun a350CessnaAndC130Fixtures() {
        val entries = listOf(airbus(), cessna(), c130(), customAircraft())
        assertEquals(listOf("a350"), run(entries, SpottingFilterState().insert(FilterToken.Aircraft(AircraftFilter.Family("ac:a350", "Airbus A350")))).map { it.id })
        assertEquals(listOf("c172"), run(entries, SpottingFilterState().insert(FilterToken.Aircraft(AircraftFilter.Model("ac:c172", "Cessna 172")))).map { it.id })
        assertEquals(listOf("c130"), run(entries, SpottingFilterState().insert(FilterToken.Aircraft(AircraftFilter.Model("ac:c130", "C-130")))).map { it.id })
        assertEquals(listOf("c172"), run(entries, SpottingFilterState().insert(FilterToken.Reference(ReferenceDimension.MANUFACTURER, ReferenceFilter.Catalog("mfr:cessna", "Cessna")))).map { it.id })
        assertEquals(listOf("c130"), run(entries, SpottingFilterState().insert(FilterToken.Reference(ReferenceDimension.MANUFACTURER, ReferenceFilter.Catalog("mfr:lockheed", "Lockheed Martin")))).map { it.id })
    }

    @Test fun performanceAcrossCollectionSizes() {
        val smallCatalog = performanceCatalog(10)
        val wideCatalog = performanceCatalog(3000)
        var wideMulti = 0.0
        listOf(100, 1_000, 10_000).forEach { size ->
            val entries = performanceEntries(size)
            val single = measure(entries, wideCatalog, Bench.SINGLE)
            val multi = measure(entries, wideCatalog, Bench.MULTI)
            val text = measure(entries, wideCatalog, Bench.TEXT)
            val family = measure(entries, wideCatalog, Bench.FAMILY)
            val reset = measure(entries, wideCatalog, Bench.RESET)
            val sorted = measure(entries, wideCatalog, Bench.SORTED)
            println("FILTER_BENCH size=$size single=${"%.2f".format(single)} multi=${"%.2f".format(multi)} text=${"%.2f".format(text)} family=${"%.2f".format(family)} reset=${"%.2f".format(reset)} sort=${"%.2f".format(sorted)}")
            assertTrue("filtering $size records took $multi ms", multi < 5_000)
            if (size == 10_000) {
                wideMulti = multi
                val narrow = measure(entries, smallCatalog, Bench.MULTI)
                val ratio = multi / maxOf(narrow, 0.01)
                println("FILTER_BENCH size=10000 catalogOperators narrow=10 wide=3000 narrowMs=${"%.2f".format(narrow)} wideMs=${"%.2f".format(multi)} ratio=${"%.2f".format(ratio)}")
                assertTrue("catalog size changed filter time by $ratio", ratio < 8)
            }
        }
        assertTrue(wideMulti > 0)
    }

    private fun run(
        entries: List<FilterableSpotting>,
        filters: SpottingFilterState,
        searchText: String = "",
        catalog: SpottingFilterCatalog = this.catalog,
        sort: SpottingFilterSort = SpottingFilterSort.DATE_NEWEST,
    ) = filteredSpottingResults(entries, searchText, filters, catalog, sort, calendar)

    private fun qantas(id: String = "qantas") = spotting(id, registration = "VH-OJA", airline = AviationSelection.catalog("wikidata:Q32491", "Qantas Airways"), aircraft = AviationSelection.catalog("ac:b789", "Boeing 787-9", "Model"), location = AviationSelection.catalog("apt:yssy", "Sydney Airport"), role = "civil", operation = "passenger")
    private fun jetstar() = spotting("jetstar", registration = "VH-VGR", airline = AviationSelection.catalog("wikidata:Q26468", "Jetstar"), location = AviationSelection.catalog("apt:yssy", "Sydney Airport"), role = "civil", operation = "passenger")
    private fun jetstarCargo() = spotting("jetstar-cargo", registration = "VH-JST", airline = AviationSelection.catalog("wikidata:Q26468", "Jetstar"), role = "civil", operation = "cargo")
    private fun military() = spotting("military", registration = "A97-001", airline = AviationSelection.catalog("op:raaf", "RAAF"), aircraft = AviationSelection.catalog("ac:c130", "C-130", "Model"), location = AviationSelection.custom("Richmond") ?: AviationSelection.absent, role = "military", operation = "cargo")
    private fun boeing789() = spotting("b789", aircraft = AviationSelection.catalog("ac:b789", "Boeing 787-9", "Model"))
    private fun boeing788() = spotting("b788", aircraft = AviationSelection.catalog("ac:b788", "Boeing 787-8", "Model"))
    private fun family787() = spotting("family-787", aircraft = AviationSelection.catalog("ac:b787", "Boeing 787", "Family"))
    private fun airbus() = spotting("a350", aircraft = AviationSelection.catalog("ac:a359", "Airbus A350-900", "Model"))
    private fun cessna() = spotting("c172", aircraft = AviationSelection.catalog("ac:c172", "Cessna 172", "Model"))
    private fun c130() = spotting("c130", aircraft = AviationSelection.catalog("ac:c130", "C-130", "Model"))
    private fun mystery() = spotting("mystery", aircraft = AviationSelection.catalog("ac:mystery", "Mystery Jet", "Model"))
    private fun customAircraft() = spotting("custom-aircraft", aircraft = AviationSelection.custom("Homebuilt") ?: AviationSelection.absent)
    private fun legacyAircraft() = legacy("legacy-aircraft", aircraftType = "Boeing 787-9")
    private fun sydney() = spotting("sydney", location = AviationSelection.catalog("apt:yssy", "Sydney Airport"))
    private fun nearbyPark() = spotting("park", location = AviationSelection.custom("Nearby park") ?: AviationSelection.absent)

    private fun legacy(
        id: String = "legacy",
        airline: String = "Local Charter Service",
        aircraftType: String? = "Light twin",
        location: String = "Nearby park",
        registration: String = "VH-OLD",
    ) = FilterableSpotting(id, registration, stamp, SpottingReferenceState.legacy(airline, location, aircraftType))

    private fun spotting(
        id: String,
        registration: String = "VH-TEST",
        timestamp: Long? = null,
        airline: AviationSelection = AviationSelection.absent,
        manufacturer: AviationSelection = AviationSelection.absent,
        aircraft: AviationSelection = AviationSelection.absent,
        location: AviationSelection = AviationSelection.absent,
        role: String? = null,
        roleNote: String? = null,
        operation: String? = null,
        operationNote: String? = null,
    ) = FilterableSpotting(
        id,
        registration,
        timestamp ?: stamp,
        SpottingReferenceState(
            operatorField = airline,
            manufacturerField = manufacturer,
            aircraftField = aircraft,
            locationField = location,
            classification = ClassificationChoice(role, roleNote, operation, operationNote).normalized(),
        ),
    )
}

private enum class Bench { SINGLE, MULTI, TEXT, FAMILY, RESET, SORTED }

private fun measure(entries: List<FilterableSpotting>, catalog: PreparedSpottingFilterCatalog, kind: Bench): Double {
    val calendar = utcCalendar()
    val filters = benchFilters(kind)
    val search = if (kind == Bench.TEXT) "VH-1" else ""
    val sort = if (kind == Bench.SORTED) SpottingFilterSort.REGISTRATION_AZ else SpottingFilterSort.DATE_NEWEST
    filteredSpottingResults(entries, search, filters, catalog, sort, calendar)
    val started = System.nanoTime()
    filteredSpottingResults(entries, search, filters, catalog, sort, calendar)
    return (System.nanoTime() - started) / 1_000_000.0
}

private fun benchFilters(kind: Bench): SpottingFilterState = when (kind) {
    Bench.SINGLE -> SpottingFilterState().insert(FilterToken.Reference(ReferenceDimension.OPERATOR, ReferenceFilter.Catalog("op:0", "Operator 0")))
    Bench.MULTI, Bench.TEXT, Bench.SORTED -> SpottingFilterState(registrationQuery = "VH-")
        .insert(FilterToken.Reference(ReferenceDimension.OPERATOR, ReferenceFilter.Catalog("op:0", "Operator 0")))
        .insert(FilterToken.Reference(ReferenceDimension.OPERATOR, ReferenceFilter.Catalog("op:1", "Operator 1")))
        .insert(FilterToken.Role(ClassificationFilter.role("civil")))
        .insert(FilterToken.Operation(ClassificationFilter.operation("passenger")))
    Bench.FAMILY -> SpottingFilterState().insert(FilterToken.Aircraft(AircraftFilter.Family("ac:bench-family", "Bench Family")))
    Bench.RESET -> SpottingFilterState()
}

private fun performanceEntries(count: Int): List<FilterableSpotting> {
    val stamp = utcMillis(2020, 1, 1)
    return (0 until count).map { index ->
        FilterableSpotting(
            "perf-$index",
            "VH-$index",
            stamp + index,
            SpottingReferenceState(
                operatorField = AviationSelection.catalog("op:${index % 10}", "Operator ${index % 10}"),
                aircraftField = AviationSelection.catalog(if (index % 3 == 0) "ac:bench-child" else "ac:bench-other", "Bench", "Model"),
                locationField = AviationSelection.custom("Field ${index % 4}") ?: AviationSelection.absent,
                classification = ClassificationChoice(
                    roleId = if (index % 2 == 0) "civil" else "military",
                    operationTypeId = if (index % 2 == 0) "passenger" else "cargo",
                ),
            ),
        )
    }
}

private fun performanceCatalog(operatorCount: Int) = PreparedSpottingFilterCatalog(
    FilterCatalogSnapshot(
        operators = (0 until operatorCount).map { FilterCatalogOperator("op:$it", "Operator $it") },
        manufacturers = listOf(FilterCatalogNamed("mfr:bench", "Bench Works")),
        aircraft = listOf(
            FilterCatalogAircraft("ac:bench-child", "Bench Child", "mfr:bench", "ac:bench-family", "Bench Family", "model"),
            FilterCatalogAircraft("ac:bench-other", "Bench Other", null, null, null, "model"),
            FilterCatalogAircraft("ac:bench-family", "Bench Family", "mfr:bench", null, null, "family"),
        ),
    ),
)

private fun sampleCatalog() = PreparedSpottingFilterCatalog(
    FilterCatalogSnapshot(
        operators = listOf(
            FilterCatalogOperator("wikidata:Q32491", "Qantas Airways"),
            FilterCatalogOperator("wikidata:Q26468", "Jetstar"),
            FilterCatalogOperator("wikidata:QFREIGHT", "Qantas Freight"),
            FilterCatalogOperator("op:raaf", "RAAF"),
            FilterCatalogOperator("op:twin-a", "Air Twin"),
            FilterCatalogOperator("op:twin-b", "Air Twin"),
        ),
        manufacturers = listOf(
            FilterCatalogNamed("mfr:boeing", "Boeing"),
            FilterCatalogNamed("mfr:airbus", "Airbus"),
            FilterCatalogNamed("mfr:cessna", "Cessna"),
            FilterCatalogNamed("mfr:lockheed", "Lockheed Martin"),
        ),
        aircraft = listOf(
            FilterCatalogAircraft("ac:b789", "Boeing 787-9", null, "ac:b787", "Boeing 787", "model"),
            FilterCatalogAircraft("ac:b788", "Boeing 787-8", "mfr:boeing", "ac:b787", "Boeing 787", "model"),
            FilterCatalogAircraft("ac:b787", "Boeing 787", "mfr:boeing", null, null, "family"),
            FilterCatalogAircraft("ac:a359", "Airbus A350-900", "mfr:airbus", "ac:a350", "Airbus A350", "model"),
            FilterCatalogAircraft("ac:a350", "Airbus A350", "mfr:airbus", null, null, "family"),
            FilterCatalogAircraft("ac:c172", "Cessna 172", "mfr:cessna", "ac:c172-family", "Cessna 172", "model"),
            FilterCatalogAircraft("ac:c172-family", "Cessna 172", "mfr:cessna", null, null, "family"),
            FilterCatalogAircraft("ac:c130", "C-130", "mfr:lockheed", null, null, "model"),
            FilterCatalogAircraft("ac:mystery", "Mystery Jet", null, null, null, "model"),
        ),
        airports = listOf(FilterCatalogNamed("apt:yssy", "Sydney Airport"), FilterCatalogNamed("apt:ymml", "Melbourne Airport")),
    ),
)

private fun utcCalendar(): Calendar = Calendar.getInstance(TimeZone.getTimeZone("UTC"), Locale.ROOT)

private fun utcMillis(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0, second: Int = 0): Long {
    val calendar = Calendar.getInstance(TimeZone.getTimeZone("UTC"), Locale.ROOT)
    calendar.clear()
    calendar.set(year, month - 1, day, hour, minute, second)
    return calendar.timeInMillis
}
