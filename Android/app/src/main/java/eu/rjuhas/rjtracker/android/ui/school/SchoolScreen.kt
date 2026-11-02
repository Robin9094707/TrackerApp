package eu.rjuhas.rjtracker.android.ui.school

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.BottomSheetScaffold
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.SheetValue
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.rememberBottomSheetScaffoldState
import androidx.compose.material3.rememberStandardBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import eu.rjuhas.rjtracker.android.ui.common.PointCluster
import eu.rjuhas.rjtracker.android.ui.common.clock
import eu.rjuhas.rjtracker.android.ui.common.clusterRoute
import eu.rjuhas.rjtracker.android.ui.common.placeColor
import eu.rjuhas.rjtracker.android.ui.map.CameraTarget
import eu.rjuhas.rjtracker.android.ui.map.MapCircle
import eu.rjuhas.rjtracker.android.ui.map.MapLine
import eu.rjuhas.rjtracker.android.ui.map.MapMarker
import eu.rjuhas.rjtracker.android.ui.map.MarkerKind
import eu.rjuhas.rjtracker.android.ui.map.TrackerMap
import kotlinx.coroutines.delay

enum class SchoolTab(val label: String) { TODAY("Heute"), HISTORY("Verlauf"), LOG("Protokoll"), PLACES("Orte") }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SchoolScreen(linkId: String, onBack: () -> Unit) {
    val vm: SchoolViewModel = viewModel(key = linkId) { SchoolViewModel(linkId) }
    val link by vm.link.collectAsState()
    val snackbar = remember { SnackbarHostState() }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var tab by rememberSaveable { mutableStateOf(SchoolTab.TODAY) }
    var showSettings by remember { mutableStateOf(false) }
    var editPlace by remember { mutableStateOf<PlaceDraft?>(null) }
    var cameraKey by remember { mutableIntStateOf(0) }
    var focus by remember { mutableStateOf<List<Pair<Double, Double>>?>(null) }
    var cursor by remember { mutableStateOf<Pair<Double, Double>?>(null) }

    LaunchedEffect(Unit) { vm.messages.collect { snackbar.showSnackbar(it) } }
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (true) {
                vm.load()
                delay((vm.overview?.pollSeconds ?: 20).coerceIn(10, 60) * 1000L)
            }
        }
    }
    val overview = vm.overview
    val bag = vm.bag
    LaunchedEffect(bag?.ref) { if (bag != null) { vm.loadHistory(); vm.loadAttendance() } }
    LaunchedEffect(tab, vm.history, bag?.location?.ts) {
        focus = when (tab) {
            SchoolTab.HISTORY -> vm.history?.points?.map { it.lat to it.lon }?.takeIf { it.isNotEmpty() }
            SchoolTab.PLACES -> overview?.places?.map { it.lat to it.lon }?.takeIf { it.isNotEmpty() }
            else -> listOfNotNull(bag?.location?.let { it.lat to it.lon })
        }
        if (focus != null) cameraKey++
    }

    val clusters: List<PointCluster> = remember(vm.history) { clusterRoute(vm.history?.points.orEmpty()) }
    val markers = buildList {
        overview?.places?.forEach { place ->
            add(MapMarker("place-${place.id}", place.lat, place.lon, MarkerKind.PLACE, place.name, place.name, placeColor(place.kind)))
        }
        if (tab == SchoolTab.HISTORY) {
            clusters.forEachIndexed { index, cluster ->
                if (cluster.count > 1) add(MapMarker("cluster-$index", cluster.lat, cluster.lon, MarkerKind.CLUSTER, cluster.count.toString(),
                    "${clock(cluster.startTs)}–${clock(cluster.endTs)}", Color(0xFF6A3DF5)))
            }
            clusters.firstOrNull()?.let { add(MapMarker("start", it.lat, it.lon, MarkerKind.START, "Start ${clock(it.startTs)}", color = Color(0xFF1E9E5A))) }
            clusters.lastOrNull()?.takeIf { clusters.size > 1 }?.let { add(MapMarker("end", it.lat, it.lon, MarkerKind.END, "Ende ${clock(it.endTs)}", color = Color(0xFFE5484D))) }
            cursor?.let { add(MapMarker("cursor", it.first, it.second, MarkerKind.CURSOR, color = Color(0xFFFF6B4A))) }
        } else {
            bag?.location?.let { add(MapMarker("bag", it.lat, it.lon, MarkerKind.BAG, bag.emoji, bag.displayName, Color(0xFF2F5DF5))) }
        }
    }
    val circles = buildList {
        overview?.places?.forEach { add(MapCircle(it.id, it.lat, it.lon, it.radiusM.toDouble(), placeColor(it.kind))) }
        if (tab != SchoolTab.HISTORY) bag?.location?.takeIf { it.acc > 0 }?.let { add(MapCircle("accuracy", it.lat, it.lon, it.acc, Color(0xFF2F5DF5).copy(alpha = 0.6f))) }
    }
    val lines = if (tab == SchoolTab.HISTORY && clusters.size >= 2) listOf(MapLine(clusters.map { it.lat to it.lon }, Color(0xFF6A3DF5), 5f)) else emptyList()

    val sheetState = rememberBottomSheetScaffoldState(rememberStandardBottomSheetState(initialValue = SheetValue.PartiallyExpanded, skipHiddenState = true), snackbar)
    BottomSheetScaffold(
        scaffoldState = sheetState,
        sheetPeekHeight = 360.dp,
        sheetContainerColor = MaterialTheme.colorScheme.surface,
        snackbarHost = { SnackbarHost(it) },
        sheetContent = {
            Column(Modifier.fillMaxWidth().fillMaxSize(0.92f)) {
                if ((overview?.bags?.size ?: 0) > 1) {
                    LazyRow(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(overview!!.bags, key = { it.ref }) { item ->
                            FilterChip(selected = item.ref == bag?.ref, onClick = { vm.selectedRef = item.ref },
                                label = { Text("${item.emoji} ${item.displayName}") })
                        }
                    }
                }
                PrimaryTabRow(selectedTabIndex = tab.ordinal, containerColor = Color.Transparent) {
                    SchoolTab.entries.forEach { entry ->
                        Tab(selected = tab == entry, onClick = { tab = entry; cursor = null }, text = { Text(entry.label) })
                    }
                }
                Box(Modifier.weight(1f)) {
                    when (tab) {
                        SchoolTab.TODAY -> TodayPanel(vm, onFocus = { focus = listOf(it); cameraKey++ })
                        SchoolTab.HISTORY -> HistoryPanel(vm, clusters, onCursor = { cursor = it }, onFocus = { focus = it; cameraKey++ })
                        SchoolTab.LOG -> AttendancePanel(vm)
                        SchoolTab.PLACES -> PlacesPanel(vm, onEdit = { editPlace = it }, onFocus = { focus = listOf(it); cameraKey++ })
                    }
                }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize()) {
            TrackerMap(
                modifier = Modifier.fillMaxSize(),
                markers = markers, circles = circles, lines = lines,
                camera = focus?.let { CameraTarget(cameraKey, it) },
                bottomPadding = 340.dp,
            )
            Row(Modifier.fillMaxWidth().statusBarsPadding().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                RoundButton(onClick = onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Zurück") }
                Spacer(Modifier.width(10.dp))
                Surface(shape = CircleShape, color = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f), modifier = Modifier.weight(1f).shadow(6.dp, CircleShape)) {
                    Column(Modifier.padding(horizontal = 18.dp, vertical = 8.dp)) {
                        Text(bag?.displayName ?: link?.title ?: "Schultasche", style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(vm.error ?: (bag?.currentPlace?.let { "Bei ${it.name} seit ${clock(it.sinceTs)}" } ?: bag?.location?.address?.ifBlank { null } ?: "Unterwegs"),
                            style = MaterialTheme.typography.bodySmall, color = if (vm.error != null) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
                Spacer(Modifier.width(10.dp))
                RoundButton(onClick = { vm.refreshNow() }) { RefreshIcon(vm.refreshing) }
                Spacer(Modifier.width(8.dp))
                RoundButton(onClick = { showSettings = true }) { Icon(Icons.Rounded.Settings, "Einstellungen") }
            }
        }
    }
    if (showSettings && link != null) SchoolSettingsSheet(vm, link!!, onDismiss = { showSettings = false }, onRemoved = onBack)
    editPlace?.let { draft -> PlaceEditorDialog(draft, onDismiss = { editPlace = null }, onSave = { vm.savePlace(it) { editPlace = null } },
        onDelete = draft.place.id.takeIf { it.isNotBlank() }?.let { id -> { vm.deletePlace(id); editPlace = null } }) }
}

@Composable
fun RoundButton(onClick: () -> Unit, content: @Composable () -> Unit) {
    Surface(onClick = onClick, shape = CircleShape, color = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f),
        modifier = Modifier.size(48.dp).shadow(6.dp, CircleShape)) {
        Box(contentAlignment = Alignment.Center) { content() }
    }
}

@Composable
fun RefreshIcon(spinning: Boolean) {
    val transition = rememberInfiniteTransition(label = "refresh")
    val angle by transition.animateFloat(0f, 360f, infiniteRepeatable(tween(900, easing = LinearEasing)), label = "angle")
    Icon(Icons.Rounded.Refresh, "Jetzt aktualisieren", modifier = if (spinning) Modifier.rotate(angle) else Modifier,
        tint = if (spinning) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface)
}

@Suppress("unused")
private val spacer = Modifier.height(0.dp).background(Color.Transparent)
