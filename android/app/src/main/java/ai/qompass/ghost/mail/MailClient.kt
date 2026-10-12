package ai.qompass.ghost.mail

import javax.mail.Authenticator
import javax.mail.Folder
import javax.mail.Message
import javax.mail.PasswordAuthentication
import javax.mail.Session
import javax.mail.Store
import javax.mail.Transport
import javax.mail.internet.InternetAddress
import javax.mail.internet.MimeMessage
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.Socket
import java.util.Properties
import javax.net.SocketFactory
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

/**
 * Mail client: IMAP + SMTP through Tor's SOCKS5 proxy.
 *
 * Contract:
 * - Every socket goes through the SOCKS5 proxy at [socksHost]:[socksPort].
 *   No clearnet connection is ever opened; DNS resolves inside Tor.
 * - [onionHost] is the Ghost onion address (no port 80/443 involved).
 * - IMAP on 993 (SSL/TLS); SMTP on 465 (SSL/TLS). AUTH PLAIN/LOGIN.
 * - Each operation is bounded by [OP_TIMEOUT_MS]; blocking I/O stays on
 *   Dispatchers.IO.
 * - A sync ([fetchInbox]) returns at most [INBOX_FETCH_MAX] messages.
 *   Each [SyncedMessage] pairs a bounded [MessageSummary] (preview
 *   truncated to [BODY_PREVIEW_CHARS]) with the message body extracted
 *   locally by [MessageBodyExtractor]; the reader renders synced state
 *   only and never triggers fetches of its own.
 */
class MailClient(
    private val onionHost: String,
    private val username: String,
    private val password: String,
    private val socksHost: String = "127.0.0.1",
    private val socksPort: Int,
) {
    init {
        require(onionHost.endsWith(".onion")) { "onionHost must be a .onion address" }
        require(username.isNotBlank()) { "username must not be blank" }
        require(socksPort in 1..65535) { "socksPort out of range" }
    }

    data class MessageSummary(
        val uid: Long,
        val from: String,
        val subject: String,
        val dateMs: Long,
        val preview: String,
    )

    /**
     * One synced message: the list [summary] plus its extracted [body],
     * held in memory by the caller. Process death drops synced state;
     * the next sync re-fetches. Nothing here touches disk.
     */
    data class SyncedMessage(
        val summary: MessageSummary,
        val body: MessageBody,
    )

    private fun session(): Session {
        val props = Properties().apply {
            put("mail.store.protocol", "imaps")
            put("mail.transport.protocol", "smtps")
            put("mail.imaps.host", onionHost)
            put("mail.imaps.port", IMAP_PORT)
            put("mail.imaps.ssl.enable", "true")
            put("mail.smtps.host", onionHost)
            put("mail.smtps.port", SMTP_PORT)
            put("mail.smtps.ssl.enable", "true")
            put("mail.smtps.auth", "true")
            // Route every socket through Tor; Jakarta Mail honors a custom
            // SocketFactory per protocol.
            put("mail.imaps.socketFactory", torSocketFactory())
            put("mail.smtps.socketFactory", torSocketFactory())
        }
        return Session.getInstance(props, object : Authenticator() {
            override fun getPasswordAuthentication() =
                PasswordAuthentication(username, password)
        })
    }

    private fun torSocketFactory(): SocketFactory = object : SocketFactory() {
        override fun createSocket(): Socket =
            Socket(Proxy(Proxy.Type.SOCKS, InetSocketAddress(socksHost, socksPort)))

        override fun createSocket(host: String, port: Int): Socket =
            createSocket().also { it.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS) }

        override fun createSocket(
            host: String, port: Int, localHost: java.net.InetAddress, localPort: Int,
        ): Socket = createSocket(host, port)

        override fun createSocket(
            host: java.net.InetAddress, port: Int,
        ): Socket = createSocket(host.hostAddress, port)

        override fun createSocket(
            address: java.net.InetAddress, port: Int,
            localAddress: java.net.InetAddress, localPort: Int,
        ): Socket = createSocket(address.hostAddress, port)
    }

    /**
     * Sync the newest inbox messages, newest first.
     *
     * Bodies are downloaded and extracted here, at sync time, so the
     * reader works purely from local state afterwards. Extraction is
     * bounded by [MessageBodyExtractor]'s caps.
     */
    suspend fun fetchInbox(): List<SyncedMessage> = withContext(Dispatchers.IO) {
        withTimeout(OP_TIMEOUT_MS) {
            val session = session()
            val store: Store = session.getStore("imaps")
            try {
                store.connect(onionHost, IMAP_PORT, username, password)
                val inbox: Folder = store.getFolder("INBOX")
                inbox.open(Folder.READ_ONLY)
                try {
                    val total = inbox.messageCount
                    val start = maxOf(1, total - INBOX_FETCH_MAX + 1)
                    inbox.getMessages(start, total)
                        .reversed()
                        .map { msg ->
                            val body = MessageBodyExtractor.extract(msg)
                            SyncedMessage(
                                summary = msg.toSummary(body),
                                body = body,
                            )
                        }
                } finally {
                    inbox.close(false)
                }
            } finally {
                store.close()
            }
        }
    }

    /** Send a (possibly PGP-encrypted) message. Body is pre-built by the caller. */
    suspend fun send(to: String, subject: String, body: String) = withContext(Dispatchers.IO) {
        require(to.isNotBlank()) { "recipient must not be blank" }
        withTimeout(OP_TIMEOUT_MS) {
            val session = session()
            val msg = MimeMessage(session).apply {
                setFrom(InternetAddress(username))
                setRecipients(Message.RecipientType.TO, InternetAddress.parse(to))
                setSubject(subject)
                setText(body, "utf-8")
            }
            val transport: Transport = session.getTransport("smtps")
            try {
                transport.connect(onionHost, SMTP_PORT, username, password)
                transport.sendMessage(msg, msg.allRecipients)
            } finally {
                transport.close()
            }
        }
    }

    private fun Message.toSummary(body: MessageBody): MessageSummary {
        val preview = when {
            body.pgpCiphertext != null -> PGP_PREVIEW
            else -> body.plainText
                ?.replace(WHITESPACE_RUN, " ")
                ?.trim()
                ?.take(BODY_PREVIEW_CHARS)
                ?: ""
        }
        return MessageSummary(
            uid = messageNumber.toLong(),
            from = from?.firstOrNull()?.toString() ?: "",
            subject = subject ?: "",
            dateMs = sentDate?.time ?: 0L,
            preview = preview,
        )
    }

    companion object {
        const val IMAP_PORT = 993
        const val SMTP_PORT = 465
        /** Newest N messages per inbox fetch; bounds memory and Tor traffic. */
        const val INBOX_FETCH_MAX = 50
        const val BODY_PREVIEW_CHARS = 280
        /** List preview shown for a PGP-encrypted body. */
        const val PGP_PREVIEW = "(PGP-encrypted message)"
        private val WHITESPACE_RUN = Regex("\\s+")
        const val OP_TIMEOUT_MS = 60_000L
        const val CONNECT_TIMEOUT_MS = 30_000
    }
}
