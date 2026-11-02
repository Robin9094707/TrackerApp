package eu.rjuhas.rjtracker.android.ui.school

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Place
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import eu.rjuhas.rjtracker.android.data.Place
import eu.rjuhas.rjtracker.android.ui.common.placeColor
import eu.rjuhas.rjtracker.android.ui.common.rememberAddress
import eu.rjuhas.rjtracker.android.ui.map.CameraTarget
import eu.rjuhas.rjtracker.android.ui.map.MapCircle
import eu.rjuhas.rjtracker.android.ui.map.TrackerMap

data class PlaceDraft(val place: Place)

private val kinds = listOf("home" to "Zuhause", "school" to "Schule", "other" to "Sonstiges")

@Composable
fun PlaceEditorDialog(draft: PlaceDraft, onDismiss: () -> Unit, onSave: (Place) -> Unit, onDelete: (() -> Unit)?) {
    var kind by remember { mutableStateOf(draft.place.kind) }
    var name by remember { mutableStateOf(draft.place.name) }
    var radius by remember { mutableFloatStateOf(draft.place.radiusM.toFloat()) }
    var center by remember { mutableStateOf(draft.place.lat to draft.place.lon) }
    val initialCamera = remember { CameraTarget("place-${draft.place.id}", listOf(draft.place.lat to draft.place.lon), 17f) }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Column(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f)) {
                    TrackerMap(
                        modifier = Modifier.fillMaxSize(),
                        circles = listOf(MapCircle("draft", center.first, center.second, radius.toDouble(), placeColor(kind))),
                        camera = initialCamera,
                        onCenterChanged = { lat, lon -> center = lat to lon },
                    )
                    Icon(Icons.Rounded.Place, null, tint = placeColor(kind),
                        modifier = Modifier.align(Alignment.Center).size(44.dp).offset(y = (-20).dp))
                    Row(Modifier.statusBarsPadding().padding(12.dp)) {
                        RoundButton(onClick = onDismiss) { Icon(Icons.Rounded.Close, "Schließen") }
                        Spacer(Modifier.width(10.dp))
                        Surface(shape = MaterialTheme.shapes.extraLarge, modifier = Modifier.shadow(6.dp, MaterialTheme.shapes.extraLarge)) {
                            Text("Karte verschieben, bis der Pin auf dem Ort steht", Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                                style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
                Column(Modifier.navigationBarsPadding().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        kinds.forEachIndexed { index, (value, label) ->
                            SegmentedButton(selected = kind == value, onClick = {
                                if (name.isBlank() || kinds.any { it.second == name }) name = if (value == "other") "" else label
                                kind = value
                            }, shape = SegmentedButtonDefaults.itemShape(index, kinds.size)) { Text(label) }
                        }
                    }
                    OutlinedTextField(name, { name = it.take(60) }, label = { Text("Name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    val pinAddress = rememberAddress(center.first, center.second, null)
                    Text(pinAddress.text ?: "Adresse wird geladen …", style = MaterialTheme.typography.titleMedium, maxLines = 2)
                    Text("Radius ${radius.toInt()} m · für Schulen 100–200 m empfohlen", style = MaterialTheme.typography.bodyMedium)
                    Slider(radius, { radius = it }, valueRange = 30f..600f)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        if (onDelete != null) TextButton(onClick = onDelete) { Icon(Icons.Rounded.Delete, null); Spacer(Modifier.width(6.dp)); Text("Löschen") }
                        Spacer(Modifier.weight(1f))
                        Button(onClick = {
                            onSave(draft.place.copy(kind = kind, name = name.ifBlank { kinds.first { it.first == kind }.second }, lat = center.first, lon = center.second, radiusM = radius.toInt()))
                        }, modifier = Modifier.height(52.dp)) { Text("Ort speichern") }
                    }
                }
            }
        }
    }
}
