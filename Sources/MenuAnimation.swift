import AppKit

enum BarAnimation: String, CaseIterable {
    case curtain, fade, hiddenBar
    var title: String {
        switch self { case .curtain: return "Curtain"; case .fade: return "Fade"; case .hiddenBar: return "Hidden Bar" }
    }
    static func choices(for side: BarSide) -> [Self] { side == .left ? [.curtain, .fade] : allCases }
}

enum AnimationPace: String, CaseIterable {
    case originalLeft, originalRight
    var title: String { self == .originalLeft ? "A · Original left" : "B · Original right" }
    // Right pacing comes from captured native icon transitions on this Mac:
    // roughly 550 ms including the reveal's settling tail, and 250 ms to hide.
    func duration(opening: Bool) -> Double {
        self == .originalLeft ? (opening ? 0.18 : 0.16) : (opening ? 0.55 : 0.25)
    }
}

enum MenuMaskDrawing {
    static func draw(in bounds: NSRect, progress: Double, style: BarAnimation,
                     mirrored: Bool = false, extent: CGFloat? = nil, background: (() -> Void)? = nil) {
        guard let background, let context = NSGraphicsContext.current?.cgContext else {
            drawAlpha(in: bounds, progress: progress, style: style, mirrored: mirrored, extent: extent)
            return
        }
        NSGraphicsContext.saveGraphicsState(); bounds.clip()
        context.beginTransparencyLayer(in: bounds, auxiliaryInfo: nil)
        drawAlpha(in: bounds, progress: progress, style: style, mirrored: mirrored, extent: extent)
        background()
        context.endTransparencyLayer(); NSGraphicsContext.restoreGraphicsState()
    }
    private static func drawAlpha(in bounds: NSRect, progress: Double, style: BarAnimation, mirrored: Bool, extent: CGFloat?) {
        let p = min(1, max(0, progress))
        guard p < 1, !bounds.isEmpty else { return }
        if style == .fade {
            NSColor.black.withAlphaComponent(1 - p).setFill(); bounds.fill()
            return
        }
        NSGraphicsContext.saveGraphicsState()
        bounds.clip()
        let transform = AffineTransform(translationByX: mirrored ? bounds.maxX : bounds.minX, byY: bounds.minY)
        var local = transform
        if mirrored { local.scale(x: -1, y: 1) }
        (local as NSAffineTransform).concat()
        let rect = NSRect(origin: .zero, size: bounds.size)
        NSColor.black.setFill()
        if p <= 0 { rect.fill() }
        else {
            let feather: CGFloat = 14
            let edge = (min(bounds.width, max(0, extent ?? bounds.width)) + feather) * p
            let start = max(0, edge - feather)
            NSGradient(starting: .clear, ending: .black)?.draw(in: NSRect(x: start, y: 0, width: max(0.01, edge - start), height: rect.height), angle: 0)
            NSColor.black.setFill()
            NSRect(x: min(edge, rect.width), y: 0, width: max(0, rect.width - edge), height: rect.height).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

protocol TransitionCover: AnyObject {
    var isVisible: Bool { get }
    var progress: Double { get }
    func prepare(frame: NSRect, progress: Double, style: BarAnimation)
    func animate(to target: Double, duration: Double, completion: @escaping () -> Void)
    func cancelAnimation()
    func dismiss()
}

final class RightMenuCover: TransitionCover {
    final class View: NSView {
        var progress = 1.0 { didSet { needsDisplay = true } }
        var style = BarAnimation.curtain { didSet { needsDisplay = true } }
        override var isOpaque: Bool { false }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.clear.setFill(); bounds.fill(using: .copy)
            MenuMaskDrawing.draw(in: bounds, progress: progress, style: style, mirrored: true) {
                MenuBarBackdrop.shared.draw(in: self.bounds, screenRect: self.window?.frame ?? .zero, operation: .sourceIn)
            }
        }
    }
    private var panel: LeftCurtain.CoverPanel?
    private var timer: Timer?
    var isVisible: Bool { panel?.isVisible ?? false }
    var progress: Double { (panel?.contentView as? View)?.progress ?? 1 }
    func prepare(frame: NSRect, progress: Double, style: BarAnimation) {
        cancelAnimation()
        if panel == nil {
            let window = LeftCurtain.CoverPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.level = .statusBar
            window.backgroundColor = .clear; window.isOpaque = false
            window.hasShadow = false; window.ignoresMouseEvents = true; window.hidesOnDeactivate = false
            // AppKit's implicit order-in/out fade can overlap our mask animation
            // when this panel is reused by a quick second click.
            window.animationBehavior = .none
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.contentView = View(frame: NSRect(origin: .zero, size: frame.size))
            panel = window
        }
        panel?.setFrame(frame, display: false)
        if let view = panel?.contentView as? View { view.progress = progress; view.style = style }
        panel?.orderFrontRegardless(); panel?.displayIfNeeded()
    }
    func animate(to target: Double, duration: Double, completion: @escaping () -> Void) {
        cancelAnimation()
        guard let view = panel?.contentView as? View else { completion(); return }
        let from = view.progress, started = ProcessInfo.processInfo.systemUptime
        guard duration > 0, abs(target - from) > 0.001 else { view.progress = target; completion(); return }
        let frames = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self, weak view] _ in
            guard let self, let view else { return }
            let t = min(1, (ProcessInfo.processInfo.systemUptime - started) / duration)
            let eased = target > from ? 1 - pow(1 - t, 3) : t * t * (3 - 2 * t)
            view.progress = from + (target - from) * eased
            if t >= 1 { self.cancelAnimation(); completion() }
        }
        timer = frames; RunLoop.main.add(frames, forMode: .common)
    }
    func cancelAnimation() { timer?.invalidate(); timer = nil }
    func refreshBackground() { panel?.contentView?.needsDisplay = true }
    func updateClosedFrame(_ frame: NSRect?) {
        guard progress == 0, let frame, let panel, panel.isVisible, panel.frame != frame else { return }
        panel.setFrame(frame, display: false)
        panel.contentView?.needsDisplay = true
    }
    func dismiss() { cancelAnimation(); panel?.orderOut(nil) }
    func stop() { dismiss(); panel?.close(); panel = nil }
}

// Keeps native layout work behind a cover, and invalidates every delayed
// callback when a user reverses direction, pauses, or changes the configuration.
final class RightMenuTransition {
    typealias Schedule = (Double, @escaping () -> Void) -> Void
    static let revealPreparation = 0.30
    static let hideSettling = 0.28
    private let engine: MenuBarEngine
    private let cover: TransitionCover
    private let schedule: Schedule
    private var generation = 0
    private(set) var expanded = true
    init(engine: MenuBarEngine, cover: TransitionCover,
         schedule: @escaping Schedule = { seconds, body in DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: body) }) {
        self.engine = engine; self.cover = cover; self.schedule = schedule
    }
    func expand(style: BarAnimation, pace: AnimationPace, frame: NSRect?, onStart: @escaping () -> Void = {}, completion: @escaping () -> Void) {
        generation += 1; let token = generation
        let needsPreparation = engine.state == .collapsed || engine.state == .calibrating
        expanded = true; cover.cancelAnimation()
        guard style != .hiddenBar, let frame else {
            cover.dismiss(); engine.expand(); onStart(); completion(); return
        }
        let progress = cover.isVisible ? cover.progress : (needsPreparation ? 0 : 1)
        cover.prepare(frame: frame, progress: progress, style: style)
        engine.expand()
        let start = { [weak self] in
            guard let self, token == self.generation else { return }
            onStart()
            self.cover.animate(to: 1, duration: pace.duration(opening: true)) { [weak self] in
                guard let self, token == self.generation else { return }
                self.cover.dismiss(); completion()
            }
        }
        if needsPreparation { schedule(Self.revealPreparation, start) } else { start() }
    }
    func collapse(style: BarAnimation, pace: AnimationPace, frame: NSRect?, completion: @escaping (CollapseResult) -> Void) {
        generation += 1; let token = generation
        expanded = false; cover.cancelAnimation()
        if engine.state == .calibrating { engine.expand() }
        let native = { [weak self] in
            guard let self, token == self.generation else { return }
            self.engine.collapse { [weak self] result in
                guard let self, token == self.generation else { return }
                if result == .collapsed {
                    self.schedule(style == .hiddenBar ? 0 : Self.hideSettling) { [weak self] in
                        guard let self, token == self.generation else { return }
                        // The assertion has been accepted, not necessarily presented. Keep
                        // the closed cover across native animation tails and fast reversals;
                        // expand removes it only after our reveal is complete.
                        completion(result)
                    }
                } else {
                    self.expanded = true; self.cover.dismiss(); completion(result)
                }
            }
            self.schedule(2) { [weak self] in
                guard let self, token == self.generation, self.engine.state == .calibrating else { return }
                self.cancelAndExpand(); completion(.unavailable)
            }
        }
        guard style != .hiddenBar, let frame else { cover.dismiss(); native(); return }
        let progress = cover.isVisible ? cover.progress : 1
        cover.prepare(frame: frame, progress: progress, style: style)
        cover.animate(to: 0, duration: pace.duration(opening: false), completion: native)
    }
    func cancelAndExpand() {
        generation += 1; expanded = true; cover.dismiss(); engine.expand()
    }
}
