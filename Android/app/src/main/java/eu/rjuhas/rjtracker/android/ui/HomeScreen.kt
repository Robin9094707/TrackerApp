package eu.rjuhas.rjtracker.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import eu.rjuhas.rjtracker.android.Graph
import eu.rjuhas.rjtracker.android.data.LinkKind
import eu.rjuhas.rjtracker.android.data.SavedLink
import eu.rjuhas.rjtracker.android.data.SchoolOverview
import eu.rjuhas.rjtracker.android.ui.common.StatusPill
import eu.rjuhas.rjtracker.android.ui.common.rememberAddress
import eu.rjuhas.rjtracker.android.ui.common.ago
import eu.rjuhas.rjtracker.android.ui.common.dateTime
import eu.rjuhas.rjtracker.android.ui.school.placeLine
import eu.rjuhas.rjtracker.android.ui.common.placeColor
import kotlinx.coroutines.delay

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(links: List<SavedLink>, name: String, onOpen: (SavedLink) -> Unit) {
    var adding by remember { mutableStateOf(false) }
    val overviews = remember { mutableStateMapOf<String, SchoolOverview>() }
    LaunchedEffect(links.map { it.id }) {
        while (true) {
            links.filter { it.kind == LinkKind.SCHOOL }.forEach { link ->
                runCatching { Graph.api.schoolOverview(link) }.onSuccess { overviews[link.id] = it }
            }
            delay(30_000)
        }
    }
    val scroll = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    Scaffold(
        modifier = Modifier.nestedScroll(scroll.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(title = { Column { Text("Hallo $name 👋"); Text("Deine Tracker", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) } },
                scrollBehavior = scroll)
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(onClick = { adding = true }, icon = { Icon(Icons.Rounded.Add, null) }, text = { Text("Link hinzufügen") })
        },
    ) { padding ->
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = padding.calculateTopPadding() + 8.dp, bottom = 120.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)) {
            if (links.isEmpty()) item {
                Text("Noch keine Links gespeichert. Frag Robin nach einem Link und füge ihn hier ein.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            items(links, key = { it.id }) { link ->
                if (link.kind == LinkKind.SCHOOL) SchoolCard(link, overviews[link.id]) { onOpen(link) } else GuestCard(link) { onOpen(link) }
            }
        }
    }
    if (adding) {
        ModalBottomSheet(onDismissRequest = { adding = false }) {
            Box(Modifier.height(520.dp)) {
                AddLinkContent(initialLink = null, compact = true, onConnected = { adding = false; onOpen(it) })
            }
        }
    }
}

@Composable
private fun SchoolCard(link: SavedLink, overview: SchoolOverview?, onClick: () -> Unit) {
    Surface(onClick = onClick, shape = RoundedCornerShape(30.dp), color = Color.Transparent, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.background(Brush.linearGradient(listOf(Color(0xFF2F5DF5), Color(0xFF6A3DF5)))).padding(22.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("🎒", fontSize = 34.sp)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text("Schultaschenmodus", color = Color.White.copy(alpha = 0.8f), style = MaterialTheme.typography.labelLarge)
                    Text(link.title.ifBlank { "Schultasche" }, color = Color.White, style = MaterialTheme.typography.titleLarge)
                }
                Icon(Icons.Rounded.ChevronRight, null, tint = Color.White)
            }
            overview?.bags?.forEach { bag ->
                Surface(shape = RoundedCornerShape(20.dp), color = Color.White.copy(alpha = 0.96f)) {
                    Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(eu.rjuhas.rjtracker.android.ui.school.bagTitle(bag), style = MaterialTheme.typography.titleMedium, color = Color(0xFF111A3A))
                        val address = rememberAddress(bag.location?.lat, bag.location?.lon, bag.location?.address)
                        Text(address.text ?: bag.currentPlace?.let { "Bei ${it.name}" } ?: "Wird geladen …",
                            color = Color(0xFF4A5170), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            placeLine(bag)?.let { StatusPill(it, placeColor(bag.currentPlace?.kind)) }
                            Spacer(Modifier.weight(1f))
                            Text(ago(bag.location?.ts), style = MaterialTheme.typography.bodySmall, color = Color(0xFF4A5170))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun GuestCard(link: SavedLink, onClick: () -> Unit) {
    Surface(onClick = onClick, shape = RoundedCornerShape(26.dp), color = MaterialTheme.colorScheme.surfaceContainer, modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(52.dp).background(MaterialTheme.colorScheme.primaryContainer, RoundedCornerShape(18.dp)), contentAlignment = Alignment.Center) {
                Text(link.emoji.ifBlank { "📍" }, fontSize = 26.sp)
            }
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(link.title.ifBlank { "Geteilter Tracker" }, style = MaterialTheme.typography.titleMedium)
                Text(when {
                    link.isExpired -> "Freigabe abgelaufen"
                    link.expiresTs > 0 -> "Gastfreigabe · gültig bis ${dateTime(link.expiresTs)}"
                    else -> "Gastfreigabe · dauerhaft"
                }, color = if (link.isExpired) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
            }
            Icon(Icons.Rounded.ChevronRight, null)
        }
    }
}
