package com.josh.tailtag

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AirplanemodeActive
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Brightness6
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Flight
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Numbers
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Sort
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.automirrored.filled.Notes
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.TimeInput
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.lifecycle.viewmodel.compose.viewModel
import com.josh.tailtag.data.AircraftTextDetector
import com.josh.tailtag.model.SortOption
import com.josh.tailtag.model.SpottingEntry
import com.josh.tailtag.model.sortedByOption
import com.josh.tailtag.ui.AccentOption
import com.josh.tailtag.ui.TailTagTheme
import com.josh.tailtag.ui.accentColor
import com.josh.tailtag.ui.accentOptions
import com.josh.tailtag.data.SaveResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.DateFormat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val viewModel: TailTagViewModel = viewModel()
            TailTagTheme(viewModel) { TailTagApp(viewModel) }
        }
    }
}

private enum class AppTab { RECENT, SEARCH, SETTINGS }

private data class EditorMode(val entry: SpottingEntry?)

@Composable
private fun TailTagApp(viewModel: TailTagViewModel) {
    if (!viewModel.hasCompletedOnboarding) {
        OnboardingScreen(viewModel)
        return
    }

    var selectedTab by rememberSaveable { mutableStateOf(AppTab.RECENT.name) }
    var searchText by rememberSaveable { mutableStateOf("") }
    var sortOption by remember { mutableStateOf(SortOption.DATE_NEWEST) }
    var selectedEntry by remember { mutableStateOf<SpottingEntry?>(null) }
    var editorMode by remember { mutableStateOf<EditorMode?>(null) }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        bottomBar = {
            NavigationBar(
                windowInsets = WindowInsets.navigationBars,
                containerColor = MaterialTheme.colorScheme.surface,
                tonalElevation = 3.dp,
            ) {
                NavigationBarItem(
                    selected = selectedTab == AppTab.RECENT.name,
                    onClick = { selectedTab = AppTab.RECENT.name },
                    icon = { Icon(Icons.Default.AccessTime, contentDescription = null) },
                    label = { Text("Recent") },
                )
                NavigationBarItem(
                    selected = selectedTab == AppTab.SEARCH.name,
                    onClick = { selectedTab = AppTab.SEARCH.name },
                    icon = { Icon(Icons.Default.Search, contentDescription = null) },
                    label = { Text("Search") },
                )
                NavigationBarItem(
                    selected = selectedTab == AppTab.SETTINGS.name,
                    onClick = { selectedTab = AppTab.SETTINGS.name },
                    icon = { Icon(Icons.Default.Settings, contentDescription = null) },
                    label = { Text("Settings") },
                )
            }
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            viewModel.storageProblem?.let { problem ->
                StorageProblemBanner(
                    problem = problem,
                    onRetry = viewModel::retryLoad,
                    onRestore = viewModel::restoreBackup,
                )
            }
            when (selectedTab) {
                AppTab.SEARCH.name -> SearchScreen(
                    entries = viewModel.entries,
                    searchText = searchText,
                    onSearchTextChanged = { searchText = it },
                    sortOption = sortOption,
                    onSortChanged = { sortOption = it },
                    onAdd = { editorMode = EditorMode(null) },
                    onEntrySelected = { selectedEntry = it },
                    isLoading = viewModel.isLoadingEntries,
                    recordsUnreadable = viewModel.storageProblem != null,
                    modifier = Modifier.weight(1f),
                )
                AppTab.SETTINGS.name -> SettingsScreen(viewModel, Modifier.weight(1f))
                else -> RecentScreen(
                    entries = viewModel.entries,
                    sortOption = sortOption,
                    onSortChanged = { sortOption = it },
                    onAdd = { editorMode = EditorMode(null) },
                    onEntrySelected = { selectedEntry = it },
                    isLoading = viewModel.isLoadingEntries,
                    recordsUnreadable = viewModel.storageProblem != null,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }

    selectedEntry?.let { entry ->
        DetailDialog(
            entry = entry,
            viewModel = viewModel,
            onDismiss = { selectedEntry = null },
            onEdit = {
                selectedEntry = null
                editorMode = EditorMode(entry)
            },
        )
    }

    editorMode?.let { mode ->
        EntryEditorDialog(
            existing = mode.entry,
            viewModel = viewModel,
            onDismiss = { editorMode = null },
            onSaved = { editorMode = null },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RecentScreen(
    entries: List<SpottingEntry>,
    sortOption: SortOption,
    onSortChanged: (SortOption) -> Unit,
    onAdd: () -> Unit,
    onEntrySelected: (SpottingEntry) -> Unit,
    isLoading: Boolean = false,
    recordsUnreadable: Boolean = false,
    modifier: Modifier = Modifier,
) {
    var showSortMenu by remember { mutableStateOf(false) }
    Column(modifier.fillMaxSize()) {
        TopAppBar(
            title = { Text("TailTag", fontWeight = FontWeight.Bold) },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            actions = {
                Box {
                    FilledTonalIconButton(
                        onClick = { showSortMenu = true },
                        shape = CircleShape,
                    ) { Icon(Icons.AutoMirrored.Filled.Sort, "Sort") }
                    SortMenu(showSortMenu, sortOption, onSortChanged) { showSortMenu = false }
                }
                FilledIconButton(
                    onClick = onAdd,
                    modifier = Modifier.padding(end = 12.dp),
                    shape = CircleShape,
                    colors = IconButtonDefaults.filledIconButtonColors(
                        containerColor = MaterialTheme.colorScheme.primary,
                        contentColor = MaterialTheme.colorScheme.onPrimary,
                    ),
                ) { Icon(Icons.Default.Add, "Add aircraft") }
            },
        )
        if (isLoading) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        } else if (recordsUnreadable && entries.isEmpty()) {
            UnreadableRecords()
        } else if (entries.isEmpty()) {
            EmptyState(onAdd)
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(top = 8.dp, bottom = 32.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                item {
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = 20.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("Aircraft", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.weight(1f))
                        Text(sortOption.label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                items(entries.sortedByOption(sortOption), key = { it.id }) { entry ->
                    SpottingCard(entry, onClick = { onEntrySelected(entry) })
                }
            }
        }
    }
}

@Composable
private fun EmptyState(onAdd: () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(Icons.Default.Flight, null, Modifier.size(86.dp), tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.5f))
        Spacer(Modifier.height(20.dp))
        Text("No aircraft yet", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(8.dp))
        Text("Start your logbook by adding your first aircraft sighting.", textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(22.dp))
        Button(onClick = onAdd, shape = RoundedCornerShape(14.dp)) {
            Icon(Icons.Default.Add, null, Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text("Add first aircraft")
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SortMenu(
    expanded: Boolean,
    selected: SortOption,
    onSelected: (SortOption) -> Unit,
    onDismiss: () -> Unit,
) {
    if (!expanded) return

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        containerColor = MaterialTheme.colorScheme.surface,
        tonalElevation = 2.dp,
        dragHandle = { BottomSheetDefaults.DragHandle() },
    ) {
        Column(Modifier.padding(bottom = 12.dp)) {
            Text(
                "Sort by",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(start = 24.dp, top = 4.dp, bottom = 8.dp),
            )
            SortOption.entries.forEach { option ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onSelected(option); onDismiss() }
                        .padding(horizontal = 16.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RadioButton(
                        selected = option == selected,
                        onClick = { onSelected(option); onDismiss() },
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(option.label, style = MaterialTheme.typography.bodyLarge)
                }
            }
        }
    }
}

@Composable
private fun SpottingCard(entry: SpottingEntry, onClick: () -> Unit) {
    val accent = MaterialTheme.colorScheme.primary
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        shape = RoundedCornerShape(20.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
    ) {
        Box(Modifier.fillMaxWidth().height(200.dp)) {
            if (entry.photos.firstOrNull() != null) {
                PhotoImage(entry.photos.first(), Modifier.fillMaxSize())
            } else {
                Box(Modifier.fillMaxSize().background(Brush.linearGradient(listOf(accent.copy(alpha = 0.3f), accent.copy(alpha = 0.75f)))))
                Icon(Icons.Default.Flight, null, Modifier.align(Alignment.Center).size(64.dp), tint = Color.White.copy(alpha = 0.75f))
            }
            Box(
                Modifier.fillMaxWidth().align(Alignment.BottomCenter).height(118.dp)
                    .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.78f)))),
            )
            Row(
                Modifier.fillMaxWidth().padding(16.dp).align(Alignment.TopEnd),
                horizontalArrangement = Arrangement.End,
            ) {
                if (entry.photos.size > 1) Badge(entry.photos.size.toString(), Icons.Default.PhotoLibrary)
                entry.aircraftType?.takeIf { it.isNotBlank() }?.let { Badge(it) }
            }
            Column(Modifier.align(Alignment.BottomStart).padding(horizontal = 20.dp, vertical = 16.dp)) {
                Text(entry.registration, color = Color.White, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Text(entry.airline, color = Color.White.copy(alpha = 0.9f), style = MaterialTheme.typography.titleMedium)
                Text(formatCardDate(entry.timestamp), color = Color.White.copy(alpha = 0.8f), style = MaterialTheme.typography.labelMedium)
            }
        }
    }
}

@Composable
private fun Badge(text: String, icon: androidx.compose.ui.graphics.vector.ImageVector? = null) {
    Surface(color = Color.Black.copy(alpha = 0.52f), shape = RoundedCornerShape(8.dp), modifier = Modifier.padding(start = 8.dp)) {
        Row(Modifier.padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            icon?.let { Icon(it, null, Modifier.size(15.dp), tint = Color.White) }
            if (icon != null) Spacer(Modifier.width(5.dp))
            Text(text, color = Color.White, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.labelMedium)
        }
    }
}

@Composable
private fun UnreadableRecords() {
    Column(
        Modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text("Records unavailable", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(8.dp))
        Text(
            "Saved aircraft records could not be read. They were not replaced with an empty log.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun StorageProblemBanner(
    problem: StorageProblem,
    onRetry: () -> Unit,
    onRestore: () -> Unit,
) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
        Text(problem.message, color = MaterialTheme.colorScheme.error)
        Row {
            TextButton(onClick = onRetry) { Text("Retry") }
            if (problem.canRestoreBackup) {
                TextButton(onClick = onRestore) { Text("Restore backup") }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SearchScreen(
    entries: List<SpottingEntry>,
    searchText: String,
    onSearchTextChanged: (String) -> Unit,
    sortOption: SortOption,
    onSortChanged: (SortOption) -> Unit,
    onAdd: () -> Unit,
    onEntrySelected: (SpottingEntry) -> Unit,
    isLoading: Boolean = false,
    recordsUnreadable: Boolean = false,
    modifier: Modifier = Modifier,
) {
    var showSortMenu by remember { mutableStateOf(false) }
    val filtered = entries.filter { entry ->
        listOf(entry.registration, entry.airline, entry.location, entry.aircraftType.orEmpty())
            .any { it.contains(searchText, ignoreCase = true) }
    }.sortedByOption(sortOption)
    Column(modifier.fillMaxSize()) {
        TopAppBar(
            title = { Text("Search") },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            actions = {
                Box {
                    FilledTonalIconButton(
                        onClick = { showSortMenu = true },
                        modifier = Modifier.padding(end = 12.dp),
                        shape = CircleShape,
                    ) { Icon(Icons.AutoMirrored.Filled.Sort, "Sort") }
                    SortMenu(showSortMenu, sortOption, onSortChanged) { showSortMenu = false }
                }
            },
        )
        TextField(
            value = searchText,
            onValueChange = onSearchTextChanged,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            placeholder = { Text("Search aircraft, airlines, places...") },
            leadingIcon = { Icon(Icons.Default.Search, null) },
            trailingIcon = { if (searchText.isNotEmpty()) IconButton({ onSearchTextChanged("") }) { Icon(Icons.Default.Close, "Clear") } },
            singleLine = true,
            shape = RoundedCornerShape(16.dp),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
            ),
        )
        Spacer(Modifier.height(8.dp))
        if (isLoading) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        } else if (recordsUnreadable && entries.isEmpty()) {
            UnreadableRecords()
        } else if (entries.isEmpty()) {
            EmptyState(onAdd)
        } else if (searchText.isNotBlank() && filtered.isEmpty()) {
            NoResults(searchText)
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(top = 20.dp, bottom = 32.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                if (searchText.isNotBlank()) {
                    item {
                        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text("Results for \"$searchText\"", color = MaterialTheme.colorScheme.onSurfaceVariant, fontWeight = FontWeight.SemiBold)
                            Spacer(Modifier.weight(1f))
                            Text(filtered.size.toString(), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                items(filtered, key = { it.id }) { entry -> SpottingCard(entry) { onEntrySelected(entry) } }
            }
        }
    }
}

@Composable
private fun NoResults(query: String) {
    Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Icon(Icons.Default.Search, null, Modifier.size(64.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(16.dp))
        Text("No results", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(8.dp))
        Text("No spottings match \"$query\"", color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun SettingsScreen(viewModel: TailTagViewModel, modifier: Modifier = Modifier) {
    var showResetConfirmation by remember { mutableStateOf(false) }
    var resetInProgress by remember { mutableStateOf(false) }
    var resetErrorMessage by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    LazyColumn(modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 32.dp)) {
        item {
            TopAppBar(
                title = { Text("Settings") },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        }
        item {
            Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp)) {
                Text("Accent color", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(12.dp))
                AccentColorGrid(viewModel)
                Spacer(Modifier.height(22.dp))
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                Spacer(Modifier.height(18.dp))
                Text("Color scheme", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(12.dp))
                ColorSchemePicker(viewModel)
            }
        }
        item { SettingsSectionTitle("App") }
        item {
            SettingsRow(
                icon = { Icon(Icons.Default.Email, null) },
                title = "Need Help?",
                onClick = {
                    runCatching {
                        context.startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:joshcumulus@proton.me?subject=TailTag%20App%20Support")))
                    }
                },
                trailing = { Icon(Icons.Default.ArrowUpward, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) },
            )
        }
        item {
            SettingsRow(
                icon = { Icon(Icons.Default.PlayCircle, null) },
                title = "Replay Onboarding",
                onClick = viewModel::replayOnboarding,
            )
        }
        item {
            SettingsRow(
                icon = { Icon(Icons.Default.Refresh, null, tint = MaterialTheme.colorScheme.error) },
                title = "Reset App",
                titleColor = MaterialTheme.colorScheme.error,
                onClick = { showResetConfirmation = true },
            )
        }
        item { SettingsSectionTitle("About") }
        item {
            SettingsRow(
                icon = { Icon(Icons.Default.Info, null) },
                title = "Version",
                subtitle = "1.0.0",
                onClick = null,
            )
        }
        item {
            SettingsRow(
                icon = { Icon(Icons.Default.Language, null) },
                title = "TailTag website",
                onClick = {
                    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://appsbyjosh.com/tailtag.html"))) }
                },
                trailing = { Icon(Icons.Default.ArrowUpward, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) },
            )
        }
    }

    if (showResetConfirmation) {
        AlertDialog(
            onDismissRequest = { showResetConfirmation = false },
            title = { Text("Reset all settings") },
            text = { Text("This will reset all app settings to their defaults and clear all spotting data. This action cannot be undone.") },
            dismissButton = { TextButton(onClick = { if (!resetInProgress) showResetConfirmation = false }) { Text("Cancel") } },
            confirmButton = {
                TextButton(
                    enabled = !resetInProgress,
                    onClick = {
                        if (resetInProgress) return@TextButton
                        resetInProgress = true
                        scope.launch {
                            val result = viewModel.resetApp()
                            resetInProgress = false
                            showResetConfirmation = false
                            if (result is SaveResult.Failed) resetErrorMessage = result.message
                            if (result is SaveResult.SavedWithCleanupFailure) resetErrorMessage = result.message
                        }
                    },
                ) {
                    Text(if (resetInProgress) "Resetting" else "Reset", color = MaterialTheme.colorScheme.error)
                }
            },
        )
    }
    resetErrorMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { resetErrorMessage = null },
            title = { Text("Reset incomplete") },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { resetErrorMessage = null }) { Text("OK") } },
        )
    }
}

@Composable
private fun SettingsSectionTitle(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp),
    )
}

@Composable
private fun SettingsRow(
    icon: @Composable () -> Unit,
    title: String,
    subtitle: String? = null,
    titleColor: Color = MaterialTheme.colorScheme.onSurface,
    onClick: (() -> Unit)?,
    trailing: @Composable (() -> Unit)? = null,
) {
    Row(
        modifier = Modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable { onClick() } else Modifier).padding(horizontal = 20.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Surface(color = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f), contentColor = MaterialTheme.colorScheme.primary, shape = RoundedCornerShape(11.dp), modifier = Modifier.size(38.dp)) {
            Box(contentAlignment = Alignment.Center) { icon() }
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(title, color = titleColor, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
            subtitle?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        trailing?.invoke()
    }
}

@Composable
private fun AccentColorGrid(viewModel: TailTagViewModel) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        accentOptions.chunked(5).forEach { row ->
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly,
            ) {
                row.forEach { option ->
                    val selected = option.id == viewModel.accentName
                    Box(
                        modifier = Modifier
                            .size(52.dp)
                            .clip(CircleShape)
                            .selectable(
                                selected = selected,
                                onClick = { viewModel.setAccent(option.id) },
                                role = Role.RadioButton,
                            )
                            .semantics { contentDescription = option.name },
                        contentAlignment = Alignment.Center,
                    ) {
                        Box(
                            modifier = Modifier
                                .size(44.dp)
                                .shadow(3.dp, CircleShape)
                                .clip(CircleShape)
                                .background(option.color),
                            contentAlignment = Alignment.Center,
                        ) {
                            if (selected) {
                                Surface(color = Color.White, shape = CircleShape, modifier = Modifier.size(22.dp)) {
                                    Icon(Icons.Default.Check, null, tint = option.color, modifier = Modifier.padding(3.dp))
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
private fun ColorSchemePicker(viewModel: TailTagViewModel) {
    Row(
        Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.72f))
            .padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        listOf("system" to "System", "light" to "Light", "dark" to "Dark").forEach { (id, label) ->
            val selected = viewModel.colorScheme == id
            Surface(
                modifier = Modifier.weight(1f).clip(RoundedCornerShape(11.dp)).clickable { viewModel.setColorScheme(id) },
                color = if (selected) MaterialTheme.colorScheme.primary else Color.Transparent,
                shape = RoundedCornerShape(11.dp),
            ) {
                Row(
                    Modifier.padding(vertical = 10.dp),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        when (id) { "light" -> Icons.Default.LightMode; "dark" -> Icons.Default.DarkMode; else -> Icons.Default.Brightness6 },
                        null,
                        Modifier.size(18.dp),
                        tint = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(label, style = MaterialTheme.typography.labelMedium, color = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface)
                }
            }
        }
    }
}

@Composable
private fun OnboardingScreen(viewModel: TailTagViewModel) {
    var page by rememberSaveable { mutableIntStateOf(0) }
    val accent = MaterialTheme.colorScheme.primary
    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 30.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
            when (page) {
                0 -> WelcomePage()
                1 -> AccentPage(viewModel)
                else -> GettingStartedPage(accent)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(bottom = 20.dp)) {
            repeat(3) { index ->
                Box(Modifier.size(if (index == page) 22.dp else 8.dp, 8.dp).clip(RoundedCornerShape(8.dp)).background(if (index == page) accent else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f)))
            }
        }
        Button(
            onClick = { if (page < 2) page++ else viewModel.completeOnboarding() },
            modifier = Modifier.fillMaxWidth().height(56.dp),
            shape = RoundedCornerShape(16.dp),
            colors = ButtonDefaults.buttonColors(containerColor = accent),
        ) {
            Text(if (page == 0) "Get started" else if (page == 2) "Start spotting" else "Continue", fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun WelcomePage() {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        androidx.compose.foundation.Image(
            painter = painterResource(com.josh.tailtag.R.drawable.tailtag_logo),
            contentDescription = "TailTag app icon",
            modifier = Modifier.size(132.dp).clip(RoundedCornerShape(28.dp)),
            contentScale = ContentScale.Crop,
        )
        Spacer(Modifier.height(30.dp))
        Text("Welcome to TailTag", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(8.dp))
        Text("Your digital planespotting logbook", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
    }
}

@Composable
private fun AccentPage(viewModel: TailTagViewModel) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text("Choose your style", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Text("Pick an accent color that you like", color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        Spacer(Modifier.height(32.dp))
        AccentColorGrid(viewModel)
    }
}

@Composable
private fun GettingStartedPage(accent: Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Default.Flight, null, Modifier.size(86.dp), tint = accent)
        Spacer(Modifier.height(28.dp))
        Text("Ready to start spotting", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
        Spacer(Modifier.height(10.dp))
        Text("Here's how to get started:", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(26.dp))
        OnboardingStep(Icons.Default.CameraAlt, "Spot an aircraft", "Take a photo when you see an interesting aircraft", accent)
        OnboardingStep(Icons.Default.Add, "Tap the + button", "Add aircraft details like registration and airline", accent)
        OnboardingStep(Icons.AutoMirrored.Filled.MenuBook, "Build your logbook", "View your collection in Recent or search for specific aircraft", accent)
    }
}

@Composable
private fun OnboardingStep(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, description: String, accent: Color) {
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.Top) {
        Icon(icon, null, Modifier.size(30.dp), tint = accent)
        Spacer(Modifier.width(16.dp))
        Column {
            Text(title, fontWeight = FontWeight.SemiBold)
            Text(description, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DetailDialog(
    entry: SpottingEntry,
    viewModel: TailTagViewModel,
    onDismiss: () -> Unit,
    onEdit: () -> Unit,
) {
    var showMenu by remember { mutableStateOf(false) }
    var showDeleteConfirmation by remember { mutableStateOf(false) }
    var deleteInProgress by remember { mutableStateOf(false) }
    var deleteErrorMessage by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val sheetHeight = with(LocalDensity.current) {
        LocalWindowInfo.current.containerSize.height.toDp() * 0.77f
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        containerColor = MaterialTheme.colorScheme.surface,
        tonalElevation = 2.dp,
        dragHandle = { BottomSheetDefaults.DragHandle() },
    ) {
        Column(Modifier.fillMaxWidth().height(sheetHeight)) {
            Row(
                Modifier.fillMaxWidth().padding(start = 20.dp, end = 8.dp, top = 4.dp, bottom = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Aircraft details",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = onDismiss) { Text("Done") }
                Box {
                    IconButton(onClick = { showMenu = true }) { Icon(Icons.Default.MoreVert, "More") }
                }
            }
            LazyColumn(
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(bottom = 28.dp),
            ) {
                item {
                    if (entry.photos.isNotEmpty()) {
                        val pagerState = rememberPagerState(pageCount = { entry.photos.size })
                        Column(
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 20.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            HorizontalPager(
                                state = pagerState,
                                modifier = Modifier.fillMaxWidth().aspectRatio(16f / 9f),
                            ) { page ->
                                PhotoImage(
                                    entry.photos[page],
                                    Modifier.fillMaxSize().clip(RoundedCornerShape(20.dp)),
                                    ContentScale.Crop,
                                )
                            }
                            if (entry.photos.size > 1) {
                                Row(
                                    modifier = Modifier.padding(top = 10.dp),
                                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    repeat(entry.photos.size) { index ->
                                        Box(
                                            Modifier
                                                .size(if (index == pagerState.currentPage) 18.dp else 6.dp, 6.dp)
                                                .clip(CircleShape)
                                                .background(
                                                    if (index == pagerState.currentPage) MaterialTheme.colorScheme.primary
                                                    else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.35f),
                                                ),
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                    item {
                        Card(
                            Modifier.fillMaxWidth().padding(horizontal = 20.dp),
                            shape = RoundedCornerShape(14.dp),
                            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.42f)),
                        ) {
                            Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
                                DetailRow(Icons.Default.Flight, "Registration", entry.registration)
                                HorizontalDivider(Modifier.padding(start = 44.dp))
                                DetailRow(Icons.Default.AccountBalance, "Airline", entry.airline)
                                HorizontalDivider(Modifier.padding(start = 44.dp))
                                DetailRow(Icons.Default.LocationOn, "Location", entry.location)
                                entry.aircraftType?.takeIf { it.isNotBlank() }?.let {
                                    HorizontalDivider(Modifier.padding(start = 44.dp))
                                    DetailRow(Icons.Default.Flight, "Aircraft type", it)
                                }
                                HorizontalDivider(Modifier.padding(start = 44.dp))
                                DetailRow(Icons.Default.CalendarMonth, "Spotted", formatDetailDate(entry.timestamp))
                                entry.notes?.takeIf { it.isNotBlank() }?.let {
                                    HorizontalDivider(Modifier.padding(start = 44.dp))
                                    DetailRow(Icons.AutoMirrored.Filled.Notes, "Notes", it)
                                }
                            }
                        }
                    }
            }
        }
    }
    if (showMenu) {
        ModalBottomSheet(
            onDismissRequest = { showMenu = false },
            shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
            containerColor = MaterialTheme.colorScheme.surface,
            tonalElevation = 2.dp,
            dragHandle = { BottomSheetDefaults.DragHandle() },
        ) {
            Column(Modifier.padding(bottom = 12.dp)) {
                Text(
                    "Aircraft actions",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(start = 24.dp, top = 4.dp, bottom = 8.dp),
                )
                ActionSheetItem(
                    icon = Icons.Default.Edit,
                    label = "Edit",
                    onClick = { showMenu = false; onEdit() },
                )
                ActionSheetItem(
                    icon = Icons.Default.Delete,
                    label = "Delete",
                    tint = MaterialTheme.colorScheme.error,
                    onClick = { showMenu = false; showDeleteConfirmation = true },
                )
            }
        }
    }
    if (showDeleteConfirmation) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirmation = false },
            title = { Text("Delete spotting") },
            text = { Text("This will permanently delete this spotting. This action cannot be undone.") },
            dismissButton = { TextButton({ if (!deleteInProgress) showDeleteConfirmation = false }) { Text("Cancel") } },
            confirmButton = {
                TextButton(enabled = !deleteInProgress, onClick = {
                    if (deleteInProgress) return@TextButton
                    deleteInProgress = true
                    scope.launch {
                        val result = viewModel.deleteEntry(entry)
                        deleteInProgress = false
                        showDeleteConfirmation = false
                        if (result is SaveResult.Failed) {
                            deleteErrorMessage = result.message
                        } else {
                            onDismiss()
                        }
                    }
                }) {
                    Text(if (deleteInProgress) "Deleting" else "Delete", color = MaterialTheme.colorScheme.error)
                }
            },
        )
    }
    deleteErrorMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { deleteErrorMessage = null },
            title = { Text("Could not delete") },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { deleteErrorMessage = null }) { Text("OK") } },
        )
    }
}

@Composable
private fun ActionSheetItem(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    tint: Color = MaterialTheme.colorScheme.onSurface,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Surface(
            color = tint.copy(alpha = 0.12f),
            contentColor = tint,
            shape = RoundedCornerShape(12.dp),
            modifier = Modifier.size(40.dp),
        ) {
            Box(contentAlignment = Alignment.Center) { Icon(icon, null, Modifier.size(21.dp)) }
        }
        Spacer(Modifier.width(16.dp))
        Text(label, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, color = tint)
    }
}

@Composable
private fun DetailRow(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 13.dp), verticalAlignment = Alignment.Top) {
        Surface(color = MaterialTheme.colorScheme.primaryContainer, contentColor = MaterialTheme.colorScheme.primary, shape = RoundedCornerShape(10.dp), modifier = Modifier.size(34.dp)) {
            Box(contentAlignment = Alignment.Center) { Icon(icon, null, Modifier.size(19.dp)) }
        }
        Spacer(Modifier.width(14.dp))
        Column {
            Text(title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun EntryEditorDialog(
    existing: SpottingEntry?,
    viewModel: TailTagViewModel,
    onDismiss: () -> Unit,
    onSaved: () -> Unit,
) {
    val context = LocalContext.current
    var registration by remember(existing?.id) { mutableStateOf(existing?.registration.orEmpty()) }
    var airline by remember(existing?.id) { mutableStateOf(existing?.airline.orEmpty()) }
    var location by remember(existing?.id) { mutableStateOf(existing?.location.orEmpty()) }
    var aircraftType by remember(existing?.id) { mutableStateOf(existing?.aircraftType.orEmpty()) }
    var notes by remember(existing?.id) { mutableStateOf(existing?.notes.orEmpty()) }
    var timestamp by remember(existing?.id) { mutableLongStateOf(existing?.timestamp ?: System.currentTimeMillis()) }
    var existingPhotos by remember(existing?.id) { mutableStateOf(existing?.photos.orEmpty()) }
    var newUris by remember(existing?.id) { mutableStateOf<List<Uri>>(emptyList()) }
    var dateFromPhoto by remember { mutableStateOf(false) }
    var registrationFromPhoto by remember { mutableStateOf(false) }
    var airlineFromPhoto by remember { mutableStateOf(false) }
    var showDatePicker by remember { mutableStateOf(false) }
    var showTimePicker by remember { mutableStateOf(false) }
    var showDeleteConfirmation by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var saveErrorMessage by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    val photoPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(maxItems = 10)) { uris ->
        val remainingSlots = (10 - existingPhotos.size - newUris.size).coerceAtLeast(0)
        newUris = (newUris + uris).distinct().take(remainingSlots + newUris.size)
    }

    val launchPhotoPicker = {
        photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
    }

    LaunchedEffect(newUris.firstOrNull()) {
        val firstUri = newUris.firstOrNull() ?: return@LaunchedEffect
        if (existingPhotos.isEmpty() && newUris.size == 1) {
            readPhotoDate(context, firstUri)?.let { timestamp = it; dateFromPhoto = true }
            AircraftTextDetector.detect(context, firstUri) { result ->
                if (result.confidence > 0.6f) {
                    if (registration.isBlank() && result.registration != null) {
                        registration = result.registration
                        registrationFromPhoto = true
                    }
                    if (airline.isBlank() && result.airline != null) {
                        airline = result.airline
                        airlineFromPhoto = true
                    }
                }
            }
        }
    }

    val allPhotoCount = existingPhotos.size + newUris.size
    val valid = registration.isNotBlank() && airline.isNotBlank() && location.isNotBlank() && allPhotoCount > 0
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val sheetHeight = with(LocalDensity.current) {
        LocalWindowInfo.current.containerSize.height.toDp() * 0.77f
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        containerColor = MaterialTheme.colorScheme.surface,
        tonalElevation = 2.dp,
        dragHandle = { BottomSheetDefaults.DragHandle() },
    ) {
        Column(Modifier.fillMaxWidth().height(sheetHeight)) {
            Row(
                Modifier.fillMaxWidth().padding(start = 20.dp, end = 8.dp, top = 4.dp, bottom = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    if (existing == null) "Add aircraft" else "Edit entry",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = { if (!saving) onDismiss() }) { Text("Cancel") }
                TextButton(enabled = valid && !saving, onClick = {
                            if (saving) return@TextButton
                            saving = true
                            saveErrorMessage = null
                            scope.launch {
                                val result = if (existing == null) {
                                    viewModel.addEntry(registration, airline, location, aircraftType, notes, timestamp, newUris)
                                } else {
                                    val updated = existing.copy(
                                        registration = registration.trim(),
                                        airline = airline.trim(),
                                        location = location.trim(),
                                        aircraftType = aircraftType.trim().takeUnless(String::isBlank),
                                        notes = notes.trim().takeUnless(String::isBlank),
                                        timestamp = timestamp,
                                    )
                                    viewModel.updateEntry(updated, existingPhotos, newUris)
                                }
                                saving = false
                                when (result) {
                                    is SaveResult.Failed -> saveErrorMessage = result.message
                                    is SaveResult.Saved, is SaveResult.SavedWithCleanupFailure -> onSaved()
                                }
                            }
                        }) { Text(if (saving) "Saving" else "Save") }
            }
            LazyColumn(
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(bottom = 28.dp),
            ) {
                    item {
                        Column(Modifier.padding(horizontal = 16.dp, vertical = 7.dp)) {
                            Text("Photos", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(start = 8.dp, bottom = 9.dp))
                            if (allPhotoCount == 0) {
                                Card(
                                    onClick = launchPhotoPicker,
                                    modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp).height(140.dp),
                                    shape = RoundedCornerShape(15.dp),
                                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.08f)),
                                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.3f)),
                                    elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
                                ) {
                                    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                                        Surface(color = MaterialTheme.colorScheme.primary, shape = CircleShape, modifier = Modifier.size(42.dp)) {
                                            Icon(Icons.Default.CameraAlt, null, tint = MaterialTheme.colorScheme.onPrimary, modifier = Modifier.padding(11.dp))
                                        }
                                        Spacer(Modifier.height(8.dp))
                                        Text("Add photos", fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                                        Text("Choose up to 10 aircraft photos", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                }
                            } else {
                                LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                    itemsIndexed(existingPhotos) { index, path ->
                                        PhotoThumbnail(path, onRemove = if (allPhotoCount > 1) { { existingPhotos = existingPhotos.toMutableList().also { it.removeAt(index) } } } else null)
                                    }
                                    itemsIndexed(newUris) { index, uri ->
                                        UriPhotoThumbnail(uri, onRemove = { newUris = newUris.toMutableList().also { it.removeAt(index) } })
                                    }
                                    item { AddPhotoTile(onClick = launchPhotoPicker) }
                                }
                            }
                        }
                    }
                    item {
                        EditorSectionCard("Aircraft details") {
                            EditorTextField("Registration", registration, { registration = it; registrationFromPhoto = false }, KeyboardCapitalization.Characters, Icons.Default.Numbers)
                            DetectionHint(registrationFromPhoto, "Registration detected from photo")
                            EditorTextField("Airline", airline, { airline = it; airlineFromPhoto = false }, KeyboardCapitalization.Words, Icons.Default.Flight)
                            DetectionHint(airlineFromPhoto, "Airline detected from photo")
                            EditorTextField("Location (e.g., EGLL or Heathrow)", location, { location = it }, KeyboardCapitalization.Characters, Icons.Default.LocationOn)
                            EditorTextField("Aircraft type (optional)", aircraftType, { aircraftType = it }, KeyboardCapitalization.Characters, Icons.Default.Flight)
                        }
                    }
                    item {
                        EditorSectionCard("Additional info") {
                            Row(
                                modifier = Modifier.padding(horizontal = 8.dp),
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                DateTimeChoice(
                                    icon = Icons.Default.CalendarMonth,
                                    label = "Date spotted",
                                    value = formatDateOnly(timestamp),
                                    modifier = Modifier.weight(1f),
                                    onClick = { showDatePicker = true },
                                )
                                DateTimeChoice(
                                    icon = Icons.Default.AccessTime,
                                    label = "Time",
                                    value = formatTimeOnly(timestamp),
                                    modifier = Modifier.weight(1f),
                                    onClick = { showTimePicker = true },
                                )
                            }
                            DetectionHint(dateFromPhoto, "Date automatically set from photo")
                            EditorTextField("Notes (optional)", notes, { notes = it }, KeyboardCapitalization.Sentences, null, minLines = 3)
                        }
                    }
                    if (existing != null) {
                        item {
                            OutlinedButton(
                                onClick = { showDeleteConfirmation = true },
                                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                                colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                            ) {
                                Icon(Icons.Default.Delete, null); Spacer(Modifier.width(8.dp)); Text("Delete spotting")
                            }
                        }
                    }
            }
        }
    }

    if (showDatePicker) {
        val dateState = rememberDatePickerState(initialSelectedDateMillis = timestamp)
        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(onClick = {
                    dateState.selectedDateMillis?.let { timestamp = mergeDate(timestamp, it) }
                    dateFromPhoto = false
                    showDatePicker = false
                }) { Text("Done") }
            },
            dismissButton = { TextButton(onClick = { showDatePicker = false }) { Text("Cancel") } },
        ) { DatePicker(state = dateState, showModeToggle = false) }
    }
    if (showTimePicker) {
        val calendar = Calendar.getInstance().apply { timeInMillis = timestamp }
        val timeState = rememberTimePickerState(
            initialHour = calendar.get(Calendar.HOUR_OF_DAY),
            initialMinute = calendar.get(Calendar.MINUTE),
            is24Hour = android.text.format.DateFormat.is24HourFormat(context),
        )
        Dialog(onDismissRequest = { showTimePicker = false }) {
            Surface(shape = RoundedCornerShape(28.dp), color = MaterialTheme.colorScheme.surface) {
                Column(Modifier.padding(horizontal = 24.dp, vertical = 20.dp)) {
                    Text("Choose time", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.height(8.dp))
                    TimeInput(state = timeState)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        TextButton(onClick = { showTimePicker = false }) { Text("Cancel") }
                        TextButton(onClick = {
                            timestamp = mergeTime(timestamp, timeState.hour, timeState.minute)
                            dateFromPhoto = false
                            showTimePicker = false
                        }) { Text("Done") }
                    }
                }
            }
        }
    }
    if (showDeleteConfirmation && existing != null) {
        AlertDialog(
            onDismissRequest = { if (!saving) showDeleteConfirmation = false },
            title = { Text("Delete spotting") },
            text = { Text("This will permanently delete this spotting. This action cannot be undone.") },
            dismissButton = { TextButton({ if (!saving) showDeleteConfirmation = false }) { Text("Cancel") } },
            confirmButton = {
                TextButton(enabled = !saving, onClick = {
                    val entryToDelete = existing ?: return@TextButton
                    if (saving) return@TextButton
                    saving = true
                    scope.launch {
                        val result = viewModel.deleteEntry(entryToDelete)
                        saving = false
                        showDeleteConfirmation = false
                        if (result is SaveResult.Failed) saveErrorMessage = result.message else onDismiss()
                    }
                }) { Text(if (saving) "Deleting" else "Delete", color = MaterialTheme.colorScheme.error) }
            },
        )
    }
    saveErrorMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { saveErrorMessage = null },
            title = { Text("Could not save") },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { saveErrorMessage = null }) { Text("OK") } },
        )
    }
}

@Composable
private fun EditorSectionCard(title: String, content: @Composable () -> Unit) {
    Column(Modifier.padding(horizontal = 16.dp, vertical = 7.dp)) {
        Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(start = 8.dp, bottom = 9.dp))
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(18.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.28f)),
            elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
        ) {
            Column(Modifier.padding(vertical = 8.dp)) { content() }
        }
    }
}

@Composable
private fun DateTimeChoice(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    value: String,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    Card(
        onClick = onClick,
        modifier = modifier,
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.75f)),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.38f)),
    ) {
        Column(Modifier.padding(horizontal = 12.dp, vertical = 11.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, null, Modifier.size(17.dp), tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(6.dp))
                Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Spacer(Modifier.height(5.dp))
            Text(value, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun EditorTextField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    capitalization: KeyboardCapitalization,
    icon: androidx.compose.ui.graphics.vector.ImageVector?,
    minLines: Int = 1,
) {
    TextField(
        value = value,
        onValueChange = onValueChange,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp),
        label = { Text(label) },
        leadingIcon = icon?.let { iconVector -> { Icon(iconVector, null) } },
        keyboardOptions = KeyboardOptions(capitalization = capitalization),
        minLines = minLines,
        maxLines = if (minLines > 1) 6 else 1,
        shape = RoundedCornerShape(13.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.78f),
            unfocusedContainerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.78f),
            disabledContainerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.55f),
            errorContainerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.78f),
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            disabledIndicatorColor = Color.Transparent,
            errorIndicatorColor = Color.Transparent,
        ),
    )
}

@Composable
private fun DetectionHint(visible: Boolean, text: String) {
    if (visible) {
        Row(Modifier.padding(start = 25.dp, top = 2.dp, bottom = 2.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.CameraAlt, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.width(5.dp))
            Text(text, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun AddPhotoTile(onClick: () -> Unit) {
    Card(onClick = onClick, modifier = Modifier.size(120.dp), shape = RoundedCornerShape(12.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))) {
        Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Icon(Icons.Default.Add, null, Modifier.size(32.dp), tint = MaterialTheme.colorScheme.primary)
            Text("Add", style = MaterialTheme.typography.labelSmall)
        }
    }
}

@Composable
private fun PhotoThumbnail(path: String, onRemove: (() -> Unit)?) {
    Box(Modifier.size(120.dp)) {
        PhotoImage(path, Modifier.fillMaxSize().clip(RoundedCornerShape(12.dp)))
        onRemove?.let { remove ->
            IconButton(onClick = remove, modifier = Modifier.align(Alignment.TopEnd).size(32.dp)) {
                Surface(color = Color.Black.copy(alpha = 0.62f), shape = CircleShape) { Icon(Icons.Default.Close, "Remove", tint = Color.White, modifier = Modifier.padding(4.dp)) }
            }
        }
    }
}

@Composable
private fun UriPhotoThumbnail(uri: Uri, onRemove: () -> Unit) {
    Box(Modifier.size(120.dp)) {
        UriPhotoImage(uri, Modifier.fillMaxSize().clip(RoundedCornerShape(12.dp)))
        IconButton(onClick = onRemove, modifier = Modifier.align(Alignment.TopEnd).size(32.dp)) {
            Surface(color = Color.Black.copy(alpha = 0.62f), shape = CircleShape) { Icon(Icons.Default.Close, "Remove", tint = Color.White, modifier = Modifier.padding(4.dp)) }
        }
    }
}

@Composable
private fun PhotoImage(path: String, modifier: Modifier, contentScale: ContentScale = ContentScale.Crop) {
    val bitmap by produceState<Bitmap?>(initialValue = null, key1 = path) {
        value = withContext(Dispatchers.IO) { BitmapFactory.decodeFile(path) }
    }
    if (bitmap != null) {
        androidx.compose.foundation.Image(bitmap!!.asImageBitmap(), contentDescription = null, modifier = modifier, contentScale = contentScale)
    } else {
        Box(modifier.background(Brush.linearGradient(listOf(MaterialTheme.colorScheme.primary.copy(alpha = 0.25f), MaterialTheme.colorScheme.primary.copy(alpha = 0.55f))))) {
            Icon(Icons.Default.Flight, null, Modifier.align(Alignment.Center).size(44.dp), tint = Color.White.copy(alpha = 0.75f))
        }
    }
}

@Composable
private fun UriPhotoImage(uri: Uri, modifier: Modifier, contentScale: ContentScale = ContentScale.Crop) {
    val context = LocalContext.current
    val bitmap by produceState<Bitmap?>(initialValue = null, key1 = uri) {
        value = withContext(Dispatchers.IO) {
            context.contentResolver.openInputStream(uri)?.use(BitmapFactory::decodeStream)
        }
    }
    if (bitmap != null) {
        androidx.compose.foundation.Image(bitmap!!.asImageBitmap(), contentDescription = null, modifier = modifier, contentScale = contentScale)
    } else {
        Box(modifier.background(MaterialTheme.colorScheme.surfaceVariant))
    }
}

private fun readPhotoDate(context: Context, uri: Uri): Long? = runCatching {
    context.contentResolver.openInputStream(uri)?.use { stream ->
        val exif = androidx.exifinterface.media.ExifInterface(stream)
        val value = exif.getAttribute(androidx.exifinterface.media.ExifInterface.TAG_DATETIME_ORIGINAL)
            ?: exif.getAttribute(androidx.exifinterface.media.ExifInterface.TAG_DATETIME)
        value?.let { SimpleDateFormat("yyyy:MM:dd HH:mm:ss", Locale.US).parse(it)?.time }
    }
}.getOrNull()

private fun formatCardDate(timestamp: Long): String = DateFormat.getDateInstance(DateFormat.SHORT).format(Date(timestamp))

private fun formatDetailDate(timestamp: Long): String = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(timestamp))

private fun formatDateOnly(timestamp: Long): String = SimpleDateFormat("dd MMM yyyy", Locale.getDefault()).format(Date(timestamp))

private fun formatTimeOnly(timestamp: Long): String = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(timestamp))

private fun mergeDate(currentTimestamp: Long, selectedDateMillis: Long): Long {
    val selected = Calendar.getInstance().apply { timeInMillis = selectedDateMillis }
    return Calendar.getInstance().apply {
        timeInMillis = currentTimestamp
        set(Calendar.YEAR, selected.get(Calendar.YEAR))
        set(Calendar.MONTH, selected.get(Calendar.MONTH))
        set(Calendar.DAY_OF_MONTH, selected.get(Calendar.DAY_OF_MONTH))
    }.timeInMillis
}

private fun mergeTime(currentTimestamp: Long, hour: Int, minute: Int): Long = Calendar.getInstance().apply {
    timeInMillis = currentTimestamp
    set(Calendar.HOUR_OF_DAY, hour)
    set(Calendar.MINUTE, minute)
    set(Calendar.SECOND, 0)
    set(Calendar.MILLISECOND, 0)
}.timeInMillis
