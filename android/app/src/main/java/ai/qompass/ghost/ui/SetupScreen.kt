package ai.qompass.ghost.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import ai.qompass.ghost.account.AccountStore

/**
 * First-run account setup.
 *
 * Contract:
 * - Validates the onion host (.onion suffix) before persisting.
 * - Password goes straight to [AccountStore]; never logged, never in
 *   savedInstanceState beyond the text field's own memory.
 * - On save, the caller re-reads [AccountStore.hasAccount] to advance.
 */
@Composable
fun SetupScreen(accountStore: AccountStore) {
    var host by remember { mutableStateOf("") }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center
    ) {
        Text("Ghost", style = MaterialTheme.typography.headlineMedium)
        Text(
            "Connect to your Ghost onion service.",
            style = MaterialTheme.typography.bodyMedium
        )
        Spacer(Modifier.height(24.dp))

        OutlinedTextField(
            value = host,
            onValueChange = { host = it.trim(); error = null },
            label = { Text("Onion address (xxx.onion)") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(12.dp))
        OutlinedTextField(
            value = username,
            onValueChange = { username = it.trim(); error = null },
            label = { Text("Username") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(12.dp))
        OutlinedTextField(
            value = password,
            onValueChange = { password = it; error = null },
            label = { Text("Password") },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            modifier = Modifier.fillMaxWidth()
        )
        error?.let {
            Spacer(Modifier.height(8.dp))
            Text(it, color = MaterialTheme.colorScheme.error)
        }
        Spacer(Modifier.height(24.dp))
        Button(
            onClick = {
                error = validate(host, username, password)
                if (error == null) {
                    accountStore.onionHost = host
                    accountStore.username = username
                    accountStore.setPassword(password)
                    password = "" // drop from composition memory
                }
            },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Connect")
        }
    }
}

private fun validate(host: String, username: String, password: String): String? =
    when {
        !host.endsWith(".onion") -> "Host must be a .onion address"
        username.isBlank() -> "Username is required"
        password.isEmpty() -> "Password is required"
        else -> null
}
