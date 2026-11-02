package eu.rjuhas.rjtracker.android.ui.school

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Battery5Bar
import androidx.compose.material.icons.rounded.DirectionsWalk
import androidx.compose.material.icons.rounded.GpsFixed
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Place
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.School
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import eu.rjuhas.rjtracker.android.data.DayRecord
import eu.rjuhas.rjtracker.android.data.Place
import eu.rjuhas.rjtracker.android.ui.common.InfoRow
import eu.rjuhas.rjtracker.android.ui.common.PointCluster
import eu.rjuhas.rjtracker.android.ui.common.SectionCard
import eu.rjuhas.rjtracker.android.ui.common.StatusPill
import eu.rjuhas.rjtracker.android.ui.common.clock
import eu.rjuhas.rjtracker.android.ui.common.dateTime
import eu.rjuhas.rjtracker.android.ui.common.dayTitle
import eu.rjuhas.rjtracker.android.ui.common.distanceM
import eu.rjuhas.rjtracker.android.ui.common.durationText
import eu.rjuhas.rjtracker.android.ui.common.placeColor
import eu.rjuhas.rjtracker.android.ui.common.providerName
import eu.rjuhas.rjtracker.android.ui.common.shareText
import eu.rjuhas.rjtracker.android.ui.common.shortDay
import eu.rjuhas.rjtracker.android.ui.common.statusColor
import eu.rjuhas.rjtracker.android.ui.common.today
import eu.rjuhas.rjtracker.android.ui.theme.StatusColors

private val listPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 32.dp)

fun headline(record: DayRecord?): String = when (record?.status) {
    null -> "Noch keine Auswertung"
    "on_time" -> if (record.alreadyThere) "Tasche war schon in der Schule" else "Pünktlich angekommen · ${clock(record.arrivalTs)}"
    "late" -> "${record.lateMinutes} min verspätet · ${clock(record.arrivalTs)}"
    "missing" -> "Noch nicht in der Schule"
    "absent" -> "Heute nicht in der Schule"
    "no_data" -> "Keine Standortdaten seit Schulbeginn"
    "upcoming" -> "Schulbeginn um ${record.start} Uhr"
    "setup" -> "Schule als Ort festlegen"
    else -> record.label.ifBlank { record.statusText.ifBlank { "Schulfrei" } }
}

@Composable
fun TodayPanel(vm: SchoolViewModel, onFocus: (Pair<Double, Double>) -> Unit) {
    val bag = vm.bag
    val today = bag?.today
    val location = bag?.location
    LazyColumn(contentPadding = listPadding, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        // Attendance only where it is meaningful; missing data never becomes a headline.
        if (today != null && (today.arrivalTs != null || today.homeDepartureTs != null)) item {
            SectionCard(title = "Schulweg heute") {
                if (today.status == "on_time" || today.status == "late") {
                    StatusPill(if (today.status == "late") "${today.lateMinutes} min nach Schulbeginn" else "Pünktlich", statusColor(today.status))
                }
                TimelineRow(Icons.Rounded.Home, StatusColors.home, "Zuhause verlassen", clock(today.homeDepartureTs), today.homeDepartureTs != null)
                TimelineRow(Icons.Rounded.DirectionsWalk, StatusColors.neutral, "Unterwegs", today.travelMinutes?.let { durationText(it) } ?: "–", today.travelMinutes != null)
                TimelineRow(Icons.Rounded.School, StatusColors.school, "In der Schule", if (today.alreadyThere) "schon dort" else clock(today.arrivalTs), today.arrivalTs != null)
                TimelineRow(Icons.Rounded.Timer, StatusColors.school, "Schule verlassen",
                    if (today.leaveTs != null) "${clock(today.leaveTs)} · ${durationText(today.presentMinutes)}" else if (today.arrivalTs != null) "noch dort · ${durationText(today.presentMinutes)}" else "–",
                    today.leaveTs != null, last = true)
            }
        }
        if (location != null) item {
            SectionCard(title = "Standortdetails") {
                InfoRow(Icons.Rounded.Schedule, "Zuletzt geortet", "${dateTime(location.ts)} Uhr")
                InfoRow(Icons.Rounded.GpsFixed, "Genauigkeit", "± ${location.acc.toInt()} m")
                InfoRow(Icons.Rounded.Place, "Gemeldet über", providerName(location.source.ifBlank { bag.provider }))
                if (bag.battery.isNotBlank()) InfoRow(Icons.Rounded.Battery5Bar, "Batterie", bag.battery)
                FilledTonalButton(onClick = { onFocus(location.lat to location.lon) }, modifier = Modifier.fillMaxWidth()) { Text("Auf der Karte zeigen") }
            }
        }
        vm.overview?.schedule?.let { schedule ->
            item {
                val cfg = schedule.days[today().dayOfWeek.value.toString()]
                SectionCard(title = "Stundenplan heute") {
                    Text(if (cfg?.enabled == true) "Beginn ${cfg.start} Uhr" + (if (cfg.end.isNotBlank()) " · Ende ${cfg.end} Uhr" else "") else "Heute ist kein Schultag eingetragen.",
                        style = MaterialTheme.typography.bodyLarge)
                }
            }
        }
    }
}

@Composable
private fun TimelineRow(icon: ImageVector, color: Color, title: String, value: String, done: Boolean, last: Boolean = false) {
    Row(verticalAlignment = Alignment.Top) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.size(34.dp).background(if (done) color else color.copy(alpha = 0.18f), CircleShape), contentAlignment = Alignment.Center) {
                Icon(icon, null, tint = if (done) Color.White else color, modifier = Modifier.size(18.dp))
            }
            if (!last) Box(Modifier.width(2.dp).height(18.dp).background(color.copy(alpha = 0.3f)))
        }
        Spacer(Modifier.width(14.dp))
        Row(Modifier.weight(1f).padding(top = 6.dp)) {
            Text(title, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
            Text(value, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
fun HistoryPanel(vm: SchoolViewModel, clusters: List<PointCluster>, onCursor: (Pair<Double, Double>?) -> Unit, onFocus: (List<Pair<Double, Double>>) -> Unit) {
    val history = vm.history
    val points = history?.points.orEmpty()
    var slider by remember(history) { mutableFloatStateOf(1f) }
    LaunchedEffect(history) { onCursor(null) }
    val distanceKm = remember(clusters) { clusters.zipWithNext { a, b -> distanceM(a.lat, a.lon, b.lat, b.lon) }.sum() / 1000 }
    LazyColumn(contentPadding = listPadding, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items((0L until 21L).toList()) { offset ->
                    val day = today().minusDays(offset)
                    FilterChip(selected = day == vm.historyDay, onClick = { vm.loadHistory(day) },
                        label = { Text(if (offset == 0L) "Heute" else if (offset == 1L) "Gestern" else shortDay(day)) })
                }
            }
        }
        if (vm.historyLoading) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Stat("Reports", "${history?.rawCount ?: 0}", Modifier.weight(1f))
                Stat("Aufenthalte", "${history?.visits?.size ?: 0}", Modifier.weight(1f))
                Stat("Strecke", "%.1f km".format(distanceKm), Modifier.weight(1f))
            }
        }
        if (points.size > 1) item {
            SectionCard(title = "Zeitreise") {
                val index = ((points.size - 1) * slider).toInt().coerceIn(0, points.size - 1)
                val point = points[index]
                Text("${clock(point.ts)} Uhr · ± ${point.acc.toInt()} m · ${providerName(point.source)}", fontWeight = FontWeight.SemiBold)
                Slider(value = slider, onValueChange = { slider = it; onCursor(point.lat to point.lon) })
                Text("Ziehen, um den Weg Report für Report nachzuverfolgen.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (history != null && history.visits.isEmpty() && points.isEmpty() && !vm.historyLoading) item {
            SectionCard { Text("An diesem Tag gibt es keine gespeicherten Standorte.") }
        }
        val visits = history?.visits.orEmpty()
        if (visits.isNotEmpty()) item { Text("Orte", style = MaterialTheme.typography.titleMedium) }
        items(visits) { visit ->
            val color = placeColor(visit.placeKind)
            val minutes = (((visit.leaveTs ?: visit.lastInTs) - visit.enterTs) / 60).toInt().coerceAtLeast(0)
            SectionCard(modifier = Modifier.clickable {
                vm.overview?.places?.firstOrNull { it.id == visit.placeId }?.let { onFocus(listOf(it.lat to it.lon)) }
            }) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(12.dp).background(color, CircleShape)); Spacer(Modifier.width(10.dp))
                    Text(visit.placeName, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                    Text(durationText(minutes), fontWeight = FontWeight.SemiBold)
                }
                Text(
                    (if (visit.enteredUnknown) "schon vorher dort" else "angekommen ${clock(visit.enterTs)}") +
                        (visit.leaveTs?.let { " · verlassen ${clock(it)} (zuletzt dort ${clock(visit.lastInTs)})" } ?: " · noch dort"),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        val stays = clusters.filter { it.count >= 3 }
        if (stays.isNotEmpty()) item { Text("Erkannte Aufenthalte", style = MaterialTheme.typography.titleMedium) }
        items(stays) { cluster ->
            Row(Modifier.fillMaxWidth().clickable { onFocus(listOf(cluster.lat to cluster.lon)) }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(36.dp).background(Color(0xFF6A3DF5).copy(alpha = 0.15f), CircleShape), contentAlignment = Alignment.Center) {
                    Text("${cluster.count}", color = Color(0xFF6A3DF5), fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text("${clock(cluster.startTs)} – ${clock(cluster.endTs)}", fontWeight = FontWeight.SemiBold)
                    Text("${cluster.count} Reports · Radius ${cluster.radiusM.toInt()} m", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text(durationText(((cluster.endTs - cluster.startTs) / 60).toInt()))
            }
            HorizontalDivider()
        }
    }
}

@Composable
private fun Stat(label: String, value: String, modifier: Modifier) {
    Column(modifier.background(MaterialTheme.colorScheme.surfaceContainer, RoundedCornerShape(20.dp)).padding(14.dp)) {
        Text(value, style = MaterialTheme.typography.headlineSmall)
        Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
fun AttendancePanel(vm: SchoolViewModel) {
    val context = LocalContext.current
    val bag = vm.bag
    val data = bag?.let { vm.attendance?.attendance?.get(it.ref) }
    LaunchedEffect(bag?.ref) { vm.loadAttendance() }
    LazyColumn(contentPadding = listPadding, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (data == null) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
        data?.summary?.let { summary ->
            item {
                SectionCard(title = "Letzte 120 Tage") {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Stat("Pünktlich", "${summary.onTime}", Modifier.weight(1f))
                        Stat("Verspätet", "${summary.late}", Modifier.weight(1f))
                        Stat("Gefehlt", "${summary.absent}", Modifier.weight(1f))
                    }
                    Text("Ø Ankunft ${summary.averageArrival.ifBlank { "–" }} · Verspätung gesamt ${durationText(summary.lateMinutesTotal)}",
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    OutlinedButton(onClick = { shareText(context, "Schulprotokoll ${bag.displayName}", protocolText(bag.displayName, data.days)) }) {
                        Icon(Icons.Rounded.Share, null); Spacer(Modifier.width(8.dp)); Text("Protokoll teilen")
                    }
                }
            }
        }
        items(data?.days.orEmpty().filter { it.status != "free" || it.label.isNotBlank() }) { day ->
            DayCard(day)
        }
    }
}

@Composable
private fun DayCard(day: DayRecord) {
    SectionCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(dayTitle(day.day), style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            StatusPill(day.statusText.ifBlank { day.status }, statusColor(day.status))
        }
        if (day.status == "free" || day.status == "setup") {
            Text(day.label.ifBlank { "Kein Schultag" }, color = MaterialTheme.colorScheme.onSurfaceVariant)
            return@SectionCard
        }
        Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
            Detail("Beginn", day.start)
            Detail("Ankunft", if (day.alreadyThere) "vorher" else clock(day.arrivalTs))
            Detail("Verlassen", clock(day.leaveTs))
            Detail("Dauer", if (day.presentMinutes > 0) durationText(day.presentMinutes) else "–")
        }
        val notes = buildList {
            if (day.lateMinutes > 0) add("${day.lateMinutes} min nach Schulbeginn")
            day.homeDepartureTs?.let { add("Zuhause los ${clock(it)}" + (day.travelMinutes?.let { m -> " · Weg ${durationText(m)}" } ?: "")) }
            if (day.earlyLeave) add("vor Schulende gegangen")
            day.evidence?.let { add("Um ${clock(it.ts)} " + (if (it.nearPlace.isNotBlank()) "bei ${it.nearPlace}" else "woanders geortet") + " (${it.reports} Reports)") }
            add("${day.reportCount} Reports an diesem Tag")
        }
        Text(notes.joinToString(" · "), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun Detail(label: String, value: String) {
    Column {
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, fontWeight = FontWeight.SemiBold)
    }
}

fun protocolText(name: String, days: List<DayRecord>): String = buildString {
    appendLine("Schulprotokoll · $name")
    appendLine("Automatisch aus Tracker-Meldungen berechnet (RJ Tracker).")
    appendLine()
    days.filter { it.status in setOf("on_time", "late", "absent", "no_data") }.forEach { day ->
        append(dayTitle(day.day)).append(": ").append(day.statusText.ifBlank { day.status })
        if (day.arrivalTs != null) append(" · Ankunft ").append(clock(day.arrivalTs))
        if (day.lateMinutes > 0) append(" (+").append(day.lateMinutes).append(" min)")
        if (day.leaveTs != null) append(" · verlassen ").append(clock(day.leaveTs))
        if (day.presentMinutes > 0) append(" · ").append(durationText(day.presentMinutes))
        if (day.homeDepartureTs != null) append(" · Zuhause los ").append(clock(day.homeDepartureTs))
        appendLine()
    }
}

@Composable
fun PlacesPanel(vm: SchoolViewModel, onEdit: (PlaceDraft) -> Unit, onFocus: (Pair<Double, Double>) -> Unit) {
    val places = vm.overview?.places.orEmpty()
    val bagLocation = vm.bag?.location
    LazyColumn(contentPadding = listPadding, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Text("Zuhause und Schule werden mit Pufferzone und Ausreißerschutz ausgewertet: Ein einzelner ungenauer Report zählt nie als „verlassen“.",
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (places.none { it.kind == "school" }) item {
            AssistChip(onClick = { onEdit(PlaceDraft(Place(kind = "school", name = "Schule", lat = bagLocation?.lat ?: 51.43, lon = bagLocation?.lon ?: 6.76))) },
                label = { Text("Schule festlegen") }, leadingIcon = { Icon(Icons.Rounded.School, null) })
        }
        if (places.none { it.kind == "home" }) item {
            AssistChip(onClick = { onEdit(PlaceDraft(Place(kind = "home", name = "Zuhause", radiusM = 80, lat = bagLocation?.lat ?: 51.43, lon = bagLocation?.lon ?: 6.76))) },
                label = { Text("Zuhause festlegen") }, leadingIcon = { Icon(Icons.Rounded.Home, null) })
        }
        items(places, key = { it.id }) { place ->
            SectionCard(modifier = Modifier.clickable { onFocus(place.lat to place.lon) }) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(42.dp).background(placeColor(place.kind).copy(alpha = 0.15f), RoundedCornerShape(14.dp)), contentAlignment = Alignment.Center) {
                        Icon(when (place.kind) { "school" -> Icons.Rounded.School; "home" -> Icons.Rounded.Home; else -> Icons.Rounded.Place }, null, tint = placeColor(place.kind))
                    }
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(place.name, style = MaterialTheme.typography.titleMedium)
                        Text("Radius ${place.radiusM} m", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    FilledTonalButton(onClick = { onEdit(PlaceDraft(place)) }) { Text("Bearbeiten") }
                }
            }
        }
        item {
            Button(onClick = { onEdit(PlaceDraft(Place(kind = "other", name = "", lat = bagLocation?.lat ?: 51.43, lon = bagLocation?.lon ?: 6.76))) }, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Rounded.Add, null); Spacer(Modifier.width(8.dp)); Text("Weiteren Ort hinzufügen")
            }
        }
    }
}

@Suppress("unused")
private val filler = Modifier.fillMaxHeight()
