package eu.simplexsmp.rjtracker.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import eu.simplexsmp.rjtracker.data.SecureStore
import eu.simplexsmp.rjtracker.data.ShareApi
import eu.simplexsmp.rjtracker.data.ShareApiException
import eu.simplexsmp.rjtracker.model.Provider
import eu.simplexsmp.rjtracker.model.SavedShare
import eu.simplexsmp.rjtracker.model.SharePayload
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID


data class TrackerUiState(
    val shares: List<SavedShare> = emptyList(),
    val selectedShareId: String? = null,
    val payload: SharePayload? = null,
    val visibleProviders: Set<Provider> = emptySet(),
    val loading: Boolean = false,
    val refreshing: Boolean = false,
    val addressLoading: Boolean = false,
    val error: String? = null,
    val accessStatusCode: Int? = null,
    val nowTs: Long = System.currentTimeMillis() / 1000,
)

class TrackerViewModel(application: Application) : AndroidViewModel(application) {
    private val store = SecureStore(application)
    private val api = ShareApi()
    private val _state = MutableStateFlow(TrackerUiState(shares = store.loadShares()))
    val state: StateFlow<TrackerUiState> = _state.asStateFlow()

    private var pollingJob: Job? = null

    init {
        viewModelScope.launch {
            while (isActive) {
                delay(1_000)
                _state.update { it.copy(nowTs = System.currentTimeMillis() / 1000) }
            }
        }
    }

    fun addShare(rawUrl: String, password: String, onResult: (Boolean, String?) -> Unit) {
        if (password.length < 4) {
            onResult(false, "Das Gast-Passwort muss mindestens 4 Zeichen lang sein.")
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null, accessStatusCode = null) }
            try {
                val parsed = api.parseShareLink(rawUrl)
                val temporary = SavedShare(
                    id = UUID.randomUUID().toString(),
                    shareUrl = parsed.shareUrl,
                    baseUrl = parsed.baseUrl,
                    linkId = parsed.linkId,
                    password = password,
                    title = "Geteilter Tracker",
                    emoji = "📍",
                    addedAt = System.currentTimeMillis() / 1000,
                )
                val payload = withContext(Dispatchers.IO) { api.fetchShare(temporary) }
                val existing = _state.value.shares.firstOrNull {
                    it.baseUrl.equals(parsed.baseUrl, ignoreCase = true) && it.linkId == parsed.linkId
                }
                val saved = temporary.copy(
                    id = existing?.id ?: temporary.id,
                    addedAt = existing?.addedAt ?: temporary.addedAt,
                    title = payload.title,
                    emoji = payload.emoji,
                )
                val updated = _state.value.shares.filterNot { it.id == saved.id } + saved
                persist(updated)
                _state.update {
                    it.copy(
                        shares = updated.sortedByDescending(SavedShare::addedAt),
                        selectedShareId = saved.id,
                        payload = payload,
                        visibleProviders = defaultVisibleProviders(payload),
                        loading = false,
                        error = null,
                        accessStatusCode = null,
                    )
                }
                startPolling(saved.id)
                resolveAddressForCurrent()
                onResult(true, null)
            } catch (e: ShareApiException) {
                _state.update { it.copy(loading = false, error = e.message, accessStatusCode = e.statusCode.takeIf { code -> code > 0 }) }
                onResult(false, e.message)
            } catch (e: Exception) {
                val message = e.message ?: "Freigabe konnte nicht hinzugefügt werden."
                _state.update { it.copy(loading = false, error = message) }
                onResult(false, message)
            }
        }
    }

    fun openShare(id: String) {
        if (_state.value.selectedShareId == id && _state.value.payload != null) return
        _state.update {
            it.copy(
                selectedShareId = id,
                payload = null,
                visibleProviders = emptySet(),
                error = null,
                accessStatusCode = null,
            )
        }
        loadCurrent(resetProviders = true)
        startPolling(id)
    }

    fun closeShare() {
        pollingJob?.cancel()
        pollingJob = null
        _state.update {
            it.copy(
                selectedShareId = null,
                payload = null,
                visibleProviders = emptySet(),
                loading = false,
                refreshing = false,
                error = null,
                accessStatusCode = null,
            )
        }
    }

    fun reloadCurrent() = loadCurrent(resetProviders = false)

    fun refreshCurrentLocation() {
        val share = currentShare() ?: return
        val payload = _state.value.payload ?: return
        if (!payload.permissions.canLocate) {
            _state.update { it.copy(error = "Der Besitzer hat Live-Ortung für diesen Link deaktiviert.") }
            return
        }
        val remaining = (payload.nextLocateTs - _state.value.nowTs).coerceAtLeast(0)
        if (remaining > 0) {
            _state.update { it.copy(error = "Live-Ortung ist in ${remaining}s wieder verfügbar.") }
            return
        }

        viewModelScope.launch {
            _state.update { it.copy(refreshing = true, error = null) }
            try {
                val result = withContext(Dispatchers.IO) { api.locate(share) }
                if (result.status == "cooldown") {
                    _state.update { state ->
                        state.copy(
                            refreshing = false,
                            payload = state.payload?.copy(nextLocateTs = result.nextLocateTs),
                            error = "Live-Ortung ist in ${result.remainingSeconds.coerceAtLeast(1)}s wieder verfügbar.",
                        )
                    }
                    return@launch
                }
                _state.update { state ->
                    state.copy(payload = state.payload?.copy(nextLocateTs = result.nextLocateTs))
                }
                delay(2_500)
                loadCurrentSuspend(resetProviders = false, showSpinner = false)
                delay(3_500)
                loadCurrentSuspend(resetProviders = false, showSpinner = false)
            } catch (e: ShareApiException) {
                _state.update { it.copy(error = e.message, accessStatusCode = e.statusCode.takeIf { code -> code > 0 }) }
            } finally {
                _state.update { it.copy(refreshing = false) }
            }
        }
    }

    fun setProviderVisible(provider: Provider, visible: Boolean) {
        val current = _state.value.visibleProviders.toMutableSet()
        if (visible) {
            current += provider
        } else if (current.size > 1) {
            current -= provider
        } else {
            _state.update { it.copy(error = "Mindestens eine Standortquelle muss sichtbar bleiben.") }
            return
        }
        _state.update { it.copy(visibleProviders = current, error = null) }
        resolveAddressForCurrent()
    }

    fun removeCurrentShare() {
        val id = _state.value.selectedShareId ?: return
        val updated = _state.value.shares.filterNot { it.id == id }
        persist(updated)
        pollingJob?.cancel()
        pollingJob = null
        _state.value = TrackerUiState(shares = updated, nowTs = System.currentTimeMillis() / 1000)
    }

    fun clearError() {
        _state.update { it.copy(error = null) }
    }

    private fun loadCurrent(resetProviders: Boolean) {
        viewModelScope.launch { loadCurrentSuspend(resetProviders, showSpinner = true) }
    }

    private suspend fun loadCurrentSuspend(resetProviders: Boolean, showSpinner: Boolean) {
        val share = currentShare() ?: return
        if (showSpinner) _state.update { it.copy(loading = true, error = null) }
        try {
            val payload = withContext(Dispatchers.IO) { api.fetchShare(share) }
            val available = defaultVisibleProviders(payload)
            val existingVisible = _state.value.visibleProviders
            val visible = if (resetProviders || existingVisible.isEmpty()) {
                available
            } else {
                existingVisible.intersect(available).ifEmpty { available }
            }
            val updatedShares = updateSavedMetadata(share, payload)
            _state.update {
                it.copy(
                    shares = updatedShares,
                    payload = payload,
                    visibleProviders = visible,
                    loading = false,
                    error = null,
                    accessStatusCode = null,
                )
            }
            resolveAddressForCurrent()
        } catch (e: ShareApiException) {
            _state.update {
                it.copy(
                    loading = false,
                    error = e.message,
                    accessStatusCode = e.statusCode.takeIf { code -> code > 0 },
                )
            }
        } catch (e: Exception) {
            _state.update { it.copy(loading = false, error = e.message ?: "Standort konnte nicht geladen werden.") }
        }
    }

    private fun resolveAddressForCurrent() {
        val share = currentShare() ?: return
        val state = _state.value
        val payload = state.payload ?: return
        if (!payload.permissions.showAddress) return
        val latest = payload.latestFor(state.visibleProviders) ?: return
        if (!latest.address.isNullOrBlank()) return

        viewModelScope.launch {
            _state.update { it.copy(addressLoading = true) }
            try {
                val address = withContext(Dispatchers.IO) { api.resolveAddress(share, latest.source) } ?: return@launch
                _state.update { current ->
                    val currentPayload = current.payload ?: return@update current
                    val old = currentPayload.sourceLocations[latest.source] ?: return@update current
                    val newLocation = old.copy(address = address)
                    val newSources = currentPayload.sourceLocations.toMutableMap().apply { put(latest.source, newLocation) }
                    val newGeneral = currentPayload.location?.let {
                        if (it.source == latest.source && it.lat == old.lat && it.lon == old.lon) it.copy(address = address) else it
                    }
                    current.copy(payload = currentPayload.copy(sourceLocations = newSources, location = newGeneral))
                }
            } catch (_: Exception) {
                // Address resolution is optional; the coordinate remains usable.
            } finally {
                _state.update { it.copy(addressLoading = false) }
            }
        }
    }

    private fun startPolling(id: String) {
        pollingJob?.cancel()
        pollingJob = viewModelScope.launch {
            while (isActive && _state.value.selectedShareId == id) {
                delay(30_000)
                if (_state.value.selectedShareId == id && !_state.value.refreshing) {
                    loadCurrentSuspend(resetProviders = false, showSpinner = false)
                }
            }
        }
    }

    private fun currentShare(): SavedShare? {
        val id = _state.value.selectedShareId ?: return null
        return _state.value.shares.firstOrNull { it.id == id }
    }

    private fun defaultVisibleProviders(payload: SharePayload): Set<Provider> {
        val sources = payload.sourceLocations.keys
        return if (sources.isNotEmpty()) sources else setOfNotNull(payload.location?.source)
    }

    private fun updateSavedMetadata(share: SavedShare, payload: SharePayload): List<SavedShare> {
        if (share.title == payload.title && share.emoji == payload.emoji) return _state.value.shares
        val updated = _state.value.shares.map {
            if (it.id == share.id) it.copy(title = payload.title, emoji = payload.emoji) else it
        }
        persist(updated)
        return updated
    }

    private fun persist(shares: List<SavedShare>) {
        runCatching { store.saveShares(shares) }
    }
}
