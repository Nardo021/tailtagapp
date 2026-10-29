package com.josh.tailtag

import android.app.Application
import android.content.Context
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.josh.tailtag.aviation.AviationCatalog
import com.josh.tailtag.aviation.AviationCatalogLoader
import com.josh.tailtag.aviation.AviationCatalogRepository
import com.josh.tailtag.aviation.entry.CatalogLoadPhase
import com.josh.tailtag.aviation.entry.CatalogLoadState
import com.josh.tailtag.aviation.entry.CatalogQueryGuidance
import com.josh.tailtag.aviation.entry.catalogQueryGuidance
import com.josh.tailtag.aviation.entry.linkedManufacturerSelection
import com.josh.tailtag.data.LoadOutcome
import com.josh.tailtag.data.SaveResult
import com.josh.tailtag.data.TailTagRepository
import com.josh.tailtag.data.UnreadableReason
import com.josh.tailtag.filters.PreparedSpottingFilterCatalog
import com.josh.tailtag.filters.SpottingFilterState
import com.josh.tailtag.filters.toFilterSnapshot
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
    var spottingFilters by mutableStateOf(SpottingFilterState())
        private set
    var filterCatalog by mutableStateOf(PreparedSpottingFilterCatalog.unavailable)
        private set
    var catalogPhase by mutableStateOf(CatalogLoadPhase.IDLE)
        private set
    var catalogError by mutableStateOf<String?>(null)
        private set
    var hasCompletedOnboarding by mutableStateOf(preferences.getBoolean("onboarding_complete", false))
        private set
    var accentName by mutableStateOf(preferences.getString("accent", "blue") ?: "blue")
        private set
    @set:JvmName("setInternalColorScheme")
    var colorScheme by mutableStateOf(preferences.getString("color_scheme", "system") ?: "system")
        private set

    private val catalogRepository = AviationCatalogRepository {
        AviationCatalogLoader.load(getApplication<Application>())
    }
    @Volatile private var catalog: AviationCatalog? = null
    private var catalogState = CatalogLoadState()

    fun applySpottingFilters(filters: SpottingFilterState) {
        spottingFilters = filters
    }

    fun ensureCatalog() {
        if (!catalogState.beginAccepted) return
        catalogState = catalogState.begin()
        catalogPhase = catalogState.phase
        catalogError = null
        viewModelScope.launch(Dispatchers.IO) {
            loadCatalog()
        }
    }

    fun retryCatalog() {
        val retried = catalogState.retry() ?: return
        catalogState = retried
        catalogPhase = CatalogLoadPhase.LOADING
        catalogError = null
        viewModelScope.launch(Dispatchers.IO) {
            loadCatalog()
        }
    }

    fun operatorExists(id: String?) = exists(id) { catalog?.operatorById(it) }
    fun manufacturerExists(id: String?) = exists(id) { catalog?.manufacturerById(it) }
    fun aircraftExists(id: String?) = exists(id) { catalog?.aircraftById(it) }
    fun airportExists(id: String?) = exists(id) { catalog?.airportById(it) }

    fun aircraftManufacturerLink(aircraftId: String?): Pair<String, String>? {
        if (catalogPhase != CatalogLoadPhase.READY || aircraftId == null) return null
        val model = catalog?.aircraftById(aircraftId) ?: return null
        val linked = linkedManufacturerSelection(model) ?: return null
        val id = linked.catalogId ?: return null
        return id to linked.displayText
    }

    fun classificationLabels(): Pair<Map<String, String>, Map<String, String>> {
        val loaded = catalog ?: return emptyMap<String, String>() to emptyMap()
        return labels(loaded, "aircraft-role") to labels(loaded, "operation-type")
    }

    suspend fun searchOperators(query: String, limit: Int) = search(query) {
        outcome(it.resolveOperators(query, limit))
    }

    suspend fun searchManufacturers(query: String, limit: Int) = search(query) {
        val records = it.searchManufacturers(query, limit)
        SearchPage(records, ambiguous = false, unmatched = records.isEmpty() && catalogQueryGuidance(query) == CatalogQueryGuidance.READY)
    }

    suspend fun searchAirports(query: String, limit: Int) = search(query) {
        outcome(it.resolveAirports(query, limit))
    }

    suspend fun searchAircraft(query: String, limit: Int, manufacturerId: String?) = search(query) { loaded ->
        if (manufacturerId == null) {
            outcome(loaded.resolveAircraft(query, limit))
        } else {
            val records = loaded.searchAircraft(query, limit, manufacturerId)
            SearchPage(
                records = records,
                ambiguous = false,
                unmatched = records.isEmpty() && catalogQueryGuidance(query) == CatalogQueryGuidance.READY,
            )
        }
    }

    init {
        ensureCatalog()
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

    suspend fun addEntry(draft: SpottingEntry, photoUris: List<Uri>): SaveResult {
        val result = repository.add(draft, photoUris)
        publishSave(result)
        return result
    }

    suspend fun updateEntry(
        entry: SpottingEntry,
        remainingPhotoPaths: List<String>,
        newPhotoUris: List<Uri>,
    ): SaveResult {
        val result = repository.update(entry, remainingPhotoPaths, newPhotoUris)
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

    private suspend fun loadCatalog() {
        try {
            val loaded = catalogRepository.catalog()
            val prepared = PreparedSpottingFilterCatalog(loaded.toFilterSnapshot())
            withContext(Dispatchers.Main) {
                catalog = loaded
                filterCatalog = prepared
                catalogState = catalogState.succeed()
                catalogPhase = catalogState.phase
                catalogError = null
            }
        } catch (_: Exception) {
            withContext(Dispatchers.Main) {
                catalogState = catalogState.fail()
                catalogPhase = catalogState.phase
                catalogError = "The aviation catalog could not be loaded."
            }
        }
    }

    private fun exists(id: String?, lookup: (String) -> Any?): Boolean? {
        if (catalogPhase != CatalogLoadPhase.READY || id.isNullOrEmpty()) return null
        return lookup(id) != null
    }

    private fun labels(loaded: AviationCatalog, dimension: String): Map<String, String> {
        val values = loaded.classifications.firstOrNull { it.id == dimension }?.values ?: return emptyMap()
        return values.associate { it.id to it.label }
    }

    private suspend fun <T> search(query: String, block: (AviationCatalog) -> SearchPage<T>): SearchPage<T>? {
        val loaded = catalog ?: return null
        return withContext(Dispatchers.Default) { block(loaded) }
    }

    private fun <T> outcome(resolution: com.josh.tailtag.aviation.AviationQueryResolution<T>): SearchPage<T> = when (resolution) {
        com.josh.tailtag.aviation.AviationQueryResolution.Blank -> SearchPage(emptyList(), ambiguous = false, unmatched = false)
        is com.josh.tailtag.aviation.AviationQueryResolution.Matches -> SearchPage(resolution.records, ambiguous = false, unmatched = false)
        is com.josh.tailtag.aviation.AviationQueryResolution.Ambiguous -> SearchPage(resolution.records, ambiguous = true, unmatched = false)
        is com.josh.tailtag.aviation.AviationQueryResolution.Unmatched -> SearchPage(emptyList(), ambiguous = false, unmatched = true)
    }
}

data class SearchPage<T>(val records: List<T>, val ambiguous: Boolean, val unmatched: Boolean)
