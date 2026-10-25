package com.josh.tailtag.aviation.entry

import com.josh.tailtag.aviation.AviationCatalogLoader
import com.josh.tailtag.aviation.AviationQueryResolution
import com.josh.tailtag.data.spottingFromJson
import com.josh.tailtag.data.spottingToJson
import com.josh.tailtag.model.SpottingEntry
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class SmartEntryTest {
    @Test
    fun selectionRoundTripAndLegacyText() {
        val catalog = AviationSelection.catalog("wikidata:Q32491", "Qantas Airways", "AU")
        assertEquals("wikidata:Q32491", PersistedAviationField(catalog).selection().catalogId)
        assertEquals("Some small charter company", AviationSelection.custom("  Some small charter company  ")?.displayText)
        assertNull(AviationSelection.custom("   "))
        val legacy = PersistedAviationField(AviationSelection.legacy("Some small charter company"))
        assertNull(legacy.kind)
        assertNull(legacy.catalogId)
        assertTrue(legacy.selection().isLegacy)
        assertEquals("Some small charter company", legacy.text)

        val missing = AviationSelection.catalog("wikidata:Qmissing", "Old name").reconciled(false)
        assertTrue(missing.unavailableInCatalog)
        assertEquals("Old name", missing.displayText)
        assertFalse(AviationSelection.catalog("id", "Name").reconciled(null).unavailableInCatalog)
    }

    @Test
    fun cancelAndSwitchSelections() {
        val committed = AviationSelection.catalog("wikidata:Q1", "Qantas Airways")
        val session = PickerSession(committed, AviationSelection.unknown())
        assertEquals(committed, session.cancel())
        assertEquals(AviationSelection.unknown(), session.confirm())
        var selection = committed
        selection = AviationSelection.custom("Local club")!!
        assertNull(selection.catalogId)
        selection = AviationSelection.catalog("wikidata:Q2", "Jetstar")
        assertEquals("wikidata:Q2", selection.catalogId)
        assertEquals("", PersistedAviationField(AviationSelection.absent).text)
    }

    @Test
    fun legacySaveDoesNotInventIds() {
        val stored = SpottingReferenceState.legacy("Some small charter company", "Nearby park", "Unknown aircraft").forStorage()
        assertNull(stored.operatorField.kind)
        assertNull(stored.operatorField.catalogId)
        assertEquals("Nearby park", stored.restored().storedLocationText)
        assertEquals("Unknown aircraft", stored.restored().storedAircraftText)
    }

    @Test
    fun classificationsStayIndependent() {
        listOf(
            "civil" to "passenger",
            "civil" to "cargo",
            "civil" to "private",
            "military" to "cargo",
            "military" to "training",
            "unknown" to "unknown",
        ).forEach { (role, operation) ->
            val choice = ClassificationChoice(role, operationTypeId = operation).normalized()
            assertEquals(role, choice.roleId)
            assertEquals(operation, choice.operationTypeId)
        }
        val other = ClassificationChoice("other", "  Survey  ", "cargo", "drop me").normalized()
        assertEquals("Survey", other.roleNote)
        assertNull(other.operationTypeNote)
        assertFalse(ClassificationCopy.roleOrder.contains("passenger"))
        assertFalse(ClassificationCopy.operationOrder.contains("military"))
    }

    @Test
    fun privateAndMilitaryCanOmitAnAirline() {
        var reference = SpottingReferenceState(
            operatorField = AviationSelection.absent,
            aircraftField = AviationSelection.custom("Cessna 172")!!,
            locationField = AviationSelection.custom("Park beside the fence")!!,
            classification = ClassificationChoice("civil", operationTypeId = "private"),
        )
        assertTrue(EntryRules.canSave("VH-TEST", 1, reference))
        reference = reference.copy(
            operatorField = AviationSelection.unknown(),
            classification = ClassificationChoice("military", operationTypeId = "training"),
        )
        assertTrue(EntryRules.canSave("A97-001", 1, reference))
        assertFalse(EntryRules.operatorIsValid(AviationSelection(AviationSelectionKind.CUSTOM, displayText = "   ")))
        assertFalse(EntryRules.locationIsValid(AviationSelection.absent))
        assertTrue(EntryRules.locationIsValid(AviationSelection.unknown()))
    }

    @Test
    fun manufacturerChangeRequiresADecision() {
        val aircraft = AviationSelection.catalog("a-787", "Boeing 787-9", "Model")
        val boeing = AviationSelection.catalog("m-boeing", "Boeing")
        val airbus = AviationSelection.catalog("m-airbus", "Airbus")
        val applied = AircraftRules.applyingAircraft(aircraft, AviationSelection.absent, boeing)
        assertEquals("m-boeing", applied.second.catalogId)
        val change = AircraftRules.proposeManufacturerChange(aircraft, "m-boeing", "Boeing", boeing, airbus)
        assertTrue(change is ManufacturerChange.Confirm)
        val confirm = change as ManufacturerChange.Confirm
        val kept = AircraftRules.resolveConflict(true, confirm.proposed, confirm.restore)
        assertNull(kept.first)
        assertEquals("m-boeing", kept.second.catalogId)
        val cleared = AircraftRules.resolveConflict(false, confirm.proposed, confirm.restore)
        assertEquals(AviationSelection.absent, cleared.first)
        assertEquals("m-airbus", cleared.second.catalogId)
        val unlinked = AircraftRules.proposeManufacturerChange(
            AviationSelection.catalog("a-x", "Homebuilt", "Model"),
            null,
            null,
            AviationSelection.absent,
            airbus,
        )
        assertTrue(unlinked is ManufacturerChange.Apply)
    }

    @Test
    fun photoSuggestionDoesNotSelectOrOverwrite() {
        val suggestion = PhotoTextSuggestion("VH-OQH", "QF", 0.91)
        val filled = PhotoSuggestions.applyOperator(OperatorFieldState(AviationSelection.absent, false), suggestion)
        assertEquals(AviationSelectionKind.CUSTOM, filled.selection.kind)
        assertEquals("QF", filled.selection.displayText)
        assertNull(filled.selection.catalogId)
        assertTrue(filled.selection.suggestedFromPhoto)
        assertNull(AmbiguityPolicy.automaticCatalogId(1, 7))
        val manual = OperatorFieldState(AviationSelection.catalog("wikidata:Q32491", "Qantas Airways"), true)
        assertEquals(manual.selection, PhotoSuggestions.applyOperator(manual, suggestion).selection)
        val custom = OperatorFieldState(AviationSelection.custom("Local club")!!, true)
        assertEquals("Local club", PhotoSuggestions.applyOperator(custom, suggestion).selection.displayText)
        assertEquals("", PhotoSuggestions.applyRegistration("", true, suggestion))
        assertEquals("VH-OLD", PhotoSuggestions.applyRegistration("VH-OLD", false, suggestion))
        assertEquals("VH-OQH", PhotoSuggestions.applyRegistration("", false, suggestion))
        assertEquals(ClassificationChoice("military", operationTypeId = "cargo"), classificationUnchanged(ClassificationChoice("military", operationTypeId = "cargo")))
        assertNull(officialDesignatorText(emptyList()))
        assertEquals("Family", aircraftKindLabel("family"))
        assertNotEquals("Model", aircraftKindLabel("family"))
    }

    @Test
    fun catalogLoadAndStaleSearch() {
        var state = CatalogLoadState()
        assertTrue(state.beginAccepted)
        state = state.begin()
        assertEquals(CatalogLoadPhase.LOADING, state.phase)
        assertFalse(state.beginAccepted)
        state = state.fail()
        state = state.retry()!!
        state = state.succeed()
        assertNull(state.retry())
        assertEquals(CatalogQueryGuidance.TOO_SHORT, catalogQueryGuidance("Q"))
        assertEquals(CatalogQueryGuidance.READY, catalogQueryGuidance("QF"))
        val gate = LatestQueryGate()
        val first = gate.issue()
        val second = gate.issue()
        assertNull(gate.accept(first, listOf("stale")))
        assertEquals(listOf("fresh"), gate.accept(second, listOf("fresh")))
        val session = PickerSession(AviationSelection.legacy("Nearby park"), AviationSelection.catalog("ourairports:1", "Sydney"))
        assertEquals(AviationSelection.legacy("Nearby park"), session.cancel())
    }

    @Test
    fun jsonLegacyAndStructuredRoundTrip() {
        val legacyJson = JSONObject(
            """
            {"id":"legacy","photos":["/tmp/a.jpg"],"registration":"VH-LEG","airline":"Some small charter company","location":"Nearby park","aircraftType":"Unknown aircraft","notes":"Keep me","timestamp":1700000000000}
            """.trimIndent(),
        )
        val legacy = spottingFromJson(legacyJson)
        assertEquals("Some small charter company", legacy.airline)
        assertNull(legacy.operatorCatalogId)
        assertNull(legacy.operatorSelectionKind)
        assertEquals(listOf("/tmp/a.jpg"), legacy.photos)
        assertEquals(1700000000000L, legacy.timestamp)
        val storedAgain = spottingToJson(legacy)
        assertFalse(storedAgain.has("operatorCatalogId"))
        assertEquals("Keep me", spottingFromJson(storedAgain).notes)

        val editor = SpottingEditorState(
            registration = "VH-OQH",
            reference = SpottingReferenceState(
                operatorField = AviationSelection.catalog("wikidata:Q32491", "Qantas Airways"),
                manufacturerField = AviationSelection.catalog("wikidata:Q66", "Boeing"),
                aircraftField = AviationSelection.catalog("wikidata:Q15111575", "Boeing 787-9", "Model"),
                locationField = AviationSelection.catalog("ourairports:1", "Sydney Airport (SYD)"),
                classification = ClassificationChoice("civil", operationTypeId = "passenger"),
            ),
            notes = "Nice light",
        )
        val entry = editor.toEntry("new", 42L, listOf("/tmp/a.jpg"))
        val reloaded = spottingFromJson(spottingToJson(entry)).referenceState()
        assertEquals("wikidata:Q32491", reloaded.operatorField.catalogId)
        assertEquals("Model", reloaded.aircraftField.detail)
        assertEquals("civil", reloaded.classification.roleId)
        assertEquals("passenger", reloaded.classification.operationTypeId)
        assertEquals(listOf("/tmp/a.jpg"), spottingFromJson(spottingToJson(entry)).photos)
        assertEquals(42L, spottingFromJson(spottingToJson(entry)).timestamp)
    }

    @Test
    fun failedCatalogStillAllowsCustomEntry() {
        val reference = SpottingReferenceState(
            operatorField = AviationSelection.custom("Unlisted operator")!!,
            aircraftField = AviationSelection.custom("Unlisted type")!!,
            locationField = AviationSelection.custom("Street outside the airfield")!!,
            classification = ClassificationChoice("civil", operationTypeId = "other", operationTypeNote = "Banner tow"),
        )
        assertTrue(EntryRules.canSave("N123", 2, reference))
        assertEquals("Banner tow", reference.forStorage().classification.operationTypeNote)
    }
}

class CatalogEntryBehaviorTest {
    private val catalog by lazy { loadBundledCatalog() }

    @Test
    fun ambiguousCodesAreNotAutoSelected() {
        listOf("QF", "QFA").forEach { query ->
            val broad = catalog.resolveOperators(query, 20)
            val narrow = catalog.resolveOperators(query, 1)
            assertTrue(broad is AviationQueryResolution.Ambiguous)
            assertTrue("$query limit 1", narrow is AviationQueryResolution.Ambiguous)
            val records = (narrow as AviationQueryResolution.Ambiguous).records
            assertNull(AmbiguityPolicy.automaticCatalogId(records.size, 2))
        }
        val qantas = catalog.searchOperators("Qantas Airways", 20).first { it.name == "Qantas Airways" }
        val selection = AviationSelection.catalog(qantas.id, qantas.name)
        val limited = (catalog.resolveOperators("QF", 1) as AviationQueryResolution.Ambiguous).records
        if (limited.first().id != qantas.id) {
            assertNotEquals(selection.catalogId, limited.first().id)
        }
    }

    @Test
    fun aircraftAliasesAreNotOfficialDesignators() {
        val a359 = catalog.searchAircraft("A359", 5).first()
        assertTrue(a359.displayName.contains("A350") || a359.model.contains("A350"))
        assertNull(officialDesignatorText(a359.icaoTypeDesignators))
        assertFalse(CatalogPresentation.aircraftSubtitle(a359).contains("ICAO"))
        val b789 = catalog.searchAircraft("B789", 5).first()
        assertTrue(b789.displayName.contains("787-9") || b789.model.contains("787-9"))
        assertNull(linkedManufacturerSelection(b789))
        assertNull(officialDesignatorText(b789.icaoTypeDesignators))
        val a350 = catalog.searchAircraft("A359", 5).first()
        assertEquals(a350.manufacturerId, linkedManufacturerSelection(a350)?.catalogId)
        listOf("A321neo", "737-800", "Cessna 172", "C-130").forEach { query ->
            val match = catalog.searchAircraft(query, 5).first()
            if (match.entryKind == "family") {
                assertEquals("Family", aircraftSelection(match).detail)
            }
        }
    }

    @Test
    fun airportsAndCustomLocations() {
        val sydney = catalog.searchAirports("YSSY", 5).first { it.iataCode == "SYD" }
        assertEquals("IATA", CatalogPresentation.primaryAirportCode(sydney)?.title)
        val heathrow = catalog.searchAirports("EGLL", 5).first { it.iataCode == "LHR" }
        assertEquals("LHR", CatalogPresentation.primaryAirportCode(heathrow)?.code)
        val noIata = catalog.airports.first { it.iataCode == null }
        assertNotEquals("IATA", CatalogPresentation.primaryAirportCode(noIata)?.title)
        val closed = catalog.airports.first { it.type == "closed" }
        assertTrue(CatalogPresentation.isClosedAirport(closed))
        val custom = SpottingReferenceState.legacy("Club", "Nearby park", null)
        assertNull(custom.forStorage().locationField.catalogId)
        assertNotEquals(CatalogPresentation.airportSnapshot(sydney), custom.locationField.displayText)
    }

    @Test
    fun searchLatencyOnLoadedCatalog() {
        val loaded = catalog
        val started = System.nanoTime()
        assertTrue(loaded.searchOperators("Qantas", 20).isNotEmpty())
        assertTrue(loaded.searchAircraft("787-9", 20).isNotEmpty())
        assertTrue(loaded.searchAirports("Sydney", 20).isNotEmpty())
        val seconds = (System.nanoTime() - started) / 1_000_000_000.0
        println("SMART_ENTRY_ANDROID_SEARCH_SECONDS $seconds")
        assertTrue(seconds < 2.0)
    }
}

private fun loadBundledCatalog(): com.josh.tailtag.aviation.AviationCatalog {
    val started = System.nanoTime()
    val loaded = loadBundledCatalogFiles()
    println("SMART_ENTRY_ANDROID_COLD_SECONDS ${(System.nanoTime() - started) / 1_000_000_000.0}")
    return loaded
}

private fun loadBundledCatalogFiles(): com.josh.tailtag.aviation.AviationCatalog {
    val candidates = listOf(
        File("src/main/assets/aviation"),
        File("app/src/main/assets/aviation"),
        File("Android/app/src/main/assets/aviation"),
    )
    val root = candidates.firstOrNull { File(it, "catalog-manifest.json").exists() }
        ?: error("Bundled catalog not found from ${File(".").absolutePath}")
    val names = listOf("catalog-manifest.json", "operators.json", "manufacturers.json", "aircraft.json", "airports.json", "classifications.json")
    val files = names.associateWith { File(root, it).readBytes() }
    return AviationCatalogLoader.load(files)
}
