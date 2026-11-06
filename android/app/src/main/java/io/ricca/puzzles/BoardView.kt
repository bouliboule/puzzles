package io.ricca.puzzles

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.os.SystemClock
import android.view.Choreographer
import android.view.HapticFeedbackConstants
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

interface BoardHost {
    fun primaryButton(): Int
    fun longPressEnabled(): Boolean
    fun stylus(): Boolean
    fun instantAnimation(): Boolean
    fun onInput(result: Int)
    fun onZoomChange()
}

/**
 * Shows an Engine's bitmap, sized to fit, with zoom and pan, and turns
 * touch, stylus and mouse input into midend button events. A port of
 * web/js/board.js. All sizes here are in device pixels.
 */
@SuppressLint("ViewConstructor")
class BoardView(context: Context, private val host: BoardHost) : View(context) {
    private val density = resources.displayMetrics.density
    private val pad = 6 * density
    private val maxTile = 96 * density

    var engine: Engine? = null; private set
    var zoom = 1f; private set
    var maxZoom = 1f; private set
    val canZoom get() = maxZoom > 1f

    private var panX = 0f
    private var panY = 0f
    private var dispScale = 1f      // view px per bitmap px
    private var dispW = 0f
    private var dispH = 0f
    private var pinchScale = 1f
    private var lastW = -1
    private var lastH = -1

    init {
        isFocusable = true
        isFocusableInTouchMode = true
    }

    fun attach(e: Engine) {
        engine?.let { detachTimer(it) }
        engine = e
        e.renderer.onUpdate = { invalidate() }
        e.renderer.onTimer = { on -> if (on) startTimer() else timerOn = false }
        zoom = 1f
        if (width > 0) layoutBoard()
        if (Native.timerActive(e.h) != 0) startTimer()
    }

    private fun detachTimer(e: Engine) {
        timerOn = false
        e.renderer.onUpdate = {}
        e.renderer.onTimer = {}
    }

    // ---- sizing ----------------------------------------------------------
    private fun render() {
        val e = engine ?: return
        if (width < 10 || height < 10) return
        val aw = max(50 * density, (width - 2 * pad) * zoom)
        val ah = max(50 * density, (height - 2 * pad) * zoom)
        var dpr = density
        if (aw * ah > MAX_PX) dpr = max(1f, density * sqrt(MAX_PX / (aw * ah)))
        val r = Native.size(e.h, floor(aw / density).toInt(), floor(ah / density).toInt(), dpr.toDouble())
        e.renderer.setSize(r[0], r[1], r[2])
        dispScale = density / dpr
        dispW = r[0] * dispScale
        dispH = r[1] * dispScale
        Native.redraw(e.h)
        invalidate()
    }

    /** Full layout at zoom 1. */
    fun layoutBoard() {
        val e = engine ?: return
        zoom = 1f
        render()
        val tile = Native.tilesize(e.h) * e.renderer.feScale * dispScale
        maxZoom = if (tile > 0) (maxTile / tile).coerceIn(1f, 6f) else 3f
        if (maxZoom < 1.15f) maxZoom = 1f
        centre()
        host.onZoomChange()
    }

    /** Re-render after a theme or settings change, keeping zoom. */
    fun redraw() {
        val e = engine ?: return
        Native.redraw(e.h)
        invalidate()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        if (engine == null || (w == lastW && h == lastH)) return
        lastW = w; lastH = h
        if (zoom == 1f) { layoutBoard(); return }
        val fx = (w / 2f - panX) / dispW
        val fy = (h / 2f - panY) / dispH
        render()
        panX = w / 2f - fx * dispW
        panY = h / 2f - fy * dispH
        clampPan()
    }

    private fun centre() {
        panX = (width - dispW) / 2
        panY = (height - dispH) / 2
        invalidate()
    }

    private fun clampPan() {
        panX = if (dispW + 2 * pad <= width) (width - dispW) / 2 else min(pad, max(width - dispW - pad, panX))
        panY = if (dispH + 2 * pad <= height) (height - dispH) / 2 else min(pad, max(height - dispH - pad, panY))
        invalidate()
    }

    fun setZoom(z0: Float, fx: Float = width / 2f, fy: Float = height / 2f) {
        val z = z0.coerceIn(1f, maxZoom)
        val ux = (fx - panX) / dispW
        val uy = (fy - panY) / dispH
        zoom = z
        render()
        panX = fx - ux * dispW
        panY = fy - uy * dispH
        clampPan()
        host.onZoomChange()
    }

    fun zoomIn() = setZoom(zoom * 1.6f)
    fun zoomOut() = setZoom(zoom / 1.6f)

    // ---- drawing ---------------------------------------------------------
    private val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeWidth = 4 * density; color = 0x99111111.toInt()
    }
    private var ringX = 0f
    private var ringY = 0f
    private var ringUntil = 0L

    override fun onDraw(canvas: Canvas) {
        val e = engine ?: return
        canvas.drawColor(e.background)
        val bmp = e.renderer.bitmap ?: return
        canvas.save()
        canvas.translate(panX.roundToInt().toFloat(), panY.roundToInt().toFloat())
        canvas.scale(dispScale * pinchScale, dispScale * pinchScale)
        canvas.drawBitmap(bmp, 0f, 0f, null)
        canvas.restore()
        if (SystemClock.uptimeMillis() < ringUntil) canvas.drawCircle(ringX, ringY, 28 * density, ringPaint)
    }

    // ---- animation timer -------------------------------------------------
    private var timerOn = false
    private var lastFrame = 0L
    private val frame = object : Choreographer.FrameCallback {
        override fun doFrame(t: Long) {
            val e = engine
            if (!timerOn || e == null) return
            val dt = if (lastFrame == 0L) 0.0 else (t - lastFrame) / 1e9
            lastFrame = t
            Native.timer(e.h, dt)
            if (timerOn) Choreographer.getInstance().postFrameCallback(this)
        }
    }

    private fun startTimer() {
        if (timerOn) return
        timerOn = true
        if (host.instantAnimation()) {
            // E-ink: skip animations entirely, in one step after this event.
            post {
                var n = 0
                val e = engine
                while (timerOn && e != null && n++ < 50) Native.timer(e.h, 60.0)
                timerOn = false
            }
        } else {
            lastFrame = 0L
            Choreographer.getInstance().postFrameCallback(frame)
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        timerOn = false
    }

    // ---- input -----------------------------------------------------------
    private enum class Kind { PENDING, GAME, PINCH, MOUSE, DONE }

    private class Gesture(var kind: Kind, var id: Int, var x0: Float, var y0: Float, var btn: Int, val slop: Float) {
        var d0 = 0f; var m0x = 0f; var m0y = 0f; var pan0x = 0f; var pan0y = 0f
        var zoom0 = 1f; var w0 = 0f; var s = 1f; var mx = 0f; var my = 0f; var moved = false
    }

    private var g: Gesture? = null
    private val longPress = Runnable { fireLongPress() }

    private fun mod() = if (host.stylus()) Btn.STYLUS else 0

    private fun send(x: Float, y: Float, button: Int): Int {
        val e = engine ?: return 0
        val s = dispScale * e.renderer.feScale
        val px = ((x - panX) / s).roundToInt()
        val py = ((y - panY) / s).roundToInt()
        val r = e.input(px, py, button)
        host.onInput(r)
        return r
    }

    private fun swap(b: Int) = if (b == Btn.LEFT) Btn.RIGHT else Btn.LEFT

    private fun fireLongPress() {
        val gg = g ?: return
        if (gg.kind != Kind.PENDING) return
        gg.btn = swap(gg.btn)
        gg.kind = Kind.GAME
        ringX = gg.x0; ringY = gg.y0
        ringUntil = SystemClock.uptimeMillis() + 350
        postInvalidateDelayed(360)
        performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
        send(gg.x0, gg.y0, gg.btn or mod())
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(ev: MotionEvent): Boolean {
        if (engine == null) return false
        if (ev.isFromSource(InputDevice.SOURCE_MOUSE) && ev.getToolType(0) == MotionEvent.TOOL_TYPE_MOUSE) return mouse(ev)
        val i = ev.actionIndex
        val id = ev.getPointerId(i)
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                requestFocus()
                parent?.requestDisallowInterceptTouchEvent(true)
                val stylus = ev.getToolType(i) == MotionEvent.TOOL_TYPE_STYLUS
                g = Gesture(Kind.PENDING, id, ev.getX(i), ev.getY(i), host.primaryButton(), (if (stylus) 4 else 9) * density)
                if (host.longPressEnabled()) postDelayed(longPress, 420)
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                val gg = g
                if (ev.pointerCount == 2 && gg != null && gg.kind == Kind.PENDING) {
                    removeCallbacks(longPress)
                    startPinch(ev)
                }
            }
            MotionEvent.ACTION_MOVE -> {
                val gg = g ?: return true
                when (gg.kind) {
                    Kind.PENDING -> {
                        val pi = ev.findPointerIndex(gg.id)
                        if (pi >= 0 && hypot(ev.getX(pi) - gg.x0, ev.getY(pi) - gg.y0) > gg.slop) {
                            removeCallbacks(longPress)
                            gg.kind = Kind.GAME
                            send(gg.x0, gg.y0, gg.btn or mod())
                            send(ev.getX(pi), ev.getY(pi), Btn.drag(gg.btn) or mod())
                        }
                    }
                    Kind.GAME -> {
                        val pi = ev.findPointerIndex(gg.id)
                        if (pi >= 0) send(ev.getX(pi), ev.getY(pi), Btn.drag(gg.btn) or mod())
                    }
                    Kind.PINCH -> updatePinch(ev)
                    else -> {}
                }
            }
            MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                val cancelled = ev.actionMasked == MotionEvent.ACTION_CANCEL
                val gg = g
                if (gg != null) when {
                    gg.kind == Kind.PENDING && id == gg.id -> {
                        removeCallbacks(longPress)
                        if (!cancelled) {
                            send(gg.x0, gg.y0, gg.btn or mod())
                            send(gg.x0, gg.y0, Btn.up(gg.btn) or mod())
                        }
                        gg.kind = Kind.DONE
                    }
                    gg.kind == Kind.GAME && id == gg.id -> {
                        send(ev.getX(i), ev.getY(i), Btn.up(gg.btn) or mod())
                        gg.kind = Kind.DONE
                    }
                    gg.kind == Kind.PINCH -> { endPinch(); gg.kind = Kind.DONE }
                }
                if (ev.actionMasked != MotionEvent.ACTION_POINTER_UP) g = null
            }
        }
        return true
    }

    private fun mouse(ev: MotionEvent): Boolean {
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                requestFocus()
                val bs = ev.buttonState
                var b = when {
                    bs and MotionEvent.BUTTON_TERTIARY != 0 -> Btn.MIDDLE
                    bs and MotionEvent.BUTTON_SECONDARY != 0 -> Btn.RIGHT
                    else -> Btn.LEFT
                }
                if (b == Btn.LEFT) b = host.primaryButton()
                g = Gesture(Kind.MOUSE, 0, ev.x, ev.y, b, 0f)
                send(ev.x, ev.y, b or mod())
            }
            MotionEvent.ACTION_MOVE -> g?.let { if (it.kind == Kind.MOUSE) send(ev.x, ev.y, Btn.drag(it.btn) or mod()) }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                g?.let { if (it.kind == Kind.MOUSE) send(ev.x, ev.y, Btn.up(it.btn) or mod()) }
                g = null
            }
        }
        return true
    }

    private fun startPinch(ev: MotionEvent) {
        val ax = ev.getX(0); val ay = ev.getY(0); val bx = ev.getX(1); val by = ev.getY(1)
        g = Gesture(Kind.PINCH, -1, 0f, 0f, 0, 0f).apply {
            d0 = max(20f, hypot(ax - bx, ay - by))
            m0x = (ax + bx) / 2; m0y = (ay + by) / 2
            pan0x = panX; pan0y = panY; zoom0 = zoom; w0 = dispW
        }
    }

    private fun updatePinch(ev: MotionEvent) {
        val gg = g ?: return
        if (ev.pointerCount < 2) return
        val ax = ev.getX(0); val ay = ev.getY(0); val bx = ev.getX(1); val by = ev.getY(1)
        var s = if (canZoom) hypot(ax - bx, ay - by) / gg.d0 else 1f
        s = s.coerceIn(1f / gg.zoom0, maxZoom / gg.zoom0)
        gg.s = s; gg.mx = (ax + bx) / 2; gg.my = (ay + by) / 2; gg.moved = true
        panX = gg.mx - (gg.m0x - gg.pan0x) * s
        panY = gg.my - (gg.m0y - gg.pan0y) * s
        if (abs(s - 1) < 0.02f) { pinchScale = 1f; clampPan() } else { pinchScale = s; invalidate() }
    }

    private fun endPinch() {
        val gg = g ?: return
        pinchScale = 1f
        if (!gg.moved) return
        if (abs(gg.s - 1) < 0.02f) { clampPan(); return }
        zoom = (gg.zoom0 * gg.s).coerceIn(1f, maxZoom)
        render()
        val r = dispW / gg.w0
        panX = gg.mx - (gg.m0x - gg.pan0x) * r
        panY = gg.my - (gg.m0y - gg.pan0y) * r
        clampPan()
        host.onZoomChange()
    }

    override fun onGenericMotionEvent(ev: MotionEvent): Boolean {
        if (engine != null && ev.actionMasked == MotionEvent.ACTION_SCROLL) {
            val v = ev.getAxisValue(MotionEvent.AXIS_VSCROLL)
            val hz = ev.getAxisValue(MotionEvent.AXIS_HSCROLL)
            if (ev.metaState and KeyEvent.META_CTRL_ON != 0) setZoom(zoom * exp(v * 0.15f), ev.x, ev.y)
            else { panX -= hz * 40 * density; panY += v * 40 * density; clampPan() }
            return true
        }
        return super.onGenericMotionEvent(ev)
    }

    companion object {
        private const val MAX_PX = 10e6f
    }
}
