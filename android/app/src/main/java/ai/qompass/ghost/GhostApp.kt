package ai.qompass.ghost

import android.app.Application
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

/**
 * Ghost application.
 *
 * Owns the single application-scoped [CoroutineScope]: every long-lived job
 * (Tor bootstrap, mail sync) is a child of [appScope] and dies with the
 * process. No GlobalScope anywhere in this app.
 */
class GhostApp : Application() {

    val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onCreate() {
        super.onCreate()
        _instance = this
    }

    override fun onTerminate() {
        appScope.cancel("application terminating")
        super.onTerminate()
    }

    companion object {
        @Volatile
        private var _instance: GhostApp? = null
        val instance: GhostApp
            get() = _instance ?: error("GhostApp not created yet")
    }
}
