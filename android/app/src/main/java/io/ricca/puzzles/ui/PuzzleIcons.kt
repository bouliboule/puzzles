package io.ricca.puzzles.ui

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.sp

/** Home-screen puzzle icons, drawn in a 48×48 box (ports of ICONS in web/js/puzzles.js). */
@Composable
fun PuzzleIcon(name: String, modifier: Modifier = Modifier, ink: Color = Color(0xFF111111), bg: Color = Color.White) {
    val tm = rememberTextMeasurer()
    Canvas(modifier) {
        val k = size.minDimension / 48f
        scale(k, k, pivot = Offset.Zero) {
            IconPainter(this, tm, ink, bg, k).apply {
                when (name) {
                    "loopy" -> loopy()
                    "bridges" -> bridges()
                    "keen" -> keen()
                    "pattern" -> pattern()
                    "pearl" -> pearl()
                    "slant" -> slant()
                }
            }
        }
    }
}

private class IconPainter(val d: DrawScope, val tm: TextMeasurer, val ink: Color, val bg: Color, val k: Float) {
    fun path(svg: String, w: Float) = d.drawPath(PathParser().parsePathString(svg).toPath(), ink,
        style = Stroke(w, cap = StrokeCap.Round, join = StrokeJoin.Round))
    fun dot(x: Float, y: Float, r: Float) = d.drawCircle(ink, r, Offset(x, y))
    fun ring(x: Float, y: Float, r: Float, w: Float) {
        d.drawCircle(bg, r, Offset(x, y))
        d.drawCircle(ink, r, Offset(x, y), style = Stroke(w))
    }
    fun rect(x: Float, y: Float, w: Float, h: Float) = d.drawRect(ink, Offset(x, y), Size(w, h))
    /** Text with its baseline at y, anchored start or centre. */
    fun text(s: String, x: Float, y: Float, size: Float, centre: Boolean = true) {
        // Measure at real pixel size, then draw in the scaled 48-unit space.
        val r = tm.measure(s, TextStyle(fontSize = (size * k / (d.density * d.fontScale)).sp, fontWeight = FontWeight.SemiBold, color = ink))
        val w = r.size.width / k
        val base = r.firstBaseline / k
        d.scale(1 / k, 1 / k, pivot = Offset.Zero) {
            drawText(r, topLeft = Offset((if (centre) x - w / 2 else x) * k, (y - base) * k))
        }
    }

    fun loopy() {
        for (y in listOf(6f, 18f, 30f, 42f)) for (x in listOf(6f, 18f, 30f, 42f)) dot(x, y, 1.6f)
        path("M6 6H30V18H42V42H18V30H6Z", 3.2f)
        text("3", 24f, 28.5f, 11f)
    }

    fun bridges() {
        path("M14 10H34M14 14H34M10 14V34M38 14V34", 2.4f)
        for ((x, y) in listOf(10f to 10f, 38f to 10f, 10f to 38f, 38f to 38f)) ring(x, y, 6.5f, 2.4f)
        text("3", 10f, 13f, 8.5f); text("3", 38f, 13f, 8.5f); text("1", 10f, 41f, 8.5f); text("1", 38f, 41f, 8.5f)
    }

    fun keen() {
        path("M17.7 5V43M30.3 5V43M5 17.7H43M5 30.3H43", 0.8f)
        path("M5 17.7H30.3V5M17.7 17.7V43M30.3 30.3H43", 3f)
        path("M5 5H43V43H5Z", 3f)
        text("6×", 7.5f, 11.5f, 6f, centre = false)
        text("2", 11.4f, 38.5f, 10f); text("3", 36.6f, 38.5f, 10f)
    }

    fun pattern() {
        listOf("0110", "1111", "1001", "0110").forEachIndexed { y, row ->
            row.forEachIndexed { x, c -> if (c == '1') rect(14 + x * 8.5f, 14 + y * 8.5f, 7.5f, 7.5f) }
        }
        listOf("1", "3", "3", "1").forEachIndexed { i, s -> text(s, 18 + i * 8.5f, 10f, 6f) }
        listOf("2", "4", "1 1", "2").forEachIndexed { i, s -> text(s, 8f, 21 + i * 8.5f, 6f) }
    }

    fun pearl() {
        path("M10 10H38V24H24V38H10Z", 3.2f)
        dot(10f, 10f, 5f); ring(24f, 10f, 5f, 2.4f); ring(10f, 24f, 5f, 2.4f); dot(24f, 38f, 5f)
    }

    fun slant() {
        path("M6 6H42V42H6Z", 1f)
        path("M18 6V42M30 6V42M6 18H42M6 30H42", 0.8f)
        path("M6 6L18 18M18 6L30 18M42 6L30 18M6 30L18 18M30 18L18 30M30 30L42 18M6 30L18 42M30 30L18 42M30 42L42 30", 3f)
        ring(18f, 18f, 4.5f, 1.6f); ring(30f, 30f, 4.5f, 1.6f)
        text("3", 18f, 20.3f, 6.5f); text("2", 30f, 32.3f, 6.5f)
    }
}
