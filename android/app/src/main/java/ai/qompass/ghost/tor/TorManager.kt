package ai.qompass.ghost.tor

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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
 * Thin seam over the tor-android artifact.
 *
 * Kept behind this bridge so the Tor provider can be swapped without
 * touching [TorManager]. tor-android is FOSS (BSD-3-Clause); no GMS.
 */
internal object TorAndroidBridge {
    /**
     * Start Tor, invoking [onProgress] with 0..100. Returns the SOCKS port.
     * Blocking: call on Dispatchers.IO.
     */
    fun start(context: Context, onProgress: (Int) -> Unit): Int {
        // Wired to org.torproject:tor-android in the app module.
        // Implementation lands with the TorService in the next change.
        TODO("wire tor-android TorService")
    }

    fun isBootstrapped(): Boolean {
        TODO("wire tor-android status check")
    }

    fun stop(context: Context) {
        TODO("wire tor-android stop")
    }
}
