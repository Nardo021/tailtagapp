package com.josh.tailtag

import android.app.Application
import android.content.Context
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.josh.tailtag.data.LoadOutcome
import com.josh.tailtag.data.SaveResult
import com.josh.tailtag.data.TailTagRepository
import com.josh.tailtag.data.UnreadableReason
import com.josh.tailtag.model.SpottingEntry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class StorageProblem(
    val message: String,
    val canRestoreBackup: Boolean,
)

class TailTagViewModel(application: Application) : AndroidViewModel(application) {
    private val repository = TailTagRepository(application)
    private val preferences = application.getSharedPreferences("tailtag_settings", Context.MODE_PRIVATE)
    private var appliedVersion = -1L

    var entries by mutableStateOf<List<SpottingEntry>>(emptyList())
        private set
    var isLoadingEntries by mutableStateOf(true)
        private set
    var storageProblem by mutableStateOf<StorageProblem?>(null)
        private set
    var hasCompletedOnboarding by mutableStateOf(preferences.getBoolean("onboarding_complete", false))
        private set
    var accentName by mutableStateOf(preferences.getString("accent", "blue") ?: "blue")
        private set
    @set:JvmName("setInternalColorScheme")
    var colorScheme by mutableStateOf(preferences.getString("color_scheme", "system") ?: "system")
        private set

    init {
        viewModelScope.launch { refresh() }
    }

    fun completeOnboarding() {
        hasCompletedOnboarding = true
        preferences.edit().putBoolean("onboarding_complete", true).apply()
    }

    fun replayOnboarding() {
        hasCompletedOnboarding = false
        preferences.edit().putBoolean("onboarding_complete", false).apply()
    }

    fun setAccent(name: String) {
        accentName = name
        preferences.edit().putString("accent", name).apply()
    }

    fun setColorScheme(value: String) {
        colorScheme = value
        preferences.edit().putString("color_scheme", value).apply()
    }

    fun retryLoad() {
        viewModelScope.launch { refresh() }
    }

    fun restoreBackup() {
        viewModelScope.launch {
            publish(repository.restoreBackup())
            isLoadingEntries = false
        }
    }

    suspend fun addEntry(
        registration: String,
        airline: String,
        location: String,
        aircraftType: String?,
        notes: String?,
        timestamp: Long,
        photoUris: List<Uri>,
    ): SaveResult {
        val result = repository.add(registration, airline, location, aircraftType, notes, timestamp, photoUris)
        publishSave(result)
        return result
    }

    suspend fun updateEntry(
        entry: SpottingEntry,
        remainingPhotoPaths: List<String>,
        newPhotoUris: List<Uri>,
    ): SaveResult {
        val result = repository.update(
            id = entry.id,
            registration = entry.registration,
            airline = entry.airline,
            location = entry.location,
            aircraftType = entry.aircraftType,
            notes = entry.notes,
            timestamp = entry.timestamp,
            remainingPhotoPaths = remainingPhotoPaths,
            newPhotoUris = newPhotoUris,
        )
        publishSave(result)
        return result
    }

    suspend fun deleteEntry(entry: SpottingEntry): SaveResult {
        val result = repository.delete(entry.id)
        publishSave(result)
        return result
    }

    suspend fun resetApp(): SaveResult {
        val result = repository.reset()
        when (result) {
            is SaveResult.Saved, is SaveResult.SavedWithCleanupFailure -> {
                publishSave(result)
                val cleared = withContext(Dispatchers.IO) { preferences.edit().clear().commit() }
                if (!cleared) {
                    return SaveResult.Failed("Aircraft records were cleared, but app settings could not be reset.")
                }
                hasCompletedOnboarding = false
                accentName = "blue"
                colorScheme = "system"
            }
            is SaveResult.Failed -> Unit
        }
        return result
    }

    private suspend fun refresh() {
        publish(repository.load())
        isLoadingEntries = false
    }

    private fun publishSave(result: SaveResult) {
        when (result) {
            is SaveResult.Saved -> publishEntries(result.version, result.entries)
            is SaveResult.SavedWithCleanupFailure -> {
                publishEntries(result.version, result.entries)
                storageProblem = StorageProblem(result.message, canRestoreBackup = false)
            }
            is SaveResult.Failed -> Unit
        }
    }

    private fun publish(outcome: LoadOutcome) {
        when (outcome) {
            is LoadOutcome.NoSavedData -> publishEntries(outcome.version, emptyList())
            is LoadOutcome.Loaded -> publishEntries(outcome.version, outcome.entries)
            is LoadOutcome.Unreadable -> {
                storageProblem = StorageProblem(messageFor(outcome.reason), outcome.canRestoreBackup)
            }
        }
    }

    private fun publishEntries(version: Long, updated: List<SpottingEntry>) {
        if (version < appliedVersion) return
        appliedVersion = version
        entries = updated
        storageProblem = null
    }

    private fun messageFor(reason: UnreadableReason): String {
        return when (reason) {
            UnreadableReason.Corrupt, UnreadableReason.MissingFields ->
                "Saved aircraft records could not be read. They were not erased."
            UnreadableReason.ReadFailed ->
                "Saved aircraft records could not be read. They were not erased."
        }
    }
}
