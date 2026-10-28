package com.josh.tailtag.aviation.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import com.josh.tailtag.SearchPage
import com.josh.tailtag.TailTagViewModel
import com.josh.tailtag.aviation.AircraftModel
import com.josh.tailtag.aviation.AviationAirport
import com.josh.tailtag.aviation.AviationManufacturer
import com.josh.tailtag.aviation.AviationOperator
import com.josh.tailtag.aviation.entry.AviationSelection
import com.josh.tailtag.aviation.entry.AviationSelectionKind
import com.josh.tailtag.aviation.entry.CatalogLoadPhase
import com.josh.tailtag.aviation.entry.CatalogPresentation
import com.josh.tailtag.aviation.entry.CatalogQueryGuidance
import com.josh.tailtag.aviation.entry.ClassificationCopy
import com.josh.tailtag.aviation.entry.LatestQueryGate
import com.josh.tailtag.aviation.entry.ManufacturerChange
import com.josh.tailtag.aviation.entry.SpottingEditorState
import com.josh.tailtag.aviation.entry.aircraftKindLabel
import com.josh.tailtag.aviation.entry.aircraftSelection
import com.josh.tailtag.aviation.entry.catalogQueryGuidance
import com.josh.tailtag.aviation.entry.classificationSummary
import com.josh.tailtag.aviation.entry.linkedManufacturerSelection
import kotlinx.coroutines.delay

private class QueryModel<T> {
    val gate = LatestQueryGate()
    var query by mutableStateOf("")
    var records by mutableStateOf<List<T>>(emptyList())
    var ambiguous by mutableStateOf(false)
    var unmatched by mutableStateOf(false)
    var searching by mutableStateOf(false)
    var limit by mutableIntStateOf(20)
    var selectedKey by mutableStateOf<String?>(null)
    var customSelected by mutableStateOf(false)
    var special by mutableStateOf<String?>(null)

    val canLoadMore: Boolean
        get() = catalogQueryGuidance(query) == CatalogQueryGuidance.READY && records.size >= limit && limit < 100 && !searching

    fun resetResults() {
        records = emptyList()
        ambiguous = false
        unmatched = false
        searching = false
    }
}

@Composable
private fun <T> BindQuery(
    model: QueryModel<T>,
    reloadKey: Any? = null,
    search: suspend (String, Int) -> SearchPage<T>?,
) {
    val query = model.query
    val limit = model.limit
    LaunchedEffect(query, limit, reloadKey) {
        delay(120)
        val guidance = catalogQueryGuidance(query)
        if (guidance != CatalogQueryGuidance.READY) {
            model.resetResults()
            return@LaunchedEffect
        }
        val token = model.gate.issue()
        model.searching = true
        val page = search(query, limit)
        if (!model.gate.isCurrent(token)) return@LaunchedEffect
        model.searching = false
        model.records = page?.records.orEmpty()
        model.ambiguous = page?.ambiguous == true
        model.unmatched = page?.unmatched == true
    }
}

@Composable
fun SpottingReferenceEditor(
    editor: SpottingEditorState,
    viewModel: TailTagViewModel,
    onChange: (SpottingEditorState) -> Unit,
) {
    var picker by remember { mutableStateOf<String?>(null) }
    var pending by remember { mutableStateOf<ManufacturerChange.Confirm?>(null) }
    val labels = viewModel.classificationLabels()
    val roleLabels = ClassificationCopy.roleLabels + labels.first
    val operationLabels = ClassificationCopy.operationLabels + labels.second

    SelectionValueRow("Airline / Operator", editor.reference.operatorField, "No operator") { picker = "operator" }
    SelectionValueRow("Manufacturer", editor.reference.manufacturerField, "Optional") { picker = "manufacturer" }
    SelectionValueRow("Aircraft Model / Family", editor.reference.aircraftField, "Optional") { picker = "aircraft" }
    SelectionValueRow("Location / Airport", editor.reference.locationField, "Airport or place") { picker = "airport" }
    ClassificationRow(
        "Aircraft role",
        classificationSummary(editor.reference.classification.roleId, editor.reference.classification.roleNote, roleLabels) ?: "Optional",
    ) { picker = "role" }
    ClassificationRow(
        "Operation type",
        classificationSummary(editor.reference.classification.operationTypeId, editor.reference.classification.operationTypeNote, operationLabels) ?: "Optional",
    ) { picker = "operation" }
    when (viewModel.catalogPhase) {
        CatalogLoadPhase.LOADING -> Text(
            "Catalog loading. Custom text can still be saved.",
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        CatalogLoadPhase.FAILED -> Column(Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) {
            Text(viewModel.catalogError ?: "The aviation catalog could not be loaded.", style = MaterialTheme.typography.bodySmall)
            TextButton(onClick = viewModel::retryCatalog) { Text("Try again") }
        }
        CatalogLoadPhase.IDLE, CatalogLoadPhase.READY -> Unit
    }

    if (picker != null) {
        Dialog(
            onDismissRequest = { picker = null },
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            when (picker) {
                "operator" -> OperatorPicker(viewModel, editor.reference.operatorField, { onChange(editor.commitOperator(it)); picker = null }, { picker = null })
                "manufacturer" -> ManufacturerPicker(viewModel, editor.reference.manufacturerField, { selection ->
                    val link = viewModel.aircraftManufacturerLink(editor.reference.aircraftField.catalogId)
                    val (updated, change) = editor.proposeManufacturer(selection, link?.first, link?.second)
                    onChange(updated)
                    if (change is ManufacturerChange.Confirm) pending = change
                    picker = null
                }, { picker = null })
                "aircraft" -> AircraftPicker(
                    viewModel,
                    editor.reference.aircraftField,
                    manufacturerName = editor.reference.manufacturerField.takeIf { it.kind == AviationSelectionKind.CATALOG }?.displayText,
                    manufacturerId = editor.reference.manufacturerField.takeIf { it.kind == AviationSelectionKind.CATALOG }?.catalogId,
                    onConfirm = { aircraft, linked ->
                        onChange(editor.commitAircraft(aircraft, linked))
                        picker = null
                    },
                    onCancel = { picker = null },
                )
                "airport" -> AirportPicker(viewModel, editor.reference.locationField, { onChange(editor.commitLocation(it)); picker = null }, { picker = null })
                "role" -> ClassificationPicker(
                    title = "Aircraft role",
                    description = "Role is separate from the kind of operation.",
                    options = ClassificationCopy.roleOrder,
                    labels = roleLabels,
                    descriptions = ClassificationCopy.roleDescriptions,
                    selectedId = editor.reference.classification.roleId,
                    note = editor.reference.classification.roleNote,
                    onConfirm = { id, note -> onChange(editor.commitRole(id, note)); picker = null },
                    onCancel = { picker = null },
                )
                "operation" -> ClassificationPicker(
                    title = "Operation type",
                    description = "Operation is separate from civil or military role.",
                    options = ClassificationCopy.operationOrder,
                    labels = operationLabels,
                    descriptions = ClassificationCopy.operationDescriptions,
                    selectedId = editor.reference.classification.operationTypeId,
                    note = editor.reference.classification.operationTypeNote,
                    onConfirm = { id, note -> onChange(editor.commitOperation(id, note)); picker = null },
                    onCancel = { picker = null },
                )
            }
        }
    }

    pending?.let { conflict ->
        AlertDialog(
            onDismissRequest = { pending = null },
            title = { Text("Manufacturer doesn't match") },
            text = { Text("The selected aircraft is linked to a different manufacturer. Keep the aircraft and its manufacturer, or clear the aircraft and use the manufacturer you chose.") },
            dismissButton = {
                TextButton(onClick = { pending = null }) { Text("Cancel") }
            },
            confirmButton = {
                Column {
                    TextButton(onClick = {
                        onChange(editor.resolvePendingManufacturer(true, conflict.proposed, conflict.restore))
                        pending = null
                    }) { Text("Keep aircraft") }
                    TextButton(onClick = {
                        onChange(editor.resolvePendingManufacturer(false, conflict.proposed, conflict.restore))
                        pending = null
                    }) { Text("Clear aircraft") }
                }
            },
        )
    }
}

@Composable
fun OperatorPicker(
    viewModel: TailTagViewModel,
    current: AviationSelection,
    onConfirm: (AviationSelection) -> Unit,
    onCancel: () -> Unit,
) {
    val model = remember { QueryModel<AviationOperator>() }
    BindQuery(model, viewModel.catalogPhase) { query, limit -> viewModel.searchOperators(query, limit) }
    RecordPicker(
        title = "Airline / Operator",
        prompt = "Name, alias, IATA, ICAO, or callsign",
        current = current,
        placeholder = "No operator",
        model = model,
        key = { it.id },
        ambiguous = if (model.ambiguous) "Several operators share this code. Choose the specific one." else null,
        empty = "No catalog operators match. You can use the text above as a custom entry.",
        absentTitle = "No operator",
        loading = viewModel.catalogPhase == CatalogLoadPhase.LOADING,
        error = if (viewModel.catalogPhase == CatalogLoadPhase.FAILED) viewModel.catalogError else null,
        onRetry = viewModel::retryCatalog,
        onCancel = onCancel,
        onConfirm = { choice -> onConfirm(choice) },
        toSelection = { record -> AviationSelection.catalog(record.id, record.name) },
        row = { record ->
            CatalogResultText(
                record.name,
                CatalogPresentation.operatorCodeSummary(record),
                if (record.historical) listOf("Historical") else emptyList(),
                CatalogPresentation.operatorAccessibilityLabel(record),
            )
        },
    )
}

@Composable
fun ManufacturerPicker(
    viewModel: TailTagViewModel,
    current: AviationSelection,
    onConfirm: (AviationSelection) -> Unit,
    onCancel: () -> Unit,
) {
    val model = remember { QueryModel<AviationManufacturer>() }
    BindQuery(model, viewModel.catalogPhase) { query, limit -> viewModel.searchManufacturers(query, limit) }
    RecordPicker(
        title = "Manufacturer",
        prompt = "Manufacturer name",
        current = current,
        placeholder = "No manufacturer",
        model = model,
        key = { it.id },
        ambiguous = null,
        empty = "No manufacturers match. You can use custom text instead.",
        absentTitle = "No manufacturer",
        loading = viewModel.catalogPhase == CatalogLoadPhase.LOADING,
        error = if (viewModel.catalogPhase == CatalogLoadPhase.FAILED) viewModel.catalogError else null,
        onRetry = viewModel::retryCatalog,
        onCancel = onCancel,
        onConfirm = onConfirm,
        toSelection = { AviationSelection.catalog(it.id, it.name) },
        row = { record ->
            CatalogResultText(record.name, CatalogPresentation.manufacturerSubtitle(record), emptyList(), record.name)
        },
    )
}

@Composable
fun AircraftPicker(
    viewModel: TailTagViewModel,
    current: AviationSelection,
    manufacturerName: String?,
    manufacturerId: String?,
    onConfirm: (AviationSelection, AviationSelection?) -> Unit,
    onCancel: () -> Unit,
) {
    var entire by remember { mutableStateOf(false) }
    val model = remember { QueryModel<AircraftModel>() }
    BindQuery(model, entire to viewModel.catalogPhase) { query, limit ->
        viewModel.searchAircraft(query, limit, if (entire || manufacturerId == null) null else manufacturerId)
    }
    RecordPicker(
            title = "Aircraft Model / Family",
            prompt = "Model, family, manufacturer, or alias",
            current = current,
            placeholder = "No aircraft selected",
            model = model,
            key = { it.id },
            ambiguous = if (model.ambiguous) "Several aircraft match this code. Choose the specific one." else null,
            empty = if (manufacturerName != null && !entire) {
                "No matches for this manufacturer. Search the full catalog, or use custom text."
            } else {
                "No aircraft match. A family is not a specific model. You can use custom text."
            },
            absentTitle = "No aircraft type",
            loading = viewModel.catalogPhase == CatalogLoadPhase.LOADING,
            error = if (viewModel.catalogPhase == CatalogLoadPhase.FAILED) viewModel.catalogError else null,
            onRetry = viewModel::retryCatalog,
            onCancel = onCancel,
            onConfirm = { selection ->
                onConfirm(selection, null)
            },
            toSelection = { aircraftSelection(it) },
            onRecord = { record -> onConfirm(aircraftSelection(record), linkedManufacturerSelection(record)) },
            row = { record ->
                CatalogResultText(
                    record.displayName,
                    CatalogPresentation.aircraftSubtitle(record),
                    listOf(aircraftKindLabel(record.entryKind)),
                    "${record.displayName}, ${CatalogPresentation.aircraftSubtitle(record)}",
                )
            },
            header = {
                if (manufacturerName != null) {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 4.dp)) {
                        Column(Modifier.weight(1f)) {
                            Text("Search all manufacturers", fontWeight = FontWeight.Medium)
                            Text(
                                if (entire) "Results are from the full catalog." else "Results prefer $manufacturerName.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(checked = entire, onCheckedChange = { entire = it })
                    }
                }
            },
        )
}

@Composable
fun AirportPicker(
    viewModel: TailTagViewModel,
    current: AviationSelection,
    onConfirm: (AviationSelection) -> Unit,
    onCancel: () -> Unit,
) {
    val model = remember { QueryModel<AviationAirport>() }
    BindQuery(model, viewModel.catalogPhase) { query, limit -> viewModel.searchAirports(query, limit) }
    RecordPicker(
        title = "Location / Airport",
        prompt = "Airport, city, ICAO, IATA, or ident",
        current = current,
        placeholder = "No location",
        model = model,
        key = { it.id },
        ambiguous = if (model.ambiguous) "Several places match this code. Choose the specific one." else null,
        empty = "No airports match. A street, park, or airshow can be saved as custom text.",
        absentTitle = null,
        loading = viewModel.catalogPhase == CatalogLoadPhase.LOADING,
        error = if (viewModel.catalogPhase == CatalogLoadPhase.FAILED) viewModel.catalogError else null,
        onRetry = viewModel::retryCatalog,
        onCancel = onCancel,
        onConfirm = onConfirm,
        toSelection = { airport ->
            AviationSelection.catalog(
                airport.id,
                CatalogPresentation.airportSnapshot(airport),
                if (CatalogPresentation.isClosedAirport(airport)) "Closed" else null,
            )
        },
        row = { airport ->
            CatalogResultText(
                airport.name,
                CatalogPresentation.airportSubtitle(airport),
                if (CatalogPresentation.isClosedAirport(airport)) listOf("Closed") else emptyList(),
                CatalogPresentation.airportAccessibilityLabel(airport),
            )
        },
    )
}

@Composable
private fun <T> RecordPicker(
    title: String,
    prompt: String,
    current: AviationSelection,
    placeholder: String,
    model: QueryModel<T>,
    key: (T) -> String,
    ambiguous: String?,
    empty: String,
    absentTitle: String?,
    loading: Boolean,
    error: String?,
    onRetry: () -> Unit,
    onCancel: () -> Unit,
    onConfirm: (AviationSelection) -> Unit,
    toSelection: (T) -> AviationSelection,
    onRecord: ((T) -> Unit)? = null,
    header: @Composable () -> Unit = {},
    row: @Composable (T) -> Unit,
) {
    val custom = AviationSelection.custom(model.query)
    val actions = buildList {
        if (custom != null) add(PickerAction("custom", "Use \"${custom.displayText}\"", "Save this text without a catalog record"))
        add(PickerAction("unknown", "Unknown", "Mark this as not known"))
        if (absentTitle != null) add(PickerAction("absent", absentTitle, "Leave this blank"))
    }
    val selected = model.special ?: model.selectedKey
    AviationSearchPicker(
        title = title,
        searchQuery = model.query,
        onQueryChange = {
            model.query = it
            model.limit = 20
            model.selectedKey = null
            model.special = null
            model.customSelected = false
        },
        searchPrompt = prompt,
        currentSummary = com.josh.tailtag.aviation.entry.selectionSummary(current, placeholder),
        guidance = catalogQueryGuidance(model.query),
        results = model.records,
        resultKey = key,
        isLoadingCatalog = loading,
        isSearching = model.searching,
        errorMessage = error,
        ambiguousMessage = ambiguous,
        emptyMessage = empty,
        canLoadMore = model.canLoadMore,
        actions = actions,
        selectedKey = selected,
        onSelectResult = {
            model.selectedKey = key(it)
            model.special = null
        },
        onSelectAction = { action ->
            model.special = action.id
            model.selectedKey = null
        },
        onLoadMore = { model.limit += 20 },
        onRetry = onRetry,
        onUse = {
            when (model.special) {
                "custom" -> AviationSelection.custom(model.query)?.let(onConfirm)
                "unknown" -> onConfirm(AviationSelection.unknown())
                "absent" -> onConfirm(AviationSelection.absent)
                else -> {
                    val id = model.selectedKey ?: return@AviationSearchPicker
                    val record = model.records.firstOrNull { key(it) == id } ?: return@AviationSearchPicker
                    if (onRecord != null) onRecord(record) else onConfirm(toSelection(record))
                }
            }
        },
        onCancel = onCancel,
        useEnabled = model.special != null || model.selectedKey != null,
        header = header,
        row = row,
    )
}

@Composable
fun ClassificationPicker(
    title: String,
    description: String,
    options: List<String>,
    labels: Map<String, String>,
    descriptions: Map<String, String>,
    selectedId: String?,
    note: String?,
    onConfirm: (String?, String?) -> Unit,
    onCancel: () -> Unit,
) {
    var draft by remember { mutableStateOf(selectedId) }
    var draftNote by remember { mutableStateOf(note.orEmpty()) }
    var chose by remember { mutableStateOf(selectedId != null) }
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
        Column {
            Row(Modifier.fillMaxWidth().padding(8.dp)) {
                TextButton(onClick = onCancel) { Text("Cancel") }
                Text(title, modifier = Modifier.weight(1f), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                TextButton(onClick = { onConfirm(draft, draftNote) }, enabled = chose) { Text("Use") }
            }
            LazyColumn {
                item { Text(description, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp), color = MaterialTheme.colorScheme.onSurfaceVariant) }
                items(options) { id ->
                    Row(
                        Modifier.fillMaxWidth().clickable {
                            draft = id
                            chose = true
                            if (id != "other") draftNote = ""
                        }.padding(horizontal = 20.dp, vertical = 12.dp).semantics { role = Role.Button },
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(labels[id] ?: id, fontWeight = FontWeight.Medium)
                            descriptions[id]?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                        }
                        if (draft == id && chose) Icon(Icons.Default.CheckCircle, "Selected", tint = MaterialTheme.colorScheme.primary)
                    }
                    HorizontalDivider()
                }
                item {
                    TextButton(onClick = { draft = null; draftNote = ""; chose = true }) { Text("Clear selection") }
                }
                if (draft == "other") {
                    item {
                        OutlinedTextField(
                            value = draftNote,
                            onValueChange = { draftNote = it },
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp),
                            label = { Text("Describe it") },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ClassificationRow(title: String, value: String, onClick: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 10.dp).semantics { role = Role.Button },
    ) {
        Text(title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodyLarge)
    }
}

@Composable
private fun CatalogResultText(title: String, subtitle: String, badges: List<String>, accessibility: String) {
    Column(Modifier.semantics { contentDescription = accessibility }) {
        Text(title, fontWeight = FontWeight.Medium)
        if (badges.isNotEmpty()) {
            Text(badges.joinToString(" · "), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
        }
        if (subtitle.isNotEmpty()) {
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
