package eu.rjuhas.rjtracker.android.ui

import android.Manifest
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.NotificationsActive
import androidx.compose.material.icons.rounded.Route
import androidx.compose.material.icons.rounded.School
import androidx.compose.material.icons.rounded.Verified
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import eu.rjuhas.rjtracker.android.BuildConfig
import eu.rjuhas.rjtracker.android.Graph
import eu.rjuhas.rjtracker.android.background.LiveWatchService
import eu.rjuhas.rjtracker.android.data.ApiException
import eu.rjuhas.rjtracker.android.data.LinkKind
import eu.rjuhas.rjtracker.android.data.LinkParser
import eu.rjuhas.rjtracker.android.data.ParsedLink
import eu.rjuhas.rjtracker.android.data.SavedLink
import eu.rjuhas.rjtracker.android.ui.theme.HeroTitle
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

val greetings = listOf(
    "Zeit, die Tasche zu ordnen. 🎒",
    "Zeit zu beweisen, wer pünktlich war. ⏰",
    "Mathe-Heft dabei? Wir prüfen nur die Tasche.",
    "Detektivmodus: an. 🕵️",
    "Die Tasche war schneller als der Bus? Mal sehen.",
    "Heute schon gepackt? Die Tasche weiß es.",
    "Pausenbrot nicht vergessen! 🥪",
)

/** Animated greeting shown on every start ("Hallo Jessy …"). */
@Composable
fun GreetingSplash(name: String, onFinished: () -> Unit) {
    val phrase = remember { greetings[Random.nextInt(greetings.size)] }
    val bag = remember { Animatable(0f) }
    val text = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        bag.animateTo(1f, spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessLow))
        text.animateTo(1f, tween(450))
        delay(1100)
        onFinished()
    }
    val wobble = rememberInfiniteTransition(label = "wobble")
    val angle by wobble.animateFloat(-6f, 6f, infiniteRepeatable(tween(700, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "angle")
    Box(
        Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color(0xFF2F5DF5), Color(0xFF6A3DF5), Color(0xFF9B4DE8)))),
        contentAlignment = Alignment.Center,
    ) {
        Sparkles()
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(32.dp)) {
            Text("🎒", fontSize = 96.sp, modifier = Modifier.scale(bag.value).rotate(angle))
            Spacer(Modifier.height(24.dp))
            Text("Hallo $name!", style = HeroTitle, color = Color.White, textAlign = TextAlign.Center,
                modifier = Modifier.alpha(text.value).graphicsLayer { translationY = (1 - text.value) * 40f })
            Spacer(Modifier.height(10.dp))
            Text(phrase, style = MaterialTheme.typography.titleLarge, color = Color.White.copy(alpha = 0.9f), textAlign = TextAlign.Center,
                modifier = Modifier.alpha(text.value))
        }
    }
}

@Composable
private fun Sparkles() {
    val transition = rememberInfiniteTransition(label = "sparkles")
    val t by transition.animateFloat(0f, 1f, infiniteRepeatable(tween(6000, easing = LinearEasing)), label = "t")
    val seeds = remember { List(26) { Triple(Random.nextFloat(), Random.nextFloat(), Random.nextFloat()) } }
    Canvas(Modifier.fillMaxSize()) {
        seeds.forEach { (x, y, s) ->
            val phase = (t + s) % 1f
            val yy = (y - phase * 0.25f + 1f) % 1f
            drawCircle(Color.White.copy(alpha = 0.10f + 0.25f * sin(phase * Math.PI).toFloat()), radius = 3f + 9f * s,
                center = Offset(size.width * x, size.height * yy))
        }
    }
}

private data class IntroPage(val icon: ImageVector, val title: String, val text: String)

/** First start: short tour, notification permission, then the link. */
@Composable
fun OnboardingScreen(name: String, initialLink: String?, onDone: (SavedLink) -> Unit) {
    val pages = listOf(
        IntroPage(Icons.Rounded.School, "Hallo $name!", "Mit dieser App siehst du jederzeit, wo die Schultasche ist – ohne Konto und ohne Anmeldung."),
        IntroPage(Icons.Rounded.Route, "Alles wird protokolliert", "Ankunft, Verlassen, Aufenthaltsdauer und Verspätungen werden automatisch und sauber berechnet. Einzelne ungenaue Meldungen zählen nicht."),
        IntroPage(Icons.Rounded.NotificationsActive, "Sofort Bescheid wissen", "Du bekommst eine Nachricht, wenn die Tasche das Zuhause verlässt, in der Schule ankommt oder sie verlässt."),
    )
    val pager = rememberPagerState { pages.size + 1 }
    val scope = rememberCoroutineScope()
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    LaunchedEffect(initialLink) { if (initialLink != null) pager.scrollToPage(pages.size) }
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).statusBarsPadding().navigationBarsPadding().imePadding()) {
        HorizontalPager(pager, modifier = Modifier.weight(1f)) { index ->
            if (index < pages.size) {
                val page = pages[index]
                Column(Modifier.fillMaxSize().padding(32.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(
                        Modifier.size(132.dp).background(Brush.linearGradient(listOf(Color(0xFF3D7BFF), Color(0xFF8E5CF7))), RoundedCornerShape(42.dp)),
                        contentAlignment = Alignment.Center,
                    ) { Icon(page.icon, null, tint = Color.White, modifier = Modifier.size(64.dp)) }
                    Spacer(Modifier.height(36.dp))
                    Text(page.title, style = MaterialTheme.typography.headlineMedium, textAlign = TextAlign.Center)
                    Spacer(Modifier.height(14.dp))
                    Text(page.text, style = MaterialTheme.typography.bodyLarge, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } else {
                AddLinkContent(initialLink = initialLink, onConnected = onDone)
            }
        }
        if (pager.currentPage < pages.size) {
            Row(Modifier.fillMaxWidth().padding(24.dp), verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    repeat(pages.size + 1) { index ->
                        Box(Modifier.height(8.dp).width(if (index == pager.currentPage) 26.dp else 8.dp)
                            .background(if (index == pager.currentPage) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant, CircleShape))
                    }
                }
                Button(onClick = {
                    if (pager.currentPage == 2 && Build.VERSION.SDK_INT >= 33) permission.launch(Manifest.permission.POST_NOTIFICATIONS)
                    scope.launch { pager.animateScrollToPage(pager.currentPage + 1) }
                }) {
                    Text(if (pager.currentPage == 2) "Erlauben & weiter" else "Weiter")
                    Spacer(Modifier.width(8.dp))
                    Icon(Icons.AutoMirrored.Rounded.ArrowForward, null)
                }
            }
        }
    }
}

private enum class ConnectPhase { INPUT, CHECKING, PASSWORD, SUCCESS }

/** Paste/receive a link, validate it with the server, then celebrate. */
@Composable
fun AddLinkContent(initialLink: String?, onConnected: (SavedLink) -> Unit, compact: Boolean = false) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var input by rememberSaveable { mutableStateOf(initialLink.orEmpty()) }
    var phase by remember { mutableStateOf(ConnectPhase.INPUT) }
    var error by remember { mutableStateOf<String?>(null) }
    var password by remember { mutableStateOf("") }
    var pending by remember { mutableStateOf<ParsedLink?>(null) }
    var saved by remember { mutableStateOf<SavedLink?>(null) }

    fun connect(passwordValue: String? = null) {
        val parsed = pending ?: LinkParser.parse(input, BuildConfig.DEFAULT_SERVER)
        if (parsed == null) { error = "Das sieht nicht wie ein RJ-Tracker-Link aus. Er beginnt mit https://…/school/ oder …/shared/."; return }
        pending = parsed
        error = null
        phase = ConnectPhase.CHECKING
        scope.launch {
            try {
                val link = when (parsed.kind) {
                    LinkKind.SCHOOL -> {
                        val overview = Graph.api.schoolOverview(parsed.baseUrl, parsed.token)
                        SavedLink(parsed.id, LinkKind.SCHOOL, parsed.baseUrl, parsed.token, title = overview.label,
                            emoji = "🎒", viewerName = overview.viewerName, lastEventSeq = overview.latestEventSeq)
                    }
                    LinkKind.GUEST -> {
                        val view = Graph.api.guestView(parsed.baseUrl, parsed.token, null, passwordValue)
                        SavedLink(parsed.id, LinkKind.GUEST, parsed.baseUrl, parsed.token, appToken = view.appToken,
                            title = view.title, emoji = view.emoji, expiresTs = view.expiresTs, liveNotifications = false)
                    }
                }
                Graph.repository.upsert(link)
                LiveWatchService.ensureRunning(context)
                saved = link
                phase = ConnectPhase.SUCCESS
                delay(1700)
                // Marking the intro as done switches to the dashboard, so it
                // happens only after the celebration has been shown.
                Graph.repository.setIntroDone()
                onConnected(link)
            } catch (exception: ApiException) {
                if (exception.needsPassword) {
                    error = if (exception.code == "wrong_password") "Das Passwort stimmt nicht." else null
                    phase = ConnectPhase.PASSWORD
                } else {
                    error = exception.message
                    phase = ConnectPhase.INPUT
                    pending = null
                }
            }
        }
    }
    LaunchedEffect(initialLink) { if (!initialLink.isNullOrBlank() && LinkParser.parse(initialLink, BuildConfig.DEFAULT_SERVER) != null) connect() }

    AnimatedContent(phase == ConnectPhase.SUCCESS, transitionSpec = { (fadeIn() + scaleIn(initialScale = 0.9f)) togetherWith fadeOut() }, label = "connect") { success ->
        if (success) {
            SuccessCelebration(saved)
        } else {
            Column(
                Modifier.fillMaxSize().padding(horizontal = 28.dp, vertical = if (compact) 8.dp else 28.dp),
                verticalArrangement = if (compact) Arrangement.Top else Arrangement.Center,
            ) {
                if (!compact) {
                    Text("🔗", fontSize = 56.sp)
                    Spacer(Modifier.height(16.dp))
                    Text("Link einfügen", style = MaterialTheme.typography.headlineMedium)
                    Spacer(Modifier.height(8.dp))
                }
                Text("Frag Robin nach einem Link, falls du noch keinen hast. Er funktioniert ohne Konto und bleibt gespeichert, bis er abläuft.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(20.dp))
                OutlinedTextField(
                    value = input, onValueChange = { input = it; error = null; pending = null },
                    label = { Text("Link") }, placeholder = { Text("https://find.rjuhas.eu/school/…") },
                    leadingIcon = { Icon(Icons.Rounded.Link, null) }, singleLine = true, isError = error != null,
                    supportingText = { if (error != null) Text(error!!) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Go),
                    keyboardActions = KeyboardActions(onGo = { connect() }),
                    modifier = Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.medium,
                )
                Spacer(Modifier.height(8.dp))
                FilledTonalButton(onClick = {
                    val clip = (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).primaryClip
                    val text = clip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(context)?.toString()
                    if (!text.isNullOrBlank()) { input = text; pending = null; error = null }
                }, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Rounded.ContentPaste, null); Spacer(Modifier.width(8.dp)); Text("Aus Zwischenablage einfügen")
                }
                Spacer(Modifier.height(8.dp))
                Button(onClick = { connect() }, enabled = phase == ConnectPhase.INPUT && input.isNotBlank(), modifier = Modifier.fillMaxWidth().height(56.dp)) {
                    if (phase == ConnectPhase.CHECKING) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.5.dp, color = MaterialTheme.colorScheme.onPrimary)
                    else Text("Verbinden", style = MaterialTheme.typography.titleMedium)
                }
            }
        }
    }
    if (phase == ConnectPhase.PASSWORD) {
        AlertDialog(
            onDismissRequest = { phase = ConnectPhase.INPUT; pending = null },
            icon = { Icon(Icons.Rounded.Lock, null) },
            title = { Text("Passwort für die Freigabe") },
            text = {
                Column {
                    Text("Diese Gastfreigabe ist geschützt. Das Passwort steht in der Nachricht, mit der du den Link bekommen hast.")
                    Spacer(Modifier.height(12.dp))
                    OutlinedTextField(password, { password = it }, label = { Text("Passwort") }, singleLine = true,
                        visualTransformation = PasswordVisualTransformation(), isError = error != null,
                        supportingText = { if (error != null) Text(error!!) })
                }
            },
            confirmButton = { TextButton(onClick = { connect(password) }, enabled = password.length >= 4) { Text("Öffnen") } },
            dismissButton = { TextButton(onClick = { phase = ConnectPhase.INPUT; pending = null }) { Text("Abbrechen") } },
        )
    }
}

@Composable
private fun SuccessCelebration(link: SavedLink?) {
    val check = remember { Animatable(0f) }
    val burst = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        launch { burst.animateTo(1f, tween(1200, easing = FastOutSlowInEasing)) }
        check.animateTo(1f, spring(dampingRatio = 0.45f, stiffness = Spring.StiffnessLow))
    }
    val colors = listOf(Color(0xFF2F5DF5), Color(0xFFFF6B4A), Color(0xFF1E9E5A), Color(0xFFF2B90C), Color(0xFF8E5CF7))
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(320.dp)) {
            repeat(28) { index ->
                val angle = index / 28.0 * 2 * Math.PI
                val distance = size.minDimension / 2 * burst.value
                drawCircle(colors[index % colors.size].copy(alpha = 1f - burst.value * 0.8f), radius = 7f + (index % 3) * 3f,
                    center = Offset(center.x + (cos(angle) * distance).toFloat(), center.y + (sin(angle) * distance).toFloat()))
            }
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Surface(shape = CircleShape, color = Color(0xFF1E9E5A), modifier = Modifier.size(120.dp).scale(check.value)) {
                Box(contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Verified, null, tint = Color.White, modifier = Modifier.size(68.dp)) }
            }
            Spacer(Modifier.height(24.dp))
            Text(if (link?.kind == LinkKind.SCHOOL) "Du bist drin!" else "Freigabe gespeichert!", style = MaterialTheme.typography.headlineMedium,
                modifier = Modifier.alpha(check.value.coerceIn(0f, 1f)))
            Text(if (link?.kind == LinkKind.SCHOOL) "Willkommen im Schultaschenmodus 🎒" else (link?.title ?: ""),
                color = MaterialTheme.colorScheme.onSurfaceVariant, fontWeight = FontWeight.Medium, modifier = Modifier.alpha(check.value.coerceIn(0f, 1f)))
        }
    }
}

@Suppress("unused")
private val enterUp = slideInVertically { it / 3 }
