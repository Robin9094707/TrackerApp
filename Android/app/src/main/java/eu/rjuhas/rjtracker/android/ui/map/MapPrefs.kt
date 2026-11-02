package eu.rjuhas.rjtracker.android.ui.map

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.graphics.Color
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

enum class MapStyle(val label: String, val hint: String, val swatch: List<Color>) {
    AUTO("Automatisch", "Hell am Tag, dunkel im Dunkelmodus", listOf(Color(0xFFF3F1EA), Color(0xFF2B2D33))),
    STANDARD("Standard", "Farbige Straßenkarte", listOf(Color(0xFFF2EFE9), Color(0xFFAAD3DF), Color(0xFFCDEBB0))),
    LIGHT("Hell", "Klar und ruhig, gut lesbar", listOf(Color(0xFFFFFFFF), Color(0xFFE8F0E0), Color(0xFFD0D0D0))),
    GRAY("Grau", "Dezent, der Pin sticht hervor", listOf(Color(0xFFEDEDED), Color(0xFFCFCFCF))),
    DARK("Dunkel", "Schont die Augen am Abend", listOf(Color(0xFF2F3035), Color(0xFF55575E))),
    SATELLITE("Satellit", "Luftbild mit Straßennamen", listOf(Color(0xFF3B5B3A), Color(0xFF7D8B6A), Color(0xFFB9A27C))),
}

data class MapPrefs(
    val style: MapStyle = MapStyle.AUTO,
    val satelliteLabels: Boolean = true,
    val showPlaces: Boolean = true,
    val showAccuracy: Boolean = true,
    val largeLabels: Boolean = false,
)

/** Small, synchronous store; map settings are per device. */
object MapPrefsStore {
    private val state = MutableStateFlow(MapPrefs())
    val prefs: StateFlow<MapPrefs> = state
    private var loaded = false

    fun init(context: Context) {
        if (loaded) return
        val p = context.getSharedPreferences("map_prefs", Context.MODE_PRIVATE)
        state.value = MapPrefs(
            style = runCatching { MapStyle.valueOf(p.getString("style", MapStyle.AUTO.name)!!) }.getOrDefault(MapStyle.AUTO),
            satelliteLabels = p.getBoolean("sat_labels", true),
            showPlaces = p.getBoolean("places", true),
            showAccuracy = p.getBoolean("accuracy", true),
            largeLabels = p.getBoolean("large", false),
        )
        loaded = true
    }

    fun update(context: Context, change: (MapPrefs) -> MapPrefs) {
        val next = change(state.value)
        state.value = next
        context.getSharedPreferences("map_prefs", Context.MODE_PRIVATE).edit()
            .putString("style", next.style.name).putBoolean("sat_labels", next.satelliteLabels)
            .putBoolean("places", next.showPlaces).putBoolean("accuracy", next.showAccuracy)
            .putBoolean("large", next.largeLabels).apply()
    }
}

@Composable
fun rememberMapPrefs(): MapPrefs {
    val prefs by MapPrefsStore.prefs.collectAsState()
    return prefs
}
