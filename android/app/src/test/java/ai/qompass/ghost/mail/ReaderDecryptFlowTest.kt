package ai.qompass.ghost.mail

import ai.qompass.ghost.pgp.PgpManager
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.security.KeyPairGenerator
import java.security.Security
import java.util.Date
import java.util.Properties
import javax.mail.Session
import javax.mail.internet.MimeMessage
import kotlinx.coroutines.runBlocking
import org.bouncycastle.bcpg.ArmoredOutputStream
import org.bouncycastle.bcpg.HashAlgorithmTags
import org.bouncycastle.jce.provider.BouncyCastleProvider
import org.bouncycastle.openpgp.PGPEncryptedData
import org.bouncycastle.openpgp.PGPKeyRingGenerator
import org.bouncycastle.openpgp.PGPPublicKey
import org.bouncycastle.openpgp.PGPPublicKeyRing
import org.bouncycastle.openpgp.PGPSecretKeyRing
import org.bouncycastle.openpgp.PGPSignature
import org.bouncycastle.openpgp.operator.jcajce.JcaPGPContentSignerBuilder
import org.bouncycastle.openpgp.operator.jcajce.JcaPGPDigestCalculatorProviderBuilder
import org.bouncycastle.openpgp.operator.jcajce.JcaPGPKeyPair
import org.bouncycastle.openpgp.operator.jcajce.JcePBESecretKeyEncryptorBuilder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Test

/**
 * The reader's decrypt flow, seeded end to end: a known plaintext is
 * encrypted with [PgpManager.encryptFor] (the app's own send-side path),
 * embedded in a mail message, extracted by [MessageBodyExtractor], and
 * decrypted through [PgpManager.decryptWith] — the exact calls
 * MessageReaderScreen makes. The body shown must be the seeded
 * plaintext, byte for byte.
 */
class ReaderDecryptFlowTest {

    @Test
    fun seededEncryptedMessageDecryptsToExactPlaintext() {
        val pgp = PgpManager()
        val secretRing = generateSecretKeyRing(PASSPHRASE)
        val recipientKey = pgp.loadPublicKey(armoredPublicKey(secretRing))

        val ciphertext = runBlocking {
            pgp.encryptFor(recipientKey, KNOWN_PLAINTEXT.toByteArray(Charsets.UTF_8))
        }

        val msg = MimeMessage(session()).apply {
            setFrom("alice@ghost.onion")
            setSubject("seeded encrypted")
            setText(ciphertext, "us-ascii")
        }
        val wire = ByteArrayOutputStream().also { msg.writeTo(it) }
        val parsed = MimeMessage(session(), ByteArrayInputStream(wire.toByteArray()))

        val syncedBody = MessageBodyExtractor.extract(parsed)
        assertNotNull(syncedBody.pgpCiphertext)

        val decrypted = runBlocking {
            pgp.decryptWith(
                secretRing,
                PASSPHRASE.toCharArray(),
                syncedBody.pgpCiphertext!!,
            )
        }
        assertEquals(KNOWN_PLAINTEXT, decrypted.toString(Charsets.UTF_8))

        val shown = MessageBodyExtractor.fromDecrypted(decrypted)
        assertEquals(KNOWN_PLAINTEXT, shown.plainText)
    }

    @Test
    fun wrongPassphraseFailsInsteadOfShowingContent() {
        val pgp = PgpManager()
        val secretRing = generateSecretKeyRing(PASSPHRASE)
        val recipientKey = pgp.loadPublicKey(armoredPublicKey(secretRing))
        val ciphertext = runBlocking {
            pgp.encryptFor(recipientKey, KNOWN_PLAINTEXT.toByteArray(Charsets.UTF_8))
        }
        assertThrows(PgpManager.PgpException::class.java) {
            runBlocking {
                pgp.decryptWith(secretRing, "not the passphrase".toCharArray(), ciphertext)
            }
        }
    }

    private fun session(): Session = Session.getInstance(Properties())

    /** Generate a passphrase-protected RSA test keyring (master + subkey). */
    private fun generateSecretKeyRing(passphrase: String): PGPSecretKeyRing {
        if (Security.getProvider(BouncyCastleProvider.PROVIDER_NAME) == null) {
            Security.addProvider(BouncyCastleProvider())
        }
        val generator = KeyPairGenerator
            .getInstance("RSA", BouncyCastleProvider.PROVIDER_NAME)
            .apply { initialize(2048) }
        val master = JcaPGPKeyPair(
            PGPPublicKey.RSA_GENERAL,
            generator.generateKeyPair(),
            Date(),
        )
        val subkey = JcaPGPKeyPair(
            PGPPublicKey.RSA_GENERAL,
            generator.generateKeyPair(),
            Date(),
        )
        // The ring generator's checksum calculator is the secret-key
        // packet checksum, for which OpenPGP uses SHA1.
        val checksumCalculator = JcaPGPDigestCalculatorProviderBuilder()
            .build()
            .get(HashAlgorithmTags.SHA1)
        val ringGenerator = PGPKeyRingGenerator(
            PGPSignature.DEFAULT_CERTIFICATION,
            master,
            "Ghost Test <test@ghost.local>",
            checksumCalculator,
            null,
            null,
            JcaPGPContentSignerBuilder(
                master.publicKey.algorithm,
                HashAlgorithmTags.SHA256,
            ),
            JcePBESecretKeyEncryptorBuilder(
                PGPEncryptedData.AES_256,
                checksumCalculator,
            ).setProvider(BouncyCastleProvider.PROVIDER_NAME)
                .build(passphrase.toCharArray()),
        )
        ringGenerator.addSubKey(subkey)
        return ringGenerator.generateSecretKeyRing()
    }

    /** ASCII-armor the public half of [secretRing] for [PgpManager.loadPublicKey]. */
    private fun armoredPublicKey(secretRing: PGPSecretKeyRing): String {
        val keys = mutableListOf<PGPPublicKey>()
        val iterator = secretRing.publicKeys
        while (iterator.hasNext()) {
            keys.add(iterator.next())
        }
        val out = ByteArrayOutputStream()
        ArmoredOutputStream(out).use { armored ->
            armored.write(PGPPublicKeyRing(keys).encoded)
        }
        return out.toString(Charsets.UTF_8.name())
    }

    private companion object {
        const val PASSPHRASE = "seeded test passphrase"
        const val KNOWN_PLAINTEXT =
            "Meet at the lighthouse at dawn. Bring the ledger, leave the radio."
    }
}
