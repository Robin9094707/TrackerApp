package eu.simplexsmp.rjtracker.share

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import eu.simplexsmp.rjtracker.ui.RJTrackerApp
import eu.simplexsmp.rjtracker.ui.RJTrackerTheme
import eu.simplexsmp.rjtracker.ui.TrackerViewModel
import org.maplibre.android.MapLibre

class MainActivity : ComponentActivity() {
    private val viewModel: TrackerViewModel by viewModels()
    private var incomingShareText by mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        MapLibre.getInstance(this)
        enableEdgeToEdge()
        incomingShareText = extractSharedText(intent)
        setContent {
            RJTrackerTheme {
                RJTrackerApp(
                    viewModel = viewModel,
                    incomingText = incomingShareText,
                    onIncomingConsumed = { incomingShareText = null },
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        incomingShareText = extractSharedText(intent)
    }

    private fun extractSharedText(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND || intent.type != "text/plain") return null
        return intent.getStringExtra(Intent.EXTRA_TEXT)?.takeIf { it.isNotBlank() }
    }
}
