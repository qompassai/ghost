package ai.qompass.ghost.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import ai.qompass.ghost.tor.TorManager

/**
 * Shown while Tor bootstraps, or when bootstrap fails.
 *
 * Contract: [onRetry] re-enters [TorManager.start]; the screen itself
 * holds no Tor state.
 */
@Composable
fun TorGateScreen(state: TorManager.State, onRetry: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        when (state) {
            is TorManager.State.Bootstrapping -> {
                CircularProgressIndicator()
                Spacer(Modifier.height(16.dp))
                Text("Connecting to Tor… ${state.percent}%")
                Text(
                    "All Ghost traffic stays inside the Tor network.",
                    style = MaterialTheme.typography.bodySmall
                )
            }
            is TorManager.State.Failed -> {
                Text("Tor failed to start", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(8.dp))
                Text(state.reason, style = MaterialTheme.typography.bodySmall)
                Spacer(Modifier.height(16.dp))
                Button(onClick = onRetry) { Text("Retry") }
            }
            else -> {
                CircularProgressIndicator()
                Spacer(Modifier.height(16.dp))
                Text("Starting Tor…")
            }
        }
    }
}
