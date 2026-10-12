package ai.qompass.ghost.pgp

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Encrypted store of recipient OpenPGP public keys.
 *
 * Contract:
 * - One armored public key per recipient email address, stored in
 *   EncryptedSharedPreferences (AES256-GCM values, AES256-SIV key names);
 *   keys are never written to plain prefs, logs, or backups (backups are
 *   disabled in the manifest).
 * - Addresses are normalized with [normalizeRecipientEmail] on every
 *   read and write, so "Alice@Ghost.ONION" and "alice@ghost.onion" are
 *   the same recipient.
 * - The store is dumb storage: callers validate keys with
 *   [PgpManager.loadPublicKey] before [put]. [put] rejects blank or
 *   oversized armor so a bad paste cannot squat in encrypted storage.
 * - All reads/writes are synchronous and cheap; call from any thread.
 */
class RecipientKeyStore(context: Context) {

    private val prefs: SharedPreferences = EncryptedSharedPreferences.create(
        context,
        PREFS_NAME,
        MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    /** Armored public key stored for [email], or null when none. */
    fun armoredKeyFor(email: String): String? =
        prefs.getString(prefKey(normalizeRecipientEmail(email)), null)

    /** Store [armoredKey] for [email], replacing any previous key. */
    fun put(email: String, armoredKey: String) {
        val trimmed = armoredKey.trim()
        require(trimmed.isNotEmpty()) { "armored key must not be blank" }
        require(trimmed.length <= ARMORED_KEY_CHARS_MAX) {
            "armored key exceeds ${ARMORED_KEY_CHARS_MAX} chars"
        }
        prefs.edit()
            .putString(prefKey(normalizeRecipientEmail(email)), trimmed)
            .apply()
    }

    /** Drop the key stored for [email]; no-op when absent. */
    fun remove(email: String) {
        prefs.edit().remove(prefKey(normalizeRecipientEmail(email))).apply()
    }

    /** All recipient addresses with a stored key, sorted. */
    fun emails(): List<String> =
        prefs.all.keys
            .filter { it.startsWith(KEY_PREFIX) }
            .map { it.removePrefix(KEY_PREFIX) }
            .sorted()

    private fun prefKey(normalizedEmail: String): String = KEY_PREFIX + normalizedEmail

    companion object {
        private const val PREFS_NAME = "ghost_recipient_keys"
        private const val KEY_PREFIX = "key:"

        /** 64 KiB of armor; bounds a paste at import time. */
        const val ARMORED_KEY_CHARS_MAX = 64 * 1024
    }
}

/**
 * Canonical form of a recipient address: trimmed, lowercased. Stored
 * keys and lookups both pass through here so casing never splits a
 * recipient into two entries.
 */
internal fun normalizeRecipientEmail(raw: String): String = raw.trim().lowercase()
