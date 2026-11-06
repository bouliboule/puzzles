// Renders the app icon PNGs into an .appiconset (same artwork as
// android/app/src/main/res/drawable/ic_launcher_fg.xml).
// Usage: swift apple/tools/make-icon.swift apple/Puzzles/Assets.xcassets/AppIcon.appiconset
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func render(size: Int, mac: Bool, to path: String) {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: s); ctx.scaleBy(x: 1, y: -1)   // y down
    let bg = CGColor(srgbRed: 0x2F/255, green: 0x5D/255, blue: 0x50/255, alpha: 1)
    let fg = CGColor(srgbRed: 0xF2/255, green: 0xF1/255, blue: 0xED/255, alpha: 1)
    // Crop the 768-unit Android viewport to its central 600 units.
    var k = s / 600, ox: CGFloat = -84 * s / 600
    if mac {
        // macOS: rounded square with margin (824/1024 grid).
        let inset = s * 100 / 1024, side = s - 2 * inset
        ctx.addPath(CGPath(roundedRect: CGRect(x: inset, y: inset, width: side, height: side),
                           cornerWidth: side * 0.225, cornerHeight: side * 0.225, transform: nil))
        ctx.setFillColor(bg); ctx.fillPath()
        k = side / 600; ox = inset - 84 * k
    } else {
        ctx.setFillColor(bg); ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    }
    ctx.translateBy(x: ox, y: ox); ctx.scaleBy(x: k, y: k); ctx.translateBy(x: 128, y: 128)
    ctx.setFillColor(fg); ctx.setStrokeColor(fg)
    for y in stride(from: 136, through: 376, by: 80) { for x in stride(from: 136, through: 376, by: 80) {
        ctx.fillEllipse(in: CGRect(x: x - 11, y: y - 11, width: 22, height: 22)) } }
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.setLineWidth(24)
    let loop = CGMutablePath()
    loop.addLines(between: [CGPoint(x: 136, y: 136), CGPoint(x: 296, y: 136), CGPoint(x: 296, y: 216), CGPoint(x: 376, y: 216),
                            CGPoint(x: 376, y: 376), CGPoint(x: 216, y: 376), CGPoint(x: 216, y: 296), CGPoint(x: 136, y: 296)])
    loop.closeSubpath()
    ctx.addPath(loop); ctx.strokePath()
    // "3": M238,222c6,-8 30,-10 34,3c3,10 -6,16 -16,17c11,1 20,7 17,19c-4,13 -29,13 -36,3
    ctx.setLineWidth(13)
    let t = CGMutablePath()
    var p = CGPoint(x: 238, y: 222); t.move(to: p)
    for c in [[6,-8,30,-10,34,3],[3,10,-6,16,-16,17],[11,1,20,7,17,19],[-4,13,-29,13,-36,3]] as [[CGFloat]] {
        let e = CGPoint(x: p.x + c[4], y: p.y + c[5])
        t.addCurve(to: e, control1: CGPoint(x: p.x + c[0], y: p.y + c[1]), control2: CGPoint(x: p.x + c[2], y: p.y + c[3]))
        p = e
    }
    ctx.addPath(t); ctx.strokePath()
    let img = ctx.makeImage()!
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
}

let dir = CommandLine.arguments[1]
render(size: 1024, mac: false, to: "\(dir)/icon-ios.png")
for px in [16, 32, 64, 128, 256, 512, 1024] { render(size: px, mac: true, to: "\(dir)/icon-mac-\(px).png") }
