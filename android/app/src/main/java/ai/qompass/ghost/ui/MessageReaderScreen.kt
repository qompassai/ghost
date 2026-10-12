package ai.qompass.ghost.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import ai.qompass.ghost.mail.AttachmentInfo
import ai.qompass.ghost.mail.MailClient
import ai.qompass.ghost.mail.MessageBodyExtractor
import ai.qompass.ghost.pgp.PgpManager
import java.text.DateFormat
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.launch

/**
 * Message reader: one synced message, rendered from local state.
 *
 * Contract:
 * - Offline by construction: this screen receives an already-synced
 *   [MailClient.SyncedMessage] and renders it. It holds no [MailClient],
 *   opens no connection, and triggers no fetch — airplane mode changes
 *   nothing here.
 * - Bodies arrive as plain text from [MessageBodyExtractor]; HTML is
 *   never rendered as markup. Attachments are metadata rows only.
 * - A PGP-encrypted body decrypts on-device through [PgpManager]. The
 *   account store holds no key material in v1, so the user pastes their
 *   armored secret key and passphrase here; both live in composition
 *   memory only, are never persisted or logged, and are dropped when
 *   the screen closes. [PgpManager.decryptWith] zeroizes the passphrase
 *   copy it is handed.
 * - Decrypted text is shown, never written anywhere, and error text is
 *   fixed per failure class — exception details stay out of the UI so
 *   message content cannot leak through them.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MessageReaderScreen(
    message: MailClient.SyncedMessage,
    pgpManager: PgpManager,
    onBack: () -> Unit,
) {
    val summary = message.summary
    var body by remember(summary.uid) { mutableStateOf(message.body) }
    var keyText by remember(summary.uid) { mutableStateOf("") }
    var passphrase by remember(summary.uid) { mutableStateOf("") }
    var decryptError by remember(summary.uid) { mutableStateOf<String?>(null) }
    var decrypting by remember(summary.uid) { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun attemptDecrypt() {
        val ciphertext = body.pgpCiphertext ?: return
        val armoredKey = keyText
        val pass = passphrase
        decrypting = true
        decryptError = null
        scope.launch {
            runCatching {
                val ring = pgpManager.loadSecretKey(armoredKey)
                val bytes = pgpManager.decryptWith(ring, pass.toCharArray(), ciphertext)
                MessageBodyExtractor.fromDecrypted(bytes)
            }.onSuccess { resolved ->
                body = resolved
                keyText = ""
                passphrase = ""
            }.onFailure { failure ->
                decryptError = decryptErrorText(failure)
                passphrase = ""
            }
            decrypting = false
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        summary.subject.ifBlank { "(no subject)" },
                        maxLines = 1,
                    )
                },
                navigationIcon = {
                    TextButton(onClick = onBack) { Text("‹ Back") }
                },
            )
        }
    ) { pad ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(pad)
                .padding(16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(summary.from, style = MaterialTheme.typography.labelMedium)
            Text(
                DateFormat.getDateTimeInstance().format(Date(summary.dateMs)),
                style = MaterialTheme.typography.labelSmall,
            )
            HorizontalDivider()

            val ciphertext = body.pgpCiphertext
            val plainText = body.plainText
            when {
                ciphertext != null -> DecryptSection(
                    keyText = keyText,
                    onKeyChange = { keyText = it; decryptError = null },
                    passphrase = passphrase,
                    onPassphraseChange = { passphrase = it; decryptError = null },
                    decrypting = decrypting,
                    error = decryptError,
                    onDecrypt = { attemptDecrypt() },
                )
                plainText != null -> SelectionContainer {
                    Text(plainText, style = MaterialTheme.typography.bodyMedium)
                }
                else -> Text(
                    "This message has no readable text body.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            }

            if (body.truncated) {
                Text(
                    "Message body was truncated for display.",
                    style = MaterialTheme.typography.labelSmall,
                )
            }

            if (body.attachments.isNotEmpty()) {
                HorizontalDivider()
                Text("Attachments", style = MaterialTheme.typography.titleSmall)
                body.attachments.forEach { attachment ->
                    AttachmentRow(attachment)
                }
            }
        }
    }
}

/** Unlock form for a PGP-encrypted body: key + passphrase, memory only. */
@Composable
private fun DecryptSection(
    keyText: String,
    onKeyChange: (String) -> Unit,
    passphrase: String,
    onPassphraseChange: (String) -> Unit,
    decrypting: Boolean,
    error: String?,
    onDecrypt: () -> Unit,
) {
    Text(
        "This message is PGP-encrypted. Decrypt it on this device with " +
            "your secret key; the key and passphrase are kept in memory " +
            "only and never leave the device.",
        style = MaterialTheme.typography.bodyMedium,
    )
    OutlinedTextField(
        value = keyText,
        onValueChange = onKeyChange,
        label = { Text("Your PGP secret key (armored)") },
        modifier = Modifier.fillMaxWidth(),
        minLines = 3,
        maxLines = 6,
    )
    OutlinedTextField(
        value = passphrase,
        onValueChange = onPassphraseChange,
        label = { Text("Key passphrase") },
        singleLine = true,
        visualTransformation = PasswordVisualTransformation(),
        modifier = Modifier.fillMaxWidth(),
    )
    error?.let {
        Text(it, color = MaterialTheme.colorScheme.error)
    }
    Button(
        onClick = onDecrypt,
        enabled = keyText.isNotBlank() && passphrase.isNotEmpty() && !decrypting,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text("Decrypt on this device")
    }
    if (decrypting) {
        CircularProgressIndicator()
    }
}

@Composable
private fun AttachmentRow(attachment: AttachmentInfo) {
    val sizeSuffix = if (attachment.sizeBytes >= 0) {
        ", ${formatSize(attachment.sizeBytes)}"
    } else {
        ""
    }
    Text(
        "${attachment.fileName} — ${attachment.contentType}$sizeSuffix",
        style = MaterialTheme.typography.bodySmall,
    )
}

/** Fixed user-facing text per PGP failure class; no exception details. */
private fun decryptErrorText(failure: Throwable): String =
    when ((failure as? PgpManager.PgpException)?.error) {
        is PgpManager.PgpError.BadKey ->
            "That secret key could not be read."
        is PgpManager.PgpError.TooLarge ->
            "This message is too large to decrypt on this device."
        is PgpManager.PgpError.DecryptFailed, null ->
            "Decryption failed — check the key and passphrase."
    }

private fun formatSize(sizeBytes: Long): String = when {
    sizeBytes < 1024 -> "$sizeBytes B"
    sizeBytes < 1024 * 1024 -> "${sizeBytes / 1024} KiB"
    else -> String.format(Locale.US, "%.1f MiB", sizeBytes / (1024.0 * 1024.0))
}
