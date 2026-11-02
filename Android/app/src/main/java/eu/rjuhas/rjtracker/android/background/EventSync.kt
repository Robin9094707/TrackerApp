package eu.rjuhas.rjtracker.android.background

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import eu.rjuhas.rjtracker.android.Graph
import eu.rjuhas.rjtracker.android.MainActivity
import eu.rjuhas.rjtracker.android.R
import eu.rjuhas.rjtracker.android.RJApp
import eu.rjuhas.rjtracker.android.data.LinkKind
import eu.rjuhas.rjtracker.android.data.NotifyMode
import eu.rjuhas.rjtracker.android.data.NotifyTopic
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Pulls new school events and turns them into notifications (shared by worker and live service). */
object EventSync {
    private val mutex = Mutex()

    suspend fun sync(context: Context): Int = mutex.withLock {
        val repository = Graph.repository
        var delivered = 0
        for (link in repository.current().filter { it.kind == LinkKind.SCHOOL }) {
            val response = runCatching { Graph.api.schoolEvents(link, maxOf(0, link.lastEventSeq)) }.getOrNull() ?: continue
            if (link.lastEventSeq < 0) {
                // First contact: start from "now", never flood with history.
                repository.modify(link.id) { it.copy(lastEventSeq = response.latestSeq) }
                continue
            }
            var notify = link.notify
            for (event in response.events.sortedBy { it.seq }) {
                val topic = NotifyTopic.forEvent(event.type) ?: continue
                val mode = notify[topic.key] ?: topic.default
                if (mode == NotifyMode.OFF) continue
                if (post(context, link.id, event.seq, event.title, event.body)) delivered++
                if (mode == NotifyMode.ONCE) notify = notify + (topic.key to NotifyMode.OFF)
            }
            val latest = maxOf(response.latestSeq, response.events.maxOfOrNull { it.seq } ?: 0)
            repository.modify(link.id) { it.copy(lastEventSeq = maxOf(it.lastEventSeq, latest), notify = notify) }
        }
        delivered
    }

    private fun post(context: Context, linkId: String, seq: Long, title: String, body: String): Boolean {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED &&
            android.os.Build.VERSION.SDK_INT >= 33) return false
        val intent = Intent(context, MainActivity::class.java)
            .putExtra(MainActivity.EXTRA_OPEN_LINK, linkId)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pending = PendingIntent.getActivity(context, seq.toInt(), intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = NotificationCompat.Builder(context, RJApp.CHANNEL_SCHOOL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setCategory(NotificationCompat.CATEGORY_EVENT)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
        return runCatching { NotificationManagerCompat.from(context).notify(("school-$seq").hashCode(), notification); true }.getOrDefault(false)
    }
}
