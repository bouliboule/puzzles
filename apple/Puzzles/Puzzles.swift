import Foundation

/// Touch input mode: which midend button a plain tap sends.
struct Mode { let id: String; let label: String; let button: Int32 }
struct ExtraMenu { let label: String; let key: Character }

/// Help text: paragraphs, headings and bullet items (Markdown **bold** / *italic*).
enum HelpBlock { case p(String), h(String), li(String) }

struct PuzzleDef {
    let name: String
    let title: String
    let tagline: String
    let defaultParams: String
    let modes: [Mode]
    let help: [HelpBlock]
    var stylus = true
    var keypad = false
    var extraMenu: [ExtraMenu] = []
    /// Prefs applied once, before the player has saved their own.
    var defaultPrefs: [String: Bool] = [:]
}

private let controls = HelpBlock.h("Controls")

/// Same content as web/js/puzzles.js and the Android app.
let PUZZLES: [PuzzleDef] = [
    PuzzleDef(
        name: "loopy", title: "Loopy", tagline: "Draw one loop around the numbers", defaultParams: "15x22t0dh",
        modes: [Mode(id: "line", label: "Line", button: Btn.left), Mode(id: "cross", label: "Cross", button: Btn.right)],
        help: [
            .p("Draw a single closed loop along the grid lines. Each number says how many of the four edges around its square are part of the loop."),
            controls,
            .li("**Tap an edge** to draw a line. Tap again to mark it with a cross; a third tap clears it."),
            .li("**Long press** an empty edge (or right-click) to cross it directly. Cross mode makes that the default tap."),
            .li("Tip: turn on *Auto-follow* in the puzzle settings to draw whole forced paths with one tap."),
        ]
    ),
    PuzzleDef(
        name: "bridges", title: "Bridges", tagline: "Connect every island", defaultParams: "15x22i30e10m2d2",
        modes: [Mode(id: "bridge", label: "Bridge", button: Btn.left), Mode(id: "block", label: "Block", button: Btn.right)],
        help: [
            .p("Connect all the islands into one network with horizontal and vertical bridges. Each island's number is how many bridges end there. At most two bridges join any pair of islands, and bridges never cross."),
            controls,
            .li("**Drag** from one island towards another to add a bridge. Drag again for a double bridge, again to block the gap (no bridge allowed), and once more to clear it."),
            .li("**Long press then drag**, right-drag, or Block mode toggles a block directly."),
            .li("**Tap an island** to mark it finished (greys it out)."),
        ],
        extraMenu: [ExtraMenu(label: "Hint", key: "h")]
    ),
    PuzzleDef(
        name: "keen", title: "Keen", tagline: "Arithmetic Latin square", defaultParams: "6dn",
        modes: [Mode(id: "number", label: "Number", button: Btn.left), Mode(id: "notes", label: "Notes", button: Btn.right)],
        help: [
            .p("Fill the grid so every row and column contains each number exactly once. Each outlined cage must produce its target using the given operation (+ − × ÷). Subtraction and division cages have two cells."),
            controls,
            .li("**Tap a cell**, then a number on the keypad (or type it). Tap the same cell again to switch it to notes (pencil marks); a third tap deselects it."),
            .li("**Long press** a cell, right-click, or use Notes mode, to go straight to notes."),
            .li("**Fill all notes** (in the menu) puts every possible number in each empty cell."),
        ],
        keypad: true,
        extraMenu: [ExtraMenu(label: "Fill all notes", key: "M")],
        defaultPrefs: ["Keep mouse highlight after changing a pencil mark": true]
    ),
    PuzzleDef(
        name: "pattern", title: "Pattern", tagline: "Nonogram picture logic", defaultParams: "20x20",
        modes: [Mode(id: "fill", label: "Fill", button: Btn.left), Mode(id: "dot", label: "Dot", button: Btn.right),
                Mode(id: "clear", label: "Clear", button: Btn.middle)],
        help: [
            .p("Shade squares to reveal a picture. The numbers beside each row and above each column list the lengths of the runs of shaded squares in that line, in order."),
            controls,
            .li("**Tap** a square to fill it, again to mark it with a dot (definitely empty), and a third time to clear it."),
            .li("**Drag** applies the first square's next state along a straight line."),
            .li("**Long press** an empty square (or right-click) to dot it directly. Dot and Clear modes are also available."),
        ]
    ),
    PuzzleDef(
        name: "pearl", title: "Pearl", tagline: "Thread a loop through the pearls", defaultParams: "10x10dt",
        modes: [Mode(id: "line", label: "Line", button: Btn.left), Mode(id: "cross", label: "Cross", button: Btn.right)],
        help: [
            .p("Draw a single closed loop through cell centres, moving horizontally and vertically. The loop must pass through every pearl."),
            .li("**Black pearl:** the loop turns on it, and goes straight through the cells on both sides."),
            .li("**White pearl:** the loop goes straight through it, and turns in at least one of the cells either side."),
            controls,
            .li("**Drag** across cells to draw the loop; dragging back over a line erases it."),
            .li("**Tap an edge** between two cells to draw a line there, again to cross it, and a third time to clear it."),
            .li("**Long press** an edge, right-click, or use Cross mode, to cross it directly."),
        ],
        extraMenu: [ExtraMenu(label: "Hint", key: "h")]
    ),
    PuzzleDef(
        name: "slant", title: "Slant", tagline: "Fill every square with a diagonal", defaultParams: "8x8dh",
        modes: [Mode(id: "back", label: "╲ first", button: Btn.left), Mode(id: "fwd", label: "╱ first", button: Btn.right)],
        help: [
            .p("Draw a diagonal line in every square. Each numbered dot says how many lines meet at it, and the lines must never form a closed loop."),
            controls,
            .li("**Tap** a square to cycle ╲ → ╱ → blank."),
            .li("**Long press** (or right-click) cycles the other way (╱ first), as does the ╱ first mode."),
        ]
    ),
]

let PUZZLE_BY_NAME = Dictionary(uniqueKeysWithValues: PUZZLES.map { ($0.name, $0) })

let HELP_EVERYWHERE: [HelpBlock] = [
    .h("Everywhere"),
    .li("**Pinch** or use the magnifier buttons to zoom; drag with **two fingers** (or scroll) to move around."),
    .li("**Long press** does the opposite action (e.g. cross instead of line) — can be turned off in App settings. With a mouse, right-click does the same."),
    .li("Your game is saved automatically."),
]
