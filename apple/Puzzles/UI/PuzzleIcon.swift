import SwiftUI

/// Home-screen puzzle icons, drawn in a 48×48 box (ports of ICONS in web/js/puzzles.js).
struct PuzzleIcon: View {
    let name: String
    var ink = Color.inkBlack
    var bg = Color.white

    var body: some View {
        Canvas { ctx, size in
            let k = min(size.width, size.height) / 48
            ctx.scaleBy(x: k, y: k)
            let p = IconPainter(ctx: ctx, ink: ink, bg: bg)
            switch name {
            case "loopy": p.loopy()
            case "bridges": p.bridges()
            case "keen": p.keen()
            case "pattern": p.pattern()
            case "pearl": p.pearl()
            case "slant": p.slant()
            default: break
            }
        }
    }
}

/// Parses absolute M/L/H/V/Z SVG path data.
func svgPath(_ d: String) -> Path {
    var path = Path()
    var cur = CGPoint.zero
    var cmd: Character = "M"
    var nums: [CGFloat] = []
    func flush() {
        var i = 0
        func next() -> CGFloat { defer { i += 1 }; return i < nums.count ? nums[i] : 0 }
        repeat {
            switch cmd {
            case "M": cur = CGPoint(x: next(), y: next()); path.move(to: cur); cmd = "L"
            case "L": cur = CGPoint(x: next(), y: next()); path.addLine(to: cur)
            case "H": cur.x = next(); path.addLine(to: cur)
            case "V": cur.y = next(); path.addLine(to: cur)
            case "Z": path.closeSubpath(); return
            default: return
            }
        } while i < nums.count
    }
    var token = ""
    func endToken() { if let v = Double(token) { nums.append(CGFloat(v)) }; token = "" }
    for ch in d {
        if ch.isLetter {
            endToken()
            if !nums.isEmpty { flush() }
            nums = []
            cmd = ch
            if ch == "Z" { flush() }
        } else if ch == " " || ch == "," {
            endToken()
        } else if ch == "-" && !token.isEmpty {
            endToken(); token = "-"
        } else {
            token.append(ch)
        }
    }
    endToken()
    if !nums.isEmpty { flush() }
    return path
}

private struct IconPainter {
    let ctx: GraphicsContext
    let ink: Color
    let bg: Color

    func path(_ d: String, _ w: CGFloat) {
        ctx.stroke(svgPath(d), with: .color(ink), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }
    func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }
    func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) { ctx.fill(circle(x, y, r), with: .color(ink)) }
    func ring(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ w: CGFloat) {
        ctx.fill(circle(x, y, r), with: .color(bg))
        ctx.stroke(circle(x, y, r), with: .color(ink), lineWidth: w)
    }
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        ctx.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(ink))
    }
    /// Text with its baseline at y, anchored at its leading edge or centre.
    func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, centre: Bool = true) {
        let t = ctx.resolve(Text(s).font(.system(size: size, weight: .semibold)).foregroundStyle(ink))
        ctx.draw(t, at: CGPoint(x: x, y: y), anchor: UnitPoint(x: centre ? 0.5 : 0, y: 0.78))
    }

    func loopy() {
        for y in [6, 18, 30, 42] as [CGFloat] { for x in [6, 18, 30, 42] as [CGFloat] { dot(x, y, 1.6) } }
        path("M6 6H30V18H42V42H18V30H6Z", 3.2)
        text("3", 24, 28.5, 11)
    }

    func bridges() {
        path("M14 10H34M14 14H34M10 14V34M38 14V34", 2.4)
        for (x, y) in [(10, 10), (38, 10), (10, 38), (38, 38)] as [(CGFloat, CGFloat)] { ring(x, y, 6.5, 2.4) }
        text("3", 10, 13, 8.5); text("3", 38, 13, 8.5); text("1", 10, 41, 8.5); text("1", 38, 41, 8.5)
    }

    func keen() {
        path("M17.7 5V43M30.3 5V43M5 17.7H43M5 30.3H43", 0.8)
        path("M5 17.7H30.3V5M17.7 17.7V43M30.3 30.3H43", 3)
        path("M5 5H43V43H5Z", 3)
        text("6×", 7.5, 11.5, 6, centre: false)
        text("2", 11.4, 38.5, 10); text("3", 36.6, 38.5, 10)
    }

    func pattern() {
        for (y, row) in ["0110", "1111", "1001", "0110"].enumerated() {
            for (x, c) in row.enumerated() where c == "1" {
                rect(14 + CGFloat(x) * 8.5, 14 + CGFloat(y) * 8.5, 7.5, 7.5)
            }
        }
        for (i, s) in ["1", "3", "3", "1"].enumerated() { text(s, 18 + CGFloat(i) * 8.5, 10, 6) }
        for (i, s) in ["2", "4", "1 1", "2"].enumerated() { text(s, 8, 21 + CGFloat(i) * 8.5, 6) }
    }

    func pearl() {
        path("M10 10H38V24H24V38H10Z", 3.2)
        dot(10, 10, 5); ring(24, 10, 5, 2.4); ring(10, 24, 5, 2.4); dot(24, 38, 5)
    }

    func slant() {
        path("M6 6H42V42H6Z", 1)
        path("M18 6V42M30 6V42M6 18H42M6 30H42", 0.8)
        path("M6 6L18 18M18 6L30 18M42 6L30 18M6 30L18 18M30 18L18 30M30 30L42 18M6 30L18 42M30 30L18 42M30 42L42 30", 3)
        ring(18, 18, 4.5, 1.6); ring(30, 30, 4.5, 1.6)
        text("3", 18, 20.3, 6.5); text("2", 30, 32.3, 6.5)
    }
}
