import CoreGraphics
import Foundation
import Observation

enum ThemeSetting: String, CaseIterable { case auto = "AUTO", light = "LIGHT", dark = "DARK", eink = "EINK" }

enum Sheet: Hashable { case menu, types, custom, prefs, gameId, help, settings }

final class Current {
    let name: String
    let def: PuzzleDef
    let engine: Engine
    var meta: Meta
    var lastStatus = 0
    init(name: String, def: PuzzleDef, engine: Engine, meta: Meta) {
        self.name = name; self.def = def; self.engine = engine; self.meta = meta
    }
}

/// App state and logic: the native counterpart of web/js/app.js and the
/// Android GameController. Main thread only.
@MainActor @Observable
final class GameController: BoardHost {
    @ObservationIgnored let store = Store()
    @ObservationIgnored private lazy var gen = Generator(store: store)
    @ObservationIgnored private(set) lazy var board: BoardView = {
        let b = BoardView()
        b.host = self
        return b
    }()
    @ObservationIgnored private var engines: [String: Engine] = [:]

    // ---- settings ------------------------------------------------------
    private(set) var themeSetting: ThemeSetting
    private(set) var longPress: Bool
    private(set) var showTimer: Bool
    var systemDark = false { didSet { if oldValue != systemDark { applyTheme() } } }

    init() {
        themeSetting = ThemeSetting(rawValue: store.str("theme") ?? "") ?? .auto
        longPress = store.str("longPress") != "0"
        showTimer = store.str("showTimer") != "0"
    }

    var theme: Theme {
        switch themeSetting {
        case .light: return .light
        case .dark: return .dark
        case .eink: return .eink
        case .auto: return systemDark ? .dark : .light
        }
    }

    func updateSettings(theme: ThemeSetting? = nil, longPress: Bool? = nil, showTimer: Bool? = nil) {
        if let theme { themeSetting = theme }
        if let longPress { self.longPress = longPress }
        if let showTimer { self.showTimer = showTimer }
        store.set("theme", themeSetting.rawValue)
        store.set("longPress", self.longPress ? "1" : "0")
        store.set("showTimer", self.showTimer ? "1" : "0")
        applyTheme()
    }

    func applyTheme() {
        guard let c = cur else { return }
        c.engine.applyPalette(theme)
        boardBg = c.engine.background
        board.redraw()
    }

    // ---- observable UI state ---------------------------------------------
    private(set) var cur: Current?
    private(set) var busy: String?
    private(set) var statusText = ""
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var canZoom = false
    private(set) var canZoomIn = false
    private(set) var canZoomOut = false
    private(set) var mode = 0
    private(set) var keys: [Key] = []
    private(set) var keypadNotes = false
    private(set) var solvedText: String?
    private(set) var elapsed = 0
    private(set) var label = ""
    private(set) var boardBg = CGColor(gray: 0.93, alpha: 1)
    var sheet: Sheet?
    private(set) var toast: String?
    private(set) var homeVersion = 0

    @ObservationIgnored private var toastTask: Task<Void, Never>?
    func toast(_ msg: String) {
        toast = msg
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    // ---- home ----------------------------------------------------------
    func cardState(_ name: String) -> (String, Bool) {
        _ = homeVersion
        let meta = store.json("\(name):meta")
        if let meta, store.str("\(name):save") != nil, meta["solved"] as? Bool != true {
            let l = meta["label"] as? String ?? ""
            return (l.isEmpty ? "Continue" : "Continue · \(l)", true)
        }
        let solved = ((store.json("stats")?[name] as? [String: Any])?["solved"] as? NSNumber)?.intValue ?? 0
        return (solved > 0 ? "\(solved) solved" : "New puzzle", false)
    }

    // ---- navigation ------------------------------------------------------
    func showHome() {
        if cur != nil { saveNow(); stopClock() }
        cur = nil
        sheet = nil
        homeVersion += 1
    }

    private func engineFor(_ name: String) -> Engine {
        if let e = engines[name] { return e }
        let e = Engine(name: name)
        let def = PUZZLE_BY_NAME[name]!
        if let prefs = store.str("\(name):prefs") {
            _ = e.pz.loadPrefs(prefs)
        } else if !def.defaultPrefs.isEmpty {
            var items = e.getConfig(CFG_PREFS)
            for i in items.indices { if let v = def.defaultPrefs[items[i].name] { items[i].bool = v } }
            _ = e.setConfig(CFG_PREFS, items)
        }
        engines[name] = e
        return e
    }

    func open(_ name: String) {
        guard let def = PUZZLE_BY_NAME[name] else { return }
        let e = engineFor(name)
        e.renderer.onStatus = { [weak self] in self?.statusText = $0 }
        statusText = ""
        solvedText = nil
        let c = Current(name: name, def: def, engine: e, meta: Meta(json: store.json("\(name):meta"), defaultParams: def.defaultParams))
        cur = c
        mode = 0
        label = c.meta.label
        if let save = store.str("\(name):save"), e.pz.load(save).isEmpty {
            afterGameStart(fresh: false)
        } else {
            newGame(c.meta.params, initial: true)
        }
    }

    // ---- game lifecycle ----------------------------------------------------
    func newGame(_ params0: String? = nil, initial: Bool = false) {
        guard let c = cur else { return }
        let params = params0 ?? c.meta.params
        busy = "Generating…"
        solvedText = nil
        stopClock()
        Task {
            let gameId: String
            do {
                gameId = try await gen.take(c.name, params)
            } catch {
                busy = nil
                toast("Could not create puzzle: \(error.localizedDescription)")
                if initial && params != c.def.defaultParams { newGame(c.def.defaultParams, initial: true) }
                return
            }
            guard cur === c else { return }
            let e = c.engine
            _ = e.pz.setId(params)
            let err = e.pz.setId(gameId)
            if !err.isEmpty { busy = nil; toast(err); return }
            e.pz.newGame()
            c.meta = Meta(params: params, label: e.paramsLabel(params))
            afterGameStart(fresh: true)
            busy = nil
            saveNow()
            gen.prefetch(c.name, params)
        }
    }

    private func afterGameStart(fresh: Bool) {
        guard let c = cur else { return }
        let e = c.engine
        if c.meta.label.isEmpty { c.meta.label = e.paramsLabel(c.meta.params) }
        label = c.meta.label
        e.loadColours(theme)
        boardBg = e.background
        keys = c.def.keypad ? e.keys() : []
        board.attach(e)
        updateUI()
        c.lastStatus = e.status
        solvedText = c.meta.solved ? solvedLabel(c.meta) : nil
        startClock()
        if !fresh { gen.prefetch(c.name, c.meta.params) }
    }

    private func solvedLabel(_ m: Meta) -> String { m.helped ? "Solved (with help)" : "Solved in \(Self.fmtTime(m.elapsed))" }

    func selectMode(_ i: Int) { mode = i; updateKeypadNotes() }

    private func updateKeypadNotes() {
        guard let c = cur, c.def.keypad else { return }
        let l = c.engine.pz.keyLabel(Btn.select)
        keypadNotes = !l.isEmpty ? l == "Ink" : (mode < c.def.modes.count && c.def.modes[mode].button == Btn.right)
    }

    func sendKey(_ button: Int32) {
        guard let c = cur, busy == nil else { return }
        afterInput(c.engine.input(0, 0, button))
    }

    func restart() { if let c = cur { c.engine.pz.restart(); afterInput(1) } }

    func solve() {
        guard let c = cur else { return }
        let msg = c.engine.pz.solve()
        if !msg.isEmpty { toast(msg) } else { c.meta.helped = true; afterInput(1) }
    }

    func extra(_ x: ExtraMenu) {
        guard let c = cur else { return }
        if x.key == "h" { c.meta.helped = true }
        sendKey(Int32(x.key.asciiValue ?? 0))
    }

    func loadGameId(_ id: String) -> String? {
        guard let c = cur else { return nil }
        if !id.contains(":") && !id.contains("#") { return "That does not look like a game ID." }
        let err = c.engine.pz.setId(id)
        if !err.isEmpty { return err }
        c.engine.pz.newGame()
        var params = c.engine.pz.params
        if params.isEmpty { params = String(id.split(whereSeparator: { $0 == ":" || $0 == "#" }).first ?? "") }
        c.meta = Meta(params: params, label: c.engine.paramsLabel(params))
        solvedText = nil
        afterGameStart(fresh: true)
        saveNow()
        return nil
    }

    func savePrefs(_ items: [ConfigItem]) -> String? {
        guard let c = cur else { return nil }
        let msg = c.engine.setConfig(CFG_PREFS, items)
        if !msg.isEmpty { return msg }
        store.set("\(c.name):prefs", c.engine.pz.savePrefs())
        board.layoutBoard()
        updateUI()
        return nil
    }

    // ---- after every move ------------------------------------------------
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    func onInput(_ result: Int32) { afterInput(result) }

    func afterInput(_ result: Int32) {
        guard let c = cur else { return }
        updateUI()
        let st = c.engine.status
        if st == 1 && c.lastStatus != 1 && !c.meta.solved { onSolved() }
        c.lastStatus = st
        if result == 1 {
            saveTask?.cancel()
            saveTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                if !Task.isCancelled { self?.saveNow() }
            }
        }
    }

    private func updateUI() {
        guard let c = cur else { return }
        updateKeypadNotes()
        canUndo = c.engine.canUndo
        canRedo = c.engine.canRedo
        onZoomChange()
    }

    func onZoomChange() {
        canZoom = board.canZoom
        canZoomIn = board.zoom < board.maxZoom - 0.01
        canZoomOut = board.zoom > 1.001
    }

    func saveNow() {
        guard let c = cur else { return }
        saveTask?.cancel()
        tickClock()
        store.set("\(c.name):save", c.engine.pz.save())
        store.set("\(c.name):meta", json: c.meta.json)
    }

    private func onSolved() {
        guard let c = cur else { return }
        tickClock()
        c.meta.solved = true
        let m = c.meta
        if !m.helped {
            var stats = store.json("stats") ?? [:]
            var s = stats[c.name] as? [String: Any] ?? ["solved": 0, "best": [String: Any]()]
            s["solved"] = ((s["solved"] as? NSNumber)?.intValue ?? 0) + 1
            var best = s["best"] as? [String: Any] ?? [:]
            if let b = (best[m.params] as? NSNumber)?.doubleValue, b <= m.elapsed {} else { best[m.params] = m.elapsed }
            s["best"] = best
            stats[c.name] = s
            store.set("stats", json: stats)
        }
        stopClock()
        saveNow()
        solvedText = solvedLabel(m)
    }

    // ---- clock -----------------------------------------------------------
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var clockFrom = Date()
    @ObservationIgnored var foreground = true {
        didSet {
            guard oldValue != foreground else { return }
            if foreground { startClock() } else { saveNow(); stopClock() }
        }
    }

    func startClock() {
        stopClock()
        guard let c = cur else { return }
        elapsed = Int(c.meta.elapsed)
        if c.meta.solved || !foreground { return }
        clockFrom = Date()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.tickClock()
                self.elapsed = Int(self.cur?.meta.elapsed ?? 0)
            }
        }
    }

    private func tickClock() {
        guard clockTask != nil, let c = cur else { return }
        let now = Date()
        c.meta.elapsed += now.timeIntervalSince(clockFrom)
        clockFrom = now
    }

    private func stopClock() {
        tickClock()
        clockTask?.cancel()
        clockTask = nil
    }

    // ---- BoardHost ---------------------------------------------------------
    func primaryButton() -> Int32 {
        guard let c = cur, mode < c.def.modes.count else { return Btn.left }
        return c.def.modes[mode].button
    }
    func longPressEnabled() -> Bool { longPress }
    func stylus() -> Bool { cur?.def.stylus == true }
    func instantAnimation() -> Bool { theme == .eink }

    func zoomIn() { board.zoomIn() }
    func zoomOut() { board.zoomOut() }

    static func fmtTime(_ s0: Double) -> String {
        let s = Int(s0)
        let h = s / 3600, m = (s / 60) % 60, ss = s % 60
        return (h > 0 ? "\(h):" + String(format: "%02d", m) : "\(m)") + ":" + String(format: "%02d", ss)
    }
}
