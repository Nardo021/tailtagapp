package com.josh.tailtag.data

import com.josh.tailtag.model.SpottingEntry
import java.io.IOException
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

sealed class LoadOutcome {
    abstract val version: Long

    data class NoSavedData(override val version: Long) : LoadOutcome()
    data class Loaded(val entries: List<SpottingEntry>, override val version: Long) : LoadOutcome()
    data class Unreadable(
        val reason: UnreadableReason,
        val canRestoreBackup: Boolean,
        override val version: Long,
    ) : LoadOutcome()
}

enum class UnreadableReason {
    Corrupt,
    MissingFields,
    ReadFailed,
}

sealed class SaveResult {
    data class Saved(val entries: List<SpottingEntry>, val version: Long) : SaveResult()
    data class SavedWithCleanupFailure(val entries: List<SpottingEntry>, val version: Long, val message: String) : SaveResult()
    data class Failed(val message: String) : SaveResult()
}

internal fun interface PhotoBytesSource {
    @Throws(IOException::class)
    fun readBytes(): ByteArray
}

/**
 * Serialises spotting mutations against one authoritative snapshot.
 * SharedPreferences is updated with commit(), and photo files are removed only after that commit succeeds.
 */
internal class SpottingPersistence(
    private val store: KeyValueStore,
    private val photos: ManagedPhotoDirectory,
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO,
) {
    private val mutex = Mutex()
    private var snapshot: LoadOutcome? = null
    private var version = 0L

    /** Test hook. Runs inside the mutation lock, after the new state is chosen and before it is committed. */
    internal var beforePersist: (suspend () -> Unit)? = null

    suspend fun load(): LoadOutcome = withContext(dispatcher) {
        mutex.withLock { readLocked() }
    }

    suspend fun add(
        registration: String,
        airline: String,
        location: String,
        aircraftType: String?,
        notes: String?,
        timestamp: Long,
        photoSources: List<PhotoBytesSource>,
        id: String = UUID.randomUUID().toString(),
    ): SaveResult = withContext(dispatcher) {
        mutex.withLock {
            val loaded = usableSnapshot() ?: return@withLock blockedResult()
            if (photoSources.isEmpty()) {
                return@withLock SaveResult.Failed("Add a photo before saving this spotting.")
            }
            val created = ArrayList<String>(photoSources.size)
            var committed = false
            try {
                cleanupStagingIfSafe()
                for (source in photoSources) {
                    created.add(photos.importBytes(source.readBytes()).absolutePath)
                }
                val entry = SpottingEntry(
                    id = id,
                    photos = created,
                    registration = registration.trim(),
                    airline = airline.trim(),
                    location = location.trim(),
                    aircraftType = aircraftType?.trim()?.takeUnless { it.isBlank() },
                    notes = notes?.trim()?.takeUnless { it.isBlank() },
                    timestamp = timestamp,
                )
                val updated = listOf(entry) + loaded
                beforePersist?.invoke()
                commit(updated)
                committed = true
                SaveResult.Saved(updated, version)
            } catch (error: CancellationException) {
                if (!committed) withContext(NonCancellable) { deleteCreated(created) }
                throw error
            } catch (error: PersistenceException) {
                deleteCreated(created)
                SaveResult.Failed(error.message ?: "The spotting could not be saved. Nothing was changed.")
            } catch (error: IOException) {
                deleteCreated(created)
                SaveResult.Failed("A photo could not be saved. Nothing was changed.")
            }
        }
    }

    suspend fun update(
        id: String,
        registration: String,
        airline: String,
        location: String,
        aircraftType: String?,
        notes: String?,
        timestamp: Long,
        remainingPhotoPaths: List<String>,
        newPhotoSources: List<PhotoBytesSource>,
    ): SaveResult = withContext(dispatcher) {
        mutex.withLock {
            val loaded = usableSnapshot() ?: return@withLock blockedResult()
            val existing = loaded.firstOrNull { it.id == id }
                ?: return@withLock SaveResult.Failed("That spotting is no longer in the saved log.")
            if (remainingPhotoPaths.isEmpty() && newPhotoSources.isEmpty()) {
                return@withLock SaveResult.Failed("Keep at least one photo before saving.")
            }
            val created = ArrayList<String>()
            var committed = false
            try {
                cleanupStagingIfSafe()
                for (path in remainingPhotoPaths) {
                    val fileExists = java.io.File(path).isFile
                    if (!fileExists || !photos.isManagedFile(path)) {
                        throw IOException("existing photo missing")
                    }
                }
                for (source in newPhotoSources) {
                    created.add(photos.importBytes(source.readBytes()).absolutePath)
                }
                val finalPaths = remainingPhotoPaths + created
                val updatedEntry = existing.copy(
                    photos = finalPaths,
                    registration = registration.trim(),
                    airline = airline.trim(),
                    location = location.trim(),
                    aircraftType = aircraftType?.trim()?.takeUnless { it.isBlank() },
                    notes = notes?.trim()?.takeUnless { it.isBlank() },
                    timestamp = timestamp,
                )
                val updated = loaded.map { if (it.id == id) updatedEntry else it }
                beforePersist?.invoke()
                commit(updated)
                committed = true
                val cleanupFailed = removeUnreferenced(existing.photos, updated)
                if (cleanupFailed) {
                    SaveResult.SavedWithCleanupFailure(
                        entries = updated,
                        version = version,
                        message = "The spotting was saved, but an old photo could not be removed.",
                    )
                } else {
                    SaveResult.Saved(updated, version)
                }
            } catch (error: CancellationException) {
                if (!committed) withContext(NonCancellable) { deleteCreated(created) }
                throw error
            } catch (error: PersistenceException) {
                deleteCreated(created)
                SaveResult.Failed(error.message ?: "The spotting could not be saved. Nothing was changed.")
            } catch (error: IOException) {
                deleteCreated(created)
                SaveResult.Failed("The spotting could not be saved. Existing photos were kept.")
            }
        }
    }

    suspend fun delete(id: String): SaveResult = withContext(dispatcher) {
        mutex.withLock {
            val loaded = usableSnapshot() ?: return@withLock blockedResult()
            val existing = loaded.firstOrNull { it.id == id }
                ?: return@withLock SaveResult.Failed("That spotting is no longer in the saved log.")
            val updated = loaded.filterNot { it.id == id }
            try {
                beforePersist?.invoke()
                commit(updated)
                val cleanupFailed = removeUnreferenced(existing.photos, updated)
                if (cleanupFailed) {
                    SaveResult.SavedWithCleanupFailure(
                        entries = updated,
                        version = version,
                        message = "The spotting was removed, but a photo file could not be deleted.",
                    )
                } else {
                    SaveResult.Saved(updated, version)
                }
            } catch (error: PersistenceException) {
                SaveResult.Failed(error.message ?: "The spotting could not be saved. Nothing was changed.")
            }
        }
    }

    suspend fun reset(): SaveResult = withContext(dispatcher) {
        mutex.withLock {
            val loaded = usableSnapshot() ?: return@withLock blockedResult()
            try {
                beforePersist?.invoke()
                commit(emptyList())
                val cleanupFailed = removeUnreferenced(loaded.flatMap { it.photos }, emptyList())
                if (cleanupFailed) {
                    SaveResult.SavedWithCleanupFailure(
                        entries = emptyList(),
                        version = version,
                        message = "Aircraft records were cleared, but some photo files could not be deleted.",
                    )
                } else {
                    SaveResult.Saved(emptyList(), version)
                }
            } catch (error: PersistenceException) {
                SaveResult.Failed(error.message ?: "The spotting could not be saved. Nothing was changed.")
            }
        }
    }

    suspend fun restoreBackup(): LoadOutcome = withContext(dispatcher) {
        mutex.withLock {
            val primary = try {
                store.getString(ENTRIES_KEY)
            } catch (error: IOException) {
                return@withLock unreadable(UnreadableReason.ReadFailed, canRestore = false)
            }
            when (decodePrimary(primary)) {
                is Parsed.Ready -> return@withLock readLocked()
                is Parsed.Unreadable -> Unit
            }
            val backup = try {
                store.getString(BACKUP_KEY)
            } catch (error: IOException) {
                return@withLock unreadable(UnreadableReason.ReadFailed, canRestore = false)
            }
            when (decodePrimary(backup)) {
                is Parsed.Unreadable -> return@withLock unreadable(currentReason(primary), canRestore = false)
                is Parsed.Ready -> Unit
            }
            if (primary != null) {
                val archived = try {
                    store.getString(CORRUPT_KEY)
                } catch (error: IOException) {
                    return@withLock unreadable(UnreadableReason.ReadFailed, canRestore = true)
                }
                if (archived == null) {
                    if (!store.commit(mapOf(CORRUPT_KEY to primary))) {
                        return@withLock unreadable(UnreadableReason.ReadFailed, canRestore = true)
                    }
                } else if (archived != primary) {
                    return@withLock unreadable(UnreadableReason.Corrupt, canRestore = false)
                }
            }
            val restored = backup ?: return@withLock unreadable(UnreadableReason.Corrupt, canRestore = false)
            if (!store.commit(mapOf(ENTRIES_KEY to restored))) {
                return@withLock unreadable(UnreadableReason.ReadFailed, canRestore = true)
            }
            snapshot = null
            readLocked()
        }
    }

    private fun usableSnapshot(): List<SpottingEntry>? {
        return when (val outcome = snapshot ?: readLocked()) {
            is LoadOutcome.Loaded -> outcome.entries
            is LoadOutcome.NoSavedData -> emptyList()
            is LoadOutcome.Unreadable -> null
        }
    }

    private fun blockedResult(): SaveResult {
        return SaveResult.Failed("Saved aircraft records could not be read, so they were not replaced.")
    }

    private fun readLocked(): LoadOutcome {
        val raw = try {
            store.getString(ENTRIES_KEY)
        } catch (error: IOException) {
            return unreadable(UnreadableReason.ReadFailed, canRestore = backupLooksRestorable())
        }
        val outcome = when (val parsed = decodePrimary(raw)) {
            is Parsed.Ready -> {
                if (raw == null) LoadOutcome.NoSavedData(nextVersion()) else LoadOutcome.Loaded(parsed.entries, nextVersion())
            }
            is Parsed.Unreadable -> unreadable(parsed.reason, canRestore = backupLooksRestorable())
        }
        snapshot = outcome
        return outcome
    }

    private fun commit(entries: List<SpottingEntry>) {
        val raw = try {
            store.getString(ENTRIES_KEY)
        } catch (error: IOException) {
            throw PersistenceException("Saved aircraft records could not be read, so they were not replaced.")
        }
        when (decodePrimary(raw)) {
            is Parsed.Unreadable -> throw PersistenceException("Saved aircraft records could not be read, so they were not replaced.")
            is Parsed.Ready -> Unit
        }
        if (raw != null && !store.commit(mapOf(BACKUP_KEY to raw))) {
            throw PersistenceException("The spotting could not be saved. Nothing was changed.")
        }
        val encoded = EntryJson.encode(entries.map { entry ->
            StoredEntry(
                id = entry.id,
                photos = entry.photos.map(photos::persistableReference),
                registration = entry.registration,
                airline = entry.airline,
                location = entry.location,
                aircraftType = entry.aircraftType,
                notes = entry.notes,
                timestamp = entry.timestamp,
            )
        })
        if (!store.commit(mapOf(ENTRIES_KEY to encoded))) {
            throw PersistenceException("The spotting could not be saved. Nothing was changed.")
        }
        snapshot = LoadOutcome.Loaded(entries, nextVersion())
    }

    private fun removeUnreferenced(previousPaths: List<String>, updated: List<SpottingEntry>): Boolean {
        val referenced = updated.flatMap { it.photos }.map { canonicalOrOriginal(it) }.toSet()
        var failed = false
        for (path in previousPaths) {
            if (canonicalOrOriginal(path) in referenced) continue
            when (photos.deleteManaged(path)) {
                PhotoDeleteResult.Failed -> failed = true
                PhotoDeleteResult.Deleted, PhotoDeleteResult.Missing, PhotoDeleteResult.Rejected -> Unit
            }
        }
        return failed
    }

    private fun deleteCreated(paths: List<String>) {
        for (path in paths) photos.deleteManaged(path)
    }

    private fun cleanupStagingIfSafe() {
        photos.cleanupExpiredStaging(System.currentTimeMillis(), ManagedPhotoDirectory.STAGING_MAX_AGE_MILLIS)
    }

    private fun backupLooksRestorable(): Boolean {
        val backup = try {
            store.getString(BACKUP_KEY)
        } catch (error: IOException) {
            return false
        }
        return decodePrimary(backup) is Parsed.Ready && backup != null
    }

    private fun currentReason(raw: String?): UnreadableReason {
        return when (val parsed = decodePrimary(raw)) {
            is Parsed.Unreadable -> parsed.reason
            is Parsed.Ready -> UnreadableReason.Corrupt
        }
    }

    private fun unreadable(reason: UnreadableReason, canRestore: Boolean): LoadOutcome.Unreadable {
        val outcome = LoadOutcome.Unreadable(reason, canRestore, nextVersion())
        snapshot = outcome
        return outcome
    }

    private fun nextVersion(): Long {
        version += 1
        return version
    }

    private fun decodePrimary(raw: String?): Parsed {
        if (raw == null) return Parsed.Ready(emptyList(), noData = true)
        return when (val decoded = EntryJson.decode(raw)) {
            is EntryDecodeResult.Entries -> Parsed.Ready(decoded.entries.map { stored ->
                SpottingEntry(
                    id = stored.id,
                    photos = stored.photos.map(photos::resolveStoredReference),
                    registration = stored.registration,
                    airline = stored.airline,
                    location = stored.location,
                    aircraftType = stored.aircraftType,
                    notes = stored.notes,
                    timestamp = stored.timestamp,
                )
            })
            EntryDecodeResult.Corrupt -> Parsed.Unreadable(UnreadableReason.Corrupt)
            EntryDecodeResult.MissingFields -> Parsed.Unreadable(UnreadableReason.MissingFields)
        }
    }

    private fun canonicalOrOriginal(path: String): String {
        return try {
            java.io.File(path).canonicalPath
        } catch (error: IOException) {
            path
        }
    }

    private sealed class Parsed {
        data class Ready(val entries: List<SpottingEntry>, val noData: Boolean = false) : Parsed()
        data class Unreadable(val reason: UnreadableReason) : Parsed()
    }

    private class PersistenceException(message: String) : Exception(message)

    companion object {
        const val PREFERENCES = "tailtag_data"
        const val ENTRIES_KEY = "entries"
        const val BACKUP_KEY = "entries_backup"
        const val CORRUPT_KEY = "entries_corrupt"
    }
}
