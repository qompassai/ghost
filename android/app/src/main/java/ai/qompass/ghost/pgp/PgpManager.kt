package ai.qompass.ghost.pgp

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.security.SecureRandom
import java.security.Security
import java.util.Date
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.bouncycastle.bcpg.ArmoredOutputStream
import org.bouncycastle.jce.provider.BouncyCastleProvider
import org.bouncycastle.openpgp.PGPCompressedData
import org.bouncycastle.openpgp.PGPCompressedDataGenerator
import org.bouncycastle.openpgp.PGPEncryptedData
import org.bouncycastle.openpgp.PGPEncryptedDataGenerator
import org.bouncycastle.openpgp.PGPEncryptedDataList
import org.bouncycastle.openpgp.PGPLiteralData
import org.bouncycastle.openpgp.PGPLiteralDataGenerator
import org.bouncycastle.openpgp.PGPPrivateKey
import org.bouncycastle.openpgp.PGPPublicKey
import org.bouncycastle.openpgp.PGPPublicKeyEncryptedData
import org.bouncycastle.openpgp.PGPPublicKeyRing
import org.bouncycastle.openpgp.PGPSecretKey
import org.bouncycastle.openpgp.PGPSecretKeyRing
import org.bouncycastle.openpgp.PGPUtil
import org.bouncycastle.openpgp.jcajce.JcaPGPObjectFactory
import org.bouncycastle.openpgp.operator.jcajce.JcePBESecretKeyDecryptorBuilder
import org.bouncycastle.openpgp.operator.jcajce.JcePGPDataEncryptorBuilder
import org.bouncycastle.openpgp.operator.jcajce.JcePublicKeyDataDecryptorFactoryBuilder
import org.bouncycastle.openpgp.operator.jcajce.JcePublicKeyKeyEncryptionMethodGenerator

/**
 * OpenPGP message encryption/decryption (Bouncy Castle, FOSS).
 *
 * Contract:
 * - [encryptFor] produces ASCII-armored ciphertext for the recipient's
 *   public key. Symmetric cipher AES-256, integrity packet on.
 * - [decryptWith] takes our secret key + passphrase and returns plaintext.
 *   Wrong passphrase / wrong key is a normal failure ([PgpError]).
 * - Key import accepts armored public/secret keys; encryption keys are
 *   validated (encryption-capable, not revoked) before use.
 * - All crypto runs on Dispatchers.Default; inputs bounded by
 *   [PLAINTEXT_BYTES_MAX].
 */
class PgpManager {

    init {
        if (Security.getProvider(BouncyCastleProvider.PROVIDER_NAME) == null) {
            Security.addProvider(BouncyCastleProvider())
        }
    }

    sealed interface PgpError {
        data class BadKey(val detail: String) : PgpError
        data class DecryptFailed(val detail: String) : PgpError
        data class TooLarge(val bytes: Long) : PgpError
    }

    class PgpException(val error: PgpError) : Exception(error.toString())

    /** Parse an armored public key ring; return its encryption-capable key. */
    fun loadPublicKey(armored: String): PGPPublicKey {
        val decoded: InputStream = PGPUtil.getDecoderStream(
            ByteArrayInputStream(armored.toByteArray())
        )
        val ringObj = JcaPGPObjectFactory(decoded).nextObject()
        decoded.close()
        val ring = when (ringObj) {
            is PGPPublicKeyRing -> ringObj
            is PGPPublicKey -> PGPPublicKeyRing(listOf(ringObj))
            else -> throw PgpException(PgpError.BadKey("not a public key"))
        }
        val it: Iterator<PGPPublicKey> = ring.publicKeys
        while (it.hasNext()) {
            val k = it.next()
            if (k.isEncryptionKey && !k.isRevoked) return k
        }
        throw PgpException(PgpError.BadKey("no usable encryption subkey"))
    }

    /** Parse an armored secret key ring (private key stays in caller's hands). */
    fun loadSecretKey(armored: String): PGPSecretKeyRing {
        val decoded: InputStream = PGPUtil.getDecoderStream(
            ByteArrayInputStream(armored.toByteArray())
        )
        val obj = JcaPGPObjectFactory(decoded).nextObject()
        decoded.close()
        return (obj as? PGPSecretKeyRing)
            ?: throw PgpException(PgpError.BadKey("not a secret key ring"))
    }

    /** Encrypt [plaintext] for [recipientKey]; returns ASCII armor. */
    suspend fun encryptFor(recipientKey: PGPPublicKey, plaintext: ByteArray): String =
        withContext(Dispatchers.Default) {
            if (plaintext.size > PLAINTEXT_BYTES_MAX) {
                throw PgpException(PgpError.TooLarge(plaintext.size.toLong()))
            }
            val out = ByteArrayOutputStream()
            val armored = ArmoredOutputStream(out)
            val encGen = PGPEncryptedDataGenerator(
                JcePGPDataEncryptorBuilder(PGPEncryptedData.AES_256)
                    .setWithIntegrityPacket(true)
                    .setSecureRandom(SecureRandom())
                    .setProvider(BouncyCastleProvider.PROVIDER_NAME)
            )
            encGen.addMethod(
                JcePublicKeyKeyEncryptionMethodGenerator(recipientKey)
                    .setProvider(BouncyCastleProvider.PROVIDER_NAME)
            )
            val cOut = encGen.open(armored, ByteArray(BUFFER_BYTES))
            val comGen = PGPCompressedDataGenerator(PGPCompressedData.ZIP)
            val cos = comGen.open(cOut)
            val litGen = PGPLiteralDataGenerator()
            val lOut = litGen.open(
                cos, PGPLiteralData.BINARY, "",
                plaintext.size.toLong(), Date()
            )
            lOut.write(plaintext)
            lOut.close()
            cos.close()
            cOut.close()
            armored.close()
            out.toString(Charsets.UTF_8.name())
        }

    /** Decrypt ASCII-armored [ciphertext] with [secretRing] + [passphrase]. */
    suspend fun decryptWith(
        secretRing: PGPSecretKeyRing,
        passphrase: CharArray,
        ciphertext: String,
    ): ByteArray = withContext(Dispatchers.Default) {
        try {
            val decoded: InputStream = PGPUtil.getDecoderStream(
                ByteArrayInputStream(ciphertext.toByteArray())
            )
            val encList = JcaPGPObjectFactory(decoded).nextObject() as? PGPEncryptedDataList
                ?: throw PgpException(PgpError.DecryptFailed("no encrypted data packet"))
            var encData: PGPPublicKeyEncryptedData? = null
            val objs = encList.encryptedDataObjects
            while (objs.hasNext()) {
                val o = objs.next()
                if (o is PGPPublicKeyEncryptedData &&
                    secretRing.getSecretKey(o.keyID) != null
                ) {
                    encData = o
                    break
                }
            }
            val data = encData
                ?: throw PgpException(PgpError.DecryptFailed("no packet for our key"))
            val secretKey: PGPSecretKey = secretRing.getSecretKey(data.keyID)
            val privateKey: PGPPrivateKey = secretKey.extractPrivateKey(
                JcePBESecretKeyDecryptorBuilder()
                    .setProvider(BouncyCastleProvider.PROVIDER_NAME)
                    .build(passphrase)
            )
            val clear = data.getDataStream(
                JcePublicKeyDataDecryptorFactoryBuilder()
                    .setProvider(BouncyCastleProvider.PROVIDER_NAME)
                    .build(privateKey)
            )
            val lit = JcaPGPObjectFactory(clear).nextObject() as? PGPLiteralData
                ?: throw PgpException(PgpError.DecryptFailed("no literal data"))
            val bytes = lit.inputStream.readBytes()
            require(bytes.size <= PLAINTEXT_BYTES_MAX) { "decrypted payload too large" }
            bytes
        } catch (e: PgpException) {
            throw e
        } catch (e: Exception) {
            throw PgpException(PgpError.DecryptFailed(e.message ?: "decrypt failed"))
        } finally {
            passphrase.fill('\u0000')
        }
    }

    companion object {
        /** 1 MiB cap per message payload; bounds memory on low-end devices. */
        const val PLAINTEXT_BYTES_MAX = 1 shl 20
        private const val BUFFER_BYTES = 1 shl 16
    }
}

private typealias InputStream = java.io.InputStream
