package eu.rjuhas.rjtracker.android.ui.school

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import eu.rjuhas.rjtracker.android.Graph
import eu.rjuhas.rjtracker.android.data.ApiException
import eu.rjuhas.rjtracker.android.data.AttendanceResponse
import eu.rjuhas.rjtracker.android.data.Bag
import eu.rjuhas.rjtracker.android.data.HistoryResponse
import eu.rjuhas.rjtracker.android.data.NotifyMode
import eu.rjuhas.rjtracker.android.data.NotifyTopic
import eu.rjuhas.rjtracker.android.data.Place
import eu.rjuhas.rjtracker.android.data.SavedLink
import eu.rjuhas.rjtracker.android.data.Schedule
import eu.rjuhas.rjtracker.android.data.SchoolOverview
import eu.rjuhas.rjtracker.android.ui.common.clock
import eu.rjuhas.rjtracker.android.ui.common.dayBounds
import eu.rjuhas.rjtracker.android.ui.common.today
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.LocalDate

class SchoolViewModel(private val linkId: String) : ViewModel() {
    val link: StateFlow<SavedLink?> = Graph.repository.links.map { list -> list.firstOrNull { it.id == linkId } }
        .stateIn(viewModelScope, SharingStarted.Eagerly, null)

    var overview by mutableStateOf<SchoolOverview?>(null); private set
    var error by mutableStateOf<String?>(null); private set
    var refreshing by mutableStateOf(false); private set
    var selectedRef by mutableStateOf<String?>(null)
    var historyDay by mutableStateOf(today()); private set
    var history by mutableStateOf<HistoryResponse?>(null); private set
    var historyLoading by mutableStateOf(false); private set
    var attendance by mutableStateOf<AttendanceResponse?>(null); private set
    var lastLoaded by mutableStateOf(0L); private set
    private val snack = Channel<String>(Channel.BUFFERED)
    val messages = snack.receiveAsFlow()

    val bag: Bag? get() = overview?.bags?.let { bags -> bags.firstOrNull { it.ref == selectedRef } ?: bags.firstOrNull() }

    private suspend fun current(): SavedLink? = link.value ?: Graph.repository.find(linkId)

    suspend fun load() {
        val saved = current() ?: return
        try {
            val result = Graph.api.schoolOverview(saved)
            overview = result
            error = null
            lastLoaded = System.currentTimeMillis()
            if (selectedRef == null || result.bags.none { it.ref == selectedRef }) selectedRef = result.bags.firstOrNull()?.ref
            if (saved.viewerName != result.viewerName || saved.title != result.label) {
                Graph.repository.modify(linkId) { it.copy(viewerName = result.viewerName, title = result.label) }
            }
        } catch (exception: ApiException) {
            error = exception.message
        }
    }

    fun refreshNow() {
        if (refreshing) return
        viewModelScope.launch {
            val saved = current() ?: return@launch
            refreshing = true
            try {
                val target = bag?.ref
                val response = Graph.api.schoolLocate(saved, target)
                val before = response.trackers.firstOrNull { it.ref == target }?.previousTs ?: bag?.location?.ts ?: 0
                var found: Long? = null
                val started = System.currentTimeMillis()
                while (System.currentTimeMillis() - started < 40_000) {
                    delay(2500)
                    load()
                    val ts = bag?.location?.ts ?: 0
                    if (ts > before) { found = ts; break }
                }
                snack.send(if (found != null) "Neuer Standort aufgetaucht · ${clock(found)}" else "Kein neuer Standort aufgetaucht")
                if (found != null && historyDay == today()) loadHistory(historyDay)
            } catch (exception: ApiException) {
                snack.send(exception.message ?: "Aktualisierung fehlgeschlagen")
            } finally {
                refreshing = false
            }
        }
    }

    fun loadHistory(day: LocalDate = historyDay) {
        historyDay = day
        viewModelScope.launch {
            val saved = current() ?: return@launch
            val ref = bag?.ref ?: return@launch
            historyLoading = true
            val (from, to) = dayBounds(day)
            runCatching { Graph.api.schoolHistory(saved, ref, from, minOf(to, System.currentTimeMillis() / 1000 + 60)) }
                .onSuccess { history = it }
                .onFailure { snack.send(it.message ?: "Verlauf nicht verfügbar") }
            historyLoading = false
        }
    }

    fun loadAttendance() {
        viewModelScope.launch {
            val saved = current() ?: return@launch
            runCatching { Graph.api.schoolAttendance(saved, 120) }.onSuccess { attendance = it }
        }
    }

    fun savePlace(place: Place, onDone: () -> Unit) = mutate("Ort gespeichert") { Graph.api.savePlace(it, place); onDone() }
    fun deletePlace(id: String) = mutate("Ort gelöscht") { Graph.api.deletePlace(it, id) }
    fun saveSchedule(schedule: Schedule) = mutate("Stundenplan gespeichert") { Graph.api.saveSchedule(it, schedule); loadAttendance() }

    private fun mutate(success: String, action: suspend (SavedLink) -> Unit) {
        viewModelScope.launch {
            val saved = current() ?: return@launch
            try {
                action(saved)
                load()
                snack.send(success)
            } catch (exception: ApiException) {
                snack.send(exception.message ?: "Speichern fehlgeschlagen")
            }
        }
    }

    fun setNotify(topic: NotifyTopic, mode: NotifyMode) = viewModelScope.launch {
        Graph.repository.modify(linkId) { it.copy(notify = it.notify + (topic.key to mode)) }
    }

    fun setLive(enabled: Boolean, after: () -> Unit) = viewModelScope.launch {
        Graph.repository.modify(linkId) { it.copy(liveNotifications = enabled) }
        after()
    }

    fun remove(after: () -> Unit) = viewModelScope.launch {
        Graph.repository.remove(linkId)
        after()
    }
}
