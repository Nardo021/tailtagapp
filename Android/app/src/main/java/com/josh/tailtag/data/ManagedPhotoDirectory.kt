package com.josh.tailtag.data

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.UUID

internal enum class PhotoDeleteResult {
    Deleted,
    Missing,
    Rejected,
    Failed,
}

/**
 * Owns files under the app photo directory.
 * Deletion uses the canonical path, so a sibling folder or a `..` segment cannot match by prefix.
 */
internal class ManagedPhotoDirectory(val root: File) {
    val staging: File = File(root, STAGING_DIRECTORY)

    init {
        root.mkdirs()
        staging.mkdirs()
    }

    @Throws(IOException::class)
    fun importBytes(bytes: ByteArray): File {
        if (bytes.isEmpty()) throw IOException("The photo could not be read.")
        val staged = File(staging, "${UUID.randomUUID()}.jpg")
        try {
            writeSynced(staged, bytes)
            val promoted = File(root, staged.name)
            if (!staged.renameTo(promoted)) {
                staged.copyTo(promoted, overwrite = false)
                if (!staged.delete()) {
                    promoted.delete()
                    throw IOException("The photo could not be stored.")
                }
            }
            if (!promoted.isFile || promoted.length() <= 0L) {
                promoted.delete()
                throw IOException("The photo could not be stored.")
            }
            return promoted
        } catch (error: IOException) {
            staged.delete()
            throw error
        }
    }

    fun deleteManaged(path: String): PhotoDeleteResult {
        val file = managedFileOrNull(path) ?: return PhotoDeleteResult.Rejected
        if (!file.exists()) return PhotoDeleteResult.Missing
        return if (deleteFile(file)) PhotoDeleteResult.Deleted else PhotoDeleteResult.Failed
    }

    fun isManagedFile(path: String): Boolean = managedFileOrNull(path) != null

    fun resolveStoredReference(stored: String): String {
        val raw = File(stored)
        if (!raw.isAbsolute) return File(root, raw.name).absolutePath
        if (raw.isFile) return raw.absolutePath
        val relocated = File(root, raw.name)
        if (relocated.isFile) return relocated.absolutePath
        return raw.absolutePath
    }

    fun persistableReference(path: String): String {
        val managed = managedFileOrNull(path)
        if (managed != null) return managed.name
        val file = File(path)
        if (!file.isAbsolute) return file.name
        return path
    }

    fun cleanupExpiredStaging(nowMillis: Long, maxAgeMillis: Long) {
        val files = staging.listFiles() ?: return
        for (file in files) {
            if (!file.isFile) continue
            val age = nowMillis - file.lastModified()
            if (age >= maxAgeMillis) file.delete()
        }
    }

    private fun managedFileOrNull(path: String): File? {
        val rootCanonical = root.canonicalFile
        val candidate = File(path).canonicalFile
        val rootPrefix = rootCanonical.path + File.separator
        if (!candidate.path.startsWith(rootPrefix)) return null
        if (candidate == rootCanonical) return null
        val stagingPrefix = staging.canonicalFile.path + File.separator
        if (candidate.path.startsWith(stagingPrefix)) return null
        return candidate
    }

    private fun writeSynced(file: File, bytes: ByteArray) {
        FileOutputStream(file).use { output ->
            output.write(bytes)
            output.getFD().sync()
        }
    }

    internal var deleteFile: (File) -> Boolean = { file -> file.delete() }

    companion object {
        const val STAGING_DIRECTORY = ".staging"
        const val STAGING_MAX_AGE_MILLIS = 60L * 60L * 1000L
    }
}
