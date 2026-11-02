package eu.rjuhas.rjtracker.android.ui.common

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Battery5Bar
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

/** Ticks every 30 s so "vor X Minuten" stays correct without new data. */
@Composable
fun rememberNow(): Long {
    var now by remember { mutableLongStateOf(System.currentTimeMillis() / 1000) }
    LaunchedEffect(Unit) { while (true) { delay(30_000); now = System.currentTimeMillis() / 1000 } }
    return now
}

fun freshnessColor(ts: Long?, now: Long): Color = when {
    ts == null || ts <= 0 -> Color(0xFF8A8F9E)
    now - ts < 30 * 60 -> Color(0xFF2FB36B)
    now - ts < 6 * 3600 -> Color(0xFFE59A12)
    else -> Color(0xFF8A8F9E)
}

/** Find-My-like header: big name, full address, "vor 14 Minuten · Akku", optional place chip. */
@Composable
fun LocationHeader(
    title: String,
    address: String?,
    ts: Long?,
    battery: String?,
    placeLabel: String? = null,
    placeColor: Color = MaterialTheme.colorScheme.primary,
    trailing: @Composable () -> Unit = {},
) {
    val now = rememberNow()
    Column(Modifier.fillMaxWidth().padding(horizontal = 22.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            Text(title, style = MaterialTheme.typography.headlineMedium.copy(fontSize = 30.sp, lineHeight = 34.sp),
                fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f), maxLines = 2, overflow = TextOverflow.Ellipsis)
            trailing()
        }
        Spacer(Modifier.height(6.dp))
        Text(address?.ifBlank { null } ?: "Adresse wird ermittelt …", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Normal),
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.86f), maxLines = 3, overflow = TextOverflow.Ellipsis)
        Spacer(Modifier.height(4.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(ago(ts, now), style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Medium), color = freshnessColor(ts, now))
            if (!battery.isNullOrBlank() && battery != "Unbekannt" && battery != "Nicht verfügbar") {
                Text("  ·  ", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Icon(Icons.Rounded.Battery5Bar, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(3.dp))
                Text(battery, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
            }
        }
        if (!placeLabel.isNullOrBlank()) {
            Spacer(Modifier.height(10.dp))
            Surface(color = placeColor.copy(alpha = 0.15f), contentColor = placeColor, shape = CircleShape) {
                Row(Modifier.padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(8.dp).background(placeColor, CircleShape))
                    Spacer(Modifier.width(8.dp))
                    Text(placeLabel, style = MaterialTheme.typography.labelLarge)
                }
            }
        }
    }
}

/** Large rounded action tile (like "Ton abspielen" / "Route" in Find My). */
@Composable
fun ActionTile(
    icon: @Composable () -> Unit,
    title: String,
    subtitle: String,
    color: Color,
    enabled: Boolean = true,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Surface(onClick = onClick, enabled = enabled, shape = RoundedCornerShape(26.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh, modifier = modifier.height(122.dp)) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.SpaceBetween) {
            Box(Modifier.size(42.dp).background(if (enabled) color else color.copy(alpha = 0.35f), CircleShape), contentAlignment = Alignment.Center) { icon() }
            Column {
                Text(title, style = MaterialTheme.typography.titleMedium, color = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f))
                Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable
fun TileIcon(icon: ImageVector) = Icon(icon, null, tint = Color.White, modifier = Modifier.size(24.dp))
