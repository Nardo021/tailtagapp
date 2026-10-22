package com.josh.tailtag.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
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

    suspend fun add(
        registration: String,
        airline: String,
        location: String,
        aircraftType: String?,
        notes: String?,
        timestamp: Long,
        photoUris: List<Uri>,
    ): SaveResult = persistence.add(
        registration = registration,
        airline = airline,
        location = location,
        aircraftType = aircraftType,
        notes = notes,
        timestamp = timestamp,
        photoSources = photoUris.map { uri -> PhotoBytesSource { importer.read(uri) } },
    )

    suspend fun update(
        id: String,
        registration: String,
        airline: String,
        location: String,
        aircraftType: String?,
        notes: String?,
        timestamp: Long,
        remainingPhotoPaths: List<String>,
        newPhotoUris: List<Uri>,
    ): SaveResult = persistence.update(
        id = id,
        registration = registration,
        airline = airline,
        location = location,
        aircraftType = aircraftType,
        notes = notes,
        timestamp = timestamp,
        remainingPhotoPaths = remainingPhotoPaths,
        newPhotoSources = newPhotoUris.map { uri -> PhotoBytesSource { importer.read(uri) } },
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
