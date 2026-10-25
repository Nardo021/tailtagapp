package com.josh.tailtag.aviation

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

sealed class AviationReference<out ID> {
    data class Catalog<ID>(val id: ID) : AviationReference<ID>()
    data object Unknown : AviationReference<Nothing>()
    data class Custom(val text: String) : AviationReference<Nothing>()
    data object Absent : AviationReference<Nothing>()
}

class AviationCatalogException(message: String) : Exception(message)

data class AviationOperator(
    val id: String,
    val name: String,
    val aliases: List<String>,
    val iataCodes: List<String>,
    val icaoCodes: List<String>,
    val callsigns: List<String>,
    val countryCode: String?,
    val tags: List<String>,
    val historical: Boolean,
    val dissolvedOn: String?,
    val sourceId: String,
)

data class AircraftModel(
    val id: String,
    val manufacturerId: String?,
    val manufacturer: String?,
    val manufacturerNames: List<String>,
    val familyId: String?,
    val family: String?,
    val model: String,
    val displayName: String,
    val entryKind: String,
    val icaoTypeDesignators: List<String>,
    val iataEquipmentCodes: List<String>,
    val aliases: List<String>,
    val sourceId: String,
)

data class AviationAirport(
    val id: String,
    val ident: String,
    val name: String,
    val iataCode: String?,
    val icaoCode: String?,
    val gpsCode: String?,
    val localCode: String?,
    val countryCode: String?,
    val municipality: String?,
    val type: String,
    val latitude: Double,
    val longitude: Double,
    val scheduledService: Boolean,
    val aliases: List<String>,
    val sourceId: String,
)

data class AviationManufacturer(
    val id: String,
    val name: String,
    val aliases: List<String>,
    val countryCode: String?,
    val sourceId: String,
)

data class AviationClassificationValue(val id: String, val label: String)

data class AviationClassificationDimension(
    val id: String,
    val label: String,
    val values: List<AviationClassificationValue>,
)

class AviationCatalog(
    val schemaVersion: Int,
    val catalogVersion: String,
    val operators: List<AviationOperator>,
    val manufacturers: List<AviationManufacturer>,
    val aircraft: List<AircraftModel>,
    val airports: List<AviationAirport>,
    val classifications: List<AviationClassificationDimension>,
) {
    private val operatorIndex = AviationSearchIndex(
        records = operators,
        id = { it.id },
        codes = { it.iataCodes + it.icaoCodes + it.callsigns + listOf(it.id) },
        names = { listOf(it.name) + it.aliases },
    )
    private val aircraftIndex = AviationSearchIndex(
        records = aircraft,
        id = { it.id },
        codes = { it.icaoTypeDesignators + it.iataEquipmentCodes + listOf(it.id) },
        names = {
            buildList {
                addAll(it.manufacturerNames)
                it.manufacturer?.let(::add)
                it.family?.let(::add)
                add(it.model)
                add(it.displayName)
                addAll(it.aliases)
            }
        },
    )
    private val airportIndex = AviationSearchIndex(
        records = airports,
        id = { it.id },
        codes = { listOfNotNull(it.iataCode, it.icaoCode, it.ident, it.gpsCode, it.localCode, it.id) },
        names = { listOfNotNull(it.name, it.municipality) + it.aliases },
    )
    private val manufacturerIndex = AviationSearchIndex(
        records = manufacturers,
        id = { it.id },
        codes = { listOf(it.id) },
        names = { listOf(it.name) + it.aliases },
    )
    private val operatorsById = operators.associateBy { it.id }
    private val aircraftById = aircraft.associateBy { it.id }
    private val airportsById = airports.associateBy { it.id }
    private val manufacturersById = manufacturers.associateBy { it.id }

    fun searchOperators(query: String, limit: Int = 20) = operatorIndex.search(query, limit)
    /** `manufacturerId` is applied before `limit`, so other manufacturers cannot crowd the match out. */
    fun searchAircraft(query: String, limit: Int = 20, manufacturerId: String? = null) =
        aircraftIndex.search(query, limit) { model ->
            manufacturerId == null || model.manufacturerId == manufacturerId
        }
    fun searchAirports(query: String, limit: Int = 20) = airportIndex.search(query, limit)
    fun searchManufacturers(query: String, limit: Int = 20) = manufacturerIndex.search(query, limit)
    fun operatorById(id: String) = operatorsById[id]
    fun aircraftById(id: String) = aircraftById[id]
    fun airportById(id: String) = airportsById[id]
    fun manufacturerById(id: String) = manufacturersById[id]

    fun resolveOperators(query: String, limit: Int = 20): AviationQueryResolution<AviationOperator> {
        val matches = searchOperators(query, limit)
        return resolveAviationQuery(query, matches, operatorIndex.exactCodeCount(query))
    }

    fun resolveAircraft(query: String, limit: Int = 20): AviationQueryResolution<AircraftModel> {
        val matches = searchAircraft(query, limit)
        return resolveAviationQuery(query, matches, aircraftIndex.exactCodeCount(query))
    }

    fun resolveAirports(query: String, limit: Int = 20): AviationQueryResolution<AviationAirport> {
        val matches = searchAirports(query, limit)
        return resolveAviationQuery(query, matches, airportIndex.exactCodeCount(query))
    }
}

object AviationCatalogLoader {
    const val supportedSchemaVersion = 1
    private val fileNames = listOf(
        "operators.json",
        "manufacturers.json",
        "aircraft.json",
        "airports.json",
        "classifications.json",
    )

    fun load(context: Context): AviationCatalog {
        val files = fileNames.associateWith { name ->
            context.assets.open("aviation/$name").use { it.readBytes() }
        } + ("catalog-manifest.json" to context.assets.open("aviation/catalog-manifest.json").use { it.readBytes() })
        return load(files)
    }

    fun load(files: Map<String, ByteArray>): AviationCatalog {
        val manifestBytes = files["catalog-manifest.json"] ?: throw AviationCatalogException("missing catalog-manifest.json")
        val manifest = JSONObject(String(manifestBytes, Charsets.UTF_8))
        val schemaVersion = manifest.getInt("schemaVersion")
        if (schemaVersion != supportedSchemaVersion) {
            throw AviationCatalogException("unsupported schema $schemaVersion")
        }
        val catalogVersion = manifest.getString("catalogVersion")
        if (catalogVersion.isBlank()) throw AviationCatalogException("missing catalogVersion")
        val listed = manifest.getJSONObject("files")
        val parsed = mutableMapOf<String, JSONObject>()
        for (name in fileNames) {
            val bytes = files[name] ?: throw AviationCatalogException("missing $name")
            val expected = listed.getJSONObject(name).getString("sha256")
            val digest = sha256(bytes)
            if (digest != expected) throw AviationCatalogException("manifest mismatch $name")
            parsed[name] = JSONObject(String(bytes, Charsets.UTF_8))
            val fileSchema = parsed[name]!!.getInt("schemaVersion")
            if (fileSchema != supportedSchemaVersion) throw AviationCatalogException("unsupported schema $fileSchema")
        }
        val operators = records(parsed.getValue("operators.json")).map(::operatorRecord)
        val manufacturers = records(parsed.getValue("manufacturers.json")).map(::manufacturerRecord)
        val aircraft = records(parsed.getValue("aircraft.json")).map(::aircraftRecord)
        val airports = records(parsed.getValue("airports.json")).map(::airportRecord)
        val classifications = classifications(parsed.getValue("classifications.json"))
        if (operators.isEmpty() || manufacturers.isEmpty() || aircraft.isEmpty() || airports.isEmpty() || classifications.isEmpty()) {
            throw AviationCatalogException("empty dataset")
        }
        return AviationCatalog(schemaVersion, catalogVersion, operators, manufacturers, aircraft, airports, classifications)
    }
}

class AviationCatalogRepository(private val load: () -> AviationCatalog) {
    @Volatile private var cached: AviationCatalog? = null

    fun catalog(): AviationCatalog {
        cached?.let { return it }
        synchronized(this) {
            cached?.let { return it }
            val loaded = load()
            cached = loaded
            return loaded
        }
    }
}

private fun records(document: JSONObject): List<JSONObject> {
    val array = document.getJSONArray("records")
    return List(array.length()) { index -> array.getJSONObject(index) }
}

internal fun operatorRecord(json: JSONObject) = AviationOperator(
    id = required(json, "id"),
    name = required(json, "name"),
    aliases = strings(json, "aliases"),
    iataCodes = strings(json, "iataCodes"),
    icaoCodes = strings(json, "icaoCodes"),
    callsigns = strings(json, "callsigns"),
    countryCode = optional(json, "countryCode"),
    tags = strings(json, "tags"),
    historical = if (json.has("historical")) json.getBoolean("historical") else false,
    dissolvedOn = optional(json, "dissolvedOn"),
    sourceId = required(json, "sourceId"),
)

private fun manufacturerRecord(json: JSONObject) = AviationManufacturer(
    id = required(json, "id"),
    name = required(json, "name"),
    aliases = strings(json, "aliases"),
    countryCode = optional(json, "countryCode"),
    sourceId = required(json, "sourceId"),
)

internal fun aircraftRecord(json: JSONObject) = AircraftModel(
    id = required(json, "id"),
    manufacturerId = optional(json, "manufacturerId"),
    manufacturer = optional(json, "manufacturer"),
    manufacturerNames = strings(json, "manufacturerNames"),
    familyId = optional(json, "familyId"),
    family = optional(json, "family"),
    model = required(json, "model"),
    displayName = required(json, "displayName"),
    entryKind = required(json, "entryKind"),
    icaoTypeDesignators = strings(json, "icaoTypeDesignators"),
    iataEquipmentCodes = strings(json, "iataEquipmentCodes"),
    aliases = strings(json, "aliases"),
    sourceId = required(json, "sourceId"),
)

internal fun airportRecord(json: JSONObject) = AviationAirport(
    id = required(json, "id"),
    ident = required(json, "ident"),
    name = required(json, "name"),
    iataCode = optional(json, "iataCode"),
    icaoCode = optional(json, "icaoCode"),
    gpsCode = optional(json, "gpsCode"),
    localCode = optional(json, "localCode"),
    countryCode = optional(json, "countryCode"),
    municipality = optional(json, "municipality"),
    type = required(json, "type"),
    latitude = json.getDouble("latitude"),
    longitude = json.getDouble("longitude"),
    scheduledService = json.getBoolean("scheduledService"),
    aliases = strings(json, "aliases"),
    sourceId = required(json, "sourceId"),
)

private fun classifications(document: JSONObject): List<AviationClassificationDimension> {
    val dimensions = document.getJSONArray("dimensions")
    return List(dimensions.length()) { index ->
        val dimension = dimensions.getJSONObject(index)
        val values = dimension.getJSONArray("values")
        AviationClassificationDimension(
            id = required(dimension, "id"),
            label = required(dimension, "label"),
            values = List(values.length()) { valueIndex ->
                val value = values.getJSONObject(valueIndex)
                AviationClassificationValue(required(value, "id"), required(value, "label"))
            },
        )
    }
}

private fun required(json: JSONObject, key: String): String {
    val value = json.optString(key, "")
    if (value.isBlank()) throw AviationCatalogException("missing $key")
    return value
}

private fun optional(json: JSONObject, key: String): String? {
    if (!json.has(key) || json.isNull(key)) return null
    val value = json.getString(key)
    return value.ifEmpty { null }
}

private fun strings(json: JSONObject, key: String): List<String> {
    if (!json.has(key) || json.isNull(key)) return emptyList()
    val array: JSONArray = json.getJSONArray(key)
    return List(array.length()) { index -> array.getString(index) }
}

private fun sha256(bytes: ByteArray): String {
    val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
    return digest.joinToString("") { byte -> "%02x".format(byte) }
}
