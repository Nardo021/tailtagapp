package com.josh.tailtag.data

import android.content.ContentResolver
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import com.josh.tailtag.model.SpottingEntry
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

class TailTagRepository(private val context: Context) {
    private val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
    private val photoDirectory = File(context.filesDir, "spotting_photos").apply { mkdirs() }

    fun loadEntries(): List<SpottingEntry> = runCatching {
        val raw = preferences.getString(ENTRIES_KEY, null) ?: return emptyList()
        val array = JSONArray(raw)
        buildList {
            for (index in 0 until array.length()) {
                val item = array.getJSONObject(index)
                add(spottingFromJson(item))
            }
        }
    }.getOrDefault(emptyList())

    fun saveEntries(entries: List<SpottingEntry>) {
        val array = JSONArray()
        entries.forEach { entry ->
            array.put(spottingToJson(entry))
        }
        preferences.edit().putString(ENTRIES_KEY, array.toString()).apply()
    }

    fun copyPhoto(uri: Uri): String? = runCatching {
        val resolver = context.contentResolver
        val source = resolver.openInputStream(uri) ?: return null
        source.use { input ->
            val bytes = input.readBytes()
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            val destination = File(photoDirectory, "${UUID.randomUUID()}.jpg")
            if (bitmap == null) {
                destination.writeBytes(bytes)
            } else {
                val scaled = scale(bitmap, 1800)
                FileOutputStream(destination).use { output ->
                    scaled.compress(Bitmap.CompressFormat.JPEG, 82, output)
                }
                if (scaled !== bitmap) scaled.recycle()
                bitmap.recycle()
            }
            destination.absolutePath
        }
    }.getOrNull()

    fun deletePhoto(path: String) {
        if (path.startsWith(photoDirectory.absolutePath)) File(path).delete()
    }

    fun deleteAllPhotos() {
        photoDirectory.listFiles()?.forEach(File::delete)
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

    companion object {
        private const val PREFERENCES = "tailtag_data"
        private const val ENTRIES_KEY = "entries"
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
