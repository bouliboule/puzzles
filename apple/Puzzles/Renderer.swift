import CoreGraphics
import CoreText
#if canImport(UIKit)
import UIKit
typealias PlatformFont = UIFont
#else
import AppKit
typealias PlatformFont = NSFont
#endif

/// Receives drawing calls from native code and paints them into an
/// offscreen bitmap, in puzzle units scaled by feScale. Mirrors
/// web/js/engine.js and the Android Renderer.
final class Renderer {
    private(set) var ctx: CGContext?
    private(set) var feScale = 1
    private(set) var width = 0
    private(set) var height = 0
    var colours: [CGColor] = []
    var bold = false { didSet { midpoints.removeAll(); fonts.removeAll() } }

    /// Called after a drawing pass that changed something.
    var onUpdate: () -> Void = {}
    var onStatus: (String) -> Void = { _ in }
    var onTimer: (Bool) -> Void = { _ in }

    private struct Blit { var w: Int; var h: Int; var image: CGImage?; var dx = 0; var dy = 0 }
    private var blitters: [Int32: Blit] = [:]
    private var midpoints: [Int: CGFloat] = [:]
    private var fonts: [Int: CTFont] = [:]
    private var dirty = false
    private static let magenta = CGColor(red: 1, green: 0, blue: 1, alpha: 1)

    /// A snapshot of the current bitmap for display.
    func image() -> CGImage? { ctx?.makeImage() }

    func setSize(_ w: Int, _ h: Int, scale: Int) {
        let w = max(1, w), h = max(1, h)
        feScale = scale
        if ctx == nil || w != width || h != height {
            width = w; height = h
            ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            ctx?.saveGState()   // the untransformed state, restored on resize
        } else {
            ctx?.restoreGState()
            ctx?.saveGState()
        }
        guard let c = ctx else { return }
        // Top-left origin, y down, in puzzle units.
        c.translateBy(x: 0, y: CGFloat(h))
        c.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        c.setLineCap(.round)
        c.setLineJoin(.round)
        midpoints.removeAll()
    }

    private func col(_ i: Int32) -> CGColor { i >= 0 && Int(i) < colours.count ? colours[Int(i)] : Self.magenta }

    // ---- callbacks from native code ----------------------------------
    func startDraw() { dirty = false }

    func endDraw() {
        if dirty { dirty = false; onUpdate() }
    }

    func drawUpdate() { dirty = true }

    func rect(_ x: Int32, _ y: Int32, _ w: Int32, _ h: Int32, _ c: Int32) {
        guard let cg = ctx else { return }
        cg.setShouldAntialias(false)
        cg.setFillColor(col(c))
        cg.fill(CGRect(x: Int(x), y: Int(y), width: Int(w), height: Int(h)))
        cg.setShouldAntialias(true)
    }

    func line(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ width: Float, _ c: Int32) {
        guard let cg = ctx else { return }
        cg.setStrokeColor(col(c))
        cg.setLineWidth(CGFloat(width))
        cg.beginPath()
        cg.move(to: CGPoint(x: CGFloat(x1) + 0.5, y: CGFloat(y1) + 0.5))
        cg.addLine(to: CGPoint(x: CGFloat(x2) + 0.5, y: CGFloat(y2) + 0.5))
        cg.strokePath()
    }

    func poly(_ pts: UnsafePointer<Int32>, _ n: Int, _ fill: Int32, _ outline: Int32) {
        guard let cg = ctx, n > 0 else { return }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: CGFloat(pts[0]) + 0.5, y: CGFloat(pts[1]) + 0.5))
        for i in 1..<n { path.addLine(to: CGPoint(x: CGFloat(pts[2 * i]) + 0.5, y: CGFloat(pts[2 * i + 1]) + 0.5)) }
        path.closeSubpath()
        if fill >= 0 { cg.setFillColor(col(fill)); cg.addPath(path); cg.fillPath() }
        cg.setStrokeColor(col(outline)); cg.setLineWidth(1)
        cg.addPath(path); cg.strokePath()
    }

    func circle(_ x: Int32, _ y: Int32, _ r: Int32, _ fill: Int32, _ outline: Int32) {
        guard let cg = ctx else { return }
        let rr = CGFloat(r)
        let rect = CGRect(x: CGFloat(x) + 0.5 - rr, y: CGFloat(y) + 0.5 - rr, width: 2 * rr, height: 2 * rr)
        if fill >= 0 { cg.setFillColor(col(fill)); cg.fillEllipse(in: rect) }
        cg.setStrokeColor(col(outline)); cg.setLineWidth(1)
        cg.strokeEllipse(in: rect)
    }

    private func font(_ size: Int, mono: Bool) -> CTFont {
        let key = size * 2 + (mono ? 1 : 0)
        if let f = fonts[key] { return f }
        let s = CGFloat(size)
        let f: PlatformFont = mono
            ? .monospacedSystemFont(ofSize: s, weight: bold ? .bold : .regular)
            : .systemFont(ofSize: s, weight: bold ? .bold : .medium)
        fonts[key] = f as CTFont
        return f as CTFont
    }

    private func ctLine(_ s: String, _ font: CTFont, _ colour: CGColor) -> CTLine {
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): colour,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
    }

    func text(_ x: Int32, _ y: Int32, _ fonttype: Int32, _ size: Int32, _ align: Int32, _ c: Int32, _ s: String) {
        guard let cg = ctx, size > 0 else { return }
        let mono = fonttype == 0
        let f = font(Int(size), mono: mono)
        let line = ctLine(s, f, col(c))
        let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        // +0.5 like line/circle: puzzle coordinates name pixels, so a circle
        // "at" x is centred on x + 0.5 and text centred with it must match.
        var xx = CGFloat(x) + 0.5
        if align & 0x001 != 0 {
            // Centre the ink, not the advance width, so digits sit centred.
            let g = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            xx -= g.isEmpty ? w / 2 : g.midX
        } else if align & 0x002 != 0 { xx -= w }
        var yy = CGFloat(y) + 0.5
        if align & 0x100 != 0 { yy += midpoint(Int(size), mono: mono, f) }
        cg.saveGState()
        cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        cg.textPosition = CGPoint(x: xx, y: yy)
        CTLineDraw(line, cg)
        cg.restoreGState()
    }

    /// Baseline offset that vertically centres typical glyphs at y.
    private func midpoint(_ size: Int, mono: Bool, _ f: CTFont) -> CGFloat {
        let key = size * 2 + (mono ? 1 : 0)
        if let m = midpoints[key] { return m }
        let b = CTLineGetBoundsWithOptions(ctLine("ABCDEFGHIKLMNOPRSTUVWXYZ0123456789", f, Self.magenta), .useGlyphPathBounds)
        let m = (b.minY + b.maxY) / 2   // unrounded: a unit can be several pixels
        midpoints[key] = m
        return m
    }

    func clip(_ x: Int32, _ y: Int32, _ w: Int32, _ h: Int32) {
        ctx?.saveGState()
        ctx?.clip(to: CGRect(x: Int(x), y: Int(y), width: Int(w), height: Int(h)))
    }

    func unclip() { ctx?.restoreGState() }

    func blitterNew(_ id: Int32, _ w: Int32, _ h: Int32) {
        blitters[id] = Blit(w: Int(w) * feScale, h: Int(h) * feScale)
    }

    func blitterFree(_ id: Int32) { blitters[id] = nil }

    func blitterSave(_ id: Int32, _ x: Int32, _ y: Int32) {
        guard var b = blitters[id], let full = ctx?.makeImage() else { return }
        let want = CGRect(x: Int(x) * feScale, y: Int(y) * feScale, width: b.w, height: b.h)
        let got = want.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        b.image = got.isEmpty ? nil : full.cropping(to: got)
        b.dx = Int(got.minX - want.minX); b.dy = Int(got.minY - want.minY)
        blitters[id] = b
    }

    func blitterLoad(_ id: Int32, _ x: Int32, _ y: Int32) {
        guard let b = blitters[id], let img = b.image, let cg = ctx else { return }
        let fe = CGFloat(feScale)
        cg.saveGState()
        cg.scaleBy(x: 1 / fe, y: 1 / fe)   // device pixels, y down
        cg.translateBy(x: CGFloat(Int(x) * feScale + b.dx), y: CGFloat(Int(y) * feScale + b.dy + img.height))
        cg.scaleBy(x: 1, y: -1)
        cg.setBlendMode(.copy)
        cg.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        cg.restoreGState()
    }
}
