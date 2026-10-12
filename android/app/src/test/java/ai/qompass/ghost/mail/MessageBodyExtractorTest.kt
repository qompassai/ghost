package ai.qompass.ghost.mail

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.Properties
import javax.activation.DataHandler
import javax.mail.Part
import javax.mail.Session
import javax.mail.internet.MimeBodyPart
import javax.mail.internet.MimeMessage
import javax.mail.internet.MimeMultipart
import javax.mail.util.ByteArrayDataSource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Seeded-mail tests for [MessageBodyExtractor]: every fixture is a real
 * RFC 5322 byte stream, parsed back through Jakarta Mail exactly as a
 * synced message arrives, and the extracted body must match the seeded
 * plaintext exactly.
 */
class MessageBodyExtractorTest {

    private fun session(): Session = Session.getInstance(Properties())

    /** Serialize [built] to wire bytes and parse it back as a fresh message. */
    private fun roundTrip(built: MimeMessage): MimeMessage {
        runCatching { built.saveChanges() }
        val out = ByteArrayOutputStream()
        built.writeTo(out)
        return MimeMessage(session(), ByteArrayInputStream(out.toByteArray()))
    }

    private fun textPart(text: String): MimeBodyPart =
        MimeBodyPart().apply { setText(text, "utf-8") }

    private fun htmlPart(html: String): MimeBodyPart =
        MimeBodyPart().apply { setContent(html, "text/html; charset=utf-8") }

    @Test
    fun simplePlainTextBodyIsExtractedExactly() {
        val msg = MimeMessage(session()).apply {
            setFrom("alice@ghost.onion")
            setSubject("plain")
            setText("Hello Ghost, this is the seeded body.", "utf-8")
        }
        val body = MessageBodyExtractor.extract(roundTrip(msg))
        assertEquals("Hello Ghost, this is the seeded body.", body.plainText)
        assertNull(body.pgpCiphertext)
        assertTrue(body.attachments.isEmpty())
        assertFalse(body.truncated)
    }

    @Test
    fun multipartAlternativePrefersPlainText() {
        val alternative = MimeMultipart("alternative").apply {
            addBodyPart(textPart("PLAIN SEEDED BODY"))
            addBodyPart(htmlPart("<html><body><p>HTML BODY</p></body></html>"))
        }
        val msg = MimeMessage(session()).apply { setContent(alternative) }
        val body = MessageBodyExtractor.extract(roundTrip(msg))
        assertEquals("PLAIN SEEDED BODY", body.plainText)
        assertTrue(body.attachments.isEmpty())
    }

    @Test
    fun htmlOnlyBodyIsConvertedToTextNeverMarkup() {
        val msg = MimeMessage(session()).apply {
            setContent(
                "<html><body><p>Line one</p><p>Line &amp; two</p>" +
                    "<script>alert(1)</script></body></html>",
                "text/html; charset=utf-8",
            )
        }
        val body = MessageBodyExtractor.extract(roundTrip(msg))
        val text = body.plainText
        assertNotNull(text)
        assertTrue(text!!.contains("Line one"))
        assertTrue(text.contains("Line & two"))
        assertFalse(text.contains("<p>"))
        assertFalse(text.contains("alert"))
    }

    @Test
    fun mixedMessageListsAttachmentMetadataAndKeepsBody() {
        val pdfBytes = byteArrayOf(0x25, 0x50, 0x44, 0x46, 0x2D) // "%PDF-"
        val attachment = MimeBodyPart().apply {
            dataHandler = DataHandler(ByteArrayDataSource(pdfBytes, "application/pdf"))
            fileName = "report.pdf"
            disposition = Part.ATTACHMENT
        }
        val mixed = MimeMultipart("mixed").apply {
            addBodyPart(textPart("See attached."))
            addBodyPart(attachment)
        }
        val msg = MimeMessage(session()).apply { setContent(mixed) }
        val body = MessageBodyExtractor.extract(roundTrip(msg))
        assertEquals("See attached.", body.plainText)
        assertEquals(1, body.attachments.size)
        val info = body.attachments.single()
        assertEquals("report.pdf", info.fileName)
        assertEquals("application/pdf", info.contentType)
        assertEquals(pdfBytes.size.toLong(), info.sizeBytes)
    }

    @Test
    fun nestedMultipartFindsBodyAndAttachment() {
        val alternative = MimeMultipart("alternative").apply {
            addBodyPart(textPart("NESTED BODY"))
            addBodyPart(htmlPart("<p>NESTED BODY</p>"))
        }
        val note = MimeBodyPart().apply {
            dataHandler = DataHandler(ByteArrayDataSource("memo".toByteArray(), "text/plain"))
            fileName = "memo.txt"
            disposition = Part.ATTACHMENT
        }
        val mixed = MimeMultipart("mixed").apply {
            addBodyPart(MimeBodyPart().apply { setContent(alternative) })
            addBodyPart(note)
        }
        val msg = MimeMessage(session()).apply { setContent(mixed) }
        val body = MessageBodyExtractor.extract(roundTrip(msg))
        assertEquals("NESTED BODY", body.plainText)
        assertEquals(listOf("memo.txt"), body.attachments.map { it.fileName })
    }

    @Test
    fun inlinePgpArmorIsDetectedAsCiphertext() {
        val armor = """
            -----BEGIN PGP MESSAGE-----

            wcFMA8SeEdedPQ==
            =ab12
            -----END PGP MESSAGE-----
        """.trimIndent()
        val msg = MimeMessage(session()).apply { setText(armor, "us-ascii") }
        val body = MessageBodyExtractor.extract(roundTrip(msg))
        assertNull(body.plainText)
        assertNotNull(body.pgpCiphertext)
        assertTrue(body.pgpCiphertext!!.startsWith("-----BEGIN PGP MESSAGE-----"))
        assertTrue(body.pgpCiphertext.endsWith("-----END PGP MESSAGE-----"))
    }

    @Test
    fun pgpMimeEncryptedPartIsCapturedAsCiphertext() {
        val version = MimeBodyPart().apply {
            setContent("Version: 1", "application/pgp-encrypted")
        }
        val payload = MimeBodyPart().apply {
            setContent(
                "-----BEGIN PGP MESSAGE-----\n\nwcFMA8SeEdedPQ==\n=ab12\n" +
                    "-----END PGP MESSAGE-----",
                "application/octet-stream",
            )
            disposition = Part.INLINE
        }
        val encrypted = MimeMultipart("encrypted").apply {
            addBodyPart(version)
            addBodyPart(payload)
        }
        val msg = MimeMessage(session()).apply { setContent(encrypted) }
        val body = MessageBodyExtractor.extract(roundTrip(msg))
        assertNull(body.plainText)
        assertNotNull(body.pgpCiphertext)
        assertTrue(body.pgpCiphertext!!.contains("wcFMA8SeEdedPQ=="))
        assertTrue(body.attachments.isEmpty())
    }

    @Test
    fun oversizedBodyIsBoundedAndFlagged() {
        val big = "a".repeat(MessageBodyExtractor.TEXT_CHARS_MAX + 5_000)
        val msg = MimeMessage(session()).apply { setText(big, "utf-8") }
        val body = MessageBodyExtractor.extract(roundTrip(msg))
        assertEquals(MessageBodyExtractor.TEXT_CHARS_MAX, body.plainText!!.length)
        assertTrue(body.truncated)
    }

    @Test
    fun decryptedPlainBytesResolveToExactText() {
        val body = MessageBodyExtractor.fromDecrypted(
            "The eagle has landed.".toByteArray(Charsets.UTF_8),
        )
        assertEquals("The eagle has landed.", body.plainText)
        assertNull(body.pgpCiphertext)
    }

    @Test
    fun decryptedMimeEntityIsReExtracted() {
        val entity = "Content-Type: text/plain; charset=utf-8\r\n" +
            "Content-Transfer-Encoding: 7bit\r\n\r\nInner seeded body."
        val body = MessageBodyExtractor.fromDecrypted(entity.toByteArray(Charsets.UTF_8))
        assertEquals("Inner seeded body.", body.plainText)
    }

    @Test
    fun messageWithoutTextBodyYieldsNoPlainText() {
        val onlyAttachment = MimeBodyPart().apply {
            dataHandler = DataHandler(
                ByteArrayDataSource(byteArrayOf(1, 2, 3), "application/octet-stream"),
            )
            fileName = "blob.bin"
            disposition = Part.ATTACHMENT
        }
        val mixed = MimeMultipart("mixed").apply { addBodyPart(onlyAttachment) }
        val msg = MimeMessage(session()).apply { setContent(mixed) }
        val body = MessageBodyExtractor.extract(roundTrip(msg))
        assertNull(body.plainText)
        assertNull(body.pgpCiphertext)
        assertEquals(1, body.attachments.size)
        assertTrue(body.attachments.single().contentType.startsWith("application/"))
    }
}
