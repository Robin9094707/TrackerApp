package eu.rjuhas.rjtracker.android.ui.map

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Path
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import eu.rjuhas.rjtracker.android.BuildConfig

enum class MarkerKind { BAG, CLUSTER, START, END, CURSOR, PLACE, EVIDENCE }

data class MapMarker(
    val id: String,
    val lat: Double,
    val lon: Double,
    val kind: MarkerKind,
    val label: String = "",
    val title: String = "",
    val color: Color = Color(0xFF2F5DF5),
)

data class MapCircle(val id: String, val lat: Double, val lon: Double, val radiusM: Double, val color: Color)
data class MapLine(val points: List<Pair<Double, Double>>, val color: Color, val widthDp: Float = 5f)

/** Changing [key] moves the camera to fit [points]. */
data class CameraTarget(val key: Any, val points: List<Pair<Double, Double>>, val singleZoom: Float = 16f)

val mapsKeyAvailable: Boolean get() = BuildConfig.MAPS_API_KEY.isNotBlank()

/**
 * Google Maps when a Maps key is built in, otherwise OpenStreetMap. Both are
 * fully interactive inside the app; only "Navigieren" opens an external app.
 */
@Composable
fun TrackerMap(
    modifier: Modifier = Modifier,
    markers: List<MapMarker> = emptyList(),
    circles: List<MapCircle> = emptyList(),
    lines: List<MapLine> = emptyList(),
    camera: CameraTarget? = null,
    bottomPadding: Dp = 0.dp,
    onMarkerClick: (String) -> Unit = {},
    onCenterChanged: ((Double, Double) -> Unit)? = null,
    satellite: Boolean = false,
) {
    if (mapsKeyAvailable) {
        GoogleTrackerMap(modifier, markers, circles, lines, camera, bottomPadding, onMarkerClick, onCenterChanged, satellite)
    } else {
        OsmTrackerMap(modifier, markers, circles, lines, camera, bottomPadding, onMarkerClick, onCenterChanged, satellite)
    }
}

/** Shared marker look (Compose for Google Maps, rendered to bitmaps for OSM). */
@Composable
fun MarkerBubble(marker: MapMarker) {
    when (marker.kind) {
        MarkerKind.BAG -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Box(
                Modifier.size(64.dp).shadow(10.dp, CircleShape).background(Color.White, CircleShape).padding(4.dp)
                    .background(Brush.linearGradient(listOf(marker.color, marker.color.copy(red = (marker.color.red * 0.6f)))), CircleShape),
                contentAlignment = Alignment.Center,
            ) { Text(marker.label.ifBlank { "🎒" }, fontSize = 32.sp) }
            Canvas(Modifier.size(width = 18.dp, height = 10.dp)) {
                drawPath(Path().apply { moveTo(0f, 0f); lineTo(size.width, 0f); lineTo(size.width / 2, size.height); close() }, Color.White)
            }
        }
        MarkerKind.CLUSTER -> Box(
            Modifier.size(if (marker.label.length > 2) 40.dp else 34.dp).shadow(4.dp, CircleShape)
                .background(marker.color, CircleShape).border(2.dp, Color.White, CircleShape),
            contentAlignment = Alignment.Center,
        ) { Text(marker.label, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold) }
        MarkerKind.START, MarkerKind.END -> Box(
            Modifier.shadow(4.dp, RoundedCornerShape(10.dp)).background(marker.color, RoundedCornerShape(10.dp)).padding(horizontal = 8.dp, vertical = 4.dp),
        ) { Text(marker.label, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold) }
        MarkerKind.CURSOR -> Box(
            Modifier.size(26.dp).background(marker.color.copy(alpha = 0.25f), CircleShape).padding(5.dp)
                .background(marker.color, CircleShape).border(3.dp, Color.White, CircleShape),
        )
        MarkerKind.PLACE -> Box(
            Modifier.shadow(3.dp, RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surface, RoundedCornerShape(12.dp))
                .border(2.dp, marker.color, RoundedCornerShape(12.dp)).padding(horizontal = 8.dp, vertical = 3.dp),
        ) { Text(marker.label, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = marker.color) }
        MarkerKind.EVIDENCE -> Box(
            Modifier.size(18.dp).background(marker.color, CircleShape).border(2.dp, Color.White, CircleShape),
        )
    }
}
