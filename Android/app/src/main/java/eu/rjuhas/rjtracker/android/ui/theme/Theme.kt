package eu.rjuhas.rjtracker.android.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val Light = lightColorScheme(
    primary = Color(0xFF2F5DF5), onPrimary = Color.White, primaryContainer = Color(0xFFDDE3FF), onPrimaryContainer = Color(0xFF00174D),
    secondary = Color(0xFF6A3DF5), secondaryContainer = Color(0xFFE9DDFF), tertiary = Color(0xFFFF6B4A), tertiaryContainer = Color(0xFFFFDAD2),
    background = Color(0xFFF7F8FF), surface = Color(0xFFF7F8FF), surfaceContainer = Color(0xFFEEF0FA), surfaceContainerHigh = Color(0xFFE6E9F6),
)
private val Dark = darkColorScheme(
    primary = Color(0xFFB7C4FF), onPrimary = Color(0xFF002A78), primaryContainer = Color(0xFF1A43D6), onPrimaryContainer = Color(0xFFDDE3FF),
    secondary = Color(0xFFCFBCFF), secondaryContainer = Color(0xFF4F25C9), tertiary = Color(0xFFFFB4A3), tertiaryContainer = Color(0xFF8E2A12),
    background = Color(0xFF0E1220), surface = Color(0xFF0E1220), surfaceContainer = Color(0xFF181C2B), surfaceContainerHigh = Color(0xFF222737),
)

/** Semantic colors for presence and attendance states. */
object StatusColors {
    val onTime = Color(0xFF1E9E5A)
    val late = Color(0xFFF29D0C)
    val absent = Color(0xFFE5484D)
    val neutral = Color(0xFF7A8199)
    val school = Color(0xFF2F5DF5)
    val home = Color(0xFF1E9E5A)
    val other = Color(0xFF8E5CF7)
}

private val AppTypography = Typography().run {
    copy(
        displaySmall = displaySmall.copy(fontWeight = FontWeight.Bold, letterSpacing = (-0.5).sp),
        headlineMedium = headlineMedium.copy(fontWeight = FontWeight.Bold, letterSpacing = (-0.3).sp),
        headlineSmall = headlineSmall.copy(fontWeight = FontWeight.SemiBold),
        titleLarge = titleLarge.copy(fontWeight = FontWeight.SemiBold),
        titleMedium = titleMedium.copy(fontWeight = FontWeight.SemiBold),
        labelLarge = labelLarge.copy(fontWeight = FontWeight.SemiBold),
    )
}

private val AppShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp), small = RoundedCornerShape(12.dp), medium = RoundedCornerShape(20.dp),
    large = RoundedCornerShape(28.dp), extraLarge = RoundedCornerShape(36.dp),
)

@Composable
fun RJTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val context = LocalContext.current
    val scheme = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        dark -> Dark
        else -> Light
    }
    MaterialTheme(colorScheme = scheme, typography = AppTypography, shapes = AppShapes, content = content)
}

val HeroTitle = TextStyle(fontSize = 40.sp, fontWeight = FontWeight.Black, letterSpacing = (-1).sp, lineHeight = 44.sp)
