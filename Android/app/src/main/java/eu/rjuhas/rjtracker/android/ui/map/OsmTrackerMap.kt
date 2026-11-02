package eu.rjuhas.rjtracker.android.ui.map

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.BitmapDrawable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import org.osmdroid.events.DelayedMapListener
import org.osmdroid.events.MapListener
import org.osmdroid.events.ScrollEvent
import org.osmdroid.events.ZoomEvent
import org.osmdroid.tileprovider.tilesource.OnlineTileSourceBase
import org.osmdroid.tileprovider.tilesource.XYTileSource
import org.osmdroid.util.MapTileIndex
import org.osmdroid.util.BoundingBox
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.CustomZoomButtonsController
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.CopyrightOverlay
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polygon
import org.osmdroid.views.overlay.Polyline
import org.osmdroid.views.overlay.TilesOverlay
import org.osmdroid.tileprovider.MapTileProviderBasic

@Composable
internal fun OsmTrackerMap(
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
    val context = LocalContext.current
    val density = LocalDensity.current.density
    val dark = isSystemInDarkTheme()
    val labelOverlays = remember { LabelOverlays(context) }
    val map = remember {
        MapView(context).apply {
            setTileSource(OSM_STANDARD)
            setMultiTouchControls(true)
            zoomController.setVisibility(CustomZoomButtonsController.Visibility.NEVER)
            isTilesScaledToDpi = true
            minZoomLevel = 3.0
            controller.setZoom(6.0)
            controller.setCenter(GeoPoint(51.1657, 10.4515))
        }
    }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> map.onResume()
                Lifecycle.Event.ON_PAUSE -> map.onPause()
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer); map.onDetach() }
    }
    if (onCenterChanged != null) {
        DisposableEffect(map) {
            val listener = DelayedMapListener(object : MapListener {
                override fun onScroll(event: ScrollEvent?): Boolean { map.mapCenter.let { onCenterChanged(it.latitude, it.longitude) }; return true }
                override fun onZoom(event: ZoomEvent?): Boolean { map.mapCenter.let { onCenterChanged(it.latitude, it.longitude) }; return true }
            }, 250)
            map.addMapListener(listener)
            onDispose { map.removeMapListener(listener) }
        }
    }
    LaunchedEffect(camera?.key) {
        val target = camera ?: return@LaunchedEffect
        val points = target.points.map { GeoPoint(it.first, it.second) }
        if (points.isEmpty()) return@LaunchedEffect
        map.post {
            // Keep the target in the visible upper part above the bottom sheet.
            val shift = (bottomPadding.value * density / 2).toInt()
            if (points.distinct().size == 1) {
                map.controller.setZoom(target.singleZoom.toDouble())
                map.controller.setCenter(points.first())
            } else {
                val box = BoundingBox.fromGeoPointsSafe(points).increaseByScale(1.35f)
                map.zoomToBoundingBox(box, false, (48 * density).toInt())
            }
            map.post { map.scrollBy(0, shift); map.invalidate() }
        }
    }
    AndroidView(factory = { map }, modifier = modifier, update = { view ->
        val style = if (prefs.style == MapStyle.AUTO) (if (dark) MapStyle.DARK else MapStyle.STANDARD) else prefs.style
        val wanted = when (style) {
            MapStyle.SATELLITE -> ESRI_IMAGERY
            MapStyle.DARK -> ESRI_DARK
            MapStyle.GRAY -> ESRI_GRAY
            MapStyle.LIGHT -> ESRI_TOPO
            else -> OSM_STANDARD
        }
        if (view.tileProvider.tileSource.name() != wanted.name()) view.setTileSource(wanted)
        val scale = if (prefs.largeLabels) 1.35f else 1f
        if (view.tilesScaleFactor != scale) view.tilesScaleFactor = scale
        view.overlays.clear()
        when {
            style == MapStyle.SATELLITE && prefs.satelliteLabels -> { view.overlays.add(labelOverlays.transport); view.overlays.add(labelOverlays.places) }
            style == MapStyle.DARK -> view.overlays.add(labelOverlays.darkReference)
            style == MapStyle.GRAY -> view.overlays.add(labelOverlays.lightReference)
        }
        view.overlays.add(CopyrightOverlay(context).apply {
            setAlignBottom(false); setAlignRight(true); setOffset((10 * density).toInt(), (262 * density).toInt()); setTextSize(9)
        })
        circles.forEach { circle ->
            view.overlays.add(Polygon(view).apply {
                points = Polygon.pointsAsCircle(GeoPoint(circle.lat, circle.lon), circle.radiusM)
                fillPaint.color = circle.color.copy(alpha = if (circle.accuracy) 0.18f else 0.10f).toArgb()
                outlinePaint.color = circle.color.copy(alpha = if (circle.accuracy) 0.0f else 0.55f).toArgb()
                outlinePaint.strokeWidth = 1.5f * density
                setOnClickListener { _, _, _ -> false }
            })
        }
        lines.forEach { line ->
            if (line.points.size >= 2) view.overlays.add(Polyline(view).apply {
                setPoints(line.points.map { GeoPoint(it.first, it.second) })
                outlinePaint.color = line.color.toArgb()
                outlinePaint.strokeWidth = line.widthDp * density
                outlinePaint.strokeCap = Paint.Cap.ROUND
                outlinePaint.strokeJoin = Paint.Join.ROUND
            })
        }
        markers.sortedBy { it.kind == MarkerKind.BAG || it.kind == MarkerKind.CURSOR }.forEach { item ->
            view.overlays.add(Marker(view).apply {
                position = GeoPoint(item.lat, item.lon)
                icon = BitmapDrawable(view.resources, markerBitmap(item, density))
                setAnchor(Marker.ANCHOR_CENTER, if (item.kind == MarkerKind.BAG) Marker.ANCHOR_BOTTOM else Marker.ANCHOR_CENTER)
                title = item.title.ifBlank { null }
                setOnMarkerClickListener { _, _ -> onMarkerClick(item.id); true }
            })
        }
        view.invalidate()
    })
}

private fun markerBitmap(marker: MapMarker, density: Float): Bitmap {
    val fill = marker.color.toArgb()
    val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER; typeface = Typeface.DEFAULT_BOLD }
    val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    fun circle(sizeDp: Float, ring: Float, label: String, textSp: Float, labelColor: Int): Bitmap {
        val size = (sizeDp * density).toInt()
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        paint.color = android.graphics.Color.WHITE
        canvas.drawCircle(size / 2f, size / 2f, size / 2f, paint)
        paint.color = fill
        canvas.drawCircle(size / 2f, size / 2f, size / 2f - ring * density, paint)
        if (label.isNotEmpty()) {
            text.textSize = textSp * density
            text.color = labelColor
            canvas.drawText(label, size / 2f, size / 2f - (text.descent() + text.ascent()) / 2, text)
        }
        return bitmap
    }
    return when (marker.kind) {
        MarkerKind.BAG -> {
            val head = circle(64f, 4f, marker.label.ifBlank { "🎒" }, 34f, android.graphics.Color.WHITE)
            val tip = 10f * density
            val pin = Bitmap.createBitmap(head.width, (head.height + tip).toInt(), Bitmap.Config.ARGB_8888)
            val canvas = Canvas(pin)
            paint.color = android.graphics.Color.WHITE
            val path = android.graphics.Path().apply {
                moveTo(head.width / 2f - 9f * density, head.height - 6f * density)
                lineTo(head.width / 2f + 9f * density, head.height - 6f * density)
                lineTo(head.width / 2f, head.height + tip)
                close()
            }
            canvas.drawPath(path, paint)
            canvas.drawBitmap(head, 0f, 0f, null)
            pin
        }
        MarkerKind.CLUSTER -> circle(if (marker.label.length > 2) 40f else 34f, 2f, marker.label, 12f, android.graphics.Color.WHITE)
        MarkerKind.CURSOR -> circle(24f, 4f, "", 0f, 0)
        MarkerKind.EVIDENCE -> circle(18f, 2f, "", 0f, 0)
        MarkerKind.START, MarkerKind.END, MarkerKind.PLACE -> {
            text.textSize = 12f * density
            val pad = 8f * density
            val width = (text.measureText(marker.label) + pad * 2).toInt().coerceAtLeast(1)
            val height = (24f * density).toInt()
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())
            val isPlace = marker.kind == MarkerKind.PLACE
            paint.color = if (isPlace) android.graphics.Color.WHITE else fill
            canvas.drawRoundRect(rect, 10f * density, 10f * density, paint)
            if (isPlace) {
                paint.style = Paint.Style.STROKE; paint.strokeWidth = 2f * density; paint.color = fill
                canvas.drawRoundRect(RectF(density, density, width - density, height - density), 10f * density, 10f * density, paint)
                paint.style = Paint.Style.FILL
            }
            text.color = if (isPlace) fill else android.graphics.Color.WHITE
            canvas.drawText(marker.label, width / 2f, height / 2f - (text.descent() + text.ascent()) / 2, text)
            bitmap
        }
    }
}

// Keyless sources only (CARTO now requires an API key). OSM tiles are used
// within the OSMF tile policy: own User-Agent, on-device cache, family use.
private val OSM_STANDARD = XYTileSource("OSMStandard", 1, 19, 256, ".png",
    arrayOf("https://tile.openstreetmap.org/"), "© OpenStreetMap-Mitwirkende")

/** Esri ArcGIS services use z/y/x ordering. */
private fun esri(name: String, service: String, maxZoom: Int, png: Boolean = false) = object : OnlineTileSourceBase(name, 1, maxZoom, 256, if (png) ".png" else "",
    arrayOf("https://server.arcgisonline.com/ArcGIS/rest/services/$service/MapServer/tile/"), "Karte © Esri, OpenStreetMap") {
    override fun getTileURLString(index: Long): String =
        baseUrl + MapTileIndex.getZoom(index) + "/" + MapTileIndex.getY(index) + "/" + MapTileIndex.getX(index)
}

private val ESRI_IMAGERY = esri("EsriImagery", "World_Imagery", 19)
private val ESRI_TOPO = esri("EsriTopo", "World_Topo_Map", 19)
private val ESRI_GRAY = esri("EsriLightGray", "Canvas/World_Light_Gray_Base", 16)
private val ESRI_DARK = esri("EsriDarkGray", "Canvas/World_Dark_Gray_Base", 16)

/** Transparent label layers drawn above the base map; created once per map. */
private class LabelOverlays(private val context: android.content.Context) {
    private fun overlay(source: OnlineTileSourceBase) = TilesOverlay(MapTileProviderBasic(context, source), context).apply {
        loadingBackgroundColor = android.graphics.Color.TRANSPARENT
        loadingLineColor = android.graphics.Color.TRANSPARENT
    }
    val transport by lazy { overlay(esri("EsriTransport", "Reference/World_Transportation", 19)) }
    val places by lazy { overlay(esri("EsriPlaces", "Reference/World_Boundaries_and_Places", 19)) }
    val lightReference by lazy { overlay(esri("EsriLightRef", "Canvas/World_Light_Gray_Reference", 16)) }
    val darkReference by lazy { overlay(esri("EsriDarkRef", "Canvas/World_Dark_Gray_Reference", 16)) }
}
