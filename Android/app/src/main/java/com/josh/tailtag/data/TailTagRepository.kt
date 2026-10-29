package com.josh.tailtag.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import com.josh.tailtag.model.SpottingEntry
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException

class TailTagRepository(context: Context) {
    private val photoDirectory = ManagedPhotoDirectory(File(context.filesDir, "spotting_photos"))
    private val persistence = SpottingPersistence(
        store = SharedPreferencesKeyValueStore(context.getSharedPreferences(SpottingPersistence.PREFERENCES, Context.MODE_PRIVATE)),
        photos = photoDirectory,
    )
    private val importer = AndroidPhotoImporter(context)

    suspend fun load(): LoadOutcome = persistence.load()

    suspend fun add(entry: SpottingEntry, photoUris: List<Uri>): SaveResult = persistence.add(
        registration = entry.registration,
        airline = entry.airline,
        location = entry.location,
        aircraftType = entry.aircraftType,
        notes = entry.notes,
        timestamp = entry.timestamp,
        photoSources = photoUris.map { uri -> PhotoBytesSource { importer.read(uri) } },
        id = entry.id,
        reference = entry.storedReference(),
    )

    suspend fun update(
        entry: SpottingEntry,
        remainingPhotoPaths: List<String>,
        newPhotoUris: List<Uri>,
    ): SaveResult = persistence.update(
        id = entry.id,
        registration = entry.registration,
        airline = entry.airline,
        location = entry.location,
        aircraftType = entry.aircraftType,
        notes = entry.notes,
        timestamp = entry.timestamp,
        remainingPhotoPaths = remainingPhotoPaths,
        newPhotoSources = newPhotoUris.map { uri -> PhotoBytesSource { importer.read(uri) } },
        reference = entry.storedReference(),
    )

    suspend fun delete(id: String): SaveResult = persistence.delete(id)

    suspend fun reset(): SaveResult = persistence.reset()

    suspend fun restoreBackup(): LoadOutcome = persistence.restoreBackup()
}

private class AndroidPhotoImporter(private val context: Context) {
    @Throws(IOException::class)
    fun read(uri: Uri): ByteArray {
        val bytes = context.contentResolver.openInputStream(uri)?.use { input -> input.readBytes() }
            ?: throw IOException("The photo could not be read.")
        if (bytes.isEmpty()) throw IOException("The photo could not be read.")
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return bytes
        return try {
            val scaled = scale(bitmap, 1800)
            val output = ByteArrayOutputStream()
            val wrote = scaled.compress(Bitmap.CompressFormat.JPEG, 82, output)
            if (scaled !== bitmap) scaled.recycle()
            bitmap.recycle()
            val compressed = output.toByteArray()
            if (!wrote || compressed.isEmpty()) bytes else compressed
        } catch (error: IOException) {
            bytes
        }
    }

    private fun scale(bitmap: Bitmap, maxDimension: Int): Bitmap {
        val largest = maxOf(bitmap.width, bitmap.height)
        if (largest <= maxDimension) return bitmap
        val ratio = maxDimension.toFloat() / largest
        return Bitmap.createScaledBitmap(
            bitmap,
            (bitmap.width * ratio).toInt().coerceAtLeast(1),
            (bitmap.height * ratio).toInt().coerceAtLeast(1),
            true,
        )
    }
}

fun spottingFromJson(item: JSONObject): SpottingEntry {
    val photos = item.getJSONArray("photos")
    return SpottingEntry(
        id = item.getString("id"),
        photos = List(photos.length()) { photos.getString(it) },
        registration = item.getString("registration"),
        airline = item.getString("airline"),
        location = item.getString("location"),
        aircraftType = item.optionalText("aircraftType"),
        notes = item.optionalText("notes"),
        timestamp = item.getLong("timestamp"),
        operatorCatalogId = item.optionalText("operatorCatalogId"),
        operatorSelectionKind = item.optionalText("operatorSelectionKind"),
        manufacturerName = item.optionalText("manufacturerName"),
        manufacturerCatalogId = item.optionalText("manufacturerCatalogId"),
        manufacturerSelectionKind = item.optionalText("manufacturerSelectionKind"),
        aircraftCatalogId = item.optionalText("aircraftCatalogId"),
        aircraftSelectionKind = item.optionalText("aircraftSelectionKind"),
        aircraftEntryKind = item.optionalText("aircraftEntryKind"),
        airportCatalogId = item.optionalText("airportCatalogId"),
        locationSelectionKind = item.optionalText("locationSelectionKind"),
        aircraftRoleId = item.optionalText("aircraftRoleId"),
        aircraftRoleNote = item.optionalText("aircraftRoleNote"),
        operationTypeId = item.optionalText("operationTypeId"),
        operationTypeNote = item.optionalText("operationTypeNote"),
    )
}

fun spottingToJson(entry: SpottingEntry): JSONObject = JSONObject().apply {
    put("id", entry.id)
    put("photos", JSONArray(entry.photos))
    put("registration", entry.registration)
    put("airline", entry.airline)
    put("location", entry.location)
    put("aircraftType", entry.aircraftType.orEmpty())
    put("notes", entry.notes.orEmpty())
    put("timestamp", entry.timestamp)
    putOptional("operatorCatalogId", entry.operatorCatalogId)
    putOptional("operatorSelectionKind", entry.operatorSelectionKind)
    putOptional("manufacturerName", entry.manufacturerName)
    putOptional("manufacturerCatalogId", entry.manufacturerCatalogId)
    putOptional("manufacturerSelectionKind", entry.manufacturerSelectionKind)
    putOptional("aircraftCatalogId", entry.aircraftCatalogId)
    putOptional("aircraftSelectionKind", entry.aircraftSelectionKind)
    putOptional("aircraftEntryKind", entry.aircraftEntryKind)
    putOptional("airportCatalogId", entry.airportCatalogId)
    putOptional("locationSelectionKind", entry.locationSelectionKind)
    putOptional("aircraftRoleId", entry.aircraftRoleId)
    putOptional("aircraftRoleNote", entry.aircraftRoleNote)
    putOptional("operationTypeId", entry.operationTypeId)
    putOptional("operationTypeNote", entry.operationTypeNote)
}

private fun JSONObject.optionalText(key: String): String? {
    if (!has(key) || isNull(key)) return null
    return optString(key).takeIf { it.isNotEmpty() }
}

private fun JSONObject.putOptional(key: String, value: String?) {
    if (!value.isNullOrEmpty()) put(key, value)
}
