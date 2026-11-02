package eu.rjuhas.rjtracker.android.ui.map

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MapSettingsSheet(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val prefs = rememberMapPrefs()
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 36.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("Karte", style = MaterialTheme.typography.headlineSmall)
            MapStyle.entries.chunked(3).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    row.forEach { style ->
                        val selected = prefs.style == style
                        Surface(onClick = { MapPrefsStore.update(context) { it.copy(style = style) } }, shape = RoundedCornerShape(20.dp),
                            color = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainerHigh,
                            modifier = Modifier.weight(1f)) {
                            Column(Modifier.padding(10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                                Box(Modifier.fillMaxWidth().height(64.dp)
                                    .background(Brush.linearGradient(style.swatch), RoundedCornerShape(14.dp))
                                    .border(if (selected) 3.dp else 0.dp, MaterialTheme.colorScheme.primary, RoundedCornerShape(14.dp)),
                                    contentAlignment = Alignment.TopEnd) {
                                    if (selected) Icon(Icons.Rounded.CheckCircle, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(6.dp).size(22.dp))
                                }
                                Spacer(Modifier.height(8.dp))
                                Text(style.label, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
                            }
                        }
                    }
                }
            }
            Text(prefs.style.hint, color = MaterialTheme.colorScheme.onSurfaceVariant)
            SettingSwitch("Straßennamen im Satellitenbild", "Beschriftung über dem Luftbild", prefs.satelliteLabels) { value -> MapPrefsStore.update(context) { it.copy(satelliteLabels = value) } }
            SettingSwitch("Orte anzeigen", "Zuhause, Schule und weitere Orte mit Radius", prefs.showPlaces) { value -> MapPrefsStore.update(context) { it.copy(showPlaces = value) } }
            SettingSwitch("Genauigkeitskreis", "Wie genau die letzte Ortung war", prefs.showAccuracy) { value -> MapPrefsStore.update(context) { it.copy(showAccuracy = value) } }
            SettingSwitch("Große Kartenschrift", "Straßennamen besser lesbar", prefs.largeLabels) { value -> MapPrefsStore.update(context) { it.copy(largeLabels = value) } }
            if (!mapsKeyAvailable) Text("Kartendaten: © OpenStreetMap-Mitwirkende, Esri. Kein Konto und kein Schlüssel nötig.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun SettingSwitch(title: String, subtitle: String, value: Boolean, onChange: (Boolean) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.SemiBold)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Switch(value, onChange)
    }
}
