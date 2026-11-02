package eu.rjuhas.rjtracker.android.ui.common

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs

val zone: ZoneId = ZoneId.of("Europe/Berlin")
private val de = Locale.GERMANY
private val timeFmt = DateTimeFormatter.ofPattern("HH:mm", de)
private val dayFmt = DateTimeFormatter.ofPattern("EEEE, d. MMMM", de)
private val shortDayFmt = DateTimeFormatter.ofPattern("EE d.M.", de)
private val dateTimeFmt = DateTimeFormatter.ofPattern("d.M. HH:mm", de)

fun clock(ts: Long?): String = if (ts == null || ts <= 0) "–" else timeFmt.format(Instant.ofEpochSecond(ts).atZone(zone))
fun dateTime(ts: Long?): String = if (ts == null || ts <= 0) "–" else dateTimeFmt.format(Instant.ofEpochSecond(ts).atZone(zone))
fun dayTitle(day: String): String = runCatching { dayFmt.format(LocalDate.parse(day)) }.getOrDefault(day)
fun shortDay(day: LocalDate): String = shortDayFmt.format(day)
fun today(): LocalDate = LocalDate.now(zone)
fun dayBounds(day: LocalDate): Pair<Long, Long> {
    val start = day.atStartOfDay(zone).toEpochSecond()
    return start to day.plusDays(1).atStartOfDay(zone).toEpochSecond() - 1
}

fun durationText(minutes: Int): String = when {
    minutes < 60 -> "$minutes min"
    minutes % 60 == 0 -> "${minutes / 60} h"
    else -> "${minutes / 60} h ${minutes % 60} min"
}

fun ago(ts: Long?, nowSec: Long = System.currentTimeMillis() / 1000): String {
    if (ts == null || ts <= 0) return "noch kein Standort"
    val diff = abs(nowSec - ts)
    return when {
        diff < 45 -> "gerade eben"
        diff < 3600 -> "vor ${diff / 60} min"
        diff < 86400 -> "vor ${diff / 3600} h ${(diff % 3600) / 60} min"
        else -> "am ${dateTime(ts)}"
    }
}

fun providerName(provider: String): String = when (provider) {
    "apple" -> "Apple Wo ist?"
    "google" -> "Google Find Hub"
    "samsung" -> "Samsung SmartThings"
    "fusion" -> "Fusion aus mehreren Netzen"
    else -> "Tracker"
}
