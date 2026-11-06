import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct SheetView: View {
    @Environment(\.tokens) private var t
    let c: GameController

    var body: some View {
        let sheet = c.sheet ?? .menu
        VStack(spacing: 0) {
            HStack {
                Text(title(sheet).uppercased()).font(.heavy(22)).foregroundStyle(t.accentText).lineLimit(2)
                Spacer()
                IconSlab(symbol: "xmark", label: "Close", size: 40, color: .white, tint: .inkBlack) { c.sheet = nil }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.leading, 20).padding(.trailing, 12).padding(.vertical, 12)
            .background(t.accent)
            Rectangle().fill(t.ink).frame(height: t.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch sheet {
                    case .menu: MenuSheet(c: c)
                    case .types: TypesSheet(c: c)
                    case .custom: CustomSheet(c: c)
                    case .prefs: PrefsSheet(c: c)
                    case .gameId: GameIdSheet(c: c)
                    case .help: HelpSheet(c: c)
                    case .settings: SettingsSheet(c: c)
                    }
                }
                .id(sheet)
                .padding(.horizontal, 16).padding(.vertical, 12).padding(.bottom, 20)
            }
        }
        .background(t.surface)
        .foregroundStyle(t.text)
        #if os(macOS)
        .frame(width: 460, height: 560)
        #endif
    }

    private func title(_ s: Sheet) -> String {
        let name = c.cur?.def.title ?? ""
        switch s {
        case .menu: return name
        case .types: return "Puzzle type"
        case .custom: return "Custom puzzle"
        case .prefs: return "\(name) settings"
        case .gameId: return "Game ID"
        case .help: return "How to play \(name)"
        case .settings: return "App settings"
        }
    }
}

// ---- building blocks -----------------------------------------------------

private struct MenuItem: View {
    @Environment(\.tokens) private var t
    let label: String
    var hint: String? = nil
    var check = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label).font(.system(size: 16, weight: .bold)).foregroundStyle(t.text)
                Spacer()
                if let hint { Text(hint).font(.mono(13)).foregroundStyle(t.text2).lineLimit(1) }
                if check { CheckMark(on: true, size: 26) }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .plainButton()
    }
}

private struct MenuSep: View {
    @Environment(\.tokens) private var t
    var body: some View {
        RoundedRectangle(cornerRadius: 2).fill(t.ink).frame(height: t.border).padding(.vertical, 8)
    }
}

private struct MenuLabel: View {
    @Environment(\.tokens) private var t
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.mono(12, .bold)).tracking(0.7).foregroundStyle(t.text2)
            .padding(.leading, 12).padding(.top, 16).padding(.bottom, 4)
    }
}

private struct CheckMark: View {
    @Environment(\.tokens) private var t
    let on: Bool
    var size: CGFloat = 28
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(on ? (t.eink ? .black : t.accent) : t.surface)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(t.ink, lineWidth: t.border))
            .overlay {
                if on {
                    Image(systemName: "checkmark").font(.system(size: size * 0.5, weight: .black))
                        .foregroundStyle(t.eink ? .white : .inkBlack)
                }
            }
            .frame(width: size, height: size)
    }
}

private struct Field<Content: View>: View {
    @Environment(\.tokens) private var t
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.system(size: 12, weight: .heavy)).tracking(0.6).foregroundStyle(t.text)
            content
        }
    }
}

private struct Toggle2: View {
    @Environment(\.tokens) private var t
    let label: String
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(label).font(.system(size: 16, weight: .bold)).foregroundStyle(t.text)
                    .multilineTextAlignment(.leading)
                Spacer()
                CheckMark(on: on)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .plainButton()
    }
}

private struct TextInput: View {
    @Environment(\.tokens) private var t
    @Binding var value: String
    var numeric = false
    var placeholder = ""
    var body: some View {
        SlabBox(radius: 8, shadow: 2) {
            TextField(placeholder, text: $value)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .bold))
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(numeric ? .numberPad : .asciiCapable)
                .textInputAutocapitalization(.never)
                #endif
                .padding(.horizontal, 12)
                .frame(height: 48)
        }
    }
}

private struct Choice: View {
    @Environment(\.tokens) private var t
    let choices: [String]
    let selected: Int
    let onSelect: (Int) -> Void
    var body: some View {
        Menu {
            ForEach(Array(choices.enumerated()), id: \.offset) { i, s in
                Button { onSelect(i) } label: {
                    if i == selected { Label(s, systemImage: "checkmark") } else { Text(s) }
                }
            }
        } label: {
            SlabBox(radius: 8, shadow: 2) {
                HStack {
                    Text(selected < choices.count ? choices[selected] : "")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(t.text)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 14, weight: .heavy)).foregroundStyle(t.text)
                }
                .padding(.horizontal, 12)
                .frame(height: 48)
                .contentShape(Rectangle())
            }
        }
        .menuIndicator(.hidden)
        .plainButton()
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
    }
}

private struct ErrorBox: View {
    @Environment(\.tokens) private var t
    let msg: String?
    var body: some View {
        if let msg {
            Text(msg).font(.system(size: 14, weight: .heavy)).foregroundStyle(t.eink ? .black : .inkBlack)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(t.eink ? .white : Color(hex: 0xFF6B4A), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(t.ink, lineWidth: t.border))
                .padding(.top, 12)
        }
    }
}

private struct Actions<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack { Spacer(); content }.padding(.top, 16)
    }
}

/// Editable form for config items.
private struct ConfigForm: View {
    @Binding var items: [ConfigItem]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach($items) { $it in
                switch it.type {
                case "b":
                    Toggle2(label: it.name, on: it.bool) { it.bool.toggle() }
                case "s":
                    Field(label: it.name) {
                        TextInput(value: $it.text, numeric: !it.text.isEmpty && it.text.allSatisfy(\.isNumber))
                    }
                default:
                    Field(label: it.name) { Choice(choices: it.choices, selected: it.choice) { it.choice = $0 } }
                }
            }
        }
        .padding(.top, 8)
    }
}

// ---- sheets --------------------------------------------------------------

private struct MenuSheet: View {
    let c: GameController
    var body: some View {
        if let cur = c.cur {
            MenuItem(label: "New game") { c.sheet = nil; c.newGame() }
            MenuItem(label: "Restart") { c.sheet = nil; c.restart() }
            if cur.engine.pz.canSolve { MenuItem(label: "Solve") { c.sheet = nil; c.solve() } }
            ForEach(cur.def.extraMenu, id: \.label) { x in MenuItem(label: x.label) { c.sheet = nil; c.extra(x) } }
            MenuSep()
            MenuItem(label: "Puzzle type", hint: c.label) { c.sheet = .types }
            MenuItem(label: "Puzzle settings") { c.sheet = .prefs }
            MenuItem(label: "Game ID") { c.sheet = .gameId }
            MenuItem(label: "How to play") { c.sheet = .help }
            MenuSep()
            MenuItem(label: "App settings") { c.sheet = .settings }
        }
    }
}

private struct TypesSheet: View {
    let c: GameController

    private enum Row: Identifiable {
        case label(String), item(String, String)
        var id: String {
            switch self {
            case .label(let s): return "L" + s
            case .item(let t, let p): return "I" + t + "\t" + p
            }
        }
    }

    var body: some View {
        if let cur = c.cur {
            let e = cur.engine
            let def = cur.def.defaultParams
            let presets = e.presets()
            if !presets.contains(where: { $0.params == def }) {
                MenuItem(label: "\(e.paramsLabel(def)) (default)", check: cur.meta.params == def) {
                    c.sheet = nil; c.newGame(def)
                }
            }
            ForEach(rows(presets)) { r in
                switch r {
                case .label(let s): MenuLabel(text: s)
                case .item(let title, let params):
                    MenuItem(label: title, check: params == cur.meta.params) { c.sheet = nil; c.newGame(params) }
                }
            }
            MenuSep()
            MenuItem(label: "Custom…") { c.sheet = .custom }
        }
    }

    private func rows(_ presets: [Preset]) -> [Row] {
        var out: [Row] = []
        var group: String?
        for p in presets {
            let parts = p.title.components(separatedBy: " / ")
            if parts.count > 1 && parts[0] != group {
                group = parts[0]
                out.append(.label(parts[0].hasSuffix("...") ? String(parts[0].dropLast(3)) : parts[0]))
            }
            out.append(.item(parts.last ?? p.title, p.params))
        }
        return out
    }
}

private struct CustomSheet: View {
    let c: GameController
    @State private var items: [ConfigItem]
    @State private var err: String?

    init(c: GameController) {
        self.c = c
        _items = State(initialValue: c.cur.map { $0.engine.paramsConfig($0.meta.params) } ?? [])
    }

    var body: some View {
        ConfigForm(items: $items)
        ErrorBox(msg: err)
        Actions {
            SlabButton(label: "Start", primary: true) {
                guard let cur = c.cur else { return }
                switch cur.engine.configToParams(base: cur.meta.params, items) {
                case .success(let p): c.sheet = nil; c.newGame(p)
                case .failure(let m): err = m.text
                }
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

private struct PrefsSheet: View {
    let c: GameController
    @State private var items: [ConfigItem]
    @State private var err: String?

    init(c: GameController) {
        self.c = c
        _items = State(initialValue: c.cur?.engine.getConfig(CFG_PREFS) ?? [])
    }

    var body: some View {
        ConfigForm(items: $items)
        ErrorBox(msg: err)
        Actions {
            SlabButton(label: "Save", primary: true) {
                err = c.savePrefs(items)
                if err == nil { c.sheet = nil }
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

private struct GameIdSheet: View {
    @Environment(\.tokens) private var t
    let c: GameController
    @State private var input = ""
    @State private var err: String?

    var body: some View {
        let id = c.cur?.engine.pz.id ?? ""
        Text("Share this ID to play the same puzzle on another device.")
            .font(.system(size: 15)).padding(.vertical, 6)
        Text(id).font(.mono(12, .regular)).textSelection(.enabled).padding(.vertical, 8)
        SlabButton(label: "Copy") {
            #if os(iOS)
            UIPasteboard.general.string = id
            #else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(id, forType: .string)
            #endif
            c.toast("Copied")
        }
        Spacer().frame(height: 20)
        Field(label: "Load a game ID") { TextInput(value: $input, placeholder: "paste ID here") }
        ErrorBox(msg: err)
        Actions {
            SlabButton(label: "Load", primary: true) {
                err = c.loadGameId(input.trimmingCharacters(in: .whitespacesAndNewlines))
                if err == nil { c.sheet = nil }
            }
        }
    }
}

private struct HelpSheet: View {
    let c: GameController

    private func md(_ s: String) -> AttributedString { (try? AttributedString(markdown: s)) ?? AttributedString(s) }

    var body: some View {
        if let cur = c.cur {
            ForEach(Array((cur.def.help + HELP_EVERYWHERE).enumerated()), id: \.offset) { _, b in
                switch b {
                case .p(let s):
                    Text(md(s)).font(.system(size: 15)).lineSpacing(5).padding(.vertical, 6)
                        .fixedSize(horizontal: false, vertical: true)
                case .h(let s):
                    Text(s.uppercased()).font(.system(size: 15, weight: .black)).tracking(0.5)
                        .padding(.top, 20).padding(.bottom, 6)
                case .li(let s):
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("•").frame(width: 18, alignment: .leading)
                        Text(md(s)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 15)).padding(.vertical, 3)
                }
            }
        }
    }
}

private struct SettingsSheet: View {
    @Environment(\.tokens) private var t
    let c: GameController

    var body: some View {
        let themes = ThemeSetting.allCases
        let labels: [ThemeSetting: String] = [
            .auto: "Automatic", .light: "Light", .dark: "Dark", .eink: "E-ink (high contrast, no animation)",
        ]
        VStack(alignment: .leading, spacing: 16) {
            Field(label: "Theme") {
                Choice(choices: themes.map { labels[$0]! }, selected: themes.firstIndex(of: c.themeSetting) ?? 0) {
                    c.updateSettings(theme: themes[$0])
                }
            }
            Toggle2(label: "Long press for secondary action", on: c.longPress) { c.updateSettings(longPress: !c.longPress) }
            Toggle2(label: "Show timer", on: c.showTimer) { c.updateSettings(showTimer: !c.showTimer) }
        }
        .padding(.top, 8)
        Text("Puzzle engine: Simon Tatham's Portable Puzzle Collection, compiled natively. MIT licence.")
            .font(.system(size: 13)).foregroundStyle(t.text2).padding(.top, 22)
    }
}
