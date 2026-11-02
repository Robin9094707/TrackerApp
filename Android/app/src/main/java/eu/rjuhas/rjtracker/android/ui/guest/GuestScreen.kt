package eu.rjuhas.rjtracker.android.ui.guest

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.TurnRight
import eu.rjuhas.rjtracker.android.ui.common.ActionTile
import eu.rjuhas.rjtracker.android.ui.common.LocationHeader
import eu.rjuhas.rjtracker.android.ui.common.TileIcon
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Battery5Bar
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Directions
import androidx.compose.material.icons.rounded.GpsFixed
import androidx.compose.material.icons.rounded.HourglassBottom
import androidx.compose.material.icons.rounded.Place
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material3.BottomSheetScaffold
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SheetValue
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberBottomSheetScaffoldState
import androidx.compose.material3.rememberStandardBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import eu.rjuhas.rjtracker.android.Graph
import eu.rjuhas.rjtracker.android.data.ApiException
import eu.rjuhas.rjtracker.android.data.GuestView
import eu.rjuhas.rjtracker.android.data.Pt
import eu.rjuhas.rjtracker.android.ui.common.InfoRow
import eu.rjuhas.rjtracker.android.ui.common.SectionCard
import eu.rjuhas.rjtracker.android.ui.common.ago
import eu.rjuhas.rjtracker.android.ui.common.clock
import eu.rjuhas.rjtracker.android.ui.common.clusterRoute
import eu.rjuhas.rjtracker.android.ui.common.dateTime
import eu.rjuhas.rjtracker.android.ui.common.dayBounds
import eu.rjuhas.rjtracker.android.ui.common.openNavigation
import eu.rjuhas.rjtracker.android.ui.common.providerName
import eu.rjuhas.rjtracker.android.ui.common.shortDay
import eu.rjuhas.rjtracker.android.ui.common.today
import eu.rjuhas.rjtracker.android.ui.map.CameraTarget
import eu.rjuhas.rjtracker.android.ui.map.MapCircle
import eu.rjuhas.rjtracker.android.ui.map.MapLine
import eu.rjuhas.rjtracker.android.ui.map.MapMarker
import eu.rjuhas.rjtracker.android.ui.map.MarkerKind
import eu.rjuhas.rjtracker.android.ui.map.TrackerMap
import eu.rjuhas.rjtracker.android.ui.map.MapSettingsSheet
import eu.rjuhas.rjtracker.android.ui.map.rememberMapPrefs
import eu.rjuhas.rjtracker.android.ui.common.rememberAddress
import androidx.compose.material.icons.rounded.Layers
import eu.rjuhas.rjtracker.android.ui.school.RefreshIcon
import eu.rjuhas.rjtracker.android.ui.school.RoundButton
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import java.time.LocalDate

class GuestViewModel(private val linkId: String) : ViewModel() {
    var view by mutableStateOf<GuestView?>(null); private set
    var error by mutableStateOf<String?>(null); private set
    var gone by mutableStateOf(false); private set
    var refreshing by mutableStateOf(false); private set
    var day by mutableStateOf(today()); private set
    var history by mutableStateOf<List<Pt>>(emptyList()); private set
    private val snack = Channel<String>(Channel.BUFFERED)
    val messages = snack.receiveAsFlow()

    suspend fun load() {
        val link = Graph.repository.find(linkId) ?: return
        try {
            val result = Graph.api.guestView(link.baseUrl, link.token, link.appToken)
            view = result; error = null
            if (result.appToken != null && result.appToken != link.appToken || result.expiresTs != link.expiresTs || result.title != link.title) {
                Graph.repository.modify(linkId) { it.copy(appToken = result.appToken ?: it.appToken, expiresTs = result.expiresTs, title = result.title, emoji = result.emoji) }
            }
        } catch (exception: ApiException) {
            error = exception.message
            gone = exception.isGone || exception.needsPassword
        }
    }

    fun loadHistory(selected: LocalDate = day) {
        day = selected
        viewModelScope.launch {
            val link = Graph.repository.find(linkId) ?: return@launch
            if (view?.permissions?.showHistory != true) return@launch
            val (from, to) = dayBounds(selected)
            runCatching { Graph.api.guestHistory(link, from, to) }.onSuccess { history = it.points }.onFailure { snack.send(it.message ?: "Verlauf nicht verfügbar") }
        }
    }

    fun refreshNow() {
        if (refreshing) return
        viewModelScope.launch {
            val link = Graph.repository.find(linkId) ?: return@launch
            refreshing = true
            try {
                val response = Graph.api.guestLocate(link)
                if (response.status == "cooldown") {
                    snack.send("Bitte noch ${response.remaining} s warten")
                } else {
                    val before = response.previousTs
                    var found: Long? = null
                    val started = System.currentTimeMillis()
                    while (System.currentTimeMillis() - started < 40_000) {
                        delay(2500); load()
                        val ts = view?.location?.ts ?: 0
                        if (ts > before) { found = ts; break }
                    }
                    snack.send(if (found != null) "Neuer Standort aufgetaucht · ${clock(found)}" else "Kein neuer Standort aufgetaucht")
                    if (found != null) loadHistory()
                }
            } catch (exception: ApiException) {
                snack.send(exception.message ?: "Aktualisierung fehlgeschlagen")
            } finally { refreshing = false }
        }
    }

    fun remove(after: () -> Unit) = viewModelScope.launch { Graph.repository.remove(linkId); after() }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GuestScreen(linkId: String, showBack: Boolean, onBack: () -> Unit) {
    val vm: GuestViewModel = viewModel(key = linkId) { GuestViewModel(linkId) }
    val context = LocalContext.current
    val snackbar = remember { SnackbarHostState() }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var cameraKey by remember { mutableIntStateOf(0) }
    var showHistory by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { vm.messages.collect { snackbar.showSnackbar(it) } }
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (true) { vm.load(); delay(20_000) }
        }
    }
    val view = vm.view
    val location = view?.location
    val address = rememberAddress(location?.lat, location?.lon, location?.address)
    val mapPrefs = rememberMapPrefs()
    var showMapSettings by remember { mutableStateOf(false) }
    LaunchedEffect(view?.permissions?.showHistory) { if (view?.permissions?.showHistory == true) vm.loadHistory() }
    LaunchedEffect(location?.ts, showHistory, vm.history) { cameraKey++ }
    val clusters = remember(vm.history) { clusterRoute(vm.history) }
    val markers = buildList {
        if (showHistory) clusters.forEachIndexed { index, cluster ->
            if (cluster.count > 1) add(MapMarker("c$index", cluster.lat, cluster.lon, MarkerKind.CLUSTER, "${cluster.count}", "${clock(cluster.startTs)}–${clock(cluster.endTs)}", Color(0xFF6A3DF5)))
        }
        location?.let { add(MapMarker("tracker", it.lat, it.lon, MarkerKind.BAG, view.emoji, view.title, Color(0xFFE5484D))) }
    }
    val focus = (if (showHistory) vm.history.map { it.lat to it.lon } else emptyList()) + listOfNotNull(location?.let { it.lat to it.lon })
    val sheetState = rememberBottomSheetScaffoldState(rememberStandardBottomSheetState(SheetValue.PartiallyExpanded, skipHiddenState = true), snackbar)
    BottomSheetScaffold(
        scaffoldState = sheetState,
        sheetPeekHeight = 404.dp,
        sheetShape = RoundedCornerShape(topStart = 32.dp, topEnd = 32.dp),
        sheetShadowElevation = 12.dp,
        snackbarHost = { SnackbarHost(it) },
        sheetContent = {
            LazyColumn(Modifier.fillMaxWidth().fillMaxSize(0.92f), contentPadding = PaddingValues(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                item {
                    LocationHeader(
                        title = view?.title ?: "Wird geladen …",
                        address = vm.error ?: address.text,
                        addressLoading = vm.error == null && address.loading,
                        ts = location?.ts,
                        battery = location?.battery,
                        placeLabel = if (view != null && view.expiresTs > 0) "Freigabe bis ${dateTime(view.expiresTs)}" else null,
                    )
                }
                if (vm.gone) item {
                    SectionCard(modifier = Modifier.padding(horizontal = 16.dp)) {
                        Text("Diese Freigabe ist nicht mehr verfügbar. Bitte frag nach einem neuen Link.")
                        TextButton(onClick = { vm.remove(onBack) }) { Icon(Icons.Rounded.Delete, null); Spacer(Modifier.width(6.dp)); Text("Entfernen") }
                    }
                }
                item {
                    Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        ActionTile(icon = { if (vm.refreshing) RefreshIcon(true) else TileIcon(Icons.Rounded.Refresh) }, title = "Aktualisieren",
                            subtitle = if (view?.permissions?.canLocate == true) (if (vm.refreshing) "Wird geortet …" else "Jetzt orten") else "Nicht freigegeben",
                            color = Color(0xFF2F7BF5), enabled = view?.permissions?.canLocate == true && !vm.refreshing, modifier = Modifier.weight(1f)) { vm.refreshNow() }
                        ActionTile(icon = { TileIcon(Icons.Rounded.TurnRight) }, title = "Route", subtitle = "Navigation starten",
                            color = Color(0xFF2FB36B), enabled = location != null && view.permissions.canNavigate, modifier = Modifier.weight(1f)) {
                            location?.let { openNavigation(context, it.lat, it.lon, view.title) }
                        }
                    }
                }
                if (location != null && view != null) item {
                    SectionCard(modifier = Modifier.padding(horizontal = 16.dp), title = "Standortdetails") {
                        InfoRow(Icons.Rounded.Schedule, "Zuletzt geortet", "${dateTime(location.ts)} Uhr")
                        if (location.acc > 0) InfoRow(Icons.Rounded.GpsFixed, "Genauigkeit", "± ${location.acc.toInt()} m")
                        if (view.permissions.showProvider && location.source.isNotBlank()) InfoRow(Icons.Rounded.Place, "Gemeldet über", providerName(location.source))
                    }
                }
                if (view?.permissions?.showHistory == true) {
                    item {
                        Row(Modifier.padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text("Standortverlauf", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                            FilterChip(selected = showHistory, onClick = { showHistory = !showHistory }, label = { Text(if (showHistory) "Auf Karte" else "Zeigen") })
                        }
                    }
                    item {
                        LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            val days = (view.privacy.historyHours / 24).coerceIn(1, 30)
                            items((0 until days).toList()) { offset ->
                                val day = today().minusDays(offset.toLong())
                                FilterChip(selected = day == vm.day, onClick = { vm.loadHistory(day); showHistory = true },
                                    label = { Text(if (offset == 0) "Heute" else if (offset == 1) "Gestern" else shortDay(day)) })
                            }
                        }
                    }
                    item { Text("${vm.history.size} Meldungen · ${clusters.count { it.count >= 3 }} Aufenthalte", Modifier.padding(horizontal = 20.dp), color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    items(clusters.filter { it.count >= 3 }) { cluster ->
                        Text("${clock(cluster.startTs)} – ${clock(cluster.endTs)} · ${cluster.count} Meldungen", Modifier.padding(horizontal = 20.dp))
                    }
                }
            }
        },
    ) {
        Box(Modifier.fillMaxSize()) {
            TrackerMap(
                modifier = Modifier.fillMaxSize(), markers = markers,
                circles = listOfNotNull(location?.takeIf { it.acc > 0 && mapPrefs.showAccuracy }?.let { MapCircle("acc", it.lat, it.lon, it.acc, Color(0xFF2F7BF5), accuracy = true) }),
                lines = if (showHistory && clusters.size > 1) listOf(MapLine(clusters.map { it.lat to it.lon }, Color(0xFF6A3DF5))) else emptyList(),
                camera = focus.takeIf { it.isNotEmpty() }?.let { CameraTarget(cameraKey, it, 16.5f) }, bottomPadding = 404.dp,
            )
            if (showBack) Box(Modifier.statusBarsPadding().padding(14.dp)) {
                RoundButton(onClick = onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Zurück") }
            }
            Box(Modifier.align(Alignment.TopEnd).statusBarsPadding().padding(14.dp)) {
                RoundButton(onClick = { showMapSettings = true }) { Icon(Icons.Rounded.Layers, "Karte einstellen") }
            }
        }
    }
    if (showMapSettings) MapSettingsSheet(onDismiss = { showMapSettings = false })
}
