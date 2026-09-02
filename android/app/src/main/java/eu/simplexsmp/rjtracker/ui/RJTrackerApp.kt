@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package eu.simplexsmp.rjtracker.ui

import android.content.Intent
import android.net.Uri
import android.text.format.DateUtils
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Navigation
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import eu.simplexsmp.rjtracker.model.Provider
import eu.simplexsmp.rjtracker.model.SavedShare
import eu.simplexsmp.rjtracker.model.SharePayload
import eu.simplexsmp.rjtracker.model.TrackerLocation
import java.net.URI
import java.text.DateFormat

@Composable
fun RJTrackerApp(
    viewModel: TrackerViewModel,
    incomingText: String?,
    onIncomingConsumed: () -> Unit,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var showAdd by rememberSaveable { mutableStateOf(false) }
    var prefill by rememberSaveable { mutableStateOf("") }

    LaunchedEffect(incomingText) {
        if (!incomingText.isNullOrBlank()) {
            prefill = incomingText
            showAdd = true
            onIncomingConsumed()
        }
    }

    if (state.selectedShareId == null) {
        ShareList(
            shares = state.shares,
            onOpen = viewModel::openShare,
            onAdd = { prefill = ""; showAdd = true },
        )
    } else {
        DetailScreen(
            state = state,
            onBack = viewModel::closeShare,
            onReload = viewModel::reloadCurrent,
            onLocate = viewModel::refreshCurrentLocation,
            onProvider = viewModel::setProviderVisible,
            onDelete = viewModel::removeCurrentShare,
        )
    }

    if (showAdd) {
        AddShareDialog(
            initial = prefill,
            loading = state.loading,
            onDismiss = { if (!state.loading) showAdd = false },
            onAdd = { link, password, report ->
                viewModel.addShare(link, password) { ok, error ->
                    report(error)
                    if (ok) showAdd = false
                }
            },
        )
    }
}

@Composable
private fun ShareList(
    shares: List<SavedShare>,
    onOpen: (String) -> Unit,
    onAdd: () -> Unit,
) {
    Scaffold(
        topBar = {
            LargeTopAppBar(title = {
                Column {
                    Text("RJ Tracker Share", fontWeight = FontWeight.Bold)
                    Text(
                        "Freigegebene Tracker sicher ansehen",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            })
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = onAdd,
                icon = { Icon(Icons.Default.Add, contentDescription = null) },
                text = { Text("Link hinzufügen") },
            )
        },
    ) { padding ->
        if (shares.isEmpty()) {
            Box(
                Modifier.fillMaxSize().padding(padding).padding(24.dp),
                contentAlignment = Alignment.Center,
            ) {
                ElevatedCard(shape = RoundedCornerShape(28.dp)) {
                    Column(
                        Modifier.padding(26.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Icon(Icons.Default.Link, null, Modifier.size(48.dp), tint = MaterialTheme.colorScheme.primary)
                        Text("Noch keine Freigabe", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
                        Text(
                            "Füge einen RJ-Tracker-/shared/-Link und das Gast-Passwort hinzu. Einzeltracker und Fusionen werden automatisch erkannt.",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Button(onClick = onAdd) { Text("Ersten Tracker hinzufügen") }
                    }
                }
            }
        } else {
            LazyColumn(
                Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(start = 16.dp, top = 8.dp, end = 16.dp, bottom = 104.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(shares, key = { it.id }) { share ->
                    ElevatedCard(
                        modifier = Modifier.fillMaxWidth().clickable { onOpen(share.id) },
                        shape = RoundedCornerShape(24.dp),
                    ) {
                        Row(Modifier.fillMaxWidth().padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
                            Surface(Modifier.size(54.dp), shape = RoundedCornerShape(18.dp), color = MaterialTheme.colorScheme.primaryContainer) {
                                Box(contentAlignment = Alignment.Center) { Text(share.emoji, style = MaterialTheme.typography.headlineMedium) }
                            }
                            Spacer(Modifier.width(14.dp))
                            Column(Modifier.weight(1f)) {
                                Text(share.title, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(
                                    runCatching { URI(share.baseUrl).authority }.getOrNull() ?: share.baseUrl,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                            Icon(Icons.Default.LocationOn, null, tint = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AddShareDialog(
    initial: String,
    loading: Boolean,
    onDismiss: () -> Unit,
    onAdd: (String, String, (String?) -> Unit) -> Unit,
) {
    var link by rememberSaveable(initial) { mutableStateOf(extractUrl(initial)) }
    var password by rememberSaveable { mutableStateOf("") }
    var visible by rememberSaveable { mutableStateOf(false) }
    var error by rememberSaveable { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Freigabe hinzufügen") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Füge den Link ein, den du von RJ Tracker bekommen hast. Das Gast-Passwort bleibt verschlüsselt auf diesem Gerät.")
                OutlinedTextField(
                    value = link,
                    onValueChange = { link = it; error = null },
                    label = { Text("Freigabelink") },
                    leadingIcon = { Icon(Icons.Default.Link, null) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it; error = null },
                    label = { Text("Gast-Passwort") },
                    visualTransformation = if (visible) VisualTransformation.None else PasswordVisualTransformation(),
                    trailingIcon = {
                        IconButton(onClick = { visible = !visible }) {
                            Icon(if (visible) Icons.Default.VisibilityOff else Icons.Default.Visibility, null)
                        }
                    },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    error = null
                    onAdd(link.trim(), password) { error = it }
                },
                enabled = !loading && link.isNotBlank() && password.length >= 4,
            ) {
                if (loading) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                else Text("Hinzufügen")
            }
        },
        dismissButton = { TextButton(onClick = onDismiss, enabled = !loading) { Text("Abbrechen") } },
    )
}

@Composable
private fun DetailScreen(
    state: TrackerUiState,
    onBack: () -> Unit,
    onReload: () -> Unit,
    onLocate: () -> Unit,
    onProvider: (Provider, Boolean) -> Unit,
    onDelete: () -> Unit,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(state.payload?.title ?: "Tracker", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.Default.ArrowBack, "Zurück") } },
                actions = { IconButton(onClick = onDelete) { Icon(Icons.Default.Delete, "Entfernen") } },
            )
        },
    ) { padding ->
        when {
            state.payload == null && state.loading -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            state.payload == null -> StatusCard(
                modifier = Modifier.padding(padding),
                title = when (state.accessStatusCode) { 410 -> "Freigabe abgelaufen"; 404 -> "Freigabe nicht verfügbar"; else -> "Tracker nicht erreichbar" },
                message = state.error ?: "Die Freigabe konnte nicht geladen werden.",
                onRetry = onReload,
                onDelete = onDelete,
            )
            else -> PayloadContent(state, state.payload, padding, onReload, onLocate, onProvider)
        }
    }
}

@Composable
private fun PayloadContent(
    state: TrackerUiState,
    payload: SharePayload,
    padding: PaddingValues,
    onReload: () -> Unit,
    onLocate: () -> Unit,
    onProvider: (Provider, Boolean) -> Unit,
) {
    val context = LocalContext.current
    val visible = payload.sourceLocations.values
        .filter { state.visibleProviders.isEmpty() || it.source in state.visibleProviders }
        .sortedByDescending { it.timestamp }
    val latest = payload.latestFor(state.visibleProviders)
    val expired = payload.expiresTs > 0 && state.nowTs >= payload.expiresTs
    val remaining = (payload.nextLocateTs - state.nowTs).coerceAtLeast(0)

    LazyColumn(
        Modifier.fillMaxSize().padding(padding),
        contentPadding = PaddingValues(16.dp, 8.dp, 16.dp, 28.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (state.error != null) {
            item {
                Surface(shape = RoundedCornerShape(18.dp), color = MaterialTheme.colorScheme.errorContainer) {
                    Text(state.error, Modifier.padding(14.dp), color = MaterialTheme.colorScheme.onErrorContainer)
                }
            }
        }

        if (payload.isFusion && payload.permissions.showProvider && payload.sourceLocations.size > 1) {
            item {
                ElevatedCard(shape = RoundedCornerShape(22.dp)) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Fusion-Quellen", fontWeight = FontWeight.SemiBold)
                        Row(
                            Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            payload.providers.filter { it.source in payload.sourceLocations.keys }.forEach { info ->
                                FilterChip(
                                    selected = info.source in state.visibleProviders,
                                    onClick = { onProvider(info.source, info.source !in state.visibleProviders) },
                                    label = { Text(providerName(info.source)) },
                                    leadingIcon = { ProviderDot(info.source) },
                                )
                            }
                        }
                        Text(
                            "Alle Quellen sind standardmäßig sichtbar. Als Hauptstandort wird immer die neueste sichtbare Meldung verwendet.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }

        item {
            ElevatedCard(shape = RoundedCornerShape(28.dp)) {
                if (latest != null) {
                    TrackerMap(
                        locations = visible.ifEmpty { listOf(latest) },
                        selected = latest,
                        modifier = Modifier.fillMaxWidth().height(390.dp).clip(RoundedCornerShape(28.dp)),
                    )
                } else {
                    Box(Modifier.fillMaxWidth().height(280.dp), contentAlignment = Alignment.Center) {
                        Text("Noch kein Standort vorhanden", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }

        item {
            ElevatedCard(shape = RoundedCornerShape(24.dp), colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
                Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(payload.emoji, style = MaterialTheme.typography.headlineMedium)
                        Spacer(Modifier.width(10.dp))
                        Column(Modifier.weight(1f)) {
                            Text(payload.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                            Text(payload.kind, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        if (payload.permissions.showProvider && latest != null) ProviderBadge(latest.source)
                    }
                    HorizontalDivider()
                    InfoRow("Adresse", when {
                        latest?.address != null -> latest.address
                        state.addressLoading -> "Adresse wird ermittelt…"
                        payload.permissions.showAddress -> "Noch nicht verfügbar"
                        else -> "Vom Besitzer ausgeblendet"
                    })
                    InfoRow("Letzte Meldung", latest?.let(::formatTimestamp) ?: "–")
                    InfoRow("Genauigkeit", when {
                        !payload.permissions.showAccuracy -> "Vom Besitzer ausgeblendet"
                        latest?.accuracyMeters != null -> "±${latest.accuracyMeters.toInt()} m"
                        else -> "–"
                    })
                    InfoRow("Freigabe", if (payload.expiresTs == 0L) "Dauerhaft aktiv" else if (expired) "Abgelaufen" else "Bis ${formatAbsolute(payload.expiresTs)}")
                    Text("Karte: OpenFreeMap · Kartendaten © OpenStreetMap-Mitwirkende", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }

        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                FilledTonalButton(
                    onClick = onLocate,
                    enabled = !state.refreshing && !expired && payload.permissions.canLocate && remaining == 0L,
                    modifier = Modifier.weight(1f),
                ) {
                    if (state.refreshing) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Icon(Icons.Default.LocationOn, null)
                    Spacer(Modifier.width(8.dp))
                    Text(if (remaining > 0) "Orten in ${remaining}s" else "Jetzt orten")
                }
                OutlinedButton(onClick = onReload, enabled = !state.loading, modifier = Modifier.weight(1f)) {
                    Icon(Icons.Default.Refresh, null)
                    Spacer(Modifier.width(8.dp))
                    Text("Neu laden")
                }
            }
        }

        if (latest != null && payload.permissions.canNavigate) {
            item {
                Button(
                    onClick = {
                        val label = Uri.encode(payload.title)
                        val uri = Uri.parse("geo:${latest.lat},${latest.lon}?q=${latest.lat},${latest.lon}($label)")
                        runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, uri)) }
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Default.Navigation, null)
                    Spacer(Modifier.width(8.dp))
                    Text("In Karten-App navigieren")
                }
            }
        }

        if (payload.permissions.showProvider && payload.sourceLocations.size > 1) {
            item {
                ElevatedCard(shape = RoundedCornerShape(24.dp)) {
                    Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Letzte Meldung je Netz", fontWeight = FontWeight.SemiBold)
                        payload.sourceLocations.values.sortedByDescending { it.timestamp }.forEachIndexed { index, location ->
                            ProviderRow(location)
                            if (index < payload.sourceLocations.size - 1) HorizontalDivider()
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ProviderRow(location: TrackerLocation) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        ProviderDot(location.source)
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(providerName(location.source), fontWeight = FontWeight.Medium)
            Text(formatTimestamp(location), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        location.accuracyMeters?.let { Text("±${it.toInt()} m", style = MaterialTheme.typography.labelMedium) }
    }
}

@Composable
private fun ProviderDot(provider: Provider) {
    Box(Modifier.size(10.dp).clip(CircleShape).background(providerColor(provider)))
}

@Composable
private fun ProviderBadge(provider: Provider) {
    AssistChip(onClick = {}, label = { Text(providerName(provider)) }, leadingIcon = { ProviderDot(provider) })
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(label, Modifier.width(96.dp), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun StatusCard(
    modifier: Modifier,
    title: String,
    message: String,
    onRetry: () -> Unit,
    onDelete: () -> Unit,
) {
    Box(modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
        ElevatedCard(shape = RoundedCornerShape(28.dp)) {
            Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Button(onClick = onRetry) { Text("Erneut versuchen") }
                    OutlinedButton(onClick = onDelete) { Text("Entfernen") }
                }
            }
        }
    }
}

private fun providerName(provider: Provider): String = when (provider) {
    Provider.APPLE -> "Apple"
    Provider.GOOGLE -> "Google"
    Provider.SAMSUNG -> "Samsung"
    Provider.TRACKER -> "Tracker"
}

private fun formatTimestamp(location: TrackerLocation): String {
    if (location.timestamp <= 0) return "Zeit unbekannt"
    val relative = DateUtils.getRelativeTimeSpanString(
        location.timestamp * 1000,
        System.currentTimeMillis(),
        DateUtils.MINUTE_IN_MILLIS,
    ).toString()
    return "$relative · ${formatAbsolute(location.timestamp)}"
}

private fun formatAbsolute(timestamp: Long): String =
    DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(timestamp * 1000)

private fun extractUrl(text: String): String =
    Regex("https?://[^\\s]+", RegexOption.IGNORE_CASE).find(text)?.value?.trimEnd('.', ',', ';', ')', ']') ?: text.trim()
