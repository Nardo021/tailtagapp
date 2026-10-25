package com.josh.tailtag.aviation

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

class AviationCatalogTest {
    @Test
    fun normalizationMatchesReference() {
        val payload = json("normalization-cases.json")
        val cases = payload.getJSONArray("cases")
        for (index in 0 until cases.length()) {
            val sample = cases.getJSONObject(index)
            val input = sample.getString("input")
            val normalized = AviationText.normalize(input)
            assertEquals(input, sample.getString("normalized"), normalized)
            assertEquals(input, sample.getString("compact"), AviationText.compact(normalized))
        }
    }

    @Test
    fun rankingMatchesReference() {
        val catalog = fixtureCatalog()
        val cases = json("ranking-cases.json").getJSONArray("cases")
        for (index in 0 until cases.length()) {
            val sample = cases.getJSONObject(index)
            val dataset = sample.getString("dataset")
            val query = sample.getString("query")
            val limit = sample.getInt("limit")
            val expected = stringArray(sample, "expectedIds")
            val resolution = when (dataset) {
                "operators" -> catalog.resolveOperators(query, limit)
                "aircraft" -> catalog.resolveAircraft(query, limit)
                "airports" -> catalog.resolveAirports(query, limit)
                else -> error(dataset)
            }
            val records = when (resolution) {
                is AviationQueryResolution.Matches<*> -> resolution.records
                is AviationQueryResolution.Ambiguous<*> -> resolution.records
                else -> emptyList()
            }
            val ids = records.map { record ->
                when (record) {
                    is AviationOperator -> record.id
                    is AircraftModel -> record.id
                    is AviationAirport -> record.id
                    else -> error(record.toString())
                }
            }
            assertEquals("$dataset $query", expected, ids)
            assertEquals(query, sample.getString("resolution"), resolution.kindName)
        }
        assertEquals("fixture:qantas", catalog.searchOperators("QF", 5).first().id)
        assertNotEquals("fixture:prefix-carrier", catalog.searchOperators("QF", 5).first().id)
        assertEquals(listOf("fixture:a320-200", "fixture:a320-family"), catalog.searchAircraft("A320", 5).map { it.id })
        val raaf = catalog.operatorById("fixture:raaf")!!
        assertTrue(raaf.iataCodes.isEmpty())
        assertEquals(listOf("military-operator"), raaf.tags)
        val dragon = catalog.aircraftById("fixture:dragon")!!
        assertTrue(dragon.icaoTypeDesignators.isEmpty())
        val unknown = catalog.resolveAirports("zzzz-not-a-place", 5)
        assertTrue(unknown is AviationQueryResolution.Unmatched)
        assertEquals("zzzz-not-a-place", (unknown as AviationQueryResolution.Unmatched).text)
        try {
            catalog.searchOperators("QF", -1)
            error("negative limit should fail")
        } catch (_: IllegalArgumentException) {
        }
    }

    @Test
    fun unmatchedTextIsNotACatalogRecord() {
        val custom = AviationReference.Custom("Not A Real Airline")
        assertTrue(custom !is AviationReference.Catalog<*>)
        assertTrue(AviationReference.Unknown !is AviationReference.Catalog<*>)
    }

    @Test
    fun bundledCatalogMatchesSearchCasesWhenPresent() {
        val root = listOf(File("../../data/aviation"), File("data/aviation")).firstOrNull { File(it, "catalog-manifest.json").isFile }
        assumeTrue(root != null)
        val directory = root!!
        val names = listOf(
            "catalog-manifest.json",
            "operators.json",
            "manufacturers.json",
            "aircraft.json",
            "airports.json",
            "classifications.json",
        )
        val files = names.associateWith { name -> File(directory, name).readBytes() }
        val started = System.nanoTime()
        val catalog = AviationCatalogLoader.load(files)
        val loadMs = (System.nanoTime() - started) / 1_000_000.0
        println("catalog load ${"%.1f".format(loadMs)} ms")
        println(
            "catalog counts operators=${catalog.operators.size} manufacturers=${catalog.manufacturers.size} " +
                "aircraft=${catalog.aircraft.size} airports=${catalog.airports.size}",
        )
        assertEquals(1, catalog.schemaVersion)
        assertEquals("LHR", catalog.airportById("ourairports:2434")!!.iataCode)
        assertEquals("EGLL", catalog.airportById("ourairports:2434")!!.icaoCode)
        val searchStarted = System.nanoTime()
        assertEquals("ourairports:27145", catalog.searchAirports("YSSY", 3).first().id)
        assertTrue(catalog.searchOperators("Qantas", 5).isNotEmpty())
        assertTrue(catalog.searchAircraft("A350", 5).isNotEmpty())
        assertTrue(catalog.searchAirports("Heathrow", 5).any { it.iataCode == "LHR" })
        assertTrue(catalog.aircraft.all { it.icaoTypeDesignators.isEmpty() && it.iataEquipmentCodes.isEmpty() })
        assertTrue(catalog.resolveAirports("zzzz-not-a-place", 5) is AviationQueryResolution.Unmatched)
        println("catalog search sample ${(System.nanoTime() - searchStarted) / 1_000_000.0} ms")
        val cases = JSONObject(File(directory, "fixtures/search-cases.json").readText()).getJSONArray("cases")
        for (index in 0 until cases.length()) {
            val sample = cases.getJSONObject(index)
            val dataset = sample.getString("dataset")
            val query = sample.getString("query")
            val limit = sample.getInt("limit")
            val expected = stringArray(sample, "expectedIds")
            val ids = when (dataset) {
                "operators" -> catalog.searchOperators(query, limit).map { it.id }
                "aircraft" -> catalog.searchAircraft(query, limit).map { it.id }
                "airports" -> catalog.searchAirports(query, limit).map { it.id }
                else -> error(dataset)
            }
            assertEquals("$dataset $query", expected, ids)
        }
    }

    @Test
    fun failedLoadIsNotCached() {
        val repository = AviationCatalogRepository { throw AviationCatalogException("missing operators.json") }
        try {
            repository.catalog()
            error("expected failure")
        } catch (_: AviationCatalogException) {
        }
        try {
            repository.catalog()
            error("failure was cached")
        } catch (error: AviationCatalogException) {
            assertEquals("missing operators.json", error.message)
        }
    }

    @Test
    fun manufacturerFilterKeepsMatchesOutsideTheGlobalWindow() {
        val common = "maker:common"
        val rare = "maker:rare"
        val aircraft = (0 until 201).map { index ->
            syntheticAircraft("zz-common-%03d".format(index), common, "Alpha $index")
        } + listOf(
            syntheticAircraft("zz-rare-early", rare, "Alpha Early"),
            syntheticAircraft("zz-rare-later", rare, "Alpha Later"),
        )
        val catalog = AviationCatalog(1, "manufacturer-window", emptyList(), emptyList(), aircraft, emptyList(), emptyList())
        val truncated = catalog.searchAircraft("alpha", 200)
        assertEquals(200, truncated.size)
        assertTrue(truncated.none { it.manufacturerId == rare })
        assertEquals(listOf("zz-rare-early", "zz-rare-later"), catalog.searchAircraft("alpha", 20, rare).map { it.id })
        assertEquals(listOf("zz-rare-early"), catalog.searchAircraft("alpha", 1, rare).map { it.id })
        assertTrue(catalog.searchAircraft("alpha", 20, "maker:missing").isEmpty())
    }

    private fun fixtureCatalog(): AviationCatalog {
        val payload = json("ranking-catalog.json")
        return AviationCatalog(
            schemaVersion = 1,
            catalogVersion = "fixture",
            operators = payload.getJSONArray("operators").objects().map(::operatorRecord),
            manufacturers = emptyList(),
            aircraft = payload.getJSONArray("aircraft").objects().map(::aircraftRecord),
            airports = payload.getJSONArray("airports").objects().map(::airportRecord),
            classifications = emptyList(),
        )
    }

    private fun json(name: String): JSONObject {
        val file = resource(name)
        return JSONObject(file.readText())
    }

    private fun resource(name: String): File {
        val candidates = listOf(
            File("src/test/resources/aviation/$name"),
            File("app/src/test/resources/aviation/$name"),
        )
        return candidates.firstOrNull { it.isFile } ?: error("missing fixture $name")
    }

    private fun stringArray(json: JSONObject, key: String): List<String> {
        val array = json.getJSONArray(key)
        return List(array.length()) { array.getString(it) }
    }
}

private fun org.json.JSONArray.objects(): List<JSONObject> = List(length()) { getJSONObject(it) }

private fun syntheticAircraft(id: String, manufacturerId: String, name: String) = AircraftModel(
    id = id,
    manufacturerId = manufacturerId,
    manufacturer = null,
    manufacturerNames = emptyList(),
    familyId = null,
    family = null,
    model = name,
    displayName = name,
    entryKind = "model",
    icaoTypeDesignators = emptyList(),
    iataEquipmentCodes = emptyList(),
    aliases = emptyList(),
    sourceId = id,
)
