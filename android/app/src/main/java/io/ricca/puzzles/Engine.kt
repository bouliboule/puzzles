package io.ricca.puzzles

import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

data class Preset(val title: String, val params: String)
data class Key(val label: String, val button: Int)

/** One config item: type 's' (string), 'b' (boolean) or 'c' (choices). */
data class ConfigItem(
    val type: Char,
    val name: String,
    var text: String = "",
    var bool: Boolean = false,
    var choice: Int = 0,
    val choices: List<String> = emptyList(),
) {
    fun encoded() = when (type) {
        'b' -> if (bool) "1" else "0"
        'c' -> choice.toString()
        else -> text
    }
}

enum class Theme { LIGHT, DARK, EINK }

/** A displayed puzzle: one native midend plus its renderer. Main thread only. */
class Engine(val name: String) {
    val renderer = Renderer()
    val h: Long = Native.create(name, renderer).also { require(it != 0L) { "unknown puzzle $name" } }
    private var raw: List<FloatArray> = emptyList()

    fun presets(): List<Preset> = lines(Native.presets(h)).map {
        val (t, p) = it.split('\t'); Preset(t, p)
    }

    fun keys(): List<Key> = lines(Native.keys(h)).map {
        val (l, b) = it.split('\t'); Key(l, b.toInt())
    }

    fun getConfig(which: Int) = parseConfig(Native.getConfig(h, which))
    fun paramsConfig(params: String) = parseConfig(Native.paramsConfig(h, params))
    fun setConfig(which: Int, items: List<ConfigItem>): String =
        Native.setConfig(h, which, items.joinToString("\n") { it.encoded() })

    /** Full params for a custom config, or an error. */
    fun configToParams(base: String, items: List<ConfigItem>): Result<String> {
        val r = Native.configParams(h, base, items.joinToString("\n") { it.encoded() })
        return if (r.startsWith("=")) Result.success(r.substring(1)) else Result.failure(Exception(r.drop(1)))
    }

    fun loadColours(theme: Theme) {
        raw = lines(Native.colours(h)).map { l -> l.split(' ').map { it.toFloat() }.toFloatArray() }
        applyPalette(theme)
    }

    fun applyPalette(theme: Theme) {
        renderer.bold = theme == Theme.EINK
        renderer.colours = IntArray(raw.size) { i -> argb(mapColour(raw[i], theme)) }
    }

    val background: Int get() = renderer.colours.firstOrNull() ?: 0xFFEEEEEE.toInt()

    fun canUndo() = Native.canUndo(h) != 0
    fun canRedo() = Native.canRedo(h) != 0
    fun status() = Native.status(h)
    fun input(x: Int, y: Int, b: Int) = Native.input(h, x, y, b)

    /** Human label for a params string, e.g. "15×22 Hard". */
    fun paramsLabel(params: String): String {
        presets().firstOrNull { it.params == params }?.let { return it.title.substringAfterLast(" / ") }
        val cfg = paramsConfig(params)
        fun get(n: String) = cfg.firstOrNull { it.name == n }
        val parts = mutableListOf<String>()
        val w = get("Width"); val hh = get("Height"); val g = get("Grid size")
        if (w != null && hh != null) parts += "${w.text}×${hh.text}"
        else if (g != null) parts += "${g.text}×${g.text}"
        get("Grid type")?.let { if (it.choice != 0) parts += it.choices[it.choice] }
        get("Difficulty")?.let { parts += it.choices[it.choice] }
        return parts.joinToString(" ")
    }

    companion object {
        fun lines(s: String) = s.split('\n').filter { it.isNotEmpty() }

        fun parseConfig(text: String): List<ConfigItem> = lines(text).map { l ->
            val f = l.split('\t')
            val type = f[0][0]
            when (type) {
                'c' -> {
                    val ch = f.getOrElse(3) { "" }
                    ConfigItem(type, f[1], choice = f[2].toInt(),
                        choices = if (ch.isEmpty()) emptyList() else ch.substring(1).split(ch[0]))
                }
                'b' -> ConfigItem(type, f[1], bool = f[2] == "1")
                else -> ConfigItem(type, f[1], text = f.getOrElse(2) { "" })
            }
        }

        private fun argb(c: FloatArray): Int {
            fun b(v: Float) = (v.coerceIn(0f, 1f) * 255).roundToInt()
            return (0xFF shl 24) or (b(c[0]) shl 16) or (b(c[1]) shl 8) or b(c[2])
        }

        /** Theme palette mapping, as paletteFor() in web/js/app.js. */
        fun mapColour(c: FloatArray, theme: Theme): FloatArray = when (theme) {
            Theme.DARK -> {
                val (hh, s, l) = rgb2hsl(c)
                hsl2rgb(hh, s * 0.85f, 0.11f + (1 - l) * 0.8f)
            }
            Theme.EINK -> {
                val y = 0.299f * c[0] + 0.587f * c[1] + 0.114f * c[2]
                val v = if (y >= 0.86f) 1f else min(1f, y / 0.86f).pow(1.35f)
                floatArrayOf(v, v, v)
            }
            Theme.LIGHT -> FloatArray(3) { min(1f, c[it] * 1.066f) }
        }

        private fun rgb2hsl(c: FloatArray): FloatArray {
            val (r, g, b) = c
            val mx = max(r, max(g, b)); val mn = min(r, min(g, b)); val l = (mx + mn) / 2
            if (mx == mn) return floatArrayOf(0f, 0f, l)
            val d = mx - mn
            val s = if (l > .5f) d / (2 - mx - mn) else d / (mx + mn)
            val h = when (mx) {
                r -> (g - b) / d + (if (g < b) 6 else 0)
                g -> (b - r) / d + 2
                else -> (r - g) / d + 4
            }
            return floatArrayOf(h / 6, s, l)
        }

        private fun hsl2rgb(h: Float, s: Float, l: Float): FloatArray {
            if (s == 0f) return floatArrayOf(l, l, l)
            val q = if (l < .5f) l * (1 + s) else l + s - l * s
            val p = 2 * l - q
            fun f(t0: Float): Float {
                val t = (t0 + 1) % 1
                return when {
                    t < 1f / 6 -> p + (q - p) * 6 * t
                    t < .5f -> q
                    t < 2f / 3 -> p + (q - p) * (2f / 3 - t) * 6
                    else -> p
                }
            }
            return floatArrayOf(f(h + 1f / 3), f(h), f(h - 1f / 3))
        }
    }
}
