package ai.qompass.ghost

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import ai.qompass.ghost.account.AccountStore
import ai.qompass.ghost.tor.TorManager
import ai.qompass.ghost.ui.InboxScreen
import ai.qompass.ghost.ui.SetupScreen
import ai.qompass.ghost.ui.TorGateScreen
import ai.qompass.ghost.ui.theme.GhostTheme

/**
 * Single-activity host.
 *
 * Flow: TorGate (bootstrap Tor) -> Setup (no account) -> Inbox.
 * The activity owns the [TorManager]; screens are stateless w.r.t. it.
 */
class MainActivity : ComponentActivity() {

    private lateinit var torManager: TorManager
    private lateinit var accountStore: AccountStore

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val app = application as GhostApp
        torManager = TorManager(this, app.appScope)
        accountStore = AccountStore(this)

        setContent {
            GhostTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    GhostNav(torManager, accountStore)
                }
            }
        }
    }

    override fun onDestroy() {
        torManager.stop()
        super.onDestroy()
    }
}

@Composable
private fun GhostNav(torManager: TorManager, accountStore: AccountStore) {
    val torState by torManager.state.collectAsState()
    val hasAccount = remember { accountStore.hasAccount }

    when (val s = torState) {
        is TorManager.State.Ready -> {
            if (hasAccount) {
                InboxScreen(torManager, accountStore)
            } else {
                SetupScreen(accountStore)
            }
        }
        is TorManager.State.Failed -> TorGateScreen(s, onRetry = { torManager.start() })
        else -> TorGateScreen(s, onRetry = { torManager.start() })
    }

    // Kick off Tor on first composition.
    androidx.compose.runtime.LaunchedEffect(Unit) {
        torManager.start()
    }
}
