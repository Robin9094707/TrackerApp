@file:Suppress("DEPRECATION")

package eu.simplexsmp.rjtracker.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Bundle
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import eu.simplexsmp.rjtracker.model.Provider
import eu.simplexsmp.rjtracker.model.TrackerLocation
import org.maplibre.android.annotations.Icon
import org.maplibre.android.annotations.IconFactory
import org.maplibre.android.annotations.MarkerOptions
import org.maplibre.android.annotations.PolygonOptions
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

@Composable
fun TrackerMap(
    locations: List<TrackerLocation>,
    selected: TrackerLocation?,
    modifier: Modifier = Modifier,
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val mapView = remember {
        MapView(context).apply { onCreate(Bundle()) }
    }
    val controller = remember { TrackerMapController(context, mapView) }

    DisposableEffect(lifecycle, mapView) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> mapView.onStart()
                Lifecycle.Event.ON_RESUME -> mapView.onResume()
                Lifecycle.Event.ON_PAUSE -> mapView.onPause()
                Lifecycle.Event.ON_STOP -> mapView.onStop()
                Lifecycle.Event.ON_DESTROY -> mapView.onDestroy()
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose {
            lifecycle.removeObserver(observer)
            runCatching { mapView.onPause() }
            runCatching { mapView.onStop() }
            runCatching { mapView.onDestroy() }
        }
    }

    LaunchedEffect(locations, selected) {
        controller.update(locations, selected)
    }

    AndroidView(
        factory = { mapView },
        modifier = modifier,
    )
}

private class TrackerMapController(
    private val context: Context,
    mapView: MapView,
) {
    private var map: MapLibreMap? = null
    private var styleLoaded = false
    private var locations: List<TrackerLocation> = emptyList()
    private var selected: TrackerLocation? = null
    private var lastCameraKey: String? = null
    private val iconCache = mutableMapOf<Provider, Icon>()

    init {
        mapView.getMapAsync { readyMap ->
            map = readyMap
            readyMap.uiSettings.isCompassEnabled = true
            readyMap.uiSettings.isAttributionEnabled = true
            readyMap.setStyle(STYLE_URI) {
                styleLoaded = true
                render()
            }
        }
    }

    fun update(newLocations: List<TrackerLocation>, newSelected: TrackerLocation?) {
        locations = newLocations
        selected = newSelected
        render()
    }

    private fun render() {
        val map = map ?: return
        if (!styleLoaded) return
        map.clear()

        selected?.accuracyMeters
            ?.takeIf { it > 0.0 }
            ?.let { radius ->
                val fill = Color.argb(42, Color.red(providerColorArgb(selected!!.source)), Color.green(providerColorArgb(selected!!.source)), Color.blue(providerColorArgb(selected!!.source)))
                map.addPolygon(
                    PolygonOptions()
                        .addAll(accuracyCircle(selected!!.lat, selected!!.lon, radius.coerceAtLeast(8.0)))
                        .fillColor(fill)
                        .strokeColor(providerColorArgb(selected!!.source))
                )
            }

        locations.sortedBy { it.timestamp }.forEach { location ->
            val snippet = buildString {
                location.address?.let { append(it) }
                if (location.accuracyMeters != null) {
                    if (isNotEmpty()) append(" · ")
                    append("±${location.accuracyMeters.toInt()} m")
                }
            }
            map.addMarker(
                MarkerOptions()
                    .position(LatLng(location.lat, location.lon))
                    .title(location.source.displayName)
                    .snippet(snippet)
                    .icon(iconFor(location.source))
            )
        }

        selected?.let { location ->
            val key = "${location.source.apiName}:${location.lat}:${location.lon}:${location.timestamp}"
            if (key != lastCameraKey) {
                lastCameraKey = key
                val zoom = when {
                    (location.accuracyMeters ?: 0.0) >= 2_000 -> 12.5
                    (location.accuracyMeters ?: 0.0) >= 600 -> 14.0
                    (location.accuracyMeters ?: 0.0) >= 150 -> 15.5
                    else -> 17.0
                }
                map.animateCamera(
                    CameraUpdateFactory.newLatLngZoom(LatLng(location.lat, location.lon), zoom),
                    650,
                )
            }
        }
    }

    private fun iconFor(provider: Provider): Icon = iconCache.getOrPut(provider) {
        val size = 64
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.style = Paint.Style.FILL
        paint.color = Color.WHITE
        canvas.drawCircle(size / 2f, size / 2f, 24f, paint)
        paint.color = providerColorArgb(provider)
        canvas.drawCircle(size / 2f, size / 2f, 18f, paint)
        IconFactory.getInstance(context).fromBitmap(bitmap)
    }

    private fun accuracyCircle(lat: Double, lon: Double, radiusMeters: Double): List<LatLng> {
        val earthRadius = 6_378_137.0
        val angularDistance = radiusMeters / earthRadius
        val lat1 = Math.toRadians(lat)
        val lon1 = Math.toRadians(lon)
        return (0..72).map { step ->
            val bearing = Math.toRadians(step * 5.0)
            val lat2 = asin(
                sin(lat1) * cos(angularDistance) +
                    cos(lat1) * sin(angularDistance) * cos(bearing)
            )
            val lon2 = lon1 + atan2(
                sin(bearing) * sin(angularDistance) * cos(lat1),
                cos(angularDistance) - sin(lat1) * sin(lat2),
            )
            LatLng(Math.toDegrees(lat2), Math.toDegrees(lon2))
        }
    }

    private companion object {
        const val STYLE_URI = "https://tiles.openfreemap.org/styles/liberty"
    }
}
