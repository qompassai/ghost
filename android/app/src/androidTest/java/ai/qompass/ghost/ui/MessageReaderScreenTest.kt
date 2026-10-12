package ai.qompass.ghost.ui

import ai.qompass.ghost.mail.AttachmentInfo
import ai.qompass.ghost.mail.MailClient
import ai.qompass.ghost.mail.MessageBody
import ai.qompass.ghost.pgp.PgpManager
import ai.qompass.ghost.ui.theme.GhostTheme
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
import java.security.KeyPairGenerator
import java.security.Security
import java.util.Date
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
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The reader screen on a real Android runtime, driven with seeded
 * synced state exactly as [InboxScreen] hands it over: the seeded
 * plaintext must be what the screen shows, and a seeded PGP body must
 * stay locked until the key + passphrase decrypt it on-device.
 * Screenshots of both end states can be captured by the host
 * files directory for visual confirmation.
 */
@RunWith(AndroidJUnit4::class)
class MessageReaderScreenTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun plaintextMessageShowsExactSeededBody() {
        composeRule.setContent {
            GhostTheme {
                MessageReaderScreen(
                    message = seededPlaintext(),
                    pgpManager = PgpManager(),
                    onBack = {},
                )
            }
        }
        composeRule.onNodeWithText(KNOWN_BODY).assertIsDisplayed()
        composeRule.onNodeWithText("alice@ghost.onion").assertIsDisplayed()
        composeRule.onNodeWithText("report.pdf", substring = true).assertExists()
        holdForScreenshotIfRequested()
    }

    @Test
    fun pgpMessageStaysLockedUntilDecryptedOnDevice() {
        // PgpManager first: its init installs the bundled provider
        // before any key material is generated (see generateSecretKeyRing).
        val pgp = PgpManager()
        val secretRing = generateSecretKeyRing(PASSPHRASE)
        val recipientKey = pgp.loadPublicKey(armoredPublicKey(secretRing))
        val ciphertext = runBlocking {
            pgp.encryptFor(recipientKey, KNOWN_BODY.toByteArray(Charsets.UTF_8))
        }

        composeRule.setContent {
            GhostTheme {
                MessageReaderScreen(
                    message = seededPgp(ciphertext),
                    pgpManager = pgp,
                    onBack = {},
                )
            }
        }

        // Locked state: unlock offered, plaintext nowhere on screen.
        composeRule.onNodeWithText("Decrypt on this device").assertIsDisplayed()
        composeRule.onNodeWithText(KNOWN_BODY).assertDoesNotExist()

        // The two text fields in order: armored secret key, passphrase.
        val fields = composeRule.onAllNodes(hasSetTextAction())
        fields[0].performTextInput(armoredSecretKey(secretRing))
        fields[1].performTextInput(PASSPHRASE)
        composeRule.onNodeWithText("Decrypt on this device").performClick()

        composeRule.waitUntil(timeoutMillis = 30_000) {
            composeRule.onAllNodes(hasText(KNOWN_BODY))
                .fetchSemanticsNodes()
                .isNotEmpty()
        }
        composeRule.onNodeWithText(KNOWN_BODY).assertIsDisplayed()
        holdForScreenshotIfRequested()
    }

    private fun seededPlaintext(): MailClient.SyncedMessage =
        MailClient.SyncedMessage(
            summary = MailClient.MessageSummary(
                uid = 7L,
                from = "alice@ghost.onion",
                subject = "Seeded plaintext",
                dateMs = 1_759_795_200_000L,
                preview = KNOWN_BODY,
            ),
            body = MessageBody(
                plainText = KNOWN_BODY,
                pgpCiphertext = null,
                attachments = listOf(
                    AttachmentInfo("report.pdf", "application/pdf", 5L),
                ),
                truncated = false,
            ),
        )

    private fun seededPgp(ciphertext: String): MailClient.SyncedMessage =
        MailClient.SyncedMessage(
            summary = MailClient.MessageSummary(
                uid = 8L,
                from = "alice@ghost.onion",
                subject = "Seeded encrypted",
                dateMs = 1_759_795_200_000L,
                preview = MailClient.PGP_PREVIEW,
            ),
            body = MessageBody(
                plainText = null,
                pgpCiphertext = ciphertext,
                attachments = emptyList(),
                truncated = false,
            ),
        )

    /**
     * Screenshot support: when the run passes `-e hold 1`, keep the
     * asserted end state on screen so the host can capture it with
     * `adb screencap` (the Gradle test runner uninstalls the app —
     * and its files — as soon as a run ends, so in-test captures do
     * not survive). Normal runs skip the hold entirely.
     */
    private fun holdForScreenshotIfRequested() {
        if (InstrumentationRegistry.getArguments().getString("hold") != null) {
            Thread.sleep(30_000)
        }
    }

    /** Generate a passphrase-protected RSA test keyring (master + subkey). */
    private fun generateSecretKeyRing(passphrase: String): PGPSecretKeyRing {
        // Mirror PgpManager: Android's built-in "BC" provider strips
        // classes OpenPGP needs, so always install the bundled one.
        Security.removeProvider(BouncyCastleProvider.PROVIDER_NAME)
        Security.addProvider(BouncyCastleProvider())
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

    private fun armoredSecretKey(secretRing: PGPSecretKeyRing): String {
        val out = ByteArrayOutputStream()
        ArmoredOutputStream(out).use { armored ->
            armored.write(secretRing.encoded)
        }
        return out.toString(Charsets.UTF_8.name())
    }

    private companion object {
        const val PASSPHRASE = "seeded test passphrase"
        const val KNOWN_BODY =
            "The seeded body renders exactly as written, word for word."
    }
}
