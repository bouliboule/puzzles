package io.ricca.puzzles.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.ricca.puzzles.Theme

/** Design tokens, as the CSS custom properties in web/css/app.css. */
data class Tokens(
    val bg: Color,
    val surface: Color,
    val surface2: Color,
    val text: Color,
    val text2: Color,
    val ink: Color,
    val accent: Color,
    val accentText: Color,
    val pop: Color,
    val popText: Color,
    val cards: Map<String, Color>,
    val border: Dp = 3.dp,
    val off: Dp = 4.dp,
    val tap: Dp = 46.dp,
    val weight: FontWeight = FontWeight.SemiBold,
    val eink: Boolean = false,
    val dark: Boolean = false,
)

private val CARDS = mapOf(
    "loopy" to Color(0xFFFFCF3F), "bridges" to Color(0xFF7AD3FF), "keen" to Color(0xFFFF8FB1),
    "pattern" to Color(0xFF9BE37F), "pearl" to Color(0xFFC3A6FF), "slant" to Color(0xFFFF9F5A),
)

fun tokensFor(t: Theme) = when (t) {
    Theme.LIGHT -> Tokens(
        bg = Color(0xFFF6EFDF), surface = Color.White, surface2 = Color(0xFFEFE6CF),
        text = Color(0xFF111111), text2 = Color(0xFF3D3A33), ink = Color(0xFF111111),
        accent = Color(0xFFFFCF3F), accentText = Color(0xFF111111),
        pop = Color(0xFFFF6B4A), popText = Color(0xFF111111), cards = CARDS,
    )
    Theme.DARK -> Tokens(
        bg = Color(0xFF17171C), surface = Color(0xFF24242C), surface2 = Color(0xFF30303A),
        text = Color(0xFFF6EFDF), text2 = Color(0xFFC9C2B0), ink = Color(0xFFF6EFDF),
        accent = Color(0xFFFFCF3F), accentText = Color(0xFF111111),
        pop = Color(0xFFFF6B4A), popText = Color(0xFF111111), cards = CARDS, dark = true,
    )
    Theme.EINK -> Tokens(
        bg = Color.White, surface = Color.White, surface2 = Color.White,
        text = Color.Black, text2 = Color.Black, ink = Color.Black,
        accent = Color.White, accentText = Color.Black,
        pop = Color.Black, popText = Color.White,
        cards = CARDS.mapValues { Color.White },
        off = 3.dp, tap = 52.dp, weight = FontWeight.Bold, eink = true,
    )
}

val LocalTokens = staticCompositionLocalOf { tokensFor(Theme.LIGHT) }
val T: Tokens @Composable get() = LocalTokens.current

@Composable
fun PuzzleTheme(theme: Theme, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalTokens provides remember(theme) { tokensFor(theme) }, content = content)
}

val Mono = FontFamily.Monospace
fun heavy(size: Int, color: Color = Color.Unspecified) =
    TextStyle(fontSize = size.sp, fontWeight = FontWeight.Black, color = color, letterSpacing = (-0.02).sp)

/**
 * Neubrutalist slab: ink outline and a hard offset shadow; it sinks into
 * its shadow while pressed. Reserve `off` space to the right/bottom.
 */
@Composable
fun Slab(
    modifier: Modifier = Modifier,
    color: Color = T.surface,
    radius: Dp = 10.dp,
    shadow: Dp = T.off,
    enabled: Boolean = true,
    onClick: (() -> Unit)? = null,
    contentAlignment: Alignment = Alignment.Center,
    content: @Composable BoxScope.() -> Unit,
) {
    val t = T
    val src = remember { MutableInteractionSource() }
    val pressed by src.collectIsPressedAsState()
    val sink = if (pressed || !enabled) shadow else 0.dp
    val shape = RoundedCornerShape(radius)
    Box(
        modifier
            .drawBehind {
                if (sink < shadow) {
                    val o = (shadow - sink).toPx()
                    drawRoundRect(t.ink, topLeft = Offset(o + sink.toPx(), o + sink.toPx()), size = size,
                        cornerRadius = CornerRadius(radius.toPx()))
                }
            }
            .offset(sink, sink)
            .background(color, shape)
            .border(t.border, t.ink, shape)
            .then(if (onClick != null) Modifier.clickable(src, null, enabled = enabled, onClick = onClick) else Modifier)
            .alpha(if (enabled) 1f else 0.35f),
        contentAlignment = contentAlignment,
        content = content,
    )
}

@Composable
fun IconSlab(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    size: Dp = T.tap,
    color: Color = T.surface,
    tint: Color = T.text,
    shadow: Dp = 2.dp,
    enabled: Boolean = true,
) {
    Slab(modifier.size(size), color = color, shadow = shadow, enabled = enabled, onClick = onClick) {
        Icon(icon, label, Modifier.padding(((size.value - 24) / 2).dp).size(24.dp), tint = tint)
    }
}

/** Stroke icons from SVG path data in a 24×24 box (as the web app's icons). */
private fun strokeIcon(vararg d: String, fill: List<String> = emptyList()) =
    ImageVector.Builder(defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f).apply {
        for (p in d) addPath(addPathNodes(p), stroke = SolidColor(Color.Black), strokeLineWidth = 2.6f,
            strokeLineCap = StrokeCap.Round, strokeLineJoin = StrokeJoin.Round)
        for (p in fill) addPath(addPathNodes(p), fill = SolidColor(Color.Black))
    }.build()

private fun circle(cx: Float, cy: Float, r: Float) =
    "M${cx - r} ${cy}a$r $r 0 1 0 ${2 * r} 0a$r $r 0 1 0 ${-2 * r} 0Z"

object Icons {
    val Back = strokeIcon("M15 5l-7 7 7 7")
    val Settings = strokeIcon(circle(12f, 12f, 3.2f),
        "M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1")
    val ZoomOut = strokeIcon(circle(10.5f, 10.5f, 6.5f), "M15.5 15.5l5 5M7.5 10.5h6")
    val ZoomIn = strokeIcon(circle(10.5f, 10.5f, 6.5f), "M15.5 15.5l5 5M7.5 10.5h6M10.5 7.5v6")
    val Menu = strokeIcon(fill = listOf(circle(5f, 12f, 1.6f), circle(12f, 12f, 1.6f), circle(19f, 12f, 1.6f)))
    val Undo = strokeIcon("M9 14L4 9l5-5", "M4 9h10.5a5.5 5.5 0 0 1 0 11H11")
    val Redo = strokeIcon("M15 14l5-5-5-5", "M20 9H9.5a5.5 5.5 0 0 0 0 11H13")
    val Close = strokeIcon("M6 6l12 12M18 6L6 18")
    val Backspace = strokeIcon("M9 5h11v14H9l-6-7z", "M12 9l5 6M17 9l-5 6")
}
