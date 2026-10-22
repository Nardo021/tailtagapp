package com.josh.tailtag.data

import com.josh.tailtag.model.SpottingEntry
import java.io.File
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SpottingPersistenceTest {
    @Test
    fun loadDistinguishesMissingEmptyAndValidData() = runBlocking {
        val harness = Harness()
        assertTrue(harness.persistence.load() is LoadOutcome.NoSavedData)

        harness.store.values[SpottingPersistence.ENTRIES_KEY] = "[]"
        harness.persistence = harness.rebuild()
        val empty = harness.persistence.load()
        assertTrue(empty is LoadOutcome.Loaded)
        assertTrue((empty as LoadOutcome.Loaded).entries.isEmpty())

        harness.store.values[SpottingPersistence.ENTRIES_KEY] = entryJson(id = "a", photos = listOf("plane.jpg"))
        harness.persistence = harness.rebuild()
        val loaded = harness.persistence.load() as LoadOutcome.Loaded
        assertEquals(listOf("a"), loaded.entries.map { it.id })
        assertEquals("VH-A", loaded.entries.first().registration)
        assertTrue(loaded.entries.first().photos.first().endsWith("plane.jpg"))
    }

    @Test
    fun optionalFieldsMayBeMissing() = runBlocking {
        val harness = Harness()
        harness.store.values[SpottingPersistence.ENTRIES_KEY] =
            """[{"id":"a","photos":[],"registration":"VH-ABC","airline":"Qantas","location":"YMML","timestamp":10}]"""
        val loaded = harness.persistence.load() as LoadOutcome.Loaded
        assertEquals(null, loaded.entries.first().aircraftType)
        assertEquals(null, loaded.entries.first().notes)
    }

    @Test
    fun corruptedJsonIsNotReplacedByAnEmptyDataset() = runBlocking {
        val harness = Harness()
        harness.store.values[SpottingPersistence.ENTRIES_KEY] = "{not json"
        val loaded = harness.persistence.load()
        assertTrue(loaded is LoadOutcome.Unreadable)
        val result = harness.persistence.add(
            registration = "VH-NEW",
            airline = "New",
            location = "YSSY",
            aircraftType = null,
            notes = null,
            timestamp = 20,
            photoSources = listOf(PhotoBytesSource { byteArrayOf(1, 2, 3) }),
            id = "new",
        )
        assertTrue(result is SaveResult.Failed)
        assertEquals("{not json", harness.store.values[SpottingPersistence.ENTRIES_KEY])
        assertTrue(harness.photoFiles().isEmpty())
    }

    @Test
    fun missingRequiredFieldsAreUnreadableAndAreNotOverwritten() = runBlocking {
        val harness = Harness()
        val raw = """[{"id":"a","photos":["a.jpg"],"airline":"Qantas","location":"YMML","timestamp":10}]"""
        harness.store.values[SpottingPersistence.ENTRIES_KEY] = raw
        val loaded = harness.persistence.load() as LoadOutcome.Unreadable
        assertEquals(UnreadableReason.MissingFields, loaded.reason)
        val result = harness.persistence.delete("a")
        assertTrue(result is SaveResult.Failed)
        assertEquals(raw, harness.store.values[SpottingPersistence.ENTRIES_KEY])
    }

    @Test
    fun readFailureIsReportedAndDoesNotClearStorage() = runBlocking {
        val harness = Harness()
        harness.store.values[SpottingPersistence.ENTRIES_KEY] = entryJson(id = "a", photos = listOf("a.jpg"))
        harness.store.throwOnRead = true
        val loaded = harness.persistence.load() as LoadOutcome.Unreadable
        assertEquals(UnreadableReason.ReadFailed, loaded.reason)
        assertEquals(entryJson(id = "a", photos = listOf("a.jpg")), harness.store.values[SpottingPersistence.ENTRIES_KEY])
    }

    @Test
    fun restoreUsesBackupAndKeepsTheCorruptCopy() = runBlocking {
        val harness = Harness()
        val backup = entryJson(id = "good", photos = listOf("good.jpg"))
        harness.store.values[SpottingPersistence.ENTRIES_KEY] = "not-json"
        harness.store.values[SpottingPersistence.BACKUP_KEY] = backup
        val restored = harness.persistence.restoreBackup() as LoadOutcome.Loaded
        assertEquals(listOf("good"), restored.entries.map { it.id })
        assertEquals(backup, harness.store.values[SpottingPersistence.ENTRIES_KEY])
        assertEquals("not-json", harness.store.values[SpottingPersistence.CORRUPT_KEY])
    }

    @Test
    fun bothCopiesCorruptStayUntouched() = runBlocking {
        val harness = Harness()
        harness.store.values[SpottingPersistence.ENTRIES_KEY] = "primary-bad"
        harness.store.values[SpottingPersistence.BACKUP_KEY] = "backup-bad"
        val restored = harness.persistence.restoreBackup() as LoadOutcome.Unreadable
        assertFalse(restored.canRestoreBackup)
        assertEquals("primary-bad", harness.store.values[SpottingPersistence.ENTRIES_KEY])
        assertEquals("backup-bad", harness.store.values[SpottingPersistence.BACKUP_KEY])
        assertFalse(harness.store.values.containsKey(SpottingPersistence.CORRUPT_KEY))
    }

    @Test
    fun occupiedCorruptArchiveIsNotOverwritten() = runBlocking {
        val harness = Harness()
        harness.store.values[SpottingPersistence.ENTRIES_KEY] = "new-bad"
        harness.store.values[SpottingPersistence.BACKUP_KEY] = entryJson(id = "good", photos = emptyList())
        harness.store.values[SpottingPersistence.CORRUPT_KEY] = "old-bad"
        val restored = harness.persistence.restoreBackup()
        assertTrue(restored is LoadOutcome.Unreadable)
        assertEquals("new-bad", harness.store.values[SpottingPersistence.ENTRIES_KEY])
        assertEquals("old-bad", harness.store.values[SpottingPersistence.CORRUPT_KEY])
    }

    @Test
    fun failedWriteLeavesThePreviousRecordAndCanBeRetried() = runBlocking {
        val harness = Harness()
        val first = harness.add("a")
        assertTrue(first is SaveResult.Saved)
        harness.store.failCommitsRemaining = 1
        val failed = harness.add("b")
        assertTrue(failed is SaveResult.Failed)
        val persisted = harness.rebuild().load() as LoadOutcome.Loaded
        assertEquals(listOf("a"), persisted.entries.map { it.id })
        val retried = harness.persistence.add(
            registration = "VH-B",
            airline = "Bee",
            location = "YMML",
            aircraftType = null,
            notes = null,
            timestamp = 2,
            photoSources = listOf(PhotoBytesSource { byteArrayOf(9) }),
            id = "b",
        )
        assertTrue(retried is SaveResult.Saved)
        val after = harness.rebuild().load() as LoadOutcome.Loaded
        assertEquals(setOf("a", "b"), after.entries.map { it.id }.toSet())
    }

    @Test
    fun photoCopyFailureDoesNotSaveOrLeaveNewFiles() = runBlocking {
        val harness = Harness()
        val saved = harness.add("a") as SaveResult.Saved
        val original = harness.store.values.getValue(SpottingPersistence.ENTRIES_KEY)
        val originalFiles = harness.photoFiles().toSet()
        val result = harness.persistence.update(
            id = "a",
            registration = "VH-A",
            airline = "Air",
            location = "YMML",
            aircraftType = null,
            notes = null,
            timestamp = 1,
            remainingPhotoPaths = saved.entries.first().photos,
            newPhotoSources = listOf(
                PhotoBytesSource { byteArrayOf(4) },
                PhotoBytesSource { throw IOException("copy failed") },
            ),
        )
        assertTrue(result is SaveResult.Failed)
        assertEquals(original, harness.store.values[SpottingPersistence.ENTRIES_KEY])
        assertEquals(originalFiles, harness.photoFiles().toSet())
    }

    @Test
    fun failureAfterPhotoPreparationKeepsExistingFiles() = runBlocking {
        val harness = Harness()
        val saved = harness.add("a") as SaveResult.Saved
        val originalPhoto = saved.entries.first().photos.first()
        harness.store.failCommitsRemaining = 1
        val result = harness.persistence.update(
            id = "a",
            registration = "CHANGED",
            airline = "Air",
            location = "YMML",
            aircraftType = null,
            notes = null,
            timestamp = 1,
            remainingPhotoPaths = listOf(originalPhoto),
            newPhotoSources = listOf(PhotoBytesSource { byteArrayOf(7, 7) }),
        )
        assertTrue(result is SaveResult.Failed)
        assertTrue(File(originalPhoto).isFile)
        assertEquals(listOf(File(originalPhoto).name), harness.photoFiles().map { it.name })
        val reloaded = harness.rebuild().load() as LoadOutcome.Loaded
        assertEquals("VH-A", reloaded.entries.first().registration)
    }

    @Test
    fun obsoletePhotoRemovalFailureKeepsTheSavedMetadata() = runBlocking {
        val harness = Harness()
        val saved = harness.add("a", bytes = byteArrayOf(1)) as SaveResult.Saved
        val second = File(harness.root, "second.jpg")
        second.writeBytes(byteArrayOf(2))
        harness.photos.deleteFile = { false }
        val result = harness.persistence.update(
            id = "a",
            registration = "VH-A",
            airline = "Air",
            location = "YMML",
            aircraftType = null,
            notes = null,
            timestamp = 3,
            remainingPhotoPaths = listOf(second.absolutePath),
            newPhotoSources = emptyList(),
        )
        assertTrue(result is SaveResult.SavedWithCleanupFailure)
        assertTrue(File(saved.entries.first().photos.first()).isFile)
        val reloaded = harness.rebuild().load() as LoadOutcome.Loaded
        assertEquals(listOf("second.jpg"), reloaded.entries.first().photos.map { File(it).name })
    }

    @Test
    fun photoOrderIsPreservedAndSharedFilesAreNotDeleted() = runBlocking {
        val harness = Harness()
        val shared = File(harness.root, "shared.jpg")
        shared.writeBytes(byteArrayOf(5))
        val extra = File(harness.root, "extra.jpg")
        extra.writeBytes(byteArrayOf(6))
        harness.store.values[SpottingPersistence.ENTRIES_KEY] = EntryJson.encode(
            listOf(
                stored("a", listOf("shared.jpg", "extra.jpg")),
                stored("b", listOf("shared.jpg")),
            ),
        )
        val loaded = harness.persistence.load() as LoadOutcome.Loaded
        val updated = harness.persistence.update(
            id = "a",
            registration = "VH-A",
            airline = "Air",
            location = "YMML",
            aircraftType = "B738",
            notes = "note",
            timestamp = 4,
            remainingPhotoPaths = listOf(loaded.entries.first { it.id == "a" }.photos[1], loaded.entries.first { it.id == "a" }.photos[0]),
            newPhotoSources = listOf(PhotoBytesSource { byteArrayOf(8) }),
        ) as SaveResult.Saved
        val names = updated.entries.first { it.id == "a" }.photos.map { File(it).name }
        assertEquals("extra.jpg", names[0])
        assertEquals("shared.jpg", names[1])
        assertTrue(shared.isFile)
        val reloaded = harness.rebuild().load() as LoadOutcome.Loaded
        assertEquals(names, reloaded.entries.first { it.id == "a" }.photos.map { File(it).name })
    }

    @Test
    fun deletionRejectsPathsOutsideThePhotoDirectory() {
        val harness = Harness()
        val siblingRoot = File(harness.root.parentFile, harness.root.name + "_evil")
        siblingRoot.mkdirs()
        val sibling = File(siblingRoot, "secret.jpg")
        sibling.writeBytes(byteArrayOf(1))
        val secret = File(harness.root.parentFile, "secret.txt")
        secret.writeBytes(byteArrayOf(2))
        val traversal = File(harness.root, "../secret.txt").path
        assertEquals(PhotoDeleteResult.Rejected, harness.photos.deleteManaged(sibling.absolutePath))
        assertEquals(PhotoDeleteResult.Rejected, harness.photos.deleteManaged(traversal))
        assertEquals(PhotoDeleteResult.Rejected, harness.photos.deleteManaged(secret.absolutePath))
        assertTrue(sibling.isFile)
        assertTrue(secret.isFile)
        sibling.delete()
        secret.delete()
        siblingRoot.delete()
    }

    @Test
    fun expiredStagingFilesAreRemovedOnlyAfterAReadableLoad() = runBlocking {
        val harness = Harness()
        val stale = File(harness.photos.staging, "stale.jpg")
        stale.writeBytes(byteArrayOf(1))
        stale.setLastModified(System.currentTimeMillis() - ManagedPhotoDirectory.STAGING_MAX_AGE_MILLIS - 5_000)
        val fresh = File(harness.photos.staging, "fresh.jpg")
        fresh.writeBytes(byteArrayOf(2))
        harness.store.values[SpottingPersistence.ENTRIES_KEY] = "not-json"
        harness.persistence.add(
            registration = "VH-A",
            airline = "Air",
            location = "YMML",
            aircraftType = null,
            notes = null,
            timestamp = 1,
            photoSources = listOf(PhotoBytesSource { byteArrayOf(3) }),
            id = "a",
        )
        assertTrue(stale.isFile)
        harness.store.values.remove(SpottingPersistence.ENTRIES_KEY)
        harness.persistence = harness.rebuild()
        harness.add("a")
        assertFalse(stale.exists())
        assertTrue(fresh.isFile)
    }

    @Test
    fun concurrentAddsBothPersist() = runBlocking {
        val harness = Harness()
        val results = listOf("a", "b").map { id ->
            async(Dispatchers.IO) { harness.add(id) }
        }.awaitAll()
        assertTrue(results.all { it is SaveResult.Saved })
        val loaded = harness.rebuild().load() as LoadOutcome.Loaded
        assertEquals(setOf("a", "b"), loaded.entries.map { it.id }.toSet())
    }

    @Test
    fun addThenUpdateDoesNotDropTheNewRecord() = runBlocking {
        val harness = Harness()
        val existing = harness.add("a") as SaveResult.Saved
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val armed = AtomicBoolean(true)
        harness.persistence.beforePersist = {
            if (armed.compareAndSet(true, false)) {
                entered.complete(Unit)
                release.await()
            }
        }
        val addJob = async(Dispatchers.IO) { harness.add("b") }
        entered.await()
        val updateJob = async(Dispatchers.IO) {
            harness.persistence.update(
                id = "a",
                registration = "UPDATED",
                airline = "Air",
                location = "YMML",
                aircraftType = null,
                notes = null,
                timestamp = 9,
                remainingPhotoPaths = existing.entries.first().photos,
                newPhotoSources = emptyList(),
            )
        }
        release.complete(Unit)
        assertTrue(addJob.await() is SaveResult.Saved)
        assertTrue(updateJob.await() is SaveResult.Saved)
        val loaded = harness.rebuild().load() as LoadOutcome.Loaded
        assertEquals(setOf("a", "b"), loaded.entries.map { it.id }.toSet())
        assertEquals("UPDATED", loaded.entries.first { it.id == "a" }.registration)
    }

    @Test
    fun addThenDeleteKeepsOnlyTheNewRecord() = runBlocking {
        val harness = Harness()
        harness.add("a")
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        harness.persistence.beforePersist = {
            entered.complete(Unit)
            release.await()
            harness.persistence.beforePersist = null
        }
        val addJob = async(Dispatchers.IO) { harness.add("b") }
        entered.await()
        val deleteJob = async(Dispatchers.IO) { harness.persistence.delete("a") }
        release.complete(Unit)
        assertTrue(addJob.await() is SaveResult.Saved)
        assertTrue(deleteJob.await() is SaveResult.Saved)
        val loaded = harness.rebuild().load() as LoadOutcome.Loaded
        assertEquals(listOf("b"), loaded.entries.map { it.id })
    }

    @Test
    fun updateThenDeleteKeepsTheUpdatedRecordOnly() = runBlocking {
        val harness = Harness()
        val first = harness.add("a") as SaveResult.Saved
        harness.add("b")
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        harness.persistence.beforePersist = {
            entered.complete(Unit)
            release.await()
            harness.persistence.beforePersist = null
        }
        val updateJob = async(Dispatchers.IO) {
            harness.persistence.update(
                id = "a",
                registration = "UPDATED",
                airline = "Air",
                location = "YMML",
                aircraftType = null,
                notes = null,
                timestamp = 4,
                remainingPhotoPaths = first.entries.first { it.id == "a" }.photos,
                newPhotoSources = emptyList(),
            )
        }
        entered.await()
        val deleteJob = async(Dispatchers.IO) { harness.persistence.delete("b") }
        release.complete(Unit)
        assertTrue(updateJob.await() is SaveResult.Saved)
        assertTrue(deleteJob.await() is SaveResult.Saved)
        val loaded = harness.rebuild().load() as LoadOutcome.Loaded
        assertEquals(listOf("a"), loaded.entries.map { it.id })
        assertEquals("UPDATED", loaded.entries.first().registration)
    }

    @Test
    fun twoDeletesLeaveNoRecords() = runBlocking {
        val harness = Harness()
        harness.add("a")
        harness.add("b")
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        harness.persistence.beforePersist = {
            entered.complete(Unit)
            release.await()
            harness.persistence.beforePersist = null
        }
        val first = async(Dispatchers.IO) { harness.persistence.delete("a") }
        entered.await()
        val second = async(Dispatchers.IO) { harness.persistence.delete("b") }
        release.complete(Unit)
        assertTrue(first.await() is SaveResult.Saved)
        assertTrue(second.await() is SaveResult.Saved)
        val loaded = harness.rebuild().load() as LoadOutcome.Loaded
        assertTrue(loaded.entries.isEmpty())
    }

    @Test
    fun resetWaitsForAnInProgressAddAndClearsIt() = runBlocking {
        val harness = Harness()
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        harness.persistence.beforePersist = {
            entered.complete(Unit)
            release.await()
            harness.persistence.beforePersist = null
        }
        val addJob = async(Dispatchers.IO) { harness.add("a") }
        entered.await()
        val resetJob = async(Dispatchers.IO) { harness.persistence.reset() }
        release.complete(Unit)
        assertTrue(addJob.await() is SaveResult.Saved)
        assertTrue(resetJob.await() is SaveResult.Saved)
        val loaded = harness.rebuild().load() as LoadOutcome.Loaded
        assertTrue(loaded.entries.isEmpty())
        assertTrue(harness.photoFiles().isEmpty())
    }

    @Test
    fun resetDoesNotDeletePhotosWhenTheWriteFails() = runBlocking {
        val harness = Harness()
        val saved = harness.add("a") as SaveResult.Saved
        val photo = File(saved.entries.first().photos.first())
        harness.store.failCommitsRemaining = 1
        val result = harness.persistence.reset()
        assertTrue(result is SaveResult.Failed)
        assertTrue(photo.isFile)
        val loaded = harness.rebuild().load() as LoadOutcome.Loaded
        assertEquals(listOf("a"), loaded.entries.map { it.id })
    }

    @Test
    fun rapidSequentialAddsAllSurvive() = runBlocking {
        val harness = Harness()
        repeat(12) { index ->
            val result = harness.add("id-$index")
            assertTrue(result is SaveResult.Saved)
        }
        val loaded = harness.rebuild().load() as LoadOutcome.Loaded
        assertEquals(12, loaded.entries.size)
        assertEquals((0 until 12).map { "id-$it" }.toSet(), loaded.entries.map { it.id }.toSet())
    }

    @Test
    fun quotedRegistrationRoundTrips() = runBlocking {
        val harness = Harness()
        val result = harness.persistence.add(
            registration = "VH \"ABC\"",
            airline = "Line\nTwo",
            location = "YMML",
            aircraftType = null,
            notes = null,
            timestamp = 42,
            photoSources = listOf(PhotoBytesSource { byteArrayOf(1) }),
            id = "quoted",
        )
        assertTrue(result is SaveResult.Saved)
        val loaded = harness.rebuild().load() as LoadOutcome.Loaded
        assertEquals("VH \"ABC\"", loaded.entries.first().registration)
        assertEquals("Line\nTwo", loaded.entries.first().airline)
    }

    private fun entryJson(id: String, photos: List<String>): String = EntryJson.encode(listOf(stored(id, photos)))

    private fun stored(id: String, photos: List<String>) = StoredEntry(
        id = id,
        photos = photos,
        registration = "VH-${id.uppercase()}",
        airline = "Qantas",
        location = "YMML",
        aircraftType = "B738",
        notes = "note",
        timestamp = 10,
    )
}

private class Harness {
    val root: File = File(System.getProperty("java.io.tmpdir"), "tailtag-test-${System.nanoTime()}").apply { mkdirs() }
    val photos = ManagedPhotoDirectory(root)
    val store = MemoryKeyValueStore()
    var persistence = rebuild()

    fun rebuild() = SpottingPersistence(store, photos, Dispatchers.IO)

    suspend fun add(id: String, bytes: ByteArray = byteArrayOf(1, 2, 3)): SaveResult {
        return persistence.add(
            registration = "VH-${id.uppercase()}",
            airline = "Air",
            location = "YMML",
            aircraftType = null,
            notes = null,
            timestamp = 1,
            photoSources = listOf(PhotoBytesSource { bytes }),
            id = id,
        )
    }

    fun photoFiles(): List<File> = root.listFiles()?.filter { it.isFile }.orEmpty()
}

private class MemoryKeyValueStore : KeyValueStore {
    val values = linkedMapOf<String, String>()
    var failCommitsRemaining = 0
    var throwOnRead = false

    override fun getString(key: String): String? {
        if (throwOnRead) throw IOException("read failed")
        return values[key]
    }

    override fun commit(edits: Map<String, String?>): Boolean {
        if (failCommitsRemaining > 0) {
            failCommitsRemaining -= 1
            return false
        }
        for ((key, value) in edits) {
            if (value == null) values.remove(key) else values[key] = value
        }
        return true
    }
}
