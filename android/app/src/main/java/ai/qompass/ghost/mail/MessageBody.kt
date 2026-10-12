package ai.qompass.ghost.mail

import java.io.ByteArrayInputStream
import java.io.InputStream
import java.util.Properties
import javax.mail.Message
import javax.mail.Multipart
import javax.mail.Part
import javax.mail.Session
import javax.mail.internet.ContentType
import javax.mail.internet.MimeMessage
import javax.mail.internet.MimeUtility

/**
 * One attachment of a synced message: metadata only.
 *
 * Attachment bytes are never pulled into local state by the reader path;
 * the UI lists what exists (name, type, size) and that is all.
 * [sizeBytes] is -1 when the part does not declare a size.
 */
data class AttachmentInfo(
    val fileName: String,
    val contentType: String,
    val sizeBytes: Long,
)

/**
 * The readable body of one synced message, extracted locally at sync time.
 *
 * Exactly one of [plainText] / [pgpCiphertext] is set for a readable
 * message:
 * - [plainText]: display-ready text. `text/plain` is preferred; an
 *   HTML-only body is converted to text by stripping markup — HTML is
 *   never handed to the UI as markup.
 * - [pgpCiphertext]: the ASCII-armored PGP payload when the body is
 *   OpenPGP-encrypted (inline armor or PGP/MIME `multipart/encrypted`).
 *   Decryption is a separate step through
 *   [ai.qompass.ghost.pgp.PgpManager]; see
 *   [MessageBodyExtractor.fromDecrypted].
 *
 * [truncated] is true when any bound below cut content short.
 */
data class MessageBody(
    val plainText: String?,
    val pgpCiphertext: String?,
    val attachments: List<AttachmentInfo>,
    val truncated: Boolean,
)

/**
 * MIME body extraction for the reader.
 *
 * Contract:
 * - Pure and local: operates on an already-fetched [Message]; opens no
 *   connections and reads nothing from the network itself. Callers run
 *   it on a background dispatcher (IMAP part access may block).
 * - The walk is bounded: at most [PARTS_MAX] parts, [DEPTH_MAX] nesting
 *   levels, [TEXT_CHARS_MAX] characters of text, [CIPHERTEXT_CHARS_MAX]
 *   characters of armored ciphertext. Overshoot sets
 *   [MessageBody.truncated] instead of growing memory.
 * - Malformed parts are skipped, never fatal: extraction of a hostile
 *   or broken message yields whatever readable body exists.
 */
object MessageBodyExtractor {

    /** Max MIME parts visited per message (attachments included). */
    const val PARTS_MAX = 64

    /** Max multipart nesting depth. */
    const val DEPTH_MAX = 6

    /** Max characters kept from a text body (plain or HTML-derived). */
    const val TEXT_CHARS_MAX = 262_144

    /** Max characters kept from an armored PGP payload. */
    const val CIPHERTEXT_CHARS_MAX = 2_097_152

    /** Max bytes read from a streamed part (e.g. binary PGP data). */
    const val STREAM_BYTES_MAX = 4_194_304

    private const val PGP_BEGIN = "-----BEGIN PGP MESSAGE-----"
    private const val PGP_END = "-----END PGP MESSAGE-----"

    /** Extract the readable body of a fetched message. */
    fun extract(message: Message): MessageBody {
        val walk = Walk()
        runCatching { walkPart(message, depth = 0, walk) }
        return walk.finish()
    }

    /**
     * Resolve decrypted PGP plaintext into a body.
     *
     * The plaintext of a mail message is one of: plain text, a nested
     * armored PGP block (double encryption), or a whole MIME entity
     * (PGP/MIME). MIME entities are detected by their header block and
     * re-extracted; anything else is shown as the text it is.
     */
    fun fromDecrypted(plaintext: ByteArray): MessageBody {
        val text = plaintext.toString(Charsets.UTF_8)
        extractPgpArmor(text)?.let { armor ->
            return MessageBody(
                plainText = null,
                pgpCiphertext = armor,
                attachments = emptyList(),
                truncated = false,
            )
        }
        if (looksLikeMimeEntity(text)) {
            val parsed = runCatching {
                val session = Session.getInstance(Properties())
                MimeMessage(session, ByteArrayInputStream(plaintext))
            }.getOrNull()
            if (parsed != null) return extract(parsed)
        }
        val bounded = boundText(text)
        return MessageBody(
            plainText = bounded.first,
            pgpCiphertext = null,
            attachments = emptyList(),
            truncated = bounded.second,
        )
    }

    /** Extract the armored PGP block out of [text]; null when absent. */
    internal fun extractPgpArmor(text: String): String? {
        val begin = text.indexOf(PGP_BEGIN)
        if (begin < 0) return null
        val end = text.indexOf(PGP_END, begin)
        if (end < 0) return text.substring(begin).trim()
        return text.substring(begin, end + PGP_END.length)
    }

    /**
     * Convert HTML to plain text: drop script/style, turn block
     * boundaries into newlines, strip every remaining tag, decode the
     * common entities. Lossy by design — the result is for reading,
     * never re-rendered as markup.
     */
    internal fun htmlToText(html: String): String {
        var text = html.replace(SCRIPT_OR_STYLE, " ")
        text = text.replace(BREAK_TAG, "\n")
        text = text.replace(BLOCK_CLOSE_TAG, "\n")
        text = text.replace(ANY_TAG, "")
        text = decodeEntities(text)
        return text.replace(BLANK_RUN, "\n\n").trim()
    }

    private fun decodeEntities(text: String): String {
        var out = text
            .replace("&nbsp;", " ")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&quot;", "\"")
            .replace("&apos;", "'")
            .replace("&#39;", "'")
        out = NUMERIC_ENTITY.replace(out) { match ->
            val code = match.groupValues[1].toIntOrNull()
            if (code != null && code in 32..0xFFFF) code.toChar().toString() else ""
        }
        // Decode &amp; last so "&amp;lt;" stays the literal text "&lt;".
        return out.replace("&amp;", "&")
    }

    private fun looksLikeMimeEntity(text: String): Boolean {
        val head = text.substringBefore("\r\n\r\n").substringBefore("\n\n")
        if (head.length == text.length) return false
        val lines = head.lines()
        if (lines.isEmpty() || !HEADER_LINE.matches(lines.first())) return false
        return lines.any {
            it.startsWith("Content-Type:", ignoreCase = true) ||
                it.startsWith("MIME-Version:", ignoreCase = true)
        }
    }

    /** Trim + cap a display text; returns (text, wasTruncated). */
    private fun boundText(raw: String): Pair<String, Boolean> {
        val normalized = raw.replace("\r\n", "\n").trim()
        if (normalized.length <= TEXT_CHARS_MAX) return normalized to false
        return normalized.substring(0, TEXT_CHARS_MAX) to true
    }

    private val SCRIPT_OR_STYLE =
        Regex("(?is)<(script|style)[^>]*>.*?</\\1>")
    private val BREAK_TAG = Regex("(?i)<br\\s*/?>")
    private val BLOCK_CLOSE_TAG = Regex("(?i)</(p|div|li|tr|h[1-6])>")
    private val ANY_TAG = Regex("<[^>]+>")
    private val NUMERIC_ENTITY = Regex("&#(\\d+);")
    private val BLANK_RUN = Regex("\n{3,}")
    private val HEADER_LINE = Regex("^[A-Za-z][A-Za-z0-9-]*:.*")

    /** Mutable accumulator for one extraction walk. */
    private class Walk {
        var plainText: String? = null
        var htmlText: String? = null
        var pgpCiphertext: String? = null
        var truncated: Boolean = false
        val attachments: MutableList<AttachmentInfo> = mutableListOf()
        private var partsSeen: Int = 0

        fun finish(): MessageBody {
            pgpCiphertext?.let { armor ->
                return MessageBody(null, armor, attachments.toList(), truncated)
            }
            val text = plainText ?: htmlText?.let { htmlToText(it) }
            val bounded = text?.let { boundText(it) }
            return MessageBody(
                plainText = bounded?.first,
                pgpCiphertext = null,
                attachments = attachments.toList(),
                truncated = truncated || (bounded?.second ?: false),
            )
        }

        fun countPart(): Boolean {
            partsSeen++
            if (partsSeen > PARTS_MAX) {
                truncated = true
                return false
            }
            return true
        }
    }

    private fun walkPart(part: Part, depth: Int, walk: Walk) {
        if (depth > DEPTH_MAX) {
            walk.truncated = true
            return
        }
        if (!walk.countPart()) return
        when {
            part.isMimeType("multipart/encrypted") -> walkEncrypted(part, depth, walk)
            part.isMimeType("multipart/*") -> {
                val multipart = part.content as? Multipart ?: return
                val count = minOf(multipart.count, PARTS_MAX)
                for (i in 0 until count) {
                    walkPart(multipart.getBodyPart(i), depth + 1, walk)
                }
            }
            part.isMimeType("message/rfc822") -> {
                (part.content as? Message)?.let { walkPart(it, depth + 1, walk) }
            }
            part.isMimeType("application/pgp-signature") -> Unit
            part.isMimeType("application/pgp-encrypted") -> Unit
            isAttachment(part) -> walk.attachments.add(attachmentInfo(part))
            part.isMimeType("text/plain") -> {
                if (walk.pgpCiphertext == null && walk.plainText == null) {
                    val text = readText(part, walk)
                    val armor = extractPgpArmor(text)
                    if (armor != null) {
                        walk.pgpCiphertext = armor
                    } else {
                        walk.plainText = text
                    }
                }
            }
            part.isMimeType("text/html") -> {
                if (walk.htmlText == null) walk.htmlText = readText(part, walk)
            }
            else -> {
                // Unknown leaf part: if it carries a file name it is an
                // attachment in everything but the sender's labeling.
                if (safeFileName(part) != null) {
                    walk.attachments.add(attachmentInfo(part))
                }
            }
        }
    }

    /** PGP/MIME: the octet-stream sibling of the version part is the payload. */
    private fun walkEncrypted(part: Part, depth: Int, walk: Walk) {
        val multipart = part.content as? Multipart ?: return
        val count = minOf(multipart.count, PARTS_MAX)
        for (i in 0 until count) {
            val child = multipart.getBodyPart(i)
            when {
                // The version part is protocol metadata, never content.
                child.isMimeType("application/pgp-encrypted") -> walk.countPart()
                child.isMimeType("application/octet-stream") -> {
                    if (!walk.countPart()) return
                    if (walk.pgpCiphertext == null) {
                        val raw = readText(child, walk, CIPHERTEXT_CHARS_MAX)
                        walk.pgpCiphertext = extractPgpArmor(raw) ?: raw.trim()
                    }
                }
                else -> walkPart(child, depth + 1, walk)
            }
        }
    }

    private fun isAttachment(part: Part): Boolean {
        val disposition = runCatching { part.disposition }.getOrNull()
        if (disposition != null) {
            return disposition.equals(Part.ATTACHMENT, ignoreCase = true)
        }
        // No disposition header: a named non-text part is an attachment.
        return safeFileName(part) != null && !part.isMimeType("text/*")
    }

    private fun attachmentInfo(part: Part): AttachmentInfo {
        val rawName = safeFileName(part)
        val decoded = rawName?.let {
            runCatching { MimeUtility.decodeText(it) }.getOrDefault(it)
        }?.takeIf { it.isNotBlank() } ?: "unnamed attachment"
        val baseType = runCatching { ContentType(part.contentType).baseType }
            .getOrNull()
            ?: part.contentType.substringBefore(';').trim()
                .ifBlank { "application/octet-stream" }
        val size = runCatching { part.size }.getOrDefault(-1)
        return AttachmentInfo(
            fileName = decoded,
            contentType = baseType,
            sizeBytes = if (size >= 0) size.toLong() else -1L,
        )
    }

    private fun safeFileName(part: Part): String? =
        runCatching { part.fileName }.getOrNull()

    /**
     * Read a text-bearing part as a string, bounded. Streamed content is
     * capped at [STREAM_BYTES_MAX]; string content at [cap] characters.
     */
    private fun readText(part: Part, walk: Walk, cap: Int = TEXT_CHARS_MAX): String {
        val content = runCatching { part.content }.getOrNull()
        val raw: String = when (content) {
            is String -> content
            is InputStream -> readStream(content, part)
            else -> ""
        }
        if (raw.length > cap) {
            walk.truncated = true
            return raw.substring(0, cap)
        }
        return raw
    }

    private fun readStream(stream: InputStream, part: Part): String {
        val buffer = ByteArray(STREAM_BYTES_MAX)
        var total = 0
        stream.use { input ->
            while (total < buffer.size) {
                val read = input.read(buffer, total, buffer.size - total)
                if (read < 0) break
                total += read
            }
        }
        val charsetName = runCatching {
            ContentType(part.contentType).getParameter("charset")
        }.getOrNull()
        val charset = charsetName?.let {
            runCatching { charset(it) }.getOrNull()
        } ?: Charsets.UTF_8
        return String(buffer, 0, total, charset)
    }
}
