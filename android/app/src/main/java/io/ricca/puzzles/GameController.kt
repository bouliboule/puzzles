package io.ricca.puzzles

import android.content.Context
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject

enum class ThemeSetting { AUTO, LIGHT, DARK, EINK }

sealed interface Sheet {
    data object Menu : Sheet
    data object Types : Sheet
    data object Custom : Sheet
    data object Prefs : Sheet
    data object GameId : Sheet
    data object Help : Sheet
    data object Settings : Sheet
}

class Current(val name: String, val def: PuzzleDef, val engine: Engine, var meta: Meta) {
    var lastStatus = 0
}

/** App state and logic: the native counterpart of web/js/app.js. Main thread only. */
class GameController(context: Context, private val scope: CoroutineScope) : BoardHost {
    val store = Store(context)
    private val gen = Generator(store)
    val board = BoardView(context, this)
    private val engines = HashMap<String, Engine>()

    // ---- settings ----------------------------------------------------
    var themeSetting by mutableStateOf(runCatching { ThemeSetting.valueOf(store.str("theme") ?: "AUTO") }.getOrDefault(ThemeSetting.AUTO))
        private set
    var longPress by mutableStateOf(store.str("longPress") != "0"); private set
    var showTimer by mutableStateOf(store.str("showTimer") != "0"); private set
    var systemDark by mutableStateOf(false)

    val theme: Theme get() = when (themeSetting) {
        ThemeSetting.LIGHT -> Theme.LIGHT
        ThemeSetting.DARK -> Theme.DARK
        ThemeSetting.EINK -> Theme.EINK
        ThemeSetting.AUTO -> when {
            IS_EINK_DEVICE -> Theme.EINK
            systemDark -> Theme.DARK
            else -> Theme.LIGHT
        }
    }

    fun updateSettings(theme: ThemeSetting = themeSetting, longPress: Boolean = this.longPress, showTimer: Boolean = this.showTimer) {
        themeSetting = theme; this.longPress = longPress; this.showTimer = showTimer
        store.set("theme", theme.name)
        store.set("longPress", if (longPress) "1" else "0")
        store.set("showTimer", if (showTimer) "1" else "0")
        applyTheme()
    }

    fun applyTheme() {
        val c = cur ?: return
        c.engine.applyPalette(theme)
        boardBg = c.engine.background
        board.redraw()
    }

    // ---- observable UI state -------------------------------------------
    var cur: Current? by mutableStateOf(null); private set
    var busy: String? by mutableStateOf(null); private set
    var statusText by mutableStateOf(""); private set
    var canUndo by mutableStateOf(false); private set
    var canRedo by mutableStateOf(false); private set
    var canZoom by mutableStateOf(false); private set
    var canZoomIn by mutableStateOf(false); private set
    var canZoomOut by mutableStateOf(false); private set
    var mode by mutableIntStateOf(0); private set
    var keys: List<Key> by mutableStateOf(emptyList()); private set
    var keypadNotes by mutableStateOf(false); private set
    var solvedText: String? by mutableStateOf(null); private set
    var elapsed by mutableIntStateOf(0); private set
    var label by mutableStateOf(""); private set
    var boardBg by mutableIntStateOf(0xFFEEEEEE.toInt()); private set
    var sheet: Sheet? by mutableStateOf(null)
    var toast: String? by mutableStateOf(null); private set
    var homeVersion by mutableIntStateOf(0); private set

    private var toastJob: Job? = null
    fun toast(msg: String) {
        toast = msg
        toastJob?.cancel()
        toastJob = scope.launch { delay(2600); toast = null }
    }

    // ---- home ----------------------------------------------------------
    fun cardState(name: String): Pair<String, Boolean> {
        val meta = store.json("$name:meta")
        val hasSave = store.str("$name:save") != null
        if (meta != null && hasSave && !meta.optBoolean("solved")) {
            val l = meta.optString("label")
            return (if (l.isEmpty()) "Continue" else "Continue · $l") to true
        }
        val solved = store.json("stats")?.optJSONObject(name)?.optInt("solved") ?: 0
        return (if (solved > 0) "$solved solved" else "New puzzle") to false
    }

    // ---- navigation ------------------------------------------------------
    fun showHome() {
        if (cur != null) { saveNow(); stopClock() }
        cur = null
        sheet = null
        homeVersion++
    }

    private fun engineFor(name: String): Engine = engines.getOrPut(name) {
        val e = Engine(name)
        val def = PUZZLE_BY_NAME.getValue(name)
        val prefs = store.str("$name:prefs")
        if (prefs != null) Native.loadPrefs(e.h, prefs)
        else if (def.defaultPrefs.isNotEmpty()) {
            val items = e.getConfig(CFG_PREFS)
            for (it in items) def.defaultPrefs[it.name]?.let { v -> it.bool = v }
            e.setConfig(CFG_PREFS, items)
        }
        e
    }

    fun open(name: String) {
        val def = PUZZLE_BY_NAME[name] ?: return
        val e = engineFor(name)
        e.renderer.onStatus = { statusText = it }
        statusText = ""
        solvedText = null
        val c = Current(name, def, e, Meta.from(store.json("$name:meta"), def.defaultParams))
        cur = c
        mode = 0
        label = c.meta.label
        val save = store.str("$name:save")
        val loaded = save != null && Native.load(e.h, save).isEmpty()
        if (loaded) afterGameStart(false) else newGame(c.meta.params, initial = true)
    }

    // ---- game lifecycle ----------------------------------------------------
    fun newGame(params0: String? = null, initial: Boolean = false) {
        val c = cur ?: return
        val params = params0 ?: c.meta.params
        busy = "Generating…"
        solvedText = null
        stopClock()
        scope.launch {
            val gameId = try {
                gen.take(c.name, params)
            } catch (ex: Exception) {
                busy = null
                toast("Could not create puzzle: ${ex.message}")
                if (initial && params != c.def.defaultParams) newGame(c.def.defaultParams, true)
                return@launch
            }
            if (cur !== c) return@launch
            val e = c.engine
            Native.setId(e.h, params)
            val err = Native.setId(e.h, gameId)
            if (err.isNotEmpty()) { busy = null; toast(err); return@launch }
            Native.newGame(e.h)
            c.meta = Meta(params, label = e.paramsLabel(params))
            afterGameStart(true)
            busy = null
            saveNow()
            gen.prefetch(c.name, params)
        }
    }

    private fun afterGameStart(fresh: Boolean) {
        val c = cur ?: return
        val e = c.engine
        if (c.meta.label.isEmpty()) c.meta.label = e.paramsLabel(c.meta.params)
        label = c.meta.label
        e.loadColours(theme)
        boardBg = e.background
        keys = if (c.def.keypad) e.keys() else emptyList()
        board.attach(e)
        updateUI()
        c.lastStatus = e.status()
        solvedText = if (c.meta.solved) solvedLabel(c.meta) else null
        startClock()
        if (!fresh) gen.prefetch(c.name, c.meta.params)
    }

    private fun solvedLabel(m: Meta) = if (m.helped) "Solved (with help)" else "Solved in ${fmtTime(m.elapsed)}"

    fun selectMode(i: Int) { mode = i; updateKeypadNotes() }

    private fun updateKeypadNotes() {
        val c = cur ?: return
        if (!c.def.keypad) return
        val l = Native.keyLabel(c.engine.h, Btn.SELECT)
        keypadNotes = if (l.isNotEmpty()) l == "Ink" else c.def.modes.getOrNull(mode)?.button == Btn.RIGHT
    }

    fun sendKey(button: Int) {
        val c = cur ?: return
        afterInput(c.engine.input(0, 0, button))
    }

    fun restart() { cur?.let { Native.restart(it.engine.h); afterInput(1) } }

    fun solve() {
        val c = cur ?: return
        val msg = Native.solve(c.engine.h)
        if (msg.isNotEmpty()) toast(msg) else { c.meta.helped = true; afterInput(1) }
    }

    fun extra(x: ExtraMenu) {
        val c = cur ?: return
        if (x.key == 'h') c.meta.helped = true
        sendKey(x.key.code)
    }

    fun loadGameId(id: String): String? {
        val c = cur ?: return null
        if (!id.contains(':') && !id.contains('#')) return "That does not look like a game ID."
        val err = Native.setId(c.engine.h, id)
        if (err.isNotEmpty()) return err
        Native.newGame(c.engine.h)
        val params = Native.getParams(c.engine.h).ifEmpty { id.split(':', '#')[0] }
        c.meta = Meta(params, label = c.engine.paramsLabel(params))
        solvedText = null
        afterGameStart(true)
        saveNow()
        return null
    }

    fun savePrefs(items: List<ConfigItem>): String? {
        val c = cur ?: return null
        val msg = c.engine.setConfig(CFG_PREFS, items)
        if (msg.isNotEmpty()) return msg
        store.set("${c.name}:prefs", Native.savePrefs(c.engine.h))
        board.layoutBoard()
        updateUI()
        return null
    }

    // ---- after every move ------------------------------------------------
    private var saveJob: Job? = null

    override fun onInput(result: Int) = afterInput(result)

    fun afterInput(result: Int) {
        val c = cur ?: return
        updateUI()
        val st = c.engine.status()
        if (st == 1 && c.lastStatus != 1 && !c.meta.solved) onSolved()
        c.lastStatus = st
        if (result == 1) {
            saveJob?.cancel()
            saveJob = scope.launch { delay(400); saveNow() }
        }
    }

    private fun updateUI() {
        val c = cur ?: return
        updateKeypadNotes()
        canUndo = c.engine.canUndo()
        canRedo = c.engine.canRedo()
        onZoomChange()
    }

    override fun onZoomChange() {
        canZoom = board.canZoom
        canZoomIn = board.zoom < board.maxZoom - 0.01f
        canZoomOut = board.zoom > 1.001f
    }

    fun saveNow() {
        val c = cur ?: return
        saveJob?.cancel()
        tickClock()
        store.set("${c.name}:save", Native.save(c.engine.h))
        store.set("${c.name}:meta", c.meta.toJson())
    }

    private fun onSolved() {
        val c = cur ?: return
        val m = c.meta
        tickClock()
        m.solved = true
        if (!m.helped) {
            val stats = store.json("stats") ?: JSONObject()
            val s = stats.optJSONObject(c.name) ?: JSONObject().put("solved", 0).put("best", JSONObject())
            s.put("solved", s.optInt("solved") + 1)
            val best = s.optJSONObject("best") ?: JSONObject()
            if (!best.has(m.params) || m.elapsed < best.getDouble(m.params)) best.put(m.params, m.elapsed)
            s.put("best", best)
            stats.put(c.name, s)
            store.set("stats", stats)
        }
        stopClock()
        saveNow()
        solvedText = solvedLabel(m)
    }

    // ---- clock -----------------------------------------------------------
    private var clockJob: Job? = null
    private var clockFrom = 0L
    var foreground = true
        set(v) {
            field = v
            if (!v) { saveNow(); stopClock() } else startClock()
        }

    fun startClock() {
        stopClock()
        val c = cur ?: return
        elapsed = c.meta.elapsed.toInt()
        if (c.meta.solved || !foreground) return
        clockFrom = System.nanoTime()
        clockJob = scope.launch {
            while (true) { delay(1000); tickClock(); elapsed = (cur?.meta?.elapsed ?: 0.0).toInt() }
        }
    }

    private fun tickClock() {
        if (clockJob == null) return
        val c = cur ?: return
        val now = System.nanoTime()
        c.meta.elapsed += (now - clockFrom) / 1e9
        clockFrom = now
    }

    private fun stopClock() {
        tickClock()
        clockJob?.cancel()
        clockJob = null
    }

    // ---- BoardHost ---------------------------------------------------------
    override fun primaryButton(): Int = cur?.def?.modes?.getOrNull(mode)?.button ?: Btn.LEFT
    override fun longPressEnabled() = longPress
    override fun stylus() = cur?.def?.stylus == true
    override fun instantAnimation() = theme == Theme.EINK

    fun zoomIn() { board.zoomIn() }
    fun zoomOut() { board.zoomOut() }

    companion object {
        /** Onyx Boox and similar e-readers: default to the e-ink theme. */
        val IS_EINK_DEVICE = Build.MANUFACTURER.equals("ONYX", true) || Build.BRAND.equals("boox", true)

        fun fmtTime(s0: Double): String {
            val s = s0.toInt()
            val h = s / 3600; val m = (s / 60) % 60; val ss = s % 60
            return (if (h > 0) "$h:" + m.toString().padStart(2, '0') else "$m") + ":" + ss.toString().padStart(2, '0')
        }
    }
}
