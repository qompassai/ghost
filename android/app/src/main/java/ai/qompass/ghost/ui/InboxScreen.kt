package ai.qompass.ghost.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import ai.qompass.ghost.GhostApp
import ai.qompass.ghost.account.AccountStore
import ai.qompass.ghost.mail.MailClient
import ai.qompass.ghost.pgp.PgpManager
import ai.qompass.ghost.tor.TorManager
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.launch

/**
 * Inbox: newest-first message list over Tor IMAP.
 *
 * Contract:
 * - Fetches once per composition entry and on manual refresh; no
 *   background polling in v1 (foreground service arrives with push).
 * - Tapping a message opens [MessageReaderScreen] over the synced
 *   state held here; the reader itself never fetches.
 * - Failures surface as text, never crash; the list keeps its last
 *   good state.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InboxScreen(torManager: TorManager, accountStore: AccountStore) {
    val scope = rememberCoroutineScope()
    val pgpManager = remember { PgpManager() }
    var messages by remember { mutableStateOf<List<MailClient.SyncedMessage>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var composing by remember { mutableStateOf(false) }
    var reading by remember { mutableStateOf<MailClient.SyncedMessage?>(null) }

    fun client(): MailClient? {
        val creds = accountStore.credentials() ?: return null
        return MailClient(
            creds.onionHost, creds.username, creds.password,
            socksPort = torManager.socksPort
        )
    }

    fun refresh() {
        scope.launch {
            loading = true
            error = null
            runCatching { client()?.fetchInbox() ?: emptyList() }
                .onSuccess { messages = it }
                .onFailure { error = it.message ?: "fetch failed" }
            loading = false
        }
    }

    LaunchedEffect(Unit) { refresh() }

    if (composing) {
        ComposeScreen(
            onSend = { to, subject, body ->
                scope.launch {
                    runCatching { client()?.send(to, subject, body) }
                        .onSuccess { composing = false; refresh() }
                        .onFailure { error = it.message ?: "send failed" }
                }
            },
            onCancel = { composing = false }
        )
        return
    }

    reading?.let { selected ->
        MessageReaderScreen(
            message = selected,
            pgpManager = pgpManager,
            onBack = { reading = null }
        )
        return
    }

    Scaffold(
        topBar = { TopAppBar(title = { Text("Ghost Inbox") }) },
        floatingActionButton = {
            FloatingActionButton(onClick = { composing = true }) { Text("+") }
        }
    ) { pad ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(pad)
        ) {
            error?.let {
                Text(
                    it,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(16.dp)
                )
            }
            if (loading && messages.isEmpty()) {
                CircularProgressIndicator(modifier = Modifier.padding(16.dp))
            } else {
                LazyColumn {
                    items(messages, key = { it.summary.uid }) { synced ->
                        val msg = synced.summary
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { reading = synced }
                                .padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Text(msg.from, style = MaterialTheme.typography.labelMedium)
                            Text(msg.subject, style = MaterialTheme.typography.titleSmall)
                            Text(
                                msg.preview,
                                style = MaterialTheme.typography.bodySmall,
                                maxLines = 2
                            )
                            Text(
                                DateFormat.getDateTimeInstance()
                                    .format(Date(msg.dateMs)),
                                style = MaterialTheme.typography.labelSmall
                            )
                        }
                        HorizontalDivider()
                    }
                }
            }
        }
    }
}
