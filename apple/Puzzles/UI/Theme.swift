import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
    static let inkBlack = Color(hex: 0x111111)
}

/// Design tokens, as the CSS custom properties in web/css/app.css.
struct Tokens {
    var bg: Color
    var surface: Color
    var surface2: Color
    var text: Color
    var text2: Color
    var ink: Color
    var accent: Color
    var accentText: Color
    var pop: Color
    var popText: Color
    var cards: [String: Color]
    var border: CGFloat = 3
    var off: CGFloat = 4
    var tap: CGFloat = 46
    var eink = false
    var dark = false

    static let cardColours: [String: Color] = [
        "loopy": Color(hex: 0xFFCF3F), "bridges": Color(hex: 0x7AD3FF), "keen": Color(hex: 0xFF8FB1),
        "pattern": Color(hex: 0x9BE37F), "pearl": Color(hex: 0xC3A6FF), "slant": Color(hex: 0xFF9F5A),
    ]

    static func forTheme(_ t: Theme) -> Tokens {
        switch t {
        case .light:
            return Tokens(bg: Color(hex: 0xF6EFDF), surface: .white, surface2: Color(hex: 0xEFE6CF),
                          text: .inkBlack, text2: Color(hex: 0x3D3A33), ink: .inkBlack,
                          accent: Color(hex: 0xFFCF3F), accentText: .inkBlack,
                          pop: Color(hex: 0xFF6B4A), popText: .inkBlack, cards: cardColours)
        case .dark:
            return Tokens(bg: Color(hex: 0x17171C), surface: Color(hex: 0x24242C), surface2: Color(hex: 0x30303A),
                          text: Color(hex: 0xF6EFDF), text2: Color(hex: 0xC9C2B0), ink: Color(hex: 0xF6EFDF),
                          accent: Color(hex: 0xFFCF3F), accentText: .inkBlack,
                          pop: Color(hex: 0xFF6B4A), popText: .inkBlack, cards: cardColours, dark: true)
        case .eink:
            return Tokens(bg: .white, surface: .white, surface2: .white, text: .black, text2: .black, ink: .black,
                          accent: .white, accentText: .black, pop: .black, popText: .white,
                          cards: cardColours.mapValues { _ in .white }, off: 3, tap: 52, eink: true)
        }
    }
}

private struct TokensKey: EnvironmentKey { static let defaultValue = Tokens.forTheme(.light) }
extension EnvironmentValues {
    var tokens: Tokens {
        get { self[TokensKey.self] }
        set { self[TokensKey.self] = newValue }
    }
}

extension Font {
    static func heavy(_ size: CGFloat) -> Font { .system(size: size, weight: .black) }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Neubrutalist slab: ink outline and a hard offset shadow; it sinks into
/// its shadow while pressed. Takes `shadow` extra space right and bottom.
struct SlabBox<Content: View>: View {
    @Environment(\.tokens) private var t
    var color: Color? = nil
    var radius: CGFloat = 10
    var shadow: CGFloat? = nil
    var pressed = false
    var enabled = true
    @ViewBuilder var content: Content

    var body: some View {
        let off = shadow ?? t.off
        let sink = pressed || !enabled ? off : 0
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(color ?? t.surface, in: shape)
            .overlay(shape.strokeBorder(t.ink, lineWidth: t.border))
            .opacity(enabled ? 1 : 0.35)
            .background(shape.fill(t.ink).offset(x: off - sink, y: off - sink).opacity(sink < off ? 1 : 0))
            .offset(x: sink, y: sink)
            .padding(.trailing, off)
            .padding(.bottom, off)
    }
}

struct SlabStyle: ButtonStyle {
    var color: Color? = nil
    var radius: CGFloat = 10
    var shadow: CGFloat? = nil
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        SlabBox(color: color, radius: radius, shadow: shadow, pressed: configuration.isPressed, enabled: enabled) {
            configuration.label.contentShape(Rectangle())
        }
    }
}

/// Square icon button (SF Symbols).
struct IconSlab: View {
    @Environment(\.tokens) private var t
    let symbol: String
    let label: String
    var size: CGFloat? = nil
    var color: Color? = nil
    var tint: Color? = nil
    var shadow: CGFloat = 2
    let action: () -> Void

    var body: some View {
        let s = size ?? t.tap
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(tint ?? t.text)
                .frame(width: s, height: s)
        }
        .buttonStyle(SlabStyle(color: color, shadow: shadow))
        .accessibilityLabel(label)
        .help(label)
    }
}

/// Wide text button.
struct SlabButton: View {
    @Environment(\.tokens) private var t
    let label: String
    var primary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(.system(size: 15, weight: .black))
                .tracking(0.6)
                .foregroundStyle(primary ? t.popText : t.text)
                .padding(.horizontal, 22)
                .frame(height: 48)
        }
        .buttonStyle(SlabStyle(color: primary ? t.pop : t.surface, radius: 8, shadow: 3))
    }
}

/// Removes the default focus ring and highlight on macOS.
extension View {
    func plainButton() -> some View { buttonStyle(.plain) }
}
