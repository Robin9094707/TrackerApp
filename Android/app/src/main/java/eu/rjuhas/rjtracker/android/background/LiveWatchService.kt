package eu.rjuhas.rjtracker.android.background

import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import eu.rjuhas.rjtracker.android.Graph
import eu.rjuhas.rjtracker.android.MainActivity
import eu.rjuhas.rjtracker.android.R
import eu.rjuhas.rjtracker.android.RJApp
import eu.rjuhas.rjtracker.android.data.LinkKind
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

/**
 * Near-instant notifications without an account or Firebase: a quiet foreground
 * service asks the server for new school events every 30 seconds. The server
 * itself records the bag every 20-30 s, independent of this phone.
 */
class LiveWatchService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var loop: Job? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val open = PendingIntent.getActivity(this, 1, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(this, RJApp.CHANNEL_WATCH)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Schultaschen-Wächter aktiv")
            .setContentText("Meldet Ankunft und Verlassen sofort")
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(open)
            .build()
        runCatching {
            ServiceCompat.startForeground(this, 42, notification,
                if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0)
        }.onFailure { stopSelf(); return START_NOT_STICKY }
        if (loop?.isActive != true) {
            loop = scope.launch {
                while (isActive) {
                    if (!wanted(this@LiveWatchService)) { stopSelf(); break }
                    runCatching { EventSync.sync(this@LiveWatchService) }
                    delay(30_000)
                }
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    companion object {
        suspend fun wanted(context: Context): Boolean =
            Graph.repository.current().any { it.kind == LinkKind.SCHOOL && it.liveNotifications }

        fun ensureRunning(context: Context) {
            val shouldRun = runBlocking { wanted(context) }
            val intent = Intent(context, LiveWatchService::class.java)
            if (shouldRun) runCatching { context.startForegroundService(intent) }
            else context.stopService(intent)
        }
    }
}
