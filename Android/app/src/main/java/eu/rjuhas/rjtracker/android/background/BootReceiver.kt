package eu.rjuhas.rjtracker.android.background

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        EventWorker.schedule(context)
        LiveWatchService.ensureRunning(context)
    }
}
