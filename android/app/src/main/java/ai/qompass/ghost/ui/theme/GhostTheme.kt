package ai.qompass.ghost.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/**
 * Ghost theme: dark, high-contrast. The app is Tor-only; the palette
 * signals that nothing here is the clearnet web.
 */
private val GhostColors = darkColorScheme(
    primary = Color(0xFF7E57C2),
    onPrimary = Color(0xFFFFFFFF),
    background = Color(0xFF121212),
    onBackground = Color(0xFFE0E0E0),
    surface = Color(0xFF1E1E1E),
    onSurface = Color(0xFFE0E0E0),
)

@Composable
fun GhostTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = GhostColors, content = content)
}
