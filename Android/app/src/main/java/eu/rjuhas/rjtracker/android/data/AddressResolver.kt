package eu.rjuhas.rjtracker.android.data

import android.content.Context
import android.location.Address
import android.location.Geocoder
import android.os.Build
import android.util.LruCache
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.Request
import java.util.Locale
import kotlin.coroutines.resume

/**
 * Turns coordinates into a readable German address on the phone itself
 * (no server change, no API key): Android's geocoder first, OpenStreetMap
 * Nominatim as fallback (max. one request per second, cached).
 */
object AddressResolver {
    private val cache = LruCache<String, String>(300)
    private val nominatimLock = Mutex()
    private var lastNominatim = 0L

    private fun key(lat: Double, lon: Double) = "%.4f,%.4f".format(Locale.ROOT, lat, lon)

    fun cached(lat: Double, lon: Double): String? = cache.get(key(lat, lon))

    suspend fun resolve(context: Context, lat: Double, lon: Double): String? {
        val key = key(lat, lon)
        cache.get(key)?.let { return it }
        val result = withTimeoutOrNull(6_000) { fromGeocoder(context, lat, lon) } ?: withTimeoutOrNull(8_000) { fromNominatim(lat, lon) }
        if (!result.isNullOrBlank()) cache.put(key, result)
        return result
    }

    private suspend fun fromGeocoder(context: Context, lat: Double, lon: Double): String? {
        if (!Geocoder.isPresent()) return null
        val geocoder = Geocoder(context, Locale.GERMANY)
        val address: Address? = if (Build.VERSION.SDK_INT >= 33) {
            suspendCancellableCoroutine { continuation ->
                geocoder.getFromLocation(lat, lon, 1, object : Geocoder.GeocodeListener {
                    override fun onGeocode(addresses: MutableList<Address>) { if (continuation.isActive) continuation.resume(addresses.firstOrNull()) }
                    override fun onError(errorMessage: String?) { if (continuation.isActive) continuation.resume(null) }
                })
            }
        } else {
            withContext(Dispatchers.IO) {
                @Suppress("DEPRECATION")
                runCatching { geocoder.getFromLocation(lat, lon, 1)?.firstOrNull() }.getOrNull()
            }
        }
        return address?.let { format(it.thoroughfare, it.subThoroughfare, it.subLocality, it.postalCode, it.locality ?: it.subAdminArea) ?: it.getAddressLine(0) }
    }

    private suspend fun fromNominatim(lat: Double, lon: Double): String? = nominatimLock.withLock {
        val wait = 1100 - (System.currentTimeMillis() - lastNominatim)
        if (wait > 0) delay(wait)
        lastNominatim = System.currentTimeMillis()
        withContext(Dispatchers.IO) {
            runCatching {
                val url = "https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=18&accept-language=de&lat=$lat&lon=$lon"
                val request = Request.Builder().url(url).header("User-Agent", "RJTrackerAndroid/1.2 (eu.rjuhas.rjtracker.android)").build()
                Api.defaultClient.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) return@use null
                    val address = Api.json.parseToJsonElement(response.body?.string().orEmpty()).jsonObject["address"]?.jsonObject ?: return@use null
                    fun field(vararg names: String) = names.firstNotNullOfOrNull { address[it]?.jsonPrimitive?.content }
                    format(field("road", "pedestrian", "footway", "path"), field("house_number"), field("suburb", "quarter", "neighbourhood"),
                        field("postcode"), field("city", "town", "village", "municipality"))
                }
            }.getOrNull()
        }
    }

    /** "Gitschiner Straße 6, Hochfeld, 47053 Duisburg" */
    private fun format(street: String?, number: String?, district: String?, postcode: String?, city: String?): String? {
        val first = listOfNotNull(street, number).joinToString(" ").ifBlank { null }
        val last = listOfNotNull(postcode, city).joinToString(" ").ifBlank { null }
        val parts = listOfNotNull(first, district?.takeIf { it != city }, last)
        return parts.joinToString(", ").ifBlank { null }
    }

    fun coordinates(lat: Double, lon: Double): String =
        "%.5f° %s, %.5f° %s".format(Locale.GERMANY, kotlin.math.abs(lat), if (lat >= 0) "N" else "S", kotlin.math.abs(lon), if (lon >= 0) "O" else "W")
}
