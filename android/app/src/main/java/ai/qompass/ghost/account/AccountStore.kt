package ai.qompass.ghost.account

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Encrypted account store.
 *
 * Contract:
 * - Holds exactly one Ghost account: onion host, username, password.
 * - Credentials live in EncryptedSharedPreferences (AES256-GCM); they are
 *   never written to plain prefs, logs, or backups (backups disabled in
 *   the manifest).
 * - All reads/writes are synchronous and cheap; call from any thread.
 * - Clearing wipes the account; the caller must also drop mail state.
 */
class AccountStore(context: Context) {

    private val prefs: SharedPreferences = EncryptedSharedPreferences.create(
        context,
        PREFS_NAME,
        MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    /** True when an onion host and username are stored. */
    val hasAccount: Boolean
        get() = prefs.getString(KEY_HOST, null) != null &&
            prefs.getString(KEY_USER, null) != null

    var onionHost: String?
        get() = prefs.getString(KEY_HOST, null)
        set(value) = prefs.edit().putString(KEY_HOST, value).apply()

    var username: String?
        get() = prefs.getString(KEY_USER, null)
        set(value) = prefs.edit().putString(KEY_USER, value).apply()

    /** Password is write-only from outside; read only when connecting. */
    fun setPassword(password: String) {
        prefs.edit().putString(KEY_PASS, password).apply()
    }

    /** Bundled credentials for connecting; null when incomplete. */
    fun credentials(): Credentials? {
        val host = onionHost ?: return null
        val user = username ?: return null
        val pass = prefs.getString(KEY_PASS, null) ?: return null
        return Credentials(host, user, pass)
    }

    data class Credentials(
        val onionHost: String,
        val username: String,
        val password: String,
    )

    fun clear() {
        prefs.edit().clear().apply()
    }

    companion object {
        private const val PREFS_NAME = "ghost_account"
        private const val KEY_HOST = "onion_host"
        private const val KEY_USER = "username"
        private const val KEY_PASS = "password"
    }
}
