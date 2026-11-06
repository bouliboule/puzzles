#if DEBUG
import Foundation
#if os(macOS)
import AppKit
#endif

/// Development helpers driven by environment variables:
///   PUZZLES_OPEN=loopy        open a puzzle at launch
///   PUZZLES_SNAPSHOT=1        (Mac) write the window to $TMPDIR/snapshot.png after 4 s
@MainActor
enum DebugHooks {
    static func run(_ c: GameController) {
        let env = ProcessInfo.processInfo.environment
        if let name = env["PUZZLES_OPEN"] { c.open(name) }
        #if os(macOS)
        if env["PUZZLES_SNAPSHOT"] != nil {
            let path = NSTemporaryDirectory() + "snapshot.png"
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                guard let v = NSApp.windows.first?.contentView,
                      let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
                v.cacheDisplay(in: v.bounds, to: rep)
                // cacheDisplay skips layer contents set directly; composite the board layer tree too.
                if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = ctx
                    let cg = ctx.cgContext
                    cg.translateBy(x: 0, y: v.bounds.height)
                    cg.scaleBy(x: 1, y: -1)
                    if let board = c.board.layer, let root = v.layer {
                        let o = root.convert(CGPoint.zero, from: board)
                        cg.translateBy(x: o.x, y: o.y)
                        board.render(in: cg)
                    }
                    NSGraphicsContext.restoreGraphicsState()
                }
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                print("snapshot:", path)
            }
        }
        #endif
    }
}
#endif
