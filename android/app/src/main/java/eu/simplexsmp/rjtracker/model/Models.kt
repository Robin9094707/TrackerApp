package eu.simplexsmp.rjtracker.model

import java.util.Locale

enum class Provider(val apiName: String, val displayName: String) {
    APPLE("apple", "Apple Find My"),
    GOOGLE("google", "Google Find Hub"),
    SAMSUNG("samsung", "Samsung SmartThings Find"),
    TRACKER("tracker", "Tracker");

    companion object {
        fun fromApi(value: String?): Provider = when (value?.lowercase(Locale.ROOT)) {
            "apple" -> APPLE
            "google" -> GOOGLE
            "samsung" -> SAMSUNG
            else -> TRACKER
        }
    }
}

data class TrackerLocation(
    val source: Provider,
    val lat: Double,
    val lon: Double,
    val accuracyMeters: Double? = null,
    val timestamp: Long = 0,
    val address: String? = null,
    val batteryLabel: String? = null,
    val privacyPrecision: String? = null,
)

data class ProviderInfo(
    val source: Provider,
    val label: String,
    val live: Boolean,
)

data class SharePermissions(
    val canLocate: Boolean = true,
    val showAccuracy: Boolean = true,
    val showAddress: Boolean = true,
    val showProvider: Boolean = true,
    val canNavigate: Boolean = true,
)

data class SharePayload(
    val device: String,
    val title: String,
    val emoji: String,
    val kind: String,
    val shareKind: String,
    val location: TrackerLocation?,
    val sourceLocations: Map<Provider, TrackerLocation>,
    val providers: List<ProviderInfo>,
    val permissions: SharePermissions,
    val expiresTs: Long,
    val generatedAt: Long,
    val nextLocateTs: Long,
    val locateCooldownSeconds: Int,
) {
    fun latestFor(visibleProviders: Set<Provider>): TrackerLocation? {
        val candidates = sourceLocations.values.filter { it.source in visibleProviders }
        return candidates.maxByOrNull { it.timestamp }
            ?: location?.takeIf { visibleProviders.isEmpty() || it.source in visibleProviders || it.source == Provider.TRACKER }
    }

    val isFusion: Boolean
        get() = shareKind == "fusion" || sourceLocations.keys.count { it != Provider.TRACKER } >= 2
}

data class SavedShare(
    val id: String,
    val shareUrl: String,
    val baseUrl: String,
    val linkId: String,
    val password: String,
    val title: String,
    val emoji: String,
    val addedAt: Long,
)

data class ParsedShareLink(
    val shareUrl: String,
    val baseUrl: String,
    val linkId: String,
)

data class LocateResult(
    val status: String,
    val nextLocateTs: Long = 0,
    val remainingSeconds: Int = 0,
)
