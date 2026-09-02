package eu.simplexsmp.rjtracker.data

import eu.simplexsmp.rjtracker.model.LocateResult
import eu.simplexsmp.rjtracker.model.ParsedShareLink
import eu.simplexsmp.rjtracker.model.Provider
import eu.simplexsmp.rjtracker.model.ProviderInfo
import eu.simplexsmp.rjtracker.model.SavedShare
import eu.simplexsmp.rjtracker.model.SharePayload
import eu.simplexsmp.rjtracker.model.SharePermissions
import eu.simplexsmp.rjtracker.model.TrackerLocation
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

class ShareApi {
    fun parseShareLink(raw: String): ParsedShareLink {
        val candidate = URL_REGEX.find(raw.trim())?.value?.trimEnd('.', ',', ';', ')', ']') ?: raw.trim()
        val uri = runCatching { URI(candidate) }.getOrElse { throw ShareApiException(0, "Der Freigabelink ist ungültig.") }
        val scheme = uri.scheme?.lowercase()
        if (scheme !in setOf("http", "https") || uri.rawAuthority.isNullOrBlank() || uri.rawUserInfo != null) {
            throw ShareApiException(0, "Bitte einen vollständigen http(s)-Freigabelink einfügen.")
        }
        val match = SHARE_PATH_REGEX.matchEntire(uri.rawPath ?: "")
            ?: throw ShareApiException(0, "Der Link muss auf /shared/… zeigen.")
        val encodedId = match.groupValues[1]
        val linkId = URLDecoder.decode(encodedId, StandardCharsets.UTF_8.name())
        if (linkId.isBlank() || linkId.length > 256) throw ShareApiException(0, "Der Link enthält keine gültige Freigabe-ID.")
        val baseUrl = "${uri.scheme}://${uri.rawAuthority}".trimEnd('/')
        val canonical = "$baseUrl/shared/${URLEncoder.encode(linkId, StandardCharsets.UTF_8.name()).replace("+", "%20")}" 
        return ParsedShareLink(canonical, baseUrl, linkId)
    }

    fun fetchShare(share: SavedShare): SharePayload {
        val json = postJson(
            "${share.baseUrl}/api/shared/${encodePath(share.linkId)}",
            JSONObject().put("pw", share.password).put("remember", false),
        )
        return parseShare(json)
    }

    fun locate(share: SavedShare): LocateResult {
        val response = request(
            "${share.baseUrl}/api/shared/${encodePath(share.linkId)}/locate",
            JSONObject().put("pw", share.password),
        )
        val json = response.json
        if (response.code == 429 && json?.optString("status") == "cooldown") {
            return LocateResult(
                status = "cooldown",
                nextLocateTs = json.optLong("next_locate_ts", 0L),
                remainingSeconds = json.optInt("remaining", 0),
            )
        }
        ensureSuccess(response)
        return LocateResult(
            status = json?.optString("status", "ok") ?: "ok",
            nextLocateTs = json?.optLong("next_locate_ts", 0L) ?: 0L,
            remainingSeconds = json?.optInt("remaining", 0) ?: 0,
        )
    }

    fun resolveAddress(share: SavedShare, source: Provider): String? {
        val response = request(
            "${share.baseUrl}/api/shared/${encodePath(share.linkId)}/address",
            JSONObject().put("pw", share.password).put("source", source.apiName),
        )
        if (response.code in setOf(403, 404, 429, 502, 503)) return null
        ensureSuccess(response)
        return response.json?.optString("address")?.takeIf { it.isNotBlank() }
    }

    private fun postJson(url: String, body: JSONObject): JSONObject {
        val response = request(url, body)
        ensureSuccess(response)
        return response.json ?: throw ShareApiException(response.code, "Der Server hat keine gültigen JSON-Daten geliefert.")
    }

    private fun request(url: String, body: JSONObject): ApiResponse {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 15_000
            readTimeout = 20_000
            useCaches = false
            doInput = true
            doOutput = true
            setRequestProperty("Accept", "application/json")
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
            setRequestProperty("User-Agent", "RJ-Tracker-Share-Android/1.0.0")
        }
        return try {
            connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val code = connection.responseCode
            val stream = if (code in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
            val json = text.takeIf { it.isNotBlank() }?.let { runCatching { JSONObject(it) }.getOrNull() }
            ApiResponse(code, json, text)
        } catch (e: ShareApiException) {
            throw e
        } catch (e: Exception) {
            throw ShareApiException(0, "Verbindung zum Tracker-Server fehlgeschlagen: ${e.message ?: "Netzwerkfehler"}")
        } finally {
            connection.disconnect()
        }
    }

    private fun ensureSuccess(response: ApiResponse) {
        if (response.code in 200..299) return
        val serverMessage = response.json?.optString("message")?.takeIf { it.isNotBlank() }
        val message = when (response.code) {
            401 -> "Das Gast-Passwort ist falsch."
            404 -> serverMessage ?: "Diese Freigabe ist nicht mehr verfügbar."
            410 -> serverMessage ?: "Diese Freigabe ist abgelaufen."
            429 -> serverMessage ?: "Zu viele Versuche. Bitte später erneut versuchen."
            else -> serverMessage ?: "Tracker-Serverfehler (${response.code})."
        }
        throw ShareApiException(response.code, message)
    }

    private fun parseShare(json: JSONObject): SharePayload {
        val meta = json.optJSONObject("meta") ?: JSONObject()
        val permissionsJson = json.optJSONObject("permissions") ?: JSONObject()
        val permissions = SharePermissions(
            canLocate = permissionsJson.optBoolean("can_locate", true),
            showAccuracy = permissionsJson.optBoolean("show_accuracy", true),
            showAddress = permissionsJson.optBoolean("show_address", true),
            showProvider = permissionsJson.optBoolean("show_provider", true),
            canNavigate = permissionsJson.optBoolean("can_navigate", true),
        )

        val sourceLocations = linkedMapOf<Provider, TrackerLocation>()
        val rawSources = json.optJSONObject("source_locations")
        if (rawSources != null) {
            rawSources.keys().forEach { sourceKey ->
                val source = Provider.fromApi(sourceKey)
                val raw = rawSources.optJSONObject(sourceKey) ?: return@forEach
                parseLocation(raw, source)?.let { sourceLocations[source] = it }
            }
        }

        val generalLocationRaw = json.optJSONObject("location")
        val generalSource = generalLocationRaw?.optString("source")?.takeIf { it.isNotBlank() }
            ?: generalLocationRaw?.optString("provider")?.takeIf { it.isNotBlank() }
        val generalLocation = generalLocationRaw?.let { parseLocation(it, Provider.fromApi(generalSource)) }
        if (sourceLocations.isEmpty() && generalLocation != null) {
            sourceLocations[generalLocation.source] = generalLocation
        }

        val providers = buildList {
            val rawProviders = json.optJSONArray("providers")
            if (rawProviders != null) {
                for (i in 0 until rawProviders.length()) {
                    val item = rawProviders.optJSONObject(i) ?: continue
                    add(
                        ProviderInfo(
                            source = Provider.fromApi(item.optString("source")),
                            label = item.optString("label").ifBlank { Provider.fromApi(item.optString("source")).displayName },
                            live = item.optBoolean("live", true),
                        )
                    )
                }
            }
            if (isEmpty()) {
                sourceLocations.keys.forEach { add(ProviderInfo(it, it.displayName, true)) }
            }
        }.distinctBy { it.source }

        return SharePayload(
            device = json.optString("device"),
            title = meta.optString("name").ifBlank { json.optString("device", "Geteilter Tracker") },
            emoji = meta.optString("emoji").ifBlank { "📍" },
            kind = meta.optString("kind").ifBlank { "Geteilter Tracker" },
            shareKind = json.optString("share_kind", "tracker"),
            location = generalLocation,
            sourceLocations = sourceLocations,
            providers = providers,
            permissions = permissions,
            expiresTs = json.optLong("expires_ts", 0L),
            generatedAt = json.optLong("generated_at", 0L),
            nextLocateTs = json.optLong("next_locate_ts", 0L),
            locateCooldownSeconds = json.optInt("locate_cooldown_seconds", 30),
        )
    }

    private fun parseLocation(json: JSONObject, fallbackSource: Provider): TrackerLocation? {
        val lat = json.nullableDouble("lat") ?: return null
        val lon = json.nullableDouble("lon") ?: return null
        if (lat !in -90.0..90.0 || lon !in -180.0..180.0) return null
        val source = Provider.fromApi(
            json.optString("source").takeIf { it.isNotBlank() }
                ?: json.optString("provider").takeIf { it.isNotBlank() }
                ?: fallbackSource.apiName
        )
        return TrackerLocation(
            source = source,
            lat = lat,
            lon = lon,
            accuracyMeters = json.nullableDouble("acc")?.coerceAtLeast(0.0),
            timestamp = json.optLong("ts", 0L),
            address = formatAddress(json.opt("address")),
            batteryLabel = firstText(json, "battery_label", "battery", "bat"),
            privacyPrecision = json.optString("privacy_precision").takeIf { it.isNotBlank() },
        )
    }

    private fun formatAddress(value: Any?): String? {
        return when (value) {
            is String -> value.takeIf { it.isNotBlank() }
            is JSONObject -> {
                val direct = listOf("display_name", "label").firstNotNullOfOrNull { key ->
                    value.optString(key).takeIf { it.isNotBlank() }
                }
                direct ?: listOf(
                    value.optString("road"),
                    value.optString("house_number"),
                    value.optString("postcode"),
                    value.optString("locality").ifBlank { value.optString("city_line") },
                    value.optString("country"),
                ).filter { it.isNotBlank() }.joinToString(" ").takeIf { it.isNotBlank() }
            }
            else -> null
        }
    }

    private fun firstText(json: JSONObject, vararg keys: String): String? {
        keys.forEach { key ->
            if (json.has(key) && !json.isNull(key)) {
                val value = json.opt(key)?.toString()?.trim()
                if (!value.isNullOrBlank()) return value
            }
        }
        return null
    }

    private fun JSONObject.nullableDouble(key: String): Double? {
        if (!has(key) || isNull(key)) return null
        return runCatching { getDouble(key) }.getOrNull()?.takeIf { it.isFinite() }
    }

    private fun encodePath(value: String): String =
        URLEncoder.encode(value, StandardCharsets.UTF_8.name()).replace("+", "%20")

    private data class ApiResponse(val code: Int, val json: JSONObject?, val raw: String)

    private companion object {
        val SHARE_PATH_REGEX = Regex("^/shared/([^/]+)/?$")
        val URL_REGEX = Regex("https?://[^\\s]+", RegexOption.IGNORE_CASE)
    }
}

class ShareApiException(
    val statusCode: Int,
    override val message: String,
) : Exception(message)
