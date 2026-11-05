package io.ricca.puzzles

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.Typeface

/**
 * Receives drawing calls from native code and paints them into an
 * offscreen bitmap, in puzzle units scaled by feScale. Mirrors
 * web/js/engine.js. Method names and signatures are looked up by jni.c.
 */
class Renderer {
    var bitmap: Bitmap? = null; private set
    var feScale = 1; private set
    var colours = IntArray(0)
    var bold = false
        set(v) { field = v; midpoints.clear() }

    /** Called after each drawing pass with the changed device-pixel rect. */
    var onUpdate: (Rect) -> Unit = {}
    var onStatus: (String) -> Unit = {}
    var onTimer: (Boolean) -> Unit = {}

    private var canvas: Canvas? = null
    private val blitters = HashMap<Int, Bitmap>()
    private val midpoints = HashMap<Int, Int>()
    private var dirty: Rect? = null
    private val path = Path()
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { isSubpixelText = true }
    private val sans get() = Typeface.create(Typeface.SANS_SERIF, if (bold) 700 else 500, false)

    fun setSize(w: Int, h: Int, scale: Int) {
        feScale = scale
        val old = bitmap
        if (old == null || old.width != w || old.height != h) {
            bitmap = Bitmap.createBitmap(w.coerceAtLeast(1), h.coerceAtLeast(1), Bitmap.Config.ARGB_8888)
            old?.recycle()
        }
        canvas = Canvas(bitmap!!).apply { setMatrix(Matrix().apply { setScale(scale.toFloat(), scale.toFloat()) }) }
        midpoints.clear()
    }

    private fun col(i: Int) = if (i in colours.indices) colours[i] else Color.MAGENTA

    // ---- callbacks from native code ----------------------------------
    fun startDraw() { dirty = null }

    fun endDraw() {
        val d = dirty ?: return
        dirty = null
        onUpdate(d)
    }

    fun drawUpdate(x: Int, y: Int, w: Int, h: Int) {
        val s = feScale
        val r = Rect(x * s, y * s, (x + w) * s, (y + h) * s)
        dirty?.union(r) ?: run { dirty = r }
    }

    fun rect(x: Int, y: Int, w: Int, h: Int, c: Int) {
        fill.color = col(c)
        fill.isAntiAlias = false
        canvas?.drawRect(x.toFloat(), y.toFloat(), (x + w).toFloat(), (y + h).toFloat(), fill)
        fill.isAntiAlias = true
    }

    fun line(x1: Float, y1: Float, x2: Float, y2: Float, width: Float, c: Int) {
        val cv = canvas ?: return
        stroke.color = col(c)
        stroke.strokeWidth = width
        cv.drawLine(x1 + 0.5f, y1 + 0.5f, x2 + 0.5f, y2 + 0.5f, stroke)
    }

    fun poly(pts: IntArray, n: Int, fillC: Int, outline: Int) {
        val cv = canvas ?: return
        path.reset()
        path.moveTo(pts[0] + 0.5f, pts[1] + 0.5f)
        for (i in 1 until n) path.lineTo(pts[2 * i] + 0.5f, pts[2 * i + 1] + 0.5f)
        path.close()
        if (fillC >= 0) { fill.color = col(fillC); cv.drawPath(path, fill) }
        stroke.color = col(outline); stroke.strokeWidth = 1f
        cv.drawPath(path, stroke)
    }

    fun circle(x: Int, y: Int, r: Int, fillC: Int, outline: Int) {
        val cv = canvas ?: return
        if (fillC >= 0) { fill.color = col(fillC); cv.drawCircle(x + 0.5f, y + 0.5f, r.toFloat(), fill) }
        stroke.color = col(outline); stroke.strokeWidth = 1f
        cv.drawCircle(x + 0.5f, y + 0.5f, r.toFloat(), stroke)
    }

    fun text(x: Int, y: Int, fonttype: Int, size: Int, align: Int, c: Int, str: String) {
        val cv = canvas ?: return
        val mono = fonttype == 0
        textPaint.typeface = if (mono) Typeface.MONOSPACE else sans
        textPaint.textSize = size.toFloat()
        textPaint.color = col(c)
        textPaint.textAlign = when {
            align and 0x001 != 0 -> Paint.Align.CENTER
            align and 0x002 != 0 -> Paint.Align.RIGHT
            else -> Paint.Align.LEFT
        }
        var yy = y.toFloat()
        if (align and 0x100 != 0) yy += midpoint(size, mono)
        cv.drawText(str, x.toFloat(), yy, textPaint)
    }

    /** Baseline offset that vertically centres typical glyphs at y. */
    private fun midpoint(size: Int, mono: Boolean): Int {
        if (size <= 0) return 0
        val key = size * 2 + if (mono) 1 else 0
        return midpoints.getOrPut(key) {
            val b = Rect()
            textPaint.getTextBounds(MIDPOINT_TEST, 0, MIDPOINT_TEST.length, b)
            -(b.top + b.bottom) / 2
        }
    }

    fun clip(x: Int, y: Int, w: Int, h: Int) {
        canvas?.save()
        canvas?.clipRect(x, y, x + w, y + h)
    }

    fun unclip() { canvas?.restore() }

    fun status(text: String) = onStatus(text)

    fun blitterNew(id: Int, w: Int, h: Int) {
        blitters[id] = Bitmap.createBitmap((w * feScale).coerceAtLeast(1), (h * feScale).coerceAtLeast(1), Bitmap.Config.ARGB_8888)
    }

    fun blitterFree(id: Int) { blitters.remove(id)?.recycle() }

    fun blitterSave(id: Int, x: Int, y: Int) {
        val b = blitters[id] ?: return
        val src = bitmap ?: return
        b.eraseColor(Color.TRANSPARENT)
        Canvas(b).drawBitmap(src, (-x * feScale).toFloat(), (-y * feScale).toFloat(), null)
    }

    fun blitterLoad(id: Int, x: Int, y: Int) {
        val b = blitters[id] ?: return
        val cv = canvas ?: return
        cv.save()
        cv.setMatrix(null)
        cv.drawBitmap(b, (x * feScale).toFloat(), (y * feScale).toFloat(), null)
        cv.restore()
    }

    fun timer(active: Boolean) = onTimer(active)

    companion object {
        private const val MIDPOINT_TEST = "ABCDEFGHIKLMNOPRSTUVWXYZ0123456789"
    }
}
