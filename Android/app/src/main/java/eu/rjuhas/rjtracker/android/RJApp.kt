package eu.rjuhas.rjtracker.android

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import eu.rjuhas.rjtracker.android.background.EventWorker
import eu.rjuhas.rjtracker.android.data.Api
import eu.rjuhas.rjtracker.android.data.LinkRepository
import org.osmdroid.config.Configuration

/** Tiny service locator; the app is small enough not to need a DI framework. */
object Graph {
    lateinit var repository: LinkRepository
        private set
    val api = Api()

    fun init(context: Context) {
        repository = LinkRepository(context.applicationContext)
    }
}

class RJApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Graph.init(this)
        Configuration.getInstance().apply {
            userAgentValue = "RJTrackerAndroid/1.0 (${packageName})"
            osmdroidBasePath = cacheDir.resolve("osmdroid")
            osmdroidTileCache = cacheDir.resolve("osmdroid/tiles")
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL_SCHOOL, getString(R.string.channel_school), NotificationManager.IMPORTANCE_HIGH).apply {
            description = getString(R.string.channel_school_desc)
            enableVibration(true)
        })
        manager.createNotificationChannel(NotificationChannel(CHANNEL_WATCH, getString(R.string.channel_watch), NotificationManager.IMPORTANCE_MIN).apply {
            description = getString(R.string.channel_watch_desc)
            setShowBadge(false)
        })
        EventWorker.schedule(this)
    }

    companion object {
        const val CHANNEL_SCHOOL = "school_events"
        const val CHANNEL_WATCH = "school_watch"
    }
}
