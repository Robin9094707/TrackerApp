package eu.rjuhas.rjtracker.android.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.TimeUnit

class ApiException(val httpStatus: Int, val code: String, message: String) : Exception(message) {
    val needsPassword get() = code == "password_required" || code == "wrong_password"
    val isGone get() = httpStatus == 404 || httpStatus == 410
}

class Api(private val client: OkHttpClient = defaultClient) {
    companion object {
        val json = Json { ignoreUnknownKeys = true; explicitNulls = false; coerceInputValues = true; encodeDefaults = true }
        val defaultClient: OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .callTimeout(45, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .build()
        private val JSON_TYPE = "application/json; charset=utf-8".toMediaType()
    }

    private suspend fun call(url: String, method: String = "GET", body: String? = null, headers: Map<String, String> = emptyMap()): String =
        withContext(Dispatchers.IO) {
            val builder = Request.Builder().url(url).header("Accept", "application/json").header("User-Agent", "RJTrackerAndroid/1.0")
            headers.forEach { (key, value) -> builder.header(key, value) }
            val requestBody = body?.toRequestBody(JSON_TYPE)
            when (method) {
                "GET" -> builder.get()
                "DELETE" -> builder.delete(requestBody ?: "{}".toRequestBody(JSON_TYPE))
                else -> builder.method(method, requestBody ?: "{}".toRequestBody(JSON_TYPE))
            }
            try {
                client.newCall(builder.build()).execute().use { response ->
                    val text = response.body?.string().orEmpty()
                    if (!response.isSuccessful && response.code != 429) {
                        val error = runCatching { json.decodeFromString(ApiError.serializer(), text) }.getOrNull()
                        throw ApiException(response.code, error?.code.orEmpty(), error?.message?.ifBlank { null } ?: defaultMessage(response.code))
                    }
                    text
                }
            } catch (error: IOException) {
                throw ApiException(0, "network", "Keine Verbindung zum Server. Bitte Internet prüfen.")
            }
        }

    private fun defaultMessage(code: Int) = when (code) {
        401 -> "Zugriff verweigert."
        404 -> "Dieser Link ist nicht mehr gültig."
        410 -> "Diese Freigabe ist abgelaufen."
        429 -> "Bitte kurz warten."
        else -> "Serverfehler ($code)."
    }

    // --- school ---------------------------------------------------------------
    private fun school(link: SavedLink, path: String = "") = "${link.baseUrl}/api/school/${link.token}$path"

    suspend fun schoolOverview(link: SavedLink): SchoolOverview =
        json.decodeFromString(SchoolOverview.serializer(), call(school(link)))

    suspend fun schoolOverview(base: String, token: String): SchoolOverview =
        json.decodeFromString(SchoolOverview.serializer(), call("$base/api/school/$token"))

    suspend fun schoolHistory(link: SavedLink, ref: String, from: Long, to: Long): HistoryResponse =
        json.decodeFromString(HistoryResponse.serializer(),
            call(school(link, "/history?ref=${android.net.Uri.encode(ref)}&from=$from&to=$to")))

    suspend fun schoolAttendance(link: SavedLink, days: Int = 60): AttendanceResponse =
        json.decodeFromString(AttendanceResponse.serializer(), call(school(link, "/attendance?days=$days")))

    suspend fun schoolEvents(link: SavedLink, after: Long): EventsResponse =
        json.decodeFromString(EventsResponse.serializer(), call(school(link, "/events?after=$after")))

    suspend fun schoolLocate(link: SavedLink, ref: String?): LocateResponse {
        val body = buildJsonObject { if (ref != null) put("ref", ref) }
        return json.decodeFromString(LocateResponse.serializer(), call(school(link, "/locate"), "POST", body.toString()))
    }

    suspend fun savePlace(link: SavedLink, place: Place) {
        val body = buildJsonObject {
            if (place.id.isNotBlank()) put("id", place.id)
            put("kind", place.kind); put("name", place.name); put("lat", place.lat); put("lon", place.lon); put("radius_m", place.radiusM)
        }
        call(school(link, "/places"), "POST", body.toString())
    }

    suspend fun deletePlace(link: SavedLink, id: String) {
        call(school(link, "/places/${android.net.Uri.encode(id)}"), "DELETE")
    }

    suspend fun saveSchedule(link: SavedLink, schedule: Schedule) {
        val body = buildJsonObject {
            putJsonObject("days") {
                schedule.days.forEach { (day, cfg) ->
                    putJsonObject(day) { put("enabled", cfg.enabled); put("start", cfg.start); put("end", cfg.end) }
                }
            }
            put("grace_minutes", schedule.graceMinutes)
            put("absent_after_minutes", schedule.absentAfterMinutes)
            put("off_days", kotlinx.serialization.json.JsonArray(schedule.offDays.map {
                JsonObject(mapOf("day" to JsonPrimitive(it.day), "label" to JsonPrimitive(it.label)))
            }))
        }
        call(school(link, "/schedule"), "POST", body.toString())
    }

    // --- guest ----------------------------------------------------------------
    private fun guest(base: String, id: String, path: String = "") = "$base/api/shared/$id/app$path"
    private fun guestHeaders(token: String?) = if (token.isNullOrBlank()) emptyMap() else mapOf("X-Share-Token" to token)

    suspend fun guestView(base: String, id: String, appToken: String?, password: String? = null): GuestView {
        val body = buildJsonObject { if (!password.isNullOrBlank()) put("pw", password) }
        return json.decodeFromString(GuestView.serializer(), call(guest(base, id), "POST", body.toString(), guestHeaders(appToken)))
    }

    suspend fun guestHistory(link: SavedLink, from: Long, to: Long): GuestHistory {
        val body = buildJsonObject { put("from", from); put("to", to) }
        return json.decodeFromString(GuestHistory.serializer(), call(guest(link.baseUrl, link.token, "/history"), "POST", body.toString(), guestHeaders(link.appToken)))
    }

    suspend fun guestLocate(link: SavedLink): LocateResponse =
        json.decodeFromString(LocateResponse.serializer(), call(guest(link.baseUrl, link.token, "/locate"), "POST", "{}", guestHeaders(link.appToken)))
}
