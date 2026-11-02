package eu.rjuhas.rjtracker.android

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import eu.rjuhas.rjtracker.android.background.LiveWatchService
import eu.rjuhas.rjtracker.android.data.LinkKind
import eu.rjuhas.rjtracker.android.data.LinkParser
import eu.rjuhas.rjtracker.android.data.SavedLink
import eu.rjuhas.rjtracker.android.ui.AddLinkContent
import eu.rjuhas.rjtracker.android.ui.GreetingSplash
import eu.rjuhas.rjtracker.android.ui.HomeScreen
import eu.rjuhas.rjtracker.android.ui.OnboardingScreen
import eu.rjuhas.rjtracker.android.ui.guest.GuestScreen
import eu.rjuhas.rjtracker.android.ui.school.SchoolScreen
import eu.rjuhas.rjtracker.android.ui.theme.RJTheme
import kotlinx.coroutines.flow.MutableStateFlow

class MainActivity : ComponentActivity() {
    private val incoming = MutableStateFlow<String?>(null)
    private val openLink = MutableStateFlow<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        handle(intent)
        LiveWatchService.ensureRunning(this)
        setContent { RJTheme { AppRoot(incoming, openLink) } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent?) {
        intent ?: return
        intent.getStringExtra(EXTRA_OPEN_LINK)?.let { openLink.value = it }
        val text = intent.dataString ?: intent.getStringExtra(Intent.EXTRA_TEXT)
        if (text != null && LinkParser.parse(text, BuildConfig.DEFAULT_SERVER) != null) incoming.value = text
    }

    companion object { const val EXTRA_OPEN_LINK = "open_link" }
}

private fun route(link: SavedLink) = if (link.kind == LinkKind.SCHOOL) "school/${android.net.Uri.encode(link.id)}" else "guest/${android.net.Uri.encode(link.id)}"

@Composable
private fun AppRoot(incoming: MutableStateFlow<String?>, openLink: MutableStateFlow<String?>) {
    val links by Graph.repository.links.collectAsState(initial = null)
    val introDone by Graph.repository.introDone.collectAsState(initial = null)
    val pendingLink by incoming.collectAsState()
    val pendingOpen by openLink.collectAsState()
    var greeted by remember { mutableStateOf(false) }
    val name = links?.firstOrNull { it.kind == LinkKind.SCHOOL }?.viewerName?.ifBlank { null } ?: "Jessy"
    if (links == null || introDone == null) return
    AnimatedContent(targetState = when {
        !greeted -> 0
        introDone != true || links!!.isEmpty() -> 1
        else -> 2
    }, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "root") { stage ->
        when (stage) {
            0 -> GreetingSplash(name) { greeted = true }
            1 -> OnboardingScreen(name, pendingLink) { incoming.value = null }
            else -> MainNav(links!!, name, pendingLink, pendingOpen, onConsumed = { incoming.value = null; openLink.value = null })
        }
    }
}

@Composable
private fun MainNav(links: List<SavedLink>, name: String, pendingLink: String?, pendingOpen: String?, onConsumed: () -> Unit) {
    val nav = rememberNavController()
    val start = remember { if (links.size == 1) route(links.first()) else "home" }
    LaunchedEffect(pendingLink, pendingOpen) {
        when {
            pendingLink != null -> nav.navigate("add")
            pendingOpen != null -> links.firstOrNull { it.id == pendingOpen }?.let { nav.navigate(route(it)) { launchSingleTop = true }; onConsumed() }
        }
    }
    NavHost(nav, startDestination = start) {
        composable("home") { HomeScreen(links, name) { nav.navigate(route(it)) } }
        composable("school/{id}") { entry ->
            val id = entry.arguments?.getString("id").orEmpty()
            SchoolScreen(id) { if (!nav.popBackStack()) nav.navigate("home") { popUpTo(0) } }
        }
        composable("guest/{id}") { entry ->
            val id = entry.arguments?.getString("id").orEmpty()
            GuestScreen(id) { if (!nav.popBackStack()) nav.navigate("home") { popUpTo(0) } }
        }
        composable("add") {
            AddLinkContent(initialLink = pendingLink, onConnected = { link ->
                onConsumed()
                nav.navigate(route(link)) { popUpTo("add") { inclusive = true } }
            })
        }
    }
}
