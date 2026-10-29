package com.josh.tailtag.filters.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.DatePicker
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.InputChip
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.josh.tailtag.aviation.entry.AviationSelection
import com.josh.tailtag.aviation.entry.catalogQueryGuidance
import com.josh.tailtag.aviation.entry.CatalogQueryGuidance
import com.josh.tailtag.filters.AircraftFilter
import com.josh.tailtag.filters.CollectionFilterChoices
import com.josh.tailtag.filters.FilterCalendarDay
import com.josh.tailtag.filters.FilterChoice
import com.josh.tailtag.filters.FilterDateRange
import com.josh.tailtag.filters.FilterDimension
import com.josh.tailtag.filters.FilterToken
import com.josh.tailtag.filters.FilterableSpotting
import com.josh.tailtag.filters.ReferenceDimension
import com.josh.tailtag.filters.ReferenceFilter
import com.josh.tailtag.filters.SpottingFilterCatalog
import com.josh.tailtag.filters.SpottingFilterChip
import com.josh.tailtag.filters.SpottingFilterSort
import com.josh.tailtag.filters.SpottingFilterState
import com.josh.tailtag.filters.collectionFilterChoices
import com.josh.tailtag.filters.filteredSpottingResults
import kotlinx.coroutines.delay
import java.util.Calendar
import java.util.TimeZone

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun AdvancedFilterScreen(
    applied: SpottingFilterState,
    entries: List<FilterableSpotting>,
    searchText: String,
    catalog: SpottingFilterCatalog,
    catalogFailed: Boolean,
    catalogLoading: Boolean,
    onCancel: () -> Unit,
    onApply: (SpottingFilterState) -> Unit,
    searchCatalog: suspend (FilterCatalogBrowse, String) -> FilterCatalogSearchResult,
) {
    var draft by remember { mutableStateOf(applied) }
    var browsing by remember { mutableStateOf<FilterCatalogBrowse?>(null) }
    val choices = remember(entries, catalog) { collectionFilterChoices(entries, catalog) }
    val browsingTarget = browsing
    if (browsingTarget != null) {
        CatalogFilterSearchPage(
            browse = browsingTarget,
            catalogFailed = catalogFailed,
            onBack = { browsing = null },
            onSelect = { token ->
                draft = draft.insert(token)
                browsing = null
            },
            searchCatalog = searchCatalog,
        )
        return
    }
    val matchCount = remember(draft, entries, searchText, catalog) {
        filteredSpottingResults(entries, searchText, draft, catalog, SpottingFilterSort.DATE_NEWEST, Calendar.getInstance()).size
    }
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text("Filters") },
                navigationIcon = {
                    TextButton(onClick = onCancel, modifier = Modifier.semantics { contentDescription = "Cancel filters" }) {
                        Text("Cancel")
                    }
                },
                actions = {
                    TextButton(
                        onClick = { onApply(draft) },
                        enabled = draft.dateRange.isValid,
                        modifier = Modifier.semantics { contentDescription = "Apply filters" },
                    ) { Text("Apply", fontWeight = FontWeight.SemiBold) }
                },
            )
        },
        bottomBar = {
            TextButton(
                onClick = { draft = draft.reset() },
                modifier = Modifier.fillMaxWidth().padding(12.dp).semantics { contentDescription = "Reset all filters" },
            ) { Text("Reset all") }
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 20.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            item {
                if (catalogLoading) {
                    Text("The aviation catalog is still loading. Saved identities can be selected now.", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
                } else if (catalogFailed || !catalog.isAvailable) {
                    Text("Some catalog details are unavailable. Saved identities still match, but family and manufacturer links cannot be resolved.", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
                }
                Text(
                    if (matchCount == 1) "1 sighting matches" else "$matchCount sightings match",
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 8.dp).semantics { contentDescription = "filter-match-count" },
                )
            }
            item { ChoiceSection("Operator", choices.operators, draft, FilterDimension.OPERATORS, FilterCatalogBrowse.OPERATORS, { draft = it }, { browsing = FilterCatalogBrowse.OPERATORS }) }
            item { ChoiceSection("Manufacturer", choices.manufacturers, draft, FilterDimension.MANUFACTURERS, FilterCatalogBrowse.MANUFACTURERS, { draft = it }, { browsing = FilterCatalogBrowse.MANUFACTURERS }) }
            item { ChoiceSection("Aircraft", choices.aircraft, draft, FilterDimension.AIRCRAFT, FilterCatalogBrowse.AIRCRAFT, { draft = it }, { browsing = FilterCatalogBrowse.AIRCRAFT }) }
            item { ChoiceSection("Aircraft role", choices.roles, draft, FilterDimension.ROLES, null, { draft = it }, {}) }
            item { ChoiceSection("Operation type", choices.operationTypes, draft, FilterDimension.OPERATION_TYPES, null, { draft = it }, {}) }
            item { ChoiceSection("Airport / location", choices.locations, draft, FilterDimension.LOCATIONS, FilterCatalogBrowse.LOCATIONS, { draft = it }, { browsing = FilterCatalogBrowse.LOCATIONS }) }
            item { RegistrationSection(draft) { draft = it } }
            item { DateSection(draft) { draft = it } }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ActiveFilterChips(
    chips: List<SpottingFilterChip>,
    onRemove: (SpottingFilterChip) -> Unit,
    onClearAll: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            chips.forEach { chip ->
                InputChip(
                    selected = true,
                    onClick = { onRemove(chip) },
                    label = { Text(chip.label) },
                    trailingIcon = { Icon(Icons.Default.Close, contentDescription = chip.accessibilityLabel) },
                    modifier = Modifier.semantics { contentDescription = chip.accessibilityLabel },
                )
            }
        }
        TextButton(onClick = onClearAll) { Text("Clear all") }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ChoiceSection(
    title: String,
    choices: List<FilterChoice>,
    draft: SpottingFilterState,
    dimension: FilterDimension,
    browse: FilterCatalogBrowse?,
    onDraft: (SpottingFilterState) -> Unit,
    onBrowse: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.weight(1f))
            if (dimensionActive(draft, dimension)) {
                TextButton(onClick = { onDraft(draft.clear(dimension)) }) { Text("Clear") }
            }
        }
        if (choices.isEmpty()) {
            Text("No saved values in this collection.", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
        } else {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                choices.forEach { choice ->
                    FilterChip(
                        selected = draft.contains(choice.token),
                        onClick = { onDraft(draft.toggle(choice.token)) },
                        label = {
                            Column {
                                Text(choice.title)
                                Text(choice.detail, style = MaterialTheme.typography.labelSmall)
                            }
                        },
                        modifier = Modifier.semantics { contentDescription = "${choice.title}, ${choice.detail}" },
                    )
                }
            }
        }
        if (browse != null) {
            TextButton(onClick = onBrowse) {
                Icon(Icons.Default.Search, contentDescription = null)
                Text("Search catalog")
            }
        }
    }
}

@Composable
private fun RegistrationSection(draft: SpottingFilterState, onDraft: (SpottingFilterState) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Registration", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.weight(1f))
            if (draft.registrationIsActive) {
                TextButton(onClick = { onDraft(draft.clear(FilterDimension.REGISTRATION)) }) { Text("Clear") }
            }
        }
        OutlinedTextField(
            value = draft.registrationQuery,
            onValueChange = { onDraft(draft.copy(registrationQuery = it)) },
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text("VH-, N123, G-") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, imeAction = ImeAction.Done),
        )
        Text("Matches the start of a registration. This stays separate from the main search.", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DateSection(draft: SpottingFilterState, onDraft: (SpottingFilterState) -> Unit) {
    var editing by remember { mutableStateOf<DateField?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Sighting date", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.weight(1f))
            if (draft.dateRange.isActive) {
                TextButton(onClick = { onDraft(draft.clear(FilterDimension.DATE_RANGE)); editing = null }) { Text("Clear") }
            }
        }
        val editingField = editing
        if (editingField == null) {
            DateRow("Start date", draft.dateRange.start) { editing = DateField.START }
            DateRow("End date", draft.dateRange.end) { editing = DateField.END }
        } else {
            val state = rememberDatePickerState()
            Text(if (editingField == DateField.START) "Choose a start date" else "Choose an end date", fontWeight = FontWeight.SemiBold)
            DatePicker(state = state, title = null, headline = null, showModeToggle = false)
            Row {
                TextButton(onClick = {
                    onDraft(draft.copy(dateRange = draft.dateRange.without(editingField)))
                    editing = null
                }) { Text("Remove") }
                Spacer(Modifier.weight(1f))
                TextButton(onClick = { editing = null }) { Text("Back") }
                Button(onClick = {
                    val millis = state.selectedDateMillis
                    if (millis != null) {
                        onDraft(draft.copy(dateRange = draft.dateRange.with(editingField, dayFromPicker(millis))))
                    }
                    editing = null
                }) { Text("Use date") }
            }
        }
        if (!draft.dateRange.isValid) {
            Text("End date is before the start date. Choose an end date on or after the start date.", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        } else {
            Text("An end date includes sightings through that calendar day.", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
private fun DateRow(title: String, day: FilterCalendarDay?, onClick: () -> Unit) {
    TextButton(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(title)
            Spacer(Modifier.weight(1f))
            Text(day?.let { com.josh.tailtag.filters.formatFilterDay(it) } ?: "Any", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun CatalogFilterSearchPage(
    browse: FilterCatalogBrowse,
    catalogFailed: Boolean,
    onBack: () -> Unit,
    onSelect: (FilterToken) -> Unit,
    searchCatalog: suspend (FilterCatalogBrowse, String) -> FilterCatalogSearchResult,
) {
    var query by remember { mutableStateOf("") }
    var result by remember { mutableStateOf(FilterCatalogSearchResult()) }
    var searching by remember { mutableStateOf(false) }
    LaunchedEffect(query, browse) {
        if (catalogQueryGuidance(query) != CatalogQueryGuidance.READY) {
            result = FilterCatalogSearchResult()
            searching = false
            return@LaunchedEffect
        }
        searching = true
        delay(120)
        result = searchCatalog(browse, query)
        searching = false
    }
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(browseTitle(browse)) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.Default.Close, contentDescription = "Back") }
                },
            )
        },
    ) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding), contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            item {
                if (catalogFailed) {
                    Text("The aviation catalog could not be loaded. Saved collection values are still available on the previous screen.", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
                    Spacer(Modifier.height(8.dp))
                }
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text(browsePrompt(browse)) },
                    singleLine = true,
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                )
            }
            if (searching) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
            if (result.ambiguous) {
                item { Text(ambiguousMessage(browse), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall) }
            }
            items(result.hits, key = { it.id }) { hit ->
                TextButton(onClick = { onSelect(hit.token) }, modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.fillMaxWidth()) {
                        Text(hit.title, color = MaterialTheme.colorScheme.onSurface)
                        if (hit.subtitle.isNotEmpty()) {
                            Text(hit.subtitle, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
            }
            if (result.unmatched) item { Text("No catalog records match.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
            val custom = customToken(browse, query)
            if (custom != null) {
                item {
                    Button(onClick = { onSelect(custom) }, modifier = Modifier.fillMaxWidth()) {
                        Text("Use \"${customLabel(custom)}\" as custom text")
                    }
                }
            }
        }
    }
}

private enum class DateField { START, END }

private fun dimensionActive(draft: SpottingFilterState, dimension: FilterDimension): Boolean = when (dimension) {
    FilterDimension.OPERATORS -> draft.operators.isNotEmpty()
    FilterDimension.MANUFACTURERS -> draft.manufacturers.isNotEmpty()
    FilterDimension.AIRCRAFT -> draft.aircraft.isNotEmpty()
    FilterDimension.ROLES -> draft.roles.isNotEmpty()
    FilterDimension.OPERATION_TYPES -> draft.operationTypes.isNotEmpty()
    FilterDimension.LOCATIONS -> draft.locations.isNotEmpty()
    FilterDimension.REGISTRATION -> draft.registrationIsActive
    FilterDimension.DATE_RANGE -> draft.dateRange.isActive
}

private fun dayFromPicker(millis: Long): FilterCalendarDay {
    val calendar = Calendar.getInstance(TimeZone.getTimeZone("UTC"))
    calendar.timeInMillis = millis
    return FilterCalendarDay(calendar.get(Calendar.YEAR), calendar.get(Calendar.MONTH) + 1, calendar.get(Calendar.DAY_OF_MONTH))
}

private fun FilterDateRange.with(field: DateField, day: FilterCalendarDay) = when (field) {
    DateField.START -> copy(start = day)
    DateField.END -> copy(end = day)
}

private fun FilterDateRange.without(field: DateField) = when (field) {
    DateField.START -> copy(start = null)
    DateField.END -> copy(end = null)
}

private fun browseTitle(browse: FilterCatalogBrowse) = when (browse) {
    FilterCatalogBrowse.OPERATORS -> "Operator"
    FilterCatalogBrowse.MANUFACTURERS -> "Manufacturer"
    FilterCatalogBrowse.AIRCRAFT -> "Aircraft"
    FilterCatalogBrowse.LOCATIONS -> "Location"
}

private fun browsePrompt(browse: FilterCatalogBrowse) = when (browse) {
    FilterCatalogBrowse.OPERATORS -> "Name or code"
    FilterCatalogBrowse.MANUFACTURERS -> "Manufacturer"
    FilterCatalogBrowse.AIRCRAFT -> "Model or family"
    FilterCatalogBrowse.LOCATIONS -> "Airport or place"
}

private fun ambiguousMessage(browse: FilterCatalogBrowse) = when (browse) {
    FilterCatalogBrowse.OPERATORS -> "Several operators share this code. Choose the specific one."
    FilterCatalogBrowse.AIRCRAFT -> "Several aircraft match this code. Choose the specific one."
    FilterCatalogBrowse.LOCATIONS -> "Several airports share this code. Choose the specific one."
    FilterCatalogBrowse.MANUFACTURERS -> "Choose the specific manufacturer."
}

private fun customToken(browse: FilterCatalogBrowse, query: String): FilterToken? {
    if (catalogQueryGuidance(query) != CatalogQueryGuidance.READY) return null
    val text = AviationSelection.custom(query)?.displayText ?: return null
    return when (browse) {
        FilterCatalogBrowse.OPERATORS -> FilterToken.Reference(ReferenceDimension.OPERATOR, ReferenceFilter.Custom(text))
        FilterCatalogBrowse.MANUFACTURERS -> FilterToken.Reference(ReferenceDimension.MANUFACTURER, ReferenceFilter.Custom(text))
        FilterCatalogBrowse.AIRCRAFT -> FilterToken.Aircraft(AircraftFilter.Custom(text))
        FilterCatalogBrowse.LOCATIONS -> FilterToken.Reference(ReferenceDimension.LOCATION, ReferenceFilter.Custom(text))
    }
}

private fun customLabel(token: FilterToken): String = when (token) {
    is FilterToken.Reference -> when (val value = token.value) {
        is ReferenceFilter.Custom -> value.text
        else -> ""
    }
    is FilterToken.Aircraft -> when (val value = token.value) {
        is AircraftFilter.Custom -> value.text
        else -> ""
    }
    else -> ""
}
