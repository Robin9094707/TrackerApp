package eu.rjuhas.rjtracker.android.ui.map

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.key
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.LatLngBounds
import com.google.maps.android.compose.Circle
import com.google.maps.android.compose.ComposeMapColorScheme
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapProperties
import com.google.maps.android.compose.MapType
import com.google.maps.android.compose.MapUiSettings
import com.google.maps.android.compose.MarkerComposable
import com.google.maps.android.compose.Polyline
import com.google.maps.android.compose.rememberCameraPositionState
import com.google.maps.android.compose.rememberUpdatedMarkerState
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter

@Composable
internal fun GoogleTrackerMap(
    modifier: Modifier,
    markers: List<MapMarker>,
    circles: List<MapCircle>,
    lines: List<MapLine>,
    camera: CameraTarget?,
    bottomPadding: Dp,
    onMarkerClick: (String) -> Unit,
    onCenterChanged: ((Double, Double) -> Unit)?,
    prefs: MapPrefs,
) {
    val cameraState = rememberCameraPositionState {
        position = CameraPosition.fromLatLngZoom(LatLng(51.1657, 10.4515), 5.5f)
    }
    LaunchedEffect(camera?.key) {
        val target = camera ?: return@LaunchedEffect
        val points = target.points.map { LatLng(it.first, it.second) }
        when {
            points.isEmpty() -> Unit
            points.size == 1 || points.distinct().size == 1 ->
                cameraState.animate(CameraUpdateFactory.newLatLngZoom(points.first(), target.singleZoom), 700)
            else -> {
                val bounds = LatLngBounds.builder().apply { points.forEach { include(it) } }.build()
                runCatching { cameraState.animate(CameraUpdateFactory.newLatLngBounds(bounds, 120), 700) }
            }
        }
    }
    if (onCenterChanged != null) {
        LaunchedEffect(cameraState) {
            snapshotFlow { cameraState.isMoving }.distinctUntilChanged().filter { !it }.collect {
                val center = cameraState.position.target
                onCenterChanged(center.latitude, center.longitude)
            }
        }
    }
    GoogleMap(
        modifier = modifier,
        cameraPositionState = cameraState,
        properties = MapProperties(isBuildingEnabled = true, mapType = when (prefs.style) { MapStyle.SATELLITE -> if (prefs.satelliteLabels) MapType.HYBRID else MapType.SATELLITE; else -> MapType.NORMAL }),
        uiSettings = MapUiSettings(zoomControlsEnabled = false, mapToolbarEnabled = false, myLocationButtonEnabled = false),
        contentPadding = PaddingValues(bottom = bottomPadding, top = 8.dp),
        mapColorScheme = when (prefs.style) { MapStyle.DARK -> ComposeMapColorScheme.DARK; MapStyle.AUTO -> ComposeMapColorScheme.FOLLOW_SYSTEM; else -> ComposeMapColorScheme.LIGHT },
    ) {
        circles.forEach { circle ->
            key(circle.id) {
                Circle(
                    center = LatLng(circle.lat, circle.lon), radius = circle.radiusM,
                    fillColor = circle.color.copy(alpha = if (circle.accuracy) 0.18f else 0.10f),
                    strokeColor = circle.color.copy(alpha = if (circle.accuracy) 0f else 0.55f), strokeWidth = 3f,
                )
            }
        }
        lines.forEach { line ->
            if (line.points.size >= 2) Polyline(
                points = line.points.map { LatLng(it.first, it.second) }, color = line.color, width = line.widthDp * 3f,
                geodesic = false,
            )
        }
        markers.forEach { marker ->
            key(marker.id) {
                MarkerComposable(
                    marker.id, marker.label, marker.kind, marker.color,
                    state = rememberUpdatedMarkerState(position = LatLng(marker.lat, marker.lon)),
                    title = marker.title.ifBlank { null },
                    zIndex = if (marker.kind == MarkerKind.BAG || marker.kind == MarkerKind.CURSOR) 10f else 1f,
                    anchor = if (marker.kind == MarkerKind.BAG) Offset(0.5f, 1f) else Offset(0.5f, 0.5f),
                    onClick = { onMarkerClick(marker.id); false },
                ) { MarkerBubble(marker) }
            }
        }
    }
}
