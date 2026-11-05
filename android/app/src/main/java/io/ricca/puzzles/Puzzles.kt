package io.ricca.puzzles

/** Touch input mode: which midend button a plain tap sends. */
data class Mode(val id: String, val label: String, val button: Int)
data class ExtraMenu(val label: String, val key: Char)

/** Help text: paragraphs, headings and bullet items with inline <b>/<i>. */
sealed interface HelpBlock {
    data class P(val html: String) : HelpBlock
    data class H(val text: String) : HelpBlock
    data class Li(val html: String) : HelpBlock
}

data class PuzzleDef(
    val name: String,
    val title: String,
    val tagline: String,
    val defaultParams: String,
    val modes: List<Mode>,
    val help: List<HelpBlock>,
    val stylus: Boolean = true,
    val keypad: Boolean = false,
    val extraMenu: List<ExtraMenu> = emptyList(),
    /** Prefs applied once, before the player has saved their own. */
    val defaultPrefs: Map<String, Boolean> = emptyMap(),
)

private fun p(s: String) = HelpBlock.P(s)
private fun h(s: String) = HelpBlock.H(s)
private fun li(s: String) = HelpBlock.Li(s)
private val CONTROLS = h("Controls")

/** Same content as web/js/puzzles.js. */
val PUZZLES: List<PuzzleDef> = listOf(
    PuzzleDef(
        "loopy", "Loopy", "Draw one loop around the numbers", "15x22t0dh",
        listOf(Mode("line", "Line", Btn.LEFT), Mode("cross", "Cross", Btn.RIGHT)),
        listOf(
            p("Draw a single closed loop along the grid lines. Each number says how many of the four edges around its square are part of the loop."),
            CONTROLS,
            li("<b>Tap an edge</b> to draw a line. Tap again to mark it with a cross; a third tap clears it."),
            li("<b>Long press</b> an empty edge to cross it directly. Cross mode makes that the default tap."),
            li("Tip: turn on <i>Auto-follow</i> in the puzzle settings to draw whole forced paths with one tap."),
        ),
    ),
    PuzzleDef(
        "bridges", "Bridges", "Connect every island", "15x22i30e10m2d2",
        listOf(Mode("bridge", "Bridge", Btn.LEFT), Mode("block", "Block", Btn.RIGHT)),
        listOf(
            p("Connect all the islands into one network with horizontal and vertical bridges. Each island's number is how many bridges end there. At most two bridges join any pair of islands, and bridges never cross."),
            CONTROLS,
            li("<b>Drag</b> from one island towards another to add a bridge. Drag again for a double bridge, again to block the gap (no bridge allowed), and once more to clear it."),
            li("<b>Long press then drag</b>, or Block mode, toggles a block directly."),
            li("<b>Tap an island</b> to mark it finished (greys it out)."),
        ),
        extraMenu = listOf(ExtraMenu("Hint", 'h')),
    ),
    PuzzleDef(
        "keen", "Keen", "Arithmetic Latin square", "6dn",
        listOf(Mode("number", "Number", Btn.LEFT), Mode("notes", "Notes", Btn.RIGHT)),
        listOf(
            p("Fill the grid so every row and column contains each number exactly once. Each outlined cage must produce its target using the given operation (+ − × ÷). Subtraction and division cages have two cells."),
            CONTROLS,
            li("<b>Tap a cell</b>, then a number on the keypad. Tap the same cell again to switch it to notes (pencil marks); a third tap deselects it."),
            li("<b>Long press</b> a cell, or use Notes mode, to go straight to notes."),
            li("<b>Fill all notes</b> (in the menu) puts every possible number in each empty cell."),
        ),
        keypad = true,
        extraMenu = listOf(ExtraMenu("Fill all notes", 'M')),
        defaultPrefs = mapOf("Keep mouse highlight after changing a pencil mark" to true),
    ),
    PuzzleDef(
        "pattern", "Pattern", "Nonogram picture logic", "20x20",
        listOf(Mode("fill", "Fill", Btn.LEFT), Mode("dot", "Dot", Btn.RIGHT), Mode("clear", "Clear", Btn.MIDDLE)),
        listOf(
            p("Shade squares to reveal a picture. The numbers beside each row and above each column list the lengths of the runs of shaded squares in that line, in order."),
            CONTROLS,
            li("<b>Tap</b> a square to fill it, again to mark it with a dot (definitely empty), and a third time to clear it."),
            li("<b>Drag</b> applies the first square's next state along a straight line."),
            li("<b>Long press</b> an empty square to dot it directly. Dot and Clear modes are also available."),
        ),
    ),
    PuzzleDef(
        "pearl", "Pearl", "Thread a loop through the pearls", "10x10dt",
        listOf(Mode("line", "Line", Btn.LEFT), Mode("cross", "Cross", Btn.RIGHT)),
        listOf(
            p("Draw a single closed loop through cell centres, moving horizontally and vertically. The loop must pass through every pearl."),
            li("<b>Black pearl:</b> the loop turns on it, and goes straight through the cells on both sides."),
            li("<b>White pearl:</b> the loop goes straight through it, and turns in at least one of the cells either side."),
            CONTROLS,
            li("<b>Drag</b> across cells to draw the loop; dragging back over a line erases it."),
            li("<b>Tap an edge</b> between two cells to draw a line there, again to cross it, and a third time to clear it."),
            li("<b>Long press</b> an edge, or use Cross mode, to cross it directly."),
        ),
        extraMenu = listOf(ExtraMenu("Hint", 'h')),
    ),
    PuzzleDef(
        "slant", "Slant", "Fill every square with a diagonal", "8x8dh",
        listOf(Mode("back", "╲ first", Btn.LEFT), Mode("fwd", "╱ first", Btn.RIGHT)),
        listOf(
            p("Draw a diagonal line in every square. Each numbered dot says how many lines meet at it, and the lines must never form a closed loop."),
            CONTROLS,
            li("<b>Tap</b> a square to cycle ╲ → ╱ → blank."),
            li("<b>Long press</b> cycles the other way (╱ first), as does the ╱ first mode."),
        ),
    ),
)

val PUZZLE_BY_NAME = PUZZLES.associateBy { it.name }

val HELP_EVERYWHERE = listOf(
    h("Everywhere"),
    li("<b>Pinch</b> or use the magnifier buttons to zoom; drag with <b>two fingers</b> to move around."),
    li("<b>Long press</b> does the opposite action (e.g. cross instead of line) — can be turned off in App settings."),
    li("Your game is saved automatically."),
)
