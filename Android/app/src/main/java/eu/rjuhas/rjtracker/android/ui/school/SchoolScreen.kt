package eu.rjuhas.rjtracker.android.ui.school

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Layers
import androidx.compose.material.icons.rounded.MyLocation
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.TurnRight
import androidx.compose.material3.BottomSheetScaffold
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import eu.rjuhas.rjtracker.android.data.Bag
import eu.rjuhas.rjtracker.android.ui.common.ActionTile
import eu.rjuhas.rjtracker.android.ui.common.LocationHeader
import eu.rjuhas.rjtracker.android.ui.common.PointCluster
import eu.rjuhas.rjtracker.android.ui.common.TileIcon
import eu.rjuhas.rjtracker.android.ui.common.clock
import eu.rjuhas.rjtracker.android.ui.common.clusterRoute
import eu.rjuhas.rjtracker.android.ui.common.openNavigation
import eu.rjuhas.rjtracker.android.ui.common.placeColor
import eu.rjuhas.rjtracker.android.ui.map.CameraTarget
import eu.rjuhas.rjtracker.android.ui.map.MapCircle
import eu.rjuhas.rjtracker.android.ui.map.MapLine
import eu.rjuhas.rjtracker.android.ui.map.MapMarker
import eu.rjuhas.rjtracker.android.ui.map.MarkerKind
import eu.rjuhas.rjtracker.android.ui.map.TrackerMap
import kotlinx.coroutines.delay

enum class SchoolTab(val label: String) { TODAY("Heute"), HISTORY("Verlauf"), LOG("Protokoll"), PLACES("Orte") }

private val SheetPeek = 372.dp

/** "Schultasche von Mila" when a child name exists, otherwise the bag label. */
fun bagTitle(bag: Bag?): String = when {
    bag == null -> "Schultasche"
    bag.childName.isBlank() -> bag.label
    bag.label.isBlank() || bag.label.equals("Schultasche", ignoreCase = true) -> "Schultasche von ${bag.childName}"
    else -> bag.label
}

/** Short, positive place line: "Zuhause" / "In der Schule seit 07:48". */
fun placeLine(bag: Bag?): String? {
    val place = bag?.currentPlace ?: return null
    val since = place.sinceTs?.let { " seit ${clock(it)}" }.orEmpty()
    return when (place.kind) {
        "school" -> "In der Schule$since"
        "home" -> "Zuhause$since"
        else -> "${place.name}$since"
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SchoolScreen(linkId: String, showBack: Boolean, onBack: () -> Unit, onAllLinks: () -> Unit) {
    val vm: SchoolViewModel = viewModel(key = linkId) { SchoolViewModel(linkId) }
    val context = LocalContext.current
    val link by vm.link.collectAsState()
    val snackbar = remember { SnackbarHostState() }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var tab by rememberSaveable { mutableStateOf(SchoolTab.TODAY) }
    var satellite by rememberSaveable { mutableStateOf(false) }
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
    val location = bag?.location
    LaunchedEffect(bag?.ref) { if (bag != null) { vm.loadHistory(); vm.loadAttendance() } }
    LaunchedEffect(tab, vm.history, location?.ts, bag?.ref) {
        focus = when (tab) {
            SchoolTab.HISTORY -> vm.history?.points?.map { it.lat to it.lon }?.takeIf { it.isNotEmpty() }
            SchoolTab.PLACES -> overview?.places?.map { it.lat to it.lon }?.takeIf { it.isNotEmpty() }
            else -> null
        } ?: listOfNotNull(location?.let { it.lat to it.lon })
        if (focus?.isNotEmpty() == true) cameraKey++
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
            location?.let { add(MapMarker("bag", it.lat, it.lon, MarkerKind.BAG, bag.emoji, bagTitle(bag), Color(0xFFE5484D))) }
        }
    }
    val circles = buildList {
        overview?.places?.forEach { add(MapCircle(it.id, it.lat, it.lon, it.radiusM.toDouble(), placeColor(it.kind))) }
        if (tab != SchoolTab.HISTORY) location?.takeIf { it.acc > 0 }?.let { add(MapCircle("accuracy", it.lat, it.lon, it.acc, Color(0xFF2F7BF5))) }
    }
    val lines = if (tab == SchoolTab.HISTORY && clusters.size >= 2) listOf(MapLine(clusters.map { it.lat to it.lon }, Color(0xFF6A3DF5), 5f)) else emptyList()

    val sheetState = rememberBottomSheetScaffoldState(rememberStandardBottomSheetState(initialValue = SheetValue.PartiallyExpanded, skipHiddenState = true), snackbar)
    BottomSheetScaffold(
        scaffoldState = sheetState,
        sheetPeekHeight = SheetPeek,
        sheetShape = RoundedCornerShape(topStart = 32.dp, topEnd = 32.dp),
        sheetContainerColor = MaterialTheme.colorScheme.surface,
        sheetShadowElevation = 12.dp,
        snackbarHost = { SnackbarHost(it) },
        sheetContent = {
            Column(Modifier.fillMaxWidth().fillMaxSize(0.94f)) {
                LocationHeader(
                    title = if (overview == null && vm.error == null) "Wird geladen …" else bagTitle(bag),
                    address = vm.error ?: location?.address,
                    ts = location?.ts,
                    battery = bag?.battery,
                    placeLabel = placeLine(bag),
                    placeColor = placeColor(bag?.currentPlace?.kind),
                )
                Spacer(Modifier.height(16.dp))
                Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    ActionTile(
                        icon = { RefreshGlyph(vm.refreshing) }, title = "Aktualisieren",
                        subtitle = if (vm.refreshing) "Wird geortet …" else "Jetzt orten",
                        color = Color(0xFF2F7BF5), enabled = !vm.refreshing && bag != null, modifier = Modifier.weight(1f),
                    ) { vm.refreshNow() }
                    ActionTile(
                        icon = { TileIcon(Icons.Rounded.TurnRight) }, title = "Route", subtitle = "Navigation starten",
                        color = Color(0xFF2FB36B), enabled = location != null, modifier = Modifier.weight(1f),
                    ) { location?.let { openNavigation(context, it.lat, it.lon, bagTitle(bag)) } }
                }
                if ((overview?.bags?.size ?: 0) > 1) {
                    Spacer(Modifier.height(12.dp))
                    LazyRow(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(overview!!.bags, key = { it.ref }) { item ->
                            FilterChip(selected = item.ref == bag?.ref, onClick = { vm.selectedRef = item.ref },
                                label = { Text("${item.emoji} ${bagTitle(item)}") })
                        }
                    }
                }
                Spacer(Modifier.height(10.dp))
                PrimaryTabRow(selectedTabIndex = tab.ordinal, containerColor = Color.Transparent) {
                    SchoolTab.entries.forEach { entry ->
                        Tab(selected = tab == entry, onClick = { tab = entry; cursor = null }, text = { Text(entry.label) })
                    }
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
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
    ) {
        Box(Modifier.fillMaxSize()) {
            TrackerMap(
                modifier = Modifier.fillMaxSize(),
                markers = markers, circles = circles, lines = lines,
                camera = focus?.let { CameraTarget(cameraKey, it, 16.5f) },
                bottomPadding = SheetPeek,
                satellite = satellite,
            )
            if (showBack) {
                Box(Modifier.statusBarsPadding().padding(14.dp)) {
                    RoundButton(onClick = onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Zurück") }
                }
            }
            // Find-My-like control stack on the top right.
            Column(Modifier.align(Alignment.TopEnd).statusBarsPadding().padding(14.dp), horizontalAlignment = Alignment.End,
                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Surface(shape = RoundedCornerShape(26.dp), color = MaterialTheme.colorScheme.surface.copy(alpha = 0.95f),
                    shadowElevation = 6.dp, modifier = Modifier.width(52.dp)) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        ControlButton(onClick = { satellite = !satellite }) {
                            Icon(Icons.Rounded.Layers, if (satellite) "Kartenansicht" else "Satellitenansicht",
                                tint = if (satellite) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface)
                        }
                        HorizontalDivider(Modifier.width(30.dp))
                        ControlButton(onClick = {
                            tab = SchoolTab.TODAY
                            focus = listOfNotNull(location?.let { it.lat to it.lon }); cameraKey++
                        }) { Icon(Icons.Rounded.MyLocation, "Tasche zentrieren") }
                    }
                }
                RoundButton(onClick = { showSettings = true }) { Icon(Icons.Rounded.Settings, "Einstellungen") }
            }
        }
    }
    if (showSettings && link != null) SchoolSettingsSheet(vm, link!!, onDismiss = { showSettings = false }, onRemoved = onBack,
        onAllLinks = { showSettings = false; onAllLinks() })
    editPlace?.let { draft -> PlaceEditorDialog(draft, onDismiss = { editPlace = null }, onSave = { vm.savePlace(it) { editPlace = null } },
        onDelete = draft.place.id.takeIf { it.isNotBlank() }?.let { id -> { vm.deletePlace(id); editPlace = null } }) }
}

@Composable
private fun ControlButton(onClick: () -> Unit, content: @Composable () -> Unit) {
    Surface(onClick = onClick, color = Color.Transparent, shape = CircleShape, modifier = Modifier.size(52.dp)) {
        Box(contentAlignment = Alignment.Center) { content() }
    }
}

@Composable
fun RoundButton(onClick: () -> Unit, content: @Composable () -> Unit) {
    Surface(onClick = onClick, shape = CircleShape, color = MaterialTheme.colorScheme.surface.copy(alpha = 0.95f),
        modifier = Modifier.size(52.dp).shadow(6.dp, CircleShape)) {
        Box(contentAlignment = Alignment.Center) { content() }
    }
}

@Composable
private fun RefreshGlyph(spinning: Boolean) {
    val transition = rememberInfiniteTransition(label = "refresh")
    val angle by transition.animateFloat(0f, 360f, infiniteRepeatable(tween(900, easing = LinearEasing)), label = "angle")
    Icon(Icons.Rounded.Refresh, null, tint = Color.White, modifier = Modifier.size(24.dp).then(if (spinning) Modifier.rotate(angle) else Modifier))
}

@Composable
fun RefreshIcon(spinning: Boolean) {
    val transition = rememberInfiniteTransition(label = "refresh")
    val angle by transition.animateFloat(0f, 360f, infiniteRepeatable(tween(900, easing = LinearEasing)), label = "angle")
    Icon(Icons.Rounded.Refresh, "Jetzt aktualisieren", modifier = if (spinning) Modifier.rotate(angle) else Modifier,
        tint = if (spinning) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface)
}
