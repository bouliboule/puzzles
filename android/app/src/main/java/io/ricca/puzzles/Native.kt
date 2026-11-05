package io.ricca.puzzles

/** JNI bindings for src/native/pz.h (see app/src/main/cpp/jni.c). */
object Native {
    init { System.loadLibrary("puzzles") }

    /** renderer == null makes a drawing-less instance for generating puzzles. */
    @JvmStatic external fun create(name: String, renderer: Renderer?): Long
    @JvmStatic external fun destroy(h: Long)

    @JvmStatic external fun canSolve(h: Long): Int
    @JvmStatic external fun wantsStatusbar(h: Long): Int
    @JvmStatic external fun presets(h: Long): String
    @JvmStatic external fun setId(h: Long, id: String): String
    @JvmStatic external fun newGame(h: Long)
    @JvmStatic external fun getId(h: Long): String
    @JvmStatic external fun generate(h: Long, params: String): String
    @JvmStatic external fun getParams(h: Long): String
    @JvmStatic external fun save(h: Long): String
    @JvmStatic external fun load(h: Long, data: String): String
    /** Returns [bitmap width, bitmap height, feScale]. */
    @JvmStatic external fun size(h: Long, w: Int, hh: Int, dpr: Double): IntArray
    @JvmStatic external fun redraw(h: Long)
    @JvmStatic external fun tilesize(h: Long): Int
    @JvmStatic external fun input(h: Long, x: Int, y: Int, button: Int): Int
    @JvmStatic external fun timer(h: Long, tplus: Double)
    @JvmStatic external fun timerActive(h: Long): Int
    @JvmStatic external fun keyLabel(h: Long, button: Int): String
    @JvmStatic external fun restart(h: Long)
    @JvmStatic external fun solve(h: Long): String
    @JvmStatic external fun canUndo(h: Long): Int
    @JvmStatic external fun canRedo(h: Long): Int
    @JvmStatic external fun status(h: Long): Int
    @JvmStatic external fun whichPreset(h: Long): Int
    @JvmStatic external fun colours(h: Long): String
    @JvmStatic external fun keys(h: Long): String
    @JvmStatic external fun getConfig(h: Long, which: Int): String
    @JvmStatic external fun setConfig(h: Long, which: Int, values: String): String
    @JvmStatic external fun savePrefs(h: Long): String
    @JvmStatic external fun loadPrefs(h: Long, data: String): String
    @JvmStatic external fun paramsConfig(h: Long, params: String): String
    @JvmStatic external fun configParams(h: Long, base: String, values: String): String
}

/** Midend button codes (puzzles.h). */
object Btn {
    const val LEFT = 0x200; const val MIDDLE = 0x201; const val RIGHT = 0x202
    const val LEFT_DRAG = 0x203; const val MIDDLE_DRAG = 0x204; const val RIGHT_DRAG = 0x205
    const val LEFT_UP = 0x206; const val MIDDLE_UP = 0x207; const val RIGHT_UP = 0x208
    const val UP = 0x209; const val DOWN = 0x20a; const val LEFT_KEY = 0x20b; const val RIGHT_KEY = 0x20c
    const val SELECT = 0x20d; const val SELECT2 = 0x20e
    const val UI_NEWGAME = 0x211; const val UI_SOLVE = 0x212; const val UI_UNDO = 0x213; const val UI_REDO = 0x214
    const val STYLUS = 0x0800; const val CTRL = 0x1000; const val SHIFT = 0x2000

    fun drag(b: Int) = b + 3
    fun up(b: Int) = b + 6
}

const val CFG_SETTINGS = 0
const val CFG_PREFS = 3
