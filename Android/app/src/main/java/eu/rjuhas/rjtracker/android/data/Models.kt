package eu.rjuhas.rjtracker.android.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Loc(
    val lat: Double,
    val lon: Double,
    val acc: Double = 0.0,
    val ts: Long = 0,
    val source: String = "",
    val address: String = "",
    val freshness: String = "",
    val battery: String = "",
)

@Serializable
data class CurrentPlace(val id: String, val name: String, val kind: String, @SerialName("since_ts") val sinceTs: Long? = null)

@Serializable
data class Evidence(val ts: Long = 0, val lat: Double = 0.0, val lon: Double = 0.0, @SerialName("near_place") val nearPlace: String = "", val reports: Int = 0)

@Serializable
data class DayRecord(
    val day: String,
    val weekday: Int = 0,
    val start: String = "",
    val end: String = "",
    val status: String = "free",
    @SerialName("status_text") val statusText: String = "",
    val label: String = "",
    @SerialName("arrival_ts") val arrivalTs: Long? = null,
    @SerialName("leave_ts") val leaveTs: Long? = null,
    @SerialName("last_in_ts") val lastInTs: Long? = null,
    @SerialName("present_minutes") val presentMinutes: Int = 0,
    @SerialName("late_minutes") val lateMinutes: Int = 0,
    @SerialName("early_leave") val earlyLeave: Boolean = false,
    @SerialName("already_there") val alreadyThere: Boolean = false,
    @SerialName("home_departure_ts") val homeDepartureTs: Long? = null,
    @SerialName("travel_minutes") val travelMinutes: Int? = null,
    @SerialName("report_count") val reportCount: Int = 0,
    val evidence: Evidence? = null,
)

@Serializable
data class Bag(
    val ref: String,
    val label: String = "Schultasche",
    @SerialName("child_name") val childName: String = "",
    val emoji: String = "🎒",
    val provider: String = "",
    val battery: String = "",
    val location: Loc? = null,
    @SerialName("current_place") val currentPlace: CurrentPlace? = null,
    val today: DayRecord? = null,
    @SerialName("last_point_ts") val lastPointTs: Long? = null,
) {
    val displayName: String get() = childName.ifBlank { label }
}

@Serializable
data class Place(
    val id: String = "",
    val kind: String = "other",
    val name: String = "",
    val lat: Double,
    val lon: Double,
    @SerialName("radius_m") val radiusM: Int = 120,
    @SerialName("created_ts") val createdTs: Long = 0,
)

@Serializable
data class DayCfg(val enabled: Boolean = false, val start: String = "08:00", val end: String = "")

@Serializable
data class OffDay(val day: String, val label: String = "")

@Serializable
data class Schedule(
    val days: Map<String, DayCfg> = emptyMap(),
    @SerialName("grace_minutes") val graceMinutes: Int = 5,
    @SerialName("absent_after_minutes") val absentAfterMinutes: Int = 90,
    @SerialName("off_days") val offDays: List<OffDay> = emptyList(),
)

@Serializable
data class SchoolOverview(
    @SerialName("server_time") val serverTime: Long = 0,
    @SerialName("viewer_name") val viewerName: String = "",
    val label: String = "",
    val bags: List<Bag> = emptyList(),
    val places: List<Place> = emptyList(),
    val schedule: Schedule = Schedule(),
    @SerialName("latest_event_seq") val latestEventSeq: Long = 0,
    @SerialName("can_edit") val canEdit: Boolean = true,
    @SerialName("poll_seconds") val pollSeconds: Int = 20,
)

@Serializable
data class Pt(val lat: Double, val lon: Double, val acc: Double = 0.0, val ts: Long, val source: String = "")

@Serializable
data class Visit(
    @SerialName("place_id") val placeId: String = "",
    @SerialName("place_name") val placeName: String = "",
    @SerialName("place_kind") val placeKind: String = "other",
    @SerialName("enter_ts") val enterTs: Long,
    @SerialName("last_in_ts") val lastInTs: Long = 0,
    @SerialName("leave_ts") val leaveTs: Long? = null,
    @SerialName("entered_unknown") val enteredUnknown: Boolean = false,
    val reports: Int = 0,
)

@Serializable
data class HistoryResponse(
    val points: List<Pt> = emptyList(),
    val visits: List<Visit> = emptyList(),
    @SerialName("raw_count") val rawCount: Int = 0,
    val from: Long = 0,
    val to: Long = 0,
)

@Serializable
data class Summary(
    @SerialName("school_days") val schoolDays: Int = 0,
    @SerialName("on_time") val onTime: Int = 0,
    val late: Int = 0,
    val absent: Int = 0,
    @SerialName("late_minutes_total") val lateMinutesTotal: Int = 0,
    @SerialName("average_arrival") val averageArrival: String = "",
)

@Serializable
data class AttendanceBag(val days: List<DayRecord> = emptyList(), val summary: Summary = Summary())

@Serializable
data class AttendanceResponse(val attendance: Map<String, AttendanceBag> = emptyMap())

@Serializable
data class SchoolEvent(
    val seq: Long,
    val type: String = "",
    val kind: String = "",
    val ref: String = "",
    @SerialName("place_name") val placeName: String = "",
    val ts: Long = 0,
    val title: String = "",
    val body: String = "",
)

@Serializable
data class EventsResponse(val events: List<SchoolEvent> = emptyList(), @SerialName("latest_seq") val latestSeq: Long = 0)

@Serializable
data class LocateTarget(val ref: String = "", @SerialName("previous_ts") val previousTs: Long = 0)

@Serializable
data class LocateResponse(
    val status: String = "",
    val trackers: List<LocateTarget> = emptyList(),
    @SerialName("previous_ts") val previousTs: Long = 0,
    val remaining: Int = 0,
)

@Serializable
data class Permissions(
    @SerialName("can_locate") val canLocate: Boolean = false,
    @SerialName("show_history") val showHistory: Boolean = false,
    @SerialName("can_navigate") val canNavigate: Boolean = true,
    @SerialName("show_accuracy") val showAccuracy: Boolean = true,
    @SerialName("show_address") val showAddress: Boolean = true,
    @SerialName("show_battery") val showBattery: Boolean = true,
    @SerialName("show_provider") val showProvider: Boolean = true,
)

@Serializable
data class GuestPrivacy(val precision: String = "exact", @SerialName("delay_minutes") val delayMinutes: Int = 0, @SerialName("history_hours") val historyHours: Int = 168)

@Serializable
data class GuestView(
    val title: String = "Geteilter Tracker",
    val emoji: String = "📍",
    val provider: String = "",
    @SerialName("share_kind") val shareKind: String = "tracker",
    val location: Loc? = null,
    val permissions: Permissions = Permissions(),
    val privacy: GuestPrivacy = GuestPrivacy(),
    @SerialName("expires_ts") val expiresTs: Long = 0,
    @SerialName("server_time") val serverTime: Long = 0,
    val available: Boolean = true,
    @SerialName("app_token") val appToken: String? = null,
)

@Serializable
data class GuestHistory(
    val points: List<Pt> = emptyList(),
    @SerialName("raw_count") val rawCount: Int = 0,
    @SerialName("earliest_ts") val earliestTs: Long = 0,
    @SerialName("app_token") val appToken: String? = null,
)

@Serializable
data class ApiError(val status: String = "", val code: String = "", val message: String = "")

@Serializable
enum class LinkKind { SCHOOL, GUEST }

@Serializable
enum class NotifyMode { OFF, ONCE, ALWAYS }

/** Notification categories the user can tune per link. */
enum class NotifyTopic(val key: String, val label: String, val description: String, val default: NotifyMode) {
    HOME_LEAVE("home_leave", "Zuhause verlassen", "Wenn die Tasche das Zuhause verlässt", NotifyMode.ALWAYS),
    SCHOOL_ENTER("school_enter", "Schule erreicht", "Ankunft in der Schule", NotifyMode.ALWAYS),
    SCHOOL_LEAVE("school_leave", "Schule verlassen", "Mit Aufenthaltsdauer", NotifyMode.ALWAYS),
    HOME_ENTER("home_enter", "Zuhause angekommen", "Rückkehr nach Hause", NotifyMode.OFF),
    LATE("late", "Verspätung", "Noch nicht da oder verspätet angekommen", NotifyMode.ALWAYS),
    ABSENT("absent", "Nicht in der Schule", "Kein Schulbesuch bis zur Frist", NotifyMode.ALWAYS),
    PLACE("place", "Weitere Orte", "Ankunft/Verlassen an eigenen Orten", NotifyMode.OFF);

    companion object {
        fun forEvent(type: String): NotifyTopic? = when (type) {
            "home_leave" -> HOME_LEAVE
            "home_enter" -> HOME_ENTER
            "school_enter" -> SCHOOL_ENTER
            "school_leave" -> SCHOOL_LEAVE
            "late_missing", "late_arrival" -> LATE
            "absent" -> ABSENT
            "other_enter", "other_leave" -> PLACE
            else -> null
        }
    }
}

@Serializable
data class SavedLink(
    val id: String,
    val kind: LinkKind,
    val baseUrl: String,
    val token: String,
    val appToken: String? = null,
    val title: String = "",
    val emoji: String = "",
    val viewerName: String = "",
    val addedAt: Long = System.currentTimeMillis(),
    val expiresTs: Long = 0,
    val lastEventSeq: Long = -1,
    val notify: Map<String, NotifyMode> = NotifyTopic.entries.associate { it.key to it.default },
    val liveNotifications: Boolean = true,
) {
    fun mode(topic: NotifyTopic): NotifyMode = notify[topic.key] ?: topic.default
    val url: String get() = "$baseUrl/${if (kind == LinkKind.SCHOOL) "school" else "shared"}/$token"
    val isExpired: Boolean get() = expiresTs > 0 && expiresTs * 1000 < System.currentTimeMillis()
}
