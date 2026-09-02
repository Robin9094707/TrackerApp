package eu.simplexsmp.rjtracker.ui

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import eu.simplexsmp.rjtracker.model.Provider

private val LightFallback = lightColorScheme(
    primary = Color(0xFF3155C6),
    secondary = Color(0xFF53658F),
    tertiary = Color(0xFF7D4E7F),
    surface = Color(0xFFF9F9FF),
    surfaceContainer = Color(0xFFF0F1F9),
)

private val DarkFallback = darkColorScheme(
    primary = Color(0xFFB6C4FF),
    secondary = Color(0xFFBBC6E4),
    tertiary = Color(0xFFE8B5E8),
)

@Composable
fun RJTrackerTheme(content: @Composable () -> Unit) {
    val context = LocalContext.current
    val dark = isSystemInDarkTheme()
    val colors = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
    } else {
        if (dark) DarkFallback else LightFallback
    }
    MaterialTheme(colorScheme = colors, content = content)
}

fun providerColor(provider: Provider): Color = when (provider) {
    Provider.APPLE -> Color(0xFF2563EB)
    Provider.GOOGLE -> Color(0xFF0F9D58)
    Provider.SAMSUNG -> Color(0xFF6D5CE7)
    Provider.TRACKER -> Color(0xFF65758B)
}

fun providerColorArgb(provider: Provider): Int = when (provider) {
    Provider.APPLE -> 0xFF2563EB.toInt()
    Provider.GOOGLE -> 0xFF0F9D58.toInt()
    Provider.SAMSUNG -> 0xFF6D5CE7.toInt()
    Provider.TRACKER -> 0xFF65758B.toInt()
}
