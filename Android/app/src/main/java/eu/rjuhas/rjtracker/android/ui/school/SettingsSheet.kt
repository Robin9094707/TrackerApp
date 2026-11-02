package eu.rjuhas.rjtracker.android.ui.school

import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.BatteryAlert
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.EventBusy
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import eu.rjuhas.rjtracker.android.background.LiveWatchService
import eu.rjuhas.rjtracker.android.data.DayCfg
import eu.rjuhas.rjtracker.android.data.NotifyMode
import eu.rjuhas.rjtracker.android.data.NotifyTopic
import eu.rjuhas.rjtracker.android.data.OffDay
import eu.rjuhas.rjtracker.android.data.SavedLink
import eu.rjuhas.rjtracker.android.data.Schedule
import eu.rjuhas.rjtracker.android.ui.common.dayTitle
import eu.rjuhas.rjtracker.android.ui.common.zone
import java.time.Instant

private val weekdays = listOf("1" to "Montag", "2" to "Dienstag", "3" to "Mittwoch", "4" to "Donnerstag", "5" to "Freitag", "6" to "Samstag", "7" to "Sonntag")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SchoolSettingsSheet(vm: SchoolViewModel, link: SavedLink, onDismiss: () -> Unit, onRemoved: () -> Unit, onAllLinks: () -> Unit) {
    val context = LocalContext.current
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val original = vm.overview?.schedule ?: Schedule()
    var schedule by remember(original) {
        mutableStateOf(original.copy(days = weekdays.associate { (key, _) -> key to (original.days[key] ?: DayCfg(enabled = key.toInt() <= 5)) }))
    }
    var timeTarget by remember { mutableStateOf<Pair<String, Boolean>?>(null) }
    var addOffDay by remember { mutableStateOf(false) }
    var confirmRemove by remember { mutableStateOf(false) }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheet) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 40.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("Einstellungen", style = MaterialTheme.typography.headlineSmall)

            Text("Benachrichtigungen", style = MaterialTheme.typography.titleMedium)
            Text("„Einmal“ meldet nur das nächste Ereignis und schaltet sich danach aus.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            NotifyTopic.entries.forEach { topic ->
                Column {
                    Text(topic.label, fontWeight = FontWeight.SemiBold)
                    Text(topic.description, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    val modes = listOf(NotifyMode.OFF to "Aus", NotifyMode.ONCE to "Einmal", NotifyMode.ALWAYS to "Immer")
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(top = 6.dp)) {
                        modes.forEachIndexed { index, (mode, label) ->
                            SegmentedButton(selected = link.mode(topic) == mode, onClick = { vm.setNotify(topic, mode) },
                                shape = SegmentedButtonDefaults.itemShape(index, modes.size)) { Text(label) }
                        }
                    }
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("Sofort-Benachrichtigungen", fontWeight = FontWeight.SemiBold)
                    Text("Prüft alle 30 s im Hintergrund (kleines Symbol in der Statusleiste). Aus: alle 15 min.",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Switch(link.liveNotifications, { enabled -> vm.setLive(enabled) { LiveWatchService.ensureRunning(context) } })
            }
            OutlinedButton(onClick = {
                runCatching { context.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) }
            }) { Icon(Icons.Rounded.BatteryAlert, null); Spacer(Modifier.width(8.dp)); Text("Akku-Optimierung ausschalten") }

            HorizontalDivider()
            Text("Stundenplan", style = MaterialTheme.typography.titleMedium)
            weekdays.forEach { (key, label) ->
                val day = schedule.days[key] ?: DayCfg()
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Switch(day.enabled, { schedule = schedule.copy(days = schedule.days + (key to day.copy(enabled = it))) })
                    Spacer(Modifier.width(12.dp))
                    Text(label, modifier = Modifier.weight(1f))
                    TextButton(onClick = { timeTarget = key to true }, enabled = day.enabled) { Text(day.start) }
                    Text("–")
                    TextButton(onClick = { timeTarget = key to false }, enabled = day.enabled) { Text(day.end.ifBlank { "Ende?" }) }
                }
            }
            Text("Toleranz bis „verspätet“: ${schedule.graceMinutes} min")
            Slider(schedule.graceMinutes.toFloat(), { schedule = schedule.copy(graceMinutes = it.toInt()) }, valueRange = 0f..30f, steps = 29)
            Text("„Nicht in der Schule“ nach ${schedule.absentAfterMinutes} min")
            Slider(schedule.absentAfterMinutes.toFloat(), { schedule = schedule.copy(absentAfterMinutes = (it / 15).toInt() * 15) }, valueRange = 30f..240f)
            Text("Schulfreie Tage", fontWeight = FontWeight.SemiBold)
            schedule.offDays.forEach { off ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.EventBusy, null)
                    Spacer(Modifier.width(10.dp))
                    Text(dayTitle(off.day) + if (off.label.isNotBlank()) " · ${off.label}" else "", Modifier.weight(1f))
                    IconButton(onClick = { schedule = schedule.copy(offDays = schedule.offDays - off) }) { Icon(Icons.Rounded.Close, "Entfernen") }
                }
            }
            FilledTonalButton(onClick = { addOffDay = true }) { Text("Schulfreien Tag hinzufügen") }
            Button(onClick = { vm.saveSchedule(schedule) }, modifier = Modifier.fillMaxWidth()) { Text("Stundenplan speichern") }

            HorizontalDivider()
            FilledTonalButton(onClick = onAllLinks, modifier = Modifier.fillMaxWidth()) { Text("Alle Links · weiteren Link hinzufügen") }
            TextButton(onClick = { confirmRemove = true }) { Text("Link von diesem Gerät entfernen", color = MaterialTheme.colorScheme.error) }
        }
    }
    timeTarget?.let { (key, isStart) ->
        val day = schedule.days[key] ?: DayCfg()
        val current = (if (isStart) day.start else day.end.ifBlank { "13:00" }).split(":").map { it.toIntOrNull() ?: 0 }
        val state = rememberTimePickerState(current[0], current.getOrElse(1) { 0 }, is24Hour = true)
        AlertDialog(
            onDismissRequest = { timeTarget = null },
            title = { Text(if (isStart) "Schulbeginn" else "Schulende") },
            text = { TimePicker(state) },
            confirmButton = {
                TextButton(onClick = {
                    val value = "%02d:%02d".format(state.hour, state.minute)
                    schedule = schedule.copy(days = schedule.days + (key to if (isStart) day.copy(start = value) else day.copy(end = value)))
                    timeTarget = null
                }) { Text("Übernehmen") }
            },
            dismissButton = {
                if (!isStart) TextButton(onClick = {
                    schedule = schedule.copy(days = schedule.days + (key to day.copy(end = ""))); timeTarget = null
                }) { Text("Kein Ende") }
            },
        )
    }
    if (addOffDay) {
        val state = rememberDatePickerState()
        DatePickerDialog(
            onDismissRequest = { addOffDay = false },
            confirmButton = {
                TextButton(onClick = {
                    state.selectedDateMillis?.let { millis ->
                        val date = Instant.ofEpochMilli(millis).atZone(java.time.ZoneOffset.UTC).toLocalDate().toString()
                        schedule = schedule.copy(offDays = (schedule.offDays + OffDay(date, "Schulfrei")).distinctBy { it.day }.sortedBy { it.day })
                    }
                    addOffDay = false
                }) { Text("Hinzufügen") }
            },
        ) { DatePicker(state) }
    }
    if (confirmRemove) {
        AlertDialog(
            onDismissRequest = { confirmRemove = false },
            title = { Text("Link entfernen?") },
            text = { Text("Du kannst ihn jederzeit wieder einfügen. Auf dem Server wird nichts gelöscht.") },
            confirmButton = { TextButton(onClick = { vm.remove { LiveWatchService.ensureRunning(context); onRemoved() } }) { Text("Entfernen") } },
            dismissButton = { TextButton(onClick = { confirmRemove = false }) { Text("Abbrechen") } },
        )
    }
}

@Suppress("unused")
private val berlin = zone
