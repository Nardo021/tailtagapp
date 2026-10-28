package com.josh.tailtag.aviation.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.clickable
import com.josh.tailtag.aviation.entry.AviationSelection
import com.josh.tailtag.aviation.entry.AviationSelectionKind
import com.josh.tailtag.aviation.entry.CatalogQueryGuidance
import com.josh.tailtag.aviation.entry.selectionCaption
import com.josh.tailtag.aviation.entry.selectionSummary

data class PickerAction(val id: String, val title: String, val subtitle: String)

@Composable
fun <T> AviationSearchPicker(
    title: String,
    searchQuery: String,
    onQueryChange: (String) -> Unit,
    searchPrompt: String,
    currentSummary: String,
    guidance: CatalogQueryGuidance,
    results: List<T>,
    resultKey: (T) -> String,
    isLoadingCatalog: Boolean,
    isSearching: Boolean,
    errorMessage: String?,
    ambiguousMessage: String?,
    emptyMessage: String,
    canLoadMore: Boolean,
    actions: List<PickerAction>,
    selectedKey: String?,
    onSelectResult: (T) -> Unit,
    onSelectAction: (PickerAction) -> Unit,
    onLoadMore: () -> Unit,
    onRetry: () -> Unit,
    onUse: () -> Unit,
    onCancel: () -> Unit,
    useEnabled: Boolean,
    header: @Composable () -> Unit = {},
    row: @Composable (T) -> Unit,
) {
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
        Column(Modifier.fillMaxSize()) {
            Row(
                Modifier.fillMaxWidth().padding(start = 12.dp, end = 8.dp, top = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(onClick = onCancel) { Text("Cancel") }
                Text(
                    title,
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                TextButton(onClick = onUse, enabled = useEnabled) { Text("Use") }
            }
            Column(Modifier.padding(horizontal = 20.dp)) {
                Text("Current", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(currentSummary, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
                Spacer(Modifier.height(8.dp))
                androidx.compose.material3.OutlinedTextField(
                    value = searchQuery,
                    onValueChange = onQueryChange,
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text(searchPrompt) },
                    singleLine = true,
                    label = { Text(searchPrompt) },
                )
            }
            if (isSearching) {
                LinearProgressIndicator(Modifier.fillMaxWidth().padding(top = 8.dp))
            }
            LazyColumn(Modifier.weight(1f).padding(top = 8.dp)) {
                item { header() }
                items(actions, key = { it.id }) { action ->
                    PickerChoiceRow(action.title, action.subtitle, selectedKey == action.id) { onSelectAction(action) }
                }
                item {
                    Text(
                        "Catalog",
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
                when (guidance) {
                    CatalogQueryGuidance.PROMPT -> item { StatusText("Search by name, alias, or code.") }
                    CatalogQueryGuidance.TOO_SHORT -> item { StatusText("Enter at least two characters.") }
                    CatalogQueryGuidance.READY -> {
                        if (errorMessage != null && results.isEmpty()) {
                            item {
                                Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
                                    Text(errorMessage)
                                    TextButton(onClick = onRetry) { Text("Try again") }
                                }
                            }
                        } else if (isLoadingCatalog && results.isEmpty()) {
                            item {
                                Row(Modifier.padding(20.dp), verticalAlignment = Alignment.CenterVertically) {
                                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                                    Spacer(Modifier.width(10.dp))
                                    Text("Loading the aviation catalog", color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        } else if (results.isEmpty() && !isSearching) {
                            item { StatusText(emptyMessage) }
                        } else {
                            if (ambiguousMessage != null) {
                                item { StatusText(ambiguousMessage) }
                            }
                            items(results, key = resultKey) { record ->
                                Row(
                                    Modifier
                                        .fillMaxWidth()
                                        .clickable { onSelectResult(record) }
                                        .padding(horizontal = 20.dp, vertical = 10.dp)
                                        .semantics { role = Role.Button },
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Column(Modifier.weight(1f)) { row(record) }
                                    if (selectedKey == resultKey(record)) {
                                        Icon(Icons.Default.CheckCircle, "Selected", tint = MaterialTheme.colorScheme.primary)
                                    }
                                }
                                HorizontalDivider(Modifier.padding(start = 20.dp))
                            }
                            if (canLoadMore) {
                                item {
                                    TextButton(onClick = onLoadMore, modifier = Modifier.padding(horizontal = 12.dp)) {
                                        Text("Show more results")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun SelectionValueRow(title: String, selection: AviationSelection, placeholder: String, onClick: () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp)
            .semantics { role = Role.Button },
    ) {
        Text(title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(
                    selectionSummary(selection, placeholder),
                    style = MaterialTheme.typography.bodyLarge,
                    color = if (selection.kind == AviationSelectionKind.ABSENT) {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    } else {
                        MaterialTheme.colorScheme.onSurface
                    },
                )
                selectionCaption(selection)?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Icon(Icons.Default.ChevronRight, null, tint = MaterialTheme.colorScheme.primary)
        }
    }
}

@Composable
private fun PickerChoiceRow(title: String, subtitle: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 12.dp)
            .semantics { role = Role.Button },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.Medium)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (selected) Icon(Icons.Default.CheckCircle, "Selected", tint = MaterialTheme.colorScheme.primary)
    }
}

@Composable
private fun StatusText(text: String) {
    Text(
        text,
        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}
