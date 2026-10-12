package ai.qompass.ghost.tor

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat
import ai.qompass.ghost.R
import org.torproject.jni.TorService as JniTorService

/**
 * Foreground service keeping Tor alive during mail sync.
 *
 * Contract: started by [TorAndroidBridge] when Tor starts, stopped when
 * Tor stops. While running it anchors the process (Android will not reap
 * a foreground service casually) and delegates the actual Tor lifecycle
 * to the tor-android provider service: ACTION_START on start, ACTION_STOP
 * on destroy. Not sticky: if the system kills us, Tor stays down until
 * the user returns — a privacy app never resurrects its tunnel silently.
 * The notification is mandatory for foreground services on Android 8+.
 */
class TorService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Ghost Tor",
            NotificationManager.IMPORTANCE_LOW
        )
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        runCatching {
            startService(
                Intent(this, JniTorService::class.java)
                    .setAction(JniTorService.ACTION_START)
            )
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        runCatching {
            startService(
                Intent(this, JniTorService::class.java)
                    .setAction(JniTorService.ACTION_STOP)
            )
        }
        super.onDestroy()
    }

    private fun buildNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.app_name))
            .setContentText("Tor connection active")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .build()

    companion object {
        private const val CHANNEL_ID = "ghost_tor"
        private const val NOTIFICATION_ID = 1
    }
}
