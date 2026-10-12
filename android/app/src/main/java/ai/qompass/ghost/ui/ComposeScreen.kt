package ai.qompass.ghost.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import ai.qompass.ghost.pgp.PgpManager
import ai.qompass.ghost.pgp.RecipientKeyStore
import ai.qompass.ghost.pgp.normalizeRecipientEmail
import kotlinx.coroutines.launch
import org.bouncycastle.openpgp.PGPPublicKey

/**
 * Compose a message. Ghost encrypts end to end or not at all:
 *
 * - The body is encrypted with [PgpManager.encryptFor] to the recipient's
 *   stored public key before [onSend] is called; [onSend] only ever
 *   receives ASCII-armored ciphertext. There is no plaintext send path.
 * - Sending is enabled only when a validated key exists for the exact
 *   recipient address (see [RecipientKeyStore]). Without one, the screen
 *   offers key import instead: paste armored public key text, it is
 *   parsed and validated by [PgpManager.loadPublicKey], and only then
 *   stored.
 */
@Composable
fun ComposeScreen(
    pgpManager: PgpManager,
    keyStore: RecipientKeyStore,
    onSend: (to: String, subject: String, armoredBody: String) -> Unit,
    onCancel: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var to by remember { mutableStateOf("") }
    var subject by remember { mutableStateOf("") }
    var body by remember { mutableStateOf("") }
    var importText by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var notice by remember { mutableStateOf<String?>(null) }
    var sending by remember { mutableStateOf(false) }
    // Bumped after every store write so key lookups re-run.
    var keyVersion by remember { mutableIntStateOf(0) }

    val recipientEmail = normalizeRecipientEmail(to)
    val storedArmor = remember(recipientEmail, keyVersion) {
        if (recipientEmail.isBlank()) null else keyStore.armoredKeyFor(recipientEmail)
    }
    val recipientKey: PGPPublicKey? = remember(storedArmor) {
        storedArmor?.let { runCatching { pgpManager.loadPublicKey(it) }.getOrNull() }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("New message", style = MaterialTheme.typography.headlineSmall)
        OutlinedTextField(
            value = to,
            onValueChange = { to = it; error = null; notice = null },
            label = { Text("To") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )
        if (recipientKey != null) {
            Text(
                "Encrypting to ${keyLabel(recipientKey)}",
                style = MaterialTheme.typography.bodySmall
            )
        } else if (recipientEmail.isNotBlank()) {
            Text(
                "No PGP key for $recipientEmail. Import one below — " +
                    "Ghost never sends plaintext.",
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall
            )
            OutlinedTextField(
                value = importText,
                onValueChange = { importText = it },
                label = { Text("Recipient public key (ASCII armor)") },
                modifier = Modifier.fillMaxWidth()
            )
            OutlinedButton(
                onClick = {
                    val parsed = runCatching { pgpManager.loadPublicKey(importText) }
                    parsed.onSuccess {
                        runCatching { keyStore.put(recipientEmail, importText) }
                            .onSuccess {
                                importText = ""
                                error = null
                                notice = "Key saved for $recipientEmail"
                                keyVersion++
                            }
                            .onFailure { error = it.message ?: "could not store key" }
                    }.onFailure {
                        error = "That does not parse as a usable public key."
                    }
                },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Import key")
            }
        }
        OutlinedTextField(
            value = subject,
            onValueChange = { subject = it },
            label = { Text("Subject") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = body,
            onValueChange = { body = it },
            label = { Text("Body") },
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
        )
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        notice?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = onCancel, modifier = Modifier.weight(1f)) {
                Text("Cancel")
            }
            Button(
                onClick = {
                    val key = recipientKey ?: return@Button
                    sending = true
                    error = null
                    scope.launch {
                        runCatching {
                            pgpManager.encryptFor(
                                key,
                                body.toByteArray(Charsets.UTF_8)
                            )
                        }.onSuccess { armored ->
                            onSend(to.trim(), subject, armored)
                        }.onFailure {
                            error = it.message ?: "encryption failed"
                            sending = false
                        }
                    }
                },
                enabled = recipientKey != null && !sending,
                modifier = Modifier.weight(1f)
            ) {
                Text(if (sending) "Encrypting…" else "Encrypt & send via Tor")
            }
        }
        Spacer(Modifier.height(8.dp))
    }
}

/** "fingerprint — user ids" label for a validated recipient key. */
private fun keyLabel(key: PGPPublicKey): String {
    val fingerprint = "%016X".format(key.keyID)
    val ids = buildList {
        val it = key.userIDs
        while (it.hasNext()) add(it.next())
    }
    return if (ids.isEmpty()) "key $fingerprint" else "key $fingerprint — ${ids.first()}"
}
