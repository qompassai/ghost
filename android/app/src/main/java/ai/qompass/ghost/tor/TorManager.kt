// File-level deprecation suppression: the tor-android provider
// publishes its status exclusively through the deprecated
// LocalBroadcastManager (0.4.9.6, ACTION_STATUS); there is no
// supported replacement channel to receive it on. The only use
// in this file is TorAndroidBridge below.
@file:Suppress("DEPRECATION")

package ai.qompass.ghost.tor

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.ServiceConnection
import android.os.IBinder
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.torproject.jni.TorService as JniTorService

/**
 * Tor lifecycle manager.
 *
 * Contract:
 * - [start] bootstraps Tor once; concurrent calls share the in-flight job.
 * - [socksPort] is valid only after [State.Ready]; 0 before.
 * - [stop] tears Tor down; a later [start] re-bootstraps cleanly.
 * - Bootstrap is bounded: [BOOTSTRAP_TIMEOUT_MS] then [State.Failed].
 * - All blocking Tor work runs on Dispatchers.IO; state flows on the
 *   caller's scope.
 *
 * Mail and XMPP clients take [socksPort] and open SOCKS5 connections
 * through it to the Ghost onion service. Nothing ever touches clearnet.
 */
class TorManager(
    private val context: Context,
    private val scope: CoroutineScope,
) {
    sealed interface State {
        data object Idle : State
        data object Starting : State
        /** percent in 0..100 */
        data class Bootstrapping(val percent: Int) : State
        data object Ready : State
        data class Failed(val reason: String) : State
    }

    private val _state = MutableStateFlow<State>(State.Idle)
    val state: StateFlow<State> = _state.asStateFlow()

    /** SOCKS5 port Tor listens on; 0 until [State.Ready]. */
    @Volatile
    var socksPort: Int = 0
        private set

    private var startJob: Job? = null

    /**
     * Start Tor. Idempotent: returns the existing job when already
     * starting or ready.
     */
    @Synchronized
    fun start(): Job {
        startJob?.let { if (it.isActive) return it }
        _state.value = State.Starting
        val job = scope.launch {
            try {
                bootstrap()
            } catch (e: Exception) {
                _state.value = State.Failed(e.message ?: "unknown tor failure")
                socksPort = 0
            }
        }
        startJob = job
        return job
    }

    @Synchronized
    fun stop() {
        startJob?.cancel()
        startJob = null
        // Tor-android cleanup happens on the IO dispatcher.
        scope.launch(Dispatchers.IO) {
            runCatching { TorAndroidBridge.stop(context) }
        }
        socksPort = 0
        _state.value = State.Idle
    }

    private suspend fun bootstrap() = withContext(Dispatchers.IO) {
        // tor-android owns the native bootstrap; we poll progress with a
        // hard deadline so a stuck bootstrap cannot hang the app.
        val deadlineMs = System.currentTimeMillis() + BOOTSTRAP_TIMEOUT_MS
        val port = TorAndroidBridge.start(context) { percent ->
            _state.value = State.Bootstrapping(percent.coerceIn(0, 100))
        }
        while (System.currentTimeMillis() < deadlineMs) {
            if (TorAndroidBridge.isBootstrapped()) {
                socksPort = port
                _state.value = State.Ready
                return@withContext
            }
            kotlinx.coroutines.delay(PROGRESS_POLL_MS)
        }
        throw IllegalStateException("Tor bootstrap timed out after ${BOOTSTRAP_TIMEOUT_MS}ms")
    }

    companion object {
        /** Hard bound on a single bootstrap attempt. */
        const val BOOTSTRAP_TIMEOUT_MS = 120_000L
        const val PROGRESS_POLL_MS = 500L
    }
}

/**
 * Seam over the tor-android artifact (info.guardianproject:tor-android).
 *
 * Kept behind this bridge so the Tor provider can be swapped without
 * touching [TorManager]. tor-android is FOSS (BSD-3-Clause); no GMS.
 *
 * How the provider works (tor-android 0.4.9.6, org.torproject.jni):
 * - The provider is a Service started and stopped with ACTION_START /
 *   ACTION_STOP intents; it owns the tor process and its torrc.
 * - Status changes are published over LocalBroadcastManager with
 *   ACTION_STATUS + EXTRA_STATUS (OFF / STARTING / ON / STOPPING).
 * - The bound service reports bootstrap percent via
 *   getInfo("status/bootstrap-phase") and the live SOCKS port once ON.
 *
 * Our own [TorService] foreground service anchors the process during
 * mail sync; starting it starts Tor, stopping it stops Tor. [start]
 * drives that service, then waits — bounded by [START_WAIT_MS] —
 * pumping [onProgress] until the provider reports ON.
 */
// Status arrives over LocalBroadcastManager; see the file-level
// suppression note at the top of this file.
internal object TorAndroidBridge {

    /** Poll cadence while waiting for bootstrap; bounds wakeups. */
    private const val POLL_INTERVAL_MS = 250L

    /**
     * Internal wait bound for [start]. [TorManager] owns the user-visible
     * 120 s deadline; the bridge gives up first so its failure reason is
     * the one that surfaces.
     */
    private const val START_WAIT_MS = 100_000L

    private val bootstrapProgress = Regex("""PROGRESS=(\d{1,3})""")

    @Volatile
    private var lastStatus: String = JniTorService.STATUS_OFF

    @Volatile
    private var boundService: JniTorService? = null

    @Volatile
    private var startThread: Thread? = null

    private var serviceConnection: ServiceConnection? = null
    private var receiverRegistered = false

    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            intent.getStringExtra(JniTorService.EXTRA_STATUS)?.let { lastStatus = it }
        }
    }

    /**
     * Start Tor, invoking [onProgress] with 0..100. Returns the SOCKS port.
     * Blocking: call on Dispatchers.IO.
     *
     * @throws IllegalStateException when Tor dies mid-bootstrap, the wait
     * is interrupted by [stop], or ON is not reached within [START_WAIT_MS].
     */
    fun start(context: Context, onProgress: (Int) -> Unit): Int {
        val appContext = context.applicationContext
        if (isBootstrapped()) {
            onProgress(100)
            return currentSocksPort()
        }
        startThread = Thread.currentThread()
        try {
            ensureStatusReceiver(appContext)
            bindControlService(appContext)
            appContext.startForegroundService(Intent(appContext, TorService::class.java))
            val deadlineMs = System.currentTimeMillis() + START_WAIT_MS
            var lastProgress = -1
            var sawStarting = false
            while (System.currentTimeMillis() < deadlineMs) {
                when (lastStatus) {
                    JniTorService.STATUS_ON -> {
                        val port = currentSocksPort()
                        if (port > 0) {
                            onProgress(100)
                            return port
                        }
                    }
                    JniTorService.STATUS_STARTING,
                    JniTorService.STATUS_STOPPING -> sawStarting = true
                    JniTorService.STATUS_OFF -> {
                        if (sawStarting) {
                            throw IllegalStateException("tor stopped during bootstrap")
                        }
                    }
                }
                val progress = bootstrapPercent()
                if (progress != null) {
                    sawStarting = true
                    if (progress != lastProgress) {
                        lastProgress = progress
                        onProgress(progress.coerceIn(0, 100))
                    }
                }
                try {
                    Thread.sleep(POLL_INTERVAL_MS)
                } catch (e: InterruptedException) {
                    Thread.currentThread().interrupt()
                    throw IllegalStateException("tor start interrupted", e)
                }
            }
            throw IllegalStateException("tor did not bootstrap within ${START_WAIT_MS}ms")
        } finally {
            startThread = null
        }
    }

    /** True only once the provider reports ON with a live SOCKS port. */
    fun isBootstrapped(): Boolean =
        lastStatus == JniTorService.STATUS_ON && currentSocksPort() > 0

    /**
     * Stop Tor: interrupt any in-flight [start], drop the control binding,
     * stop the foreground anchor (its onDestroy forwards STOP), and send
     * STOP to the provider directly in case the anchor never ran.
     */
    fun stop(context: Context) {
        val appContext = context.applicationContext
        startThread?.interrupt()
        unbindControlService(appContext)
        appContext.stopService(Intent(appContext, TorService::class.java))
        runCatching {
            appContext.startService(
                Intent(appContext, JniTorService::class.java)
                    .setAction(JniTorService.ACTION_STOP)
            )
        }
        lastStatus = JniTorService.STATUS_OFF
    }

    private fun currentSocksPort(): Int =
        boundService?.socksPort?.takeIf { it > 0 } ?: JniTorService.socksPort

    /** Bootstrap percent from the control connection; null when unknown. */
    private fun bootstrapPercent(): Int? {
        val service = boundService ?: return null
        val phase = runCatching { service.getInfo("status/bootstrap-phase") }
            .getOrNull() ?: return null
        return bootstrapProgress.find(phase)?.groupValues?.get(1)?.toIntOrNull()
    }

    @Synchronized
    private fun ensureStatusReceiver(appContext: Context) {
        if (receiverRegistered) return
        LocalBroadcastManager.getInstance(appContext).registerReceiver(
            statusReceiver,
            IntentFilter(JniTorService.ACTION_STATUS)
        )
        receiverRegistered = true
    }

    @Synchronized
    private fun bindControlService(appContext: Context) {
        if (serviceConnection != null) return
        val connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName, binder: IBinder) {
                boundService = (binder as JniTorService.LocalBinder).service
            }

            override fun onServiceDisconnected(name: ComponentName) {
                boundService = null
            }
        }
        val bound = appContext.bindService(
            Intent(appContext, JniTorService::class.java),
            connection,
            Context.BIND_AUTO_CREATE
        )
        if (bound) serviceConnection = connection
    }

    @Synchronized
    private fun unbindControlService(appContext: Context) {
        val connection = serviceConnection ?: return
        serviceConnection = null
        boundService = null
        runCatching { appContext.unbindService(connection) }
    }
}
