import QuartzCore
#if os(iOS)
import UIKit
typealias PlatformView = UIView
#else
import AppKit
typealias PlatformView = NSView
#endif

@MainActor
protocol BoardHost: AnyObject {
    func primaryButton() -> Int32
    func longPressEnabled() -> Bool
    func stylus() -> Bool
    func instantAnimation() -> Bool
    func onInput(_ result: Int32)
    func onZoomChange()
}

/// Shows an Engine's bitmap, sized to fit, with zoom and pan, and turns
/// touch, pencil, mouse, trackpad and keyboard input into midend button
/// events. A port of web/js/board.js. All sizes here are in points.
final class BoardView: PlatformView {
    weak var host: BoardHost?
    private let pad: CGFloat = 6
    private let maxTile: CGFloat = 96
    private static let maxPx: CGFloat = 10e6
    /// Points per puzzle unit. Puzzles draw 1-unit grid lines and outlines,
    /// which read as hairlines on iPhone/iPad; magnify for a bolder look.
    #if os(iOS)
    private static let lineWeight = 2.0
    #else
    private static let lineWeight = 1.0
    #endif

    private(set) var engine: Engine?
    private(set) var zoom: CGFloat = 1
    private(set) var maxZoom: CGFloat = 1
    var canZoom: Bool { maxZoom > 1 }

    private var panX: CGFloat = 0
    private var panY: CGFloat = 0
    private var dispScale: CGFloat = 1   // points per bitmap pixel
    private var dispW: CGFloat = 0
    private var dispH: CGFloat = 0
    private var pinchScale: CGFloat = 1
    private var lastSize = CGSize.zero

    private let imageLayer = CALayer()
    private let ringLayer = CAShapeLayer()

    init() {
        super.init(frame: .zero)
        #if os(macOS)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        #else
        isMultipleTouchEnabled = true
        #endif
        imageLayer.magnificationFilter = .linear
        imageLayer.minificationFilter = .linear
        imageLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        ringLayer.fillColor = nil
        ringLayer.strokeColor = CGColor(gray: 0.07, alpha: 0.6)
        ringLayer.lineWidth = 4
        ringLayer.isHidden = true
        #if os(macOS)
        let root = layer!
        #else
        let root = layer
        #endif
        root.addSublayer(imageLayer)
        root.addSublayer(ringLayer)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    #if os(macOS)
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var density: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }
    #else
    override var canBecomeFirstResponder: Bool { true }
    private var density: CGFloat { window?.screen.scale ?? traitCollection.displayScale }
    #endif

    func attach(_ e: Engine) {
        if let old = engine { detach(old) }
        engine = e
        e.renderer.onUpdate = { [weak self] in self?.showImage() }
        e.renderer.onTimer = { [weak self] on in on ? self?.startTimer() : self?.stopTimer() }
        zoom = 1
        if bounds.width > 0 { layoutBoard() }
        if e.pz.timerActive { startTimer() }
    }

    private func detach(_ e: Engine) {
        stopTimer()
        e.renderer.onUpdate = {}
        e.renderer.onTimer = { _ in }
    }

    // ---- sizing ------------------------------------------------------------
    private func render() {
        guard let e = engine, bounds.width >= 10, bounds.height >= 10 else { return }
        let aw = max(50, (bounds.width - 2 * pad) * zoom)
        let ah = max(50, (bounds.height - 2 * pad) * zoom)
        var dpr = density
        if aw * ah * dpr * dpr > Self.maxPx { dpr = max(1, sqrt(Self.maxPx / (aw * ah))) }
        let (w, h, fe) = e.pz.size(Int(aw), Int(ah), dpr: Double(dpr), weight: Self.lineWeight)
        e.renderer.setSize(w, h, scale: fe)
        dispScale = 1 / dpr
        dispW = CGFloat(w) * dispScale
        dispH = CGFloat(h) * dispScale
        e.pz.redraw()
        showImage()
    }

    /// Full layout at zoom 1.
    func layoutBoard() {
        guard let e = engine else { return }
        zoom = 1
        render()
        let tile = CGFloat(e.pz.tilesize * e.renderer.feScale) * dispScale
        maxZoom = tile > 0 ? min(6, max(1, maxTile / tile)) : 3
        if maxZoom < 1.15 { maxZoom = 1 }
        centre()
        host?.onZoomChange()
    }

    /// Re-render after a theme or settings change, keeping zoom.
    func redraw() {
        engine?.pz.redraw()
        showImage()
    }

    private func sizeChanged() {
        let s = bounds.size
        guard engine != nil, s != lastSize, s.width > 0, s.height > 0 else { return }
        lastSize = s
        if zoom == 1 { layoutBoard(); return }
        let fx = (s.width / 2 - panX) / dispW
        let fy = (s.height / 2 - panY) / dispH
        render()
        panX = s.width / 2 - fx * dispW
        panY = s.height / 2 - fy * dispH
        clampPan()
    }

    #if os(macOS)
    override func layout() { super.layout(); sizeChanged() }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if engine != nil && bounds.width > 0 { lastSize = .zero; sizeChanged() }
    }
    #else
    override func layoutSubviews() { super.layoutSubviews(); sizeChanged() }
    #endif

    private func centre() {
        panX = (bounds.width - dispW) / 2
        panY = (bounds.height - dispH) / 2
        place()
    }

    private func clampPan() {
        let w = bounds.width, h = bounds.height
        panX = dispW + 2 * pad <= w ? (w - dispW) / 2 : min(pad, max(w - dispW - pad, panX))
        panY = dispH + 2 * pad <= h ? (h - dispH) / 2 : min(pad, max(h - dispH - pad, panY))
        place()
    }

    func setZoom(_ z0: CGFloat, focus: CGPoint? = nil) {
        let f = focus ?? CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let z = min(maxZoom, max(1, z0))
        let ux = (f.x - panX) / dispW, uy = (f.y - panY) / dispH
        zoom = z
        render()
        panX = f.x - ux * dispW
        panY = f.y - uy * dispH
        clampPan()
        host?.onZoomChange()
    }

    func zoomIn() { setZoom(zoom * 1.6) }
    func zoomOut() { setZoom(zoom / 1.6) }

    // ---- display -----------------------------------------------------------
    private func showImage() {
        imageLayer.contents = engine?.renderer.image()
    }

    private func place() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let d = 1 / density
        imageLayer.frame = CGRect(x: (panX / d).rounded() * d, y: (panY / d).rounded() * d,
                                  width: dispW * pinchScale, height: dispH * pinchScale)
        CATransaction.commit()
    }

    private func showRing(at p: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringLayer.path = CGPath(ellipseIn: CGRect(x: p.x - 28, y: p.y - 28, width: 56, height: 56), transform: nil)
        ringLayer.isHidden = false
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.ringLayer.isHidden = true }
    }

    // ---- animation timer ---------------------------------------------------
    private var link: CADisplayLink?
    private var timerOn = false
    private var lastFrame: CFTimeInterval = 0

    private func startTimer() {
        if timerOn { return }
        timerOn = true
        if host?.instantAnimation() == true {
            // E-ink: skip animations entirely, in one step after this event.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var n = 0
                while self.timerOn, let e = self.engine, n < 50 { e.pz.timer(60); n += 1 }
                self.timerOn = false
            }
            return
        }
        lastFrame = 0
        #if os(macOS)
        let l = displayLink(target: self, selector: #selector(frame(_:)))
        #else
        let l = CADisplayLink(target: self, selector: #selector(frame(_:)))
        #endif
        l.add(to: .main, forMode: .common)
        link = l
    }

    private func stopTimer() {
        timerOn = false
        link?.invalidate()
        link = nil
    }

    @objc private func frame(_ l: CADisplayLink) {
        guard timerOn, let e = engine else { stopTimer(); return }
        let t = l.timestamp
        let dt = lastFrame == 0 ? 0 : t - lastFrame
        lastFrame = t
        e.pz.timer(dt)
    }

    #if os(macOS)
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { stopTimer() } }
    #else
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { stopTimer() } }
    #endif

    // ---- input: shared -----------------------------------------------------
    private var mod: Int32 { host?.stylus() == true ? Btn.stylus : 0 }

    @discardableResult
    private func send(_ p: CGPoint, _ button: Int32) -> Int32 {
        guard let e = engine else { return 0 }
        let s = dispScale * CGFloat(e.renderer.feScale)
        let r = e.input(Int(((p.x - panX) / s).rounded()), Int(((p.y - panY) / s).rounded()), button)
        host?.onInput(r)
        return r
    }

    private func sendKey(_ button: Int32) {
        guard let e = engine else { return }
        host?.onInput(e.input(0, 0, button))
    }

    private func swap(_ b: Int32) -> Int32 { b == Btn.left ? Btn.right : Btn.left }

    /// Maps a typed character to a midend key, skipping the midend's own
    /// one-key shortcuts that would generate or quit synchronously.
    private func charKey(_ s: String) -> Int32? {
        guard s.count == 1, let a = s.unicodeScalars.first?.value, a >= 32, a < 127 else { return nil }
        if "nNqQ".unicodeScalars.contains(where: { $0.value == a }) { return nil }
        return a == 32 ? Btn.select2 : Int32(a)
    }

    // ---- pinch (touch and trackpad) ----------------------------------------
    private struct Pinch { var m0: CGPoint; var pan0: CGPoint; var zoom0: CGFloat; var w0: CGFloat; var s: CGFloat = 1; var m: CGPoint; var moved = false }
    private var pinch: Pinch?

    private func startPinch(mid: CGPoint) {
        pinch = Pinch(m0: mid, pan0: CGPoint(x: panX, y: panY), zoom0: zoom, w0: dispW, m: mid)
    }

    private func updatePinch(mid: CGPoint, scale: CGFloat) {
        guard var p = pinch else { return }
        let s = min(maxZoom / p.zoom0, max(1 / p.zoom0, canZoom ? scale : 1))
        p.s = s; p.m = mid; p.moved = true
        pinch = p
        panX = mid.x - (p.m0.x - p.pan0.x) * s
        panY = mid.y - (p.m0.y - p.pan0.y) * s
        if abs(s - 1) < 0.02 { pinchScale = 1; clampPan() } else { pinchScale = s; place() }
    }

    private func endPinch() {
        guard let p = pinch else { return }
        pinch = nil
        pinchScale = 1
        if !p.moved { return }
        if abs(p.s - 1) < 0.02 { clampPan(); return }
        zoom = min(maxZoom, max(1, p.zoom0 * p.s))
        render()
        let r = dispW / p.w0
        panX = p.m.x - (p.m0.x - p.pan0.x) * r
        panY = p.m.y - (p.m0.y - p.pan0.y) * r
        clampPan()
        host?.onZoomChange()
    }

    private func pan(by dx: CGFloat, _ dy: CGFloat) {
        panX += dx; panY += dy
        clampPan()
    }

    #if os(iOS)
    // ---- input: touch ------------------------------------------------------
    private enum Kind { case pending, game, pinch, mouse, done }
    private struct Gesture { var kind: Kind; var touch: UITouch; var p0: CGPoint; var btn: Int32; var slop: CGFloat; var d0: CGFloat = 0 }
    private var g: Gesture?
    private var touchesDown: [UITouch] = []
    private var longPressWork: DispatchWorkItem?

    private func cancelLongPress() { longPressWork?.cancel(); longPressWork = nil }

    private func fireLongPress() {
        guard var gg = g, gg.kind == .pending else { return }
        gg.btn = swap(gg.btn)
        gg.kind = .game
        g = gg
        showRing(at: gg.p0)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        send(gg.p0, gg.btn | mod)
    }

    private func mid(_ a: UITouch, _ b: UITouch) -> (CGPoint, CGFloat) {
        let p = a.location(in: self), q = b.location(in: self)
        return (CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2), hypot(p.x - q.x, p.y - q.y))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard engine != nil else { return }
        for t in touches {
            touchesDown.append(t)
            let p = t.location(in: self)
            if g == nil {
                becomeFirstResponder()
                if t.type == .indirectPointer {
                    let mask = event?.buttonMask ?? .primary
                    var b = mask.contains(.secondary) ? Btn.right : Btn.left
                    if b == Btn.left { b = host?.primaryButton() ?? Btn.left }
                    g = Gesture(kind: .mouse, touch: t, p0: p, btn: b, slop: 0)
                    send(p, b)
                } else {
                    g = Gesture(kind: .pending, touch: t, p0: p, btn: host?.primaryButton() ?? Btn.left,
                                slop: t.type == .pencil ? 4 : 9)
                    if host?.longPressEnabled() == true {
                        let w = DispatchWorkItem { [weak self] in self?.fireLongPress() }
                        longPressWork = w
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: w)
                    }
                }
            } else if var gg = g, gg.kind == .pending, touchesDown.count == 2 {
                cancelLongPress()
                let (m, d) = mid(touchesDown[0], touchesDown[1])
                gg.kind = .pinch
                gg.d0 = max(20, d)
                g = gg
                startPinch(mid: m)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard var gg = g else { return }
        switch gg.kind {
        case .pending:
            guard touches.contains(gg.touch) else { return }
            let p = gg.touch.location(in: self)
            if hypot(p.x - gg.p0.x, p.y - gg.p0.y) > gg.slop {
                cancelLongPress()
                gg.kind = .game
                g = gg
                send(gg.p0, gg.btn | mod)
                send(p, Btn.drag(gg.btn) | mod)
            }
        case .game:
            if touches.contains(gg.touch) { send(gg.touch.location(in: self), Btn.drag(gg.btn) | mod) }
        case .mouse:
            if touches.contains(gg.touch) { send(gg.touch.location(in: self), Btn.drag(gg.btn)) }
        case .pinch:
            if touchesDown.count >= 2 {
                let (m, d) = mid(touchesDown[0], touchesDown[1])
                updatePinch(mid: m, scale: d / gg.d0)
            }
        case .done:
            break
        }
    }

    private func ended(_ touches: Set<UITouch>, cancelled: Bool) {
        for t in touches {
            if var gg = g {
                switch gg.kind {
                case .pending where t === gg.touch:
                    cancelLongPress()
                    if !cancelled {
                        send(gg.p0, gg.btn | mod)
                        send(gg.p0, Btn.release(gg.btn) | mod)
                    }
                    gg.kind = .done
                case .game where t === gg.touch:
                    send(t.location(in: self), Btn.release(gg.btn) | mod)
                    gg.kind = .done
                case .mouse where t === gg.touch:
                    send(t.location(in: self), Btn.release(gg.btn))
                    gg.kind = .done
                case .pinch:
                    endPinch()
                    gg.kind = .done
                default:
                    break
                }
                g = gg
            }
            touchesDown.removeAll { $0 === t }
        }
        if touchesDown.isEmpty { g = nil }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { ended(touches, cancelled: false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { ended(touches, cancelled: true) }

    // ---- input: hardware keyboard -----------------------------------------
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for p in presses {
            guard let k = p.key, k.modifierFlags.intersection([.command, .control, .alternate]).isEmpty else { continue }
            var b: Int32?
            switch k.keyCode {
            case .keyboardUpArrow: b = Btn.up
            case .keyboardDownArrow: b = Btn.down
            case .keyboardLeftArrow: b = Btn.leftKey
            case .keyboardRightArrow: b = Btn.rightKey
            case .keyboardReturnOrEnter, .keypadEnter: b = Btn.select
            case .keyboardDeleteOrBackspace: b = 8
            default: b = charKey(k.charactersIgnoringModifiers)
            }
            if let b { sendKey(b); handled = true }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }

    #else
    // ---- input: mouse and trackpad ------------------------------------------
    private var mouseBtn: Int32?

    private func loc(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    private func down(_ e: NSEvent, _ b: Int32) {
        guard engine != nil else { return }
        window?.makeFirstResponder(self)
        mouseBtn = b
        send(loc(e), b)
    }

    private func drag(_ e: NSEvent) { if let b = mouseBtn { send(loc(e), Btn.drag(b)) } }
    private func up(_ e: NSEvent) { if let b = mouseBtn { send(loc(e), Btn.release(b)) }; mouseBtn = nil }

    override func mouseDown(with e: NSEvent) {
        down(e, e.modifierFlags.contains(.control) ? Btn.right : (host?.primaryButton() ?? Btn.left))
    }
    override func rightMouseDown(with e: NSEvent) { down(e, Btn.right) }
    override func otherMouseDown(with e: NSEvent) { down(e, Btn.middle) }
    override func mouseDragged(with e: NSEvent) { drag(e) }
    override func rightMouseDragged(with e: NSEvent) { drag(e) }
    override func otherMouseDragged(with e: NSEvent) { drag(e) }
    override func mouseUp(with e: NSEvent) { up(e) }
    override func rightMouseUp(with e: NSEvent) { up(e) }
    override func otherMouseUp(with e: NSEvent) { up(e) }

    override func scrollWheel(with e: NSEvent) {
        guard engine != nil else { return }
        let k: CGFloat = e.hasPreciseScrollingDeltas ? 1 : 12
        if e.modifierFlags.contains(.command) || e.modifierFlags.contains(.control) {
            setZoom(zoom * exp(e.scrollingDeltaY * k * 0.01), focus: loc(e))
        } else {
            pan(by: e.scrollingDeltaX * k, e.scrollingDeltaY * k)
        }
    }

    private var magnifyScale: CGFloat = 1

    override func magnify(with e: NSEvent) {
        guard engine != nil else { return }
        switch e.phase {
        case .began:
            magnifyScale = 1
            startPinch(mid: loc(e))
        case .changed:
            magnifyScale *= 1 + e.magnification
            updatePinch(mid: pinch?.m0 ?? loc(e), scale: magnifyScale)
        case .ended, .cancelled:
            endPinch()
        default:
            break
        }
    }

    override func keyDown(with e: NSEvent) {
        guard engine != nil, e.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            super.keyDown(with: e); return
        }
        var b: Int32?
        switch e.specialKey {
        case .upArrow?: b = Btn.up
        case .downArrow?: b = Btn.down
        case .leftArrow?: b = Btn.leftKey
        case .rightArrow?: b = Btn.rightKey
        case .carriageReturn?, .enter?, .newline?: b = Btn.select
        case .delete?, .backspace?, .deleteForward?: b = 8
        default: b = charKey(e.charactersIgnoringModifiers ?? "")
        }
        if let b { sendKey(b) } else { super.keyDown(with: e) }
    }
    #endif
}
