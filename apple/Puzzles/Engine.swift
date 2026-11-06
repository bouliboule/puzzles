import CoreGraphics
import Foundation

struct Preset { let title: String; let params: String }
struct Key: Hashable { let label: String; let button: Int32 }

/// One config item: type "s" (string), "b" (boolean) or "c" (choices).
struct ConfigItem: Identifiable {
    var id: String { name }
    let type: Character
    let name: String
    var text = ""
    var bool = false
    var choice = 0
    var choices: [String] = []

    var encoded: String {
        switch type {
        case "b": return bool ? "1" : "0"
        case "c": return String(choice)
        default: return text
        }
    }
}

enum Theme { case light, dark, eink }

/// A displayed puzzle: one native midend plus its renderer. Main thread only.
final class Engine {
    let name: String
    let renderer = Renderer()
    let pz: PZ
    private var raw: [[Float]] = []

    init(name: String) {
        self.name = name
        guard let p = PZ(name: name, renderer: renderer) else { fatalError("unknown puzzle \(name)") }
        pz = p
    }

    func presets() -> [Preset] {
        Self.lines(pz.presets).compactMap {
            let f = $0.split(separator: "\t", omittingEmptySubsequences: false)
            return f.count >= 2 ? Preset(title: String(f[0]), params: String(f[1])) : nil
        }
    }

    func keys() -> [Key] {
        Self.lines(pz.keys).compactMap {
            let f = $0.split(separator: "\t", omittingEmptySubsequences: false)
            guard f.count >= 2, let b = Int32(f[1]) else { return nil }
            return Key(label: String(f[0]), button: b)
        }
    }

    func getConfig(_ which: Int32) -> [ConfigItem] { Self.parseConfig(pz.getConfig(which)) }
    func paramsConfig(_ params: String) -> [ConfigItem] { Self.parseConfig(pz.paramsConfig(params)) }
    func setConfig(_ which: Int32, _ items: [ConfigItem]) -> String {
        pz.setConfig(which, items.map(\.encoded).joined(separator: "\n"))
    }

    /// Full params for a custom config, or an error message.
    func configToParams(base: String, _ items: [ConfigItem]) -> Result<String, Message> {
        let r = pz.configParams(base, items.map(\.encoded).joined(separator: "\n"))
        return r.hasPrefix("=") ? .success(String(r.dropFirst())) : .failure(Message(String(r.dropFirst())))
    }

    func loadColours(_ theme: Theme) {
        raw = Self.lines(pz.colours).map { $0.split(separator: " ").compactMap { Float($0) } }
        applyPalette(theme)
    }

    func applyPalette(_ theme: Theme) {
        #if os(iOS)
        renderer.bold = true   // matches the heavier iOS line weight
        #else
        renderer.bold = theme == .eink
        #endif
        renderer.colours = raw.map { c in
            let m = Self.mapColour(c.count == 3 ? c : [1, 0, 1], theme)
            return CGColor(srgbRed: CGFloat(m[0]), green: CGFloat(m[1]), blue: CGFloat(m[2]), alpha: 1)
        }
    }

    var background: CGColor { renderer.colours.first ?? CGColor(gray: 0.93, alpha: 1) }

    var canUndo: Bool { pz.canUndo }
    var canRedo: Bool { pz.canRedo }
    var status: Int { pz.status }
    func input(_ x: Int, _ y: Int, _ b: Int32) -> Int32 { pz.input(x, y, b) }

    /// Human label for a params string, e.g. "15×22 Hard".
    func paramsLabel(_ params: String) -> String {
        if let p = presets().first(where: { $0.params == params }) {
            return p.title.components(separatedBy: " / ").last ?? p.title
        }
        let cfg = paramsConfig(params)
        func get(_ n: String) -> ConfigItem? { cfg.first { $0.name == n } }
        var parts: [String] = []
        if let w = get("Width"), let h = get("Height") { parts.append("\(w.text)×\(h.text)") }
        else if let g = get("Grid size") { parts.append("\(g.text)×\(g.text)") }
        if let g = get("Grid type"), g.choice != 0, g.choice < g.choices.count { parts.append(g.choices[g.choice]) }
        if let d = get("Difficulty"), d.choice < d.choices.count { parts.append(d.choices[d.choice]) }
        return parts.joined(separator: " ")
    }

    // ---- helpers -------------------------------------------------------
    static func lines(_ s: String) -> [String] { s.split(separator: "\n").map(String.init) }

    static func parseConfig(_ text: String) -> [ConfigItem] {
        lines(text).compactMap { l in
            let f = l.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 2, let type = f[0].first else { return nil }
            let v = f.count > 2 ? f[2] : ""
            switch type {
            case "c":
                let ch = f.count > 3 ? f[3] : ""
                let choices = ch.isEmpty ? [] : ch.dropFirst().split(separator: ch.first!, omittingEmptySubsequences: false).map(String.init)
                return ConfigItem(type: type, name: f[1], choice: Int(v) ?? 0, choices: choices)
            case "b":
                return ConfigItem(type: type, name: f[1], bool: v == "1")
            default:
                return ConfigItem(type: type, name: f[1], text: v)
            }
        }
    }

    /// Theme palette mapping, as paletteFor() in web/js/app.js.
    static func mapColour(_ c: [Float], _ theme: Theme) -> [Float] {
        switch theme {
        case .dark:
            let (h, s, l) = rgb2hsl(c)
            return hsl2rgb(h, s * 0.85, 0.11 + (1 - l) * 0.8)
        case .eink:
            let y = 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]
            let v: Float = y >= 0.86 ? 1 : pow(min(1, y / 0.86), 1.35)
            return [v, v, v]
        case .light:
            return c.map { min(1, $0 * 1.066) }
        }
    }

    private static func rgb2hsl(_ c: [Float]) -> (Float, Float, Float) {
        let r = c[0], g = c[1], b = c[2]
        let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2
        if mx == mn { return (0, 0, l) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        let h: Float
        if mx == r { h = (g - b) / d + (g < b ? 6 : 0) }
        else if mx == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        return (h / 6, s, l)
    }

    private static func hsl2rgb(_ h: Float, _ s: Float, _ l: Float) -> [Float] {
        if s == 0 { return [l, l, l] }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func f(_ t0: Float) -> Float {
            let t = (t0 + 1).truncatingRemainder(dividingBy: 1)
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        return [f(h + 1 / 3), f(h), f(h - 1 / 3)]
    }
}

struct Message: Error, LocalizedError {
    let text: String
    init(_ text: String) { self.text = text }
    var errorDescription: String? { text }
}
