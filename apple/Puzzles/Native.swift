import Foundation

/// Midend button codes (puzzles.h).
enum Btn {
    static let left: Int32 = 0x200, middle: Int32 = 0x201, right: Int32 = 0x202
    static let up: Int32 = 0x209, down: Int32 = 0x20a, leftKey: Int32 = 0x20b, rightKey: Int32 = 0x20c
    static let select: Int32 = 0x20d, select2: Int32 = 0x20e
    static let uiUndo: Int32 = 0x213, uiRedo: Int32 = 0x214
    static let stylus: Int32 = 0x0800

    static func drag(_ b: Int32) -> Int32 { b + 3 }
    static func release(_ b: Int32) -> Int32 { b + 6 }
}

let CFG_SETTINGS: Int32 = 0
let CFG_PREFS: Int32 = 3

private func R(_ c: UnsafeMutableRawPointer?) -> Renderer {
    Unmanaged<Renderer>.fromOpaque(c!).takeUnretainedValue()
}

private func S(_ p: UnsafePointer<CChar>?) -> String { p.map { String(cString: $0) } ?? "" }

/// Owns one handle from src/native/pz.h. Not thread-safe: use a handle
/// from one thread at a time (different handles may run concurrently).
final class PZ {
    let h: OpaquePointer
    /// Kept alive for as long as the handle: pz_free may still call back.
    private let renderer: Renderer?

    /// renderer == nil makes a drawing-less instance for generating puzzles.
    init?(name: String, renderer: Renderer?) {
        self.renderer = renderer
        var handle: OpaquePointer?
        if let r = renderer {
            var cb = pz_callbacks()
            cb.ctx = Unmanaged.passUnretained(r).toOpaque()
            cb.start_draw = { R($0).startDraw() }
            cb.end_draw = { R($0).endDraw() }
            cb.draw_update = { c, _, _, _, _ in R(c).drawUpdate() }
            cb.rect = { R($0).rect($1, $2, $3, $4, $5) }
            cb.line = { R($0).line($1, $2, $3, $4, $5, $6) }
            cb.poly = { R($0).poly($1!, Int($2), $3, $4) }
            cb.circle = { R($0).circle($1, $2, $3, $4, $5) }
            cb.text = { R($0).text($1, $2, $3, $4, $5, $6, S($7)) }
            cb.clip = { R($0).clip($1, $2, $3, $4) }
            cb.unclip = { R($0).unclip() }
            cb.status = { R($0).onStatus(S($1)) }
            cb.blitter_new = { R($0).blitterNew($1, $2, $3) }
            cb.blitter_free = { R($0).blitterFree($1) }
            cb.blitter_save = { R($0).blitterSave($1, $2, $3) }
            cb.blitter_load = { R($0).blitterLoad($1, $2, $3) }
            cb.timer = { R($0).onTimer($1 != 0) }
            handle = pz_new(name, &cb)
        } else {
            handle = pz_new(name, nil)
        }
        guard let handle else { return nil }
        h = handle
    }

    deinit { pz_free(h) }

    var canSolve: Bool { pz_can_solve(h) != 0 }
    var presets: String { S(pz_presets(h)) }
    func setId(_ id: String) -> String { S(pz_set_id(h, id)) }
    func newGame() { pz_new_game(h) }
    var id: String { S(pz_get_id(h)) }
    func generate(_ params: String) -> String { S(pz_generate(h, params)) }
    var params: String { S(pz_get_params(h)) }
    func save() -> String { S(pz_save(h)) }
    func load(_ data: String) -> String { S(pz_load(h, data)) }

    /// Returns (bitmap width, bitmap height, feScale).
    /// `weight` > 1 draws each puzzle unit larger, for heavier lines.
    func size(_ w: Int, _ hh: Int, dpr: Double, weight: Double = 1) -> (Int, Int, Int) {
        var out: [Int32] = [0, 0, 0]
        pz_size_weighted(h, Int32(w), Int32(hh), dpr, weight, &out)
        return (Int(out[0]), Int(out[1]), Int(out[2]))
    }

    func redraw() { pz_redraw(h) }
    var tilesize: Int { Int(pz_tilesize(h)) }
    func input(_ x: Int, _ y: Int, _ button: Int32) -> Int32 { pz_input(h, Int32(x), Int32(y), button) }
    func timer(_ t: Double) { pz_timer(h, t) }
    var timerActive: Bool { pz_timer_active(h) != 0 }
    func keyLabel(_ button: Int32) -> String { S(pz_key_label(h, button)) }
    func restart() { pz_restart(h) }
    func solve() -> String { S(pz_solve(h)) }
    var canUndo: Bool { pz_can_undo(h) != 0 }
    var canRedo: Bool { pz_can_redo(h) != 0 }
    var status: Int { Int(pz_status(h)) }
    var colours: String { S(pz_colours(h)) }
    var keys: String { S(pz_keys(h)) }
    func getConfig(_ which: Int32) -> String { S(pz_get_config(h, which)) }
    func setConfig(_ which: Int32, _ values: String) -> String { S(pz_set_config(h, which, values)) }
    func savePrefs() -> String { S(pz_save_prefs(h)) }
    func loadPrefs(_ data: String) -> String { S(pz_load_prefs(h, data)) }
    func paramsConfig(_ params: String) -> String { S(pz_params_config(h, params)) }
    func configParams(_ base: String, _ values: String) -> String { S(pz_config_params(h, base, values)) }
}
