package eu.rjuhas.rjtracker.android.ui.common

import eu.rjuhas.rjtracker.android.data.Pt
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

fun distanceM(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
    val r = 6_371_000.0
    val p1 = Math.toRadians(lat1); val p2 = Math.toRadians(lat2)
    val dp = Math.toRadians(lat2 - lat1); val dl = Math.toRadians(lon2 - lon1)
    val a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
    return 2 * r * atan2(sqrt(a), sqrt(1 - a))
}

/** A stay-like group of consecutive reports. */
data class PointCluster(
    val lat: Double,
    val lon: Double,
    val count: Int,
    val startTs: Long,
    val endTs: Long,
    val radiusM: Double,
)

/**
 * Groups consecutive reports into stays. Accuracy-weighted centroids keep a
 * single vague report from pulling the route around, and lone reports that
 * jump away and straight back (classic crowd-sourcing outliers) are dropped
 * from the drawn route.
 */
fun clusterRoute(points: List<Pt>, mergeRadiusM: Double = 75.0): List<PointCluster> {
    val clean = dropSpikes(points.sortedBy { it.ts })
    val clusters = mutableListOf<MutableList<Pt>>()
    for (point in clean) {
        val current = clusters.lastOrNull()
        if (current != null) {
            val (cLat, cLon) = weightedCenter(current)
            val threshold = mergeRadiusM + minOf(point.acc, 150.0) * 0.5
            if (distanceM(cLat, cLon, point.lat, point.lon) <= threshold) { current.add(point); continue }
        }
        clusters.add(mutableListOf(point))
    }
    return clusters.map { group ->
        val (lat, lon) = weightedCenter(group)
        PointCluster(lat, lon, group.size, group.first().ts, group.last().ts,
            group.maxOf { distanceM(lat, lon, it.lat, it.lon) })
    }
}

private fun weightedCenter(points: List<Pt>): Pair<Double, Double> {
    var w = 0.0; var lat = 0.0; var lon = 0.0
    for (p in points) {
        val weight = 1.0 / maxOf(10.0, p.acc).let { it * it }
        w += weight; lat += p.lat * weight; lon += p.lon * weight
    }
    return lat / w to lon / w
}

fun dropSpikes(points: List<Pt>): List<Pt> {
    if (points.size < 3) return points
    val result = mutableListOf(points.first())
    for (i in 1 until points.size - 1) {
        val prev = result.last(); val p = points[i]; val next = points[i + 1]
        val out = distanceM(prev.lat, prev.lon, p.lat, p.lon)
        val back = distanceM(p.lat, p.lon, next.lat, next.lon)
        val direct = distanceM(prev.lat, prev.lon, next.lat, next.lon)
        val spike = out > 300 && back > 300 && direct < minOf(out, back) * 0.35 && (next.ts - prev.ts) < 30 * 60
        if (!spike) result.add(p)
    }
    result.add(points.last())
    return result
}
