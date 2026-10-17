import AppKit

var assertions = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message); assertions += 1
}
func frame(_ x: CGFloat) -> CGRect { CGRect(x: x, y: 0, width: 20, height: 24) }
let inventory = [
    MenuBarInventoryItem(bundleIdentifier: "visible", frame: frame(700)),
    MenuBarInventoryItem(bundleIdentifier: "hidden", frame: frame(500)),
    MenuBarInventoryItem(bundleIdentifier: "always", frame: frame(200)),
    MenuBarInventoryItem(bundleIdentifier: "siblings", frame: frame(100)),
    MenuBarInventoryItem(bundleIdentifier: "siblings", frame: frame(800)),
    MenuBarInventoryItem(bundleIdentifier: "com.apple.controlcenter", frame: frame(100)),
    MenuBarInventoryItem(bundleIdentifier: "own", frame: frame(100)),
]
let layout = MenuBarLayoutResolver.resolve(inventory: inventory, separatorFrame: frame(600),
                                         alwaysHiddenSeparatorFrame: frame(300), isLTR: true, excludingBundle: "own")
check(layout.sections["hidden"] == .hidden, "Hidden zone")
check(layout.sections["always"] == .alwaysHidden, "Always-hidden zone")
check(layout.sections["siblings"] == .visible, "Most-visible sibling must win")
check(layout.sections["own"] == nil && layout.sections["com.apple.controlcenter"] == nil, "Never hide own/system controls by bundle")
check(MenuBarLayoutResolver.section(of: frame(700), separatorFrame: frame(600), alwaysHiddenSeparatorFrame: frame(800), isLTR: false) == .hidden, "RTL reverses boundaries")

final class Items: MenuBarItemProvider {
    let toggleItem = NSStatusBar.system.statusItem(withLength: 20)
    let separatorItem = NSStatusBar.system.statusItem(withLength: 20)
    let alwaysHiddenItem: NSStatusItem? = nil
    deinit { NSStatusBar.system.removeStatusItem(toggleItem); NSStatusBar.system.removeStatusItem(separatorItem) }
}
final class Inventory: MenuBarInventoryProviding {
    var isAuthorized = true
    var callback: (([MenuBarInventoryItem]) -> Void)?
    func requestAuthorization() {}
    func snapshot(completion: @escaping ([MenuBarInventoryItem]) -> Void) { callback = completion }
    func finish() { let completion = callback; callback = nil; completion?(inventory) }
}
final class Handle: NativeVisibilityAssertion {
    var invalidated = false
    func invalidate() { invalidated = true }
}
final class Visibility: NativeVisibilityProviding {
    var isAvailable = true
    var callback: ((Result<NativeVisibilityAssertion, Error>) -> Void)?
    var allowed: [String] = []
    func activate(allowedSystemItems: [Int], allowedBundleIdentifiers: [String], completion: @escaping (Result<NativeVisibilityAssertion, Error>) -> Void) {
        allowed = allowedBundleIdentifiers; callback = completion
    }
    func finish(_ result: Result<NativeVisibilityAssertion, Error>) { let completion = callback; callback = nil; completion?(result) }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let cover = NSRect(x: 43, y: 923, width: 602.5, height: 33)
let openArrow = LeftCurtain.indicatorFrame(cover: cover, titleWidth: 100, menuEnd: 377, expanded: true)
check(openArrow.minX >= cover.minX + 377 && openArrow.maxX <= cover.maxX,
      "The expanded toggle stays beyond every native heading and clear of the notch")
let tightArrow = LeftCurtain.indicatorFrame(cover: cover, titleWidth: 38, menuEnd: 587, expanded: true)
check(tightArrow.minX == 630 && tightArrow.width >= 14 && tightArrow.maxX <= cover.maxX,
      "Orion's narrow remaining gap still fits the complete indicator without covering Help")
let fullMenuArrow = LeftCurtain.indicatorFrame(cover: cover, titleWidth: 100, menuEnd: cover.width, expanded: true)
check(fullMenuArrow.maxX <= cover.minX && fullMenuArrow.minX >= 0,
      "A full menu bar keeps its toggle in the empty Apple-menu padding rather than covering Help")
// Exercise the actual collapse callback on an offscreen panel. The arrow must
// not jump onto File before the first frame of the covering animation.
if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
    let curtain = LeftCurtain()
    let testFrame = NSRect(x: -4000, y: 0, width: 602.5, height: 33)
    let testPanel = LeftCurtain.CoverPanel(contentRect: testFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    testPanel.isReleasedWhenClosed = false
    let testView = LeftCurtain.CoverView(frame: NSRect(origin: .zero, size: testFrame.size))
    testView.applicationName = "T3 Code (Beta)"
    testView.menuStart = 118; testView.menuEnd = 377; testView.progress = 1
    testPanel.contentView = testView
    curtain.coverFrame = testFrame; curtain.panel = testPanel
    curtain.enabled = true; curtain.revealed = true
    testPanel.orderFrontRegardless()
    curtain.updateClickTarget()
    let expandedX = curtain.clickPanel!.frame.minX
    curtain.indicatorClicked()
    check(curtain.animationRunning && testView.progress == 1 && curtain.clickPanel!.frame.minX == expandedX,
          "Click-collapse starts at the expanded arrow position, preserving the first visible animation frame")
    curtain.animationStart = ProcessInfo.processInfo.systemUptime - curtain.animationDuration / 2
    curtain.animate()
    check(testView.progress > 0 && testView.progress < 1 && curtain.clickPanel!.frame.minX < expandedX,
          "The collapse button moves with an intermediate covering frame")
    curtain.animationStart = ProcessInfo.processInfo.systemUptime - curtain.animationDuration
    curtain.animate()
    check(!curtain.animationRunning && testView.progress == 0 && curtain.clickPanel!.isVisible,
          "Animated collapse finishes with a visible clickable toggle")
    let collapsedX = curtain.clickPanel!.frame.minX
    testView.progress = 1; curtain.revealed = true
    curtain.updateClickTarget()
    (curtain.clickPanel!.contentView!.subviews.first as! NSButton).performClick(nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.24))
    check(!curtain.animationRunning && curtain.animationFrameCount >= 4 && testView.progress == 0,
          "A real NSButton collapse delivers multiple timer frames through to completion")
    check((curtain.animationFirstFrameDelay ?? 1) < curtain.animationDuration / 2,
          "Button tracking does not delay the first frame until the collapse is already over")
    testView.progress = 1; curtain.revealed = true
    curtain.updateClickTarget()
    curtain.setReveal(false, "test-app-switch", animated: false)
    check(testView.progress == 0 && curtain.clickPanel!.frame.minX == collapsedX,
          "An immediate app-switch cover also puts its toggle in the closed position immediately")
    testView.animationStyle = .fade; testView.progress = 0.5
    curtain.updateClickTarget()
    check(curtain.clickPanel!.frame.minX == expandedX,
          "Fade keeps its opaque toggle clear of partially visible native headings")
    curtain.stop()
}
let items = Items(), reader = Inventory(), bridge = Visibility()
let engine = NativeVisibilityEngine(items: items, inventory: reader, visibility: bridge,
                                    ownBundleIdentifier: "own", itemFrame: { _ in frame(600) }, isLTR: { true })
engine.collapse { _ in }
engine.expand()
reader.finish()
check(bridge.callback == nil && engine.state == .expanded, "Expansion cancels pending inventory reads")
engine.collapse { _ in }
reader.finish()
check(bridge.allowed.contains("own") && bridge.allowed.contains("visible") && !bridge.allowed.contains("hidden"), "Own controls remain allowed")
engine.expand()
let stale = Handle()
bridge.finish(.success(stale))
check(stale.invalidated && engine.state == .expanded, "A late native assertion cannot re-hide icons after expand")
engine.collapse { _ in }
reader.finish()
let active = Handle()
bridge.finish(.success(active))
check(engine.state == .collapsed, "Successful assertion collapses")
engine.expand()
check(active.invalidated, "Expansion releases held assertion")
engine.collapse { _ in }
reader.finish()
bridge.finish(.failure(NSError(domain: "Test", code: 1)))
check(engine.state == .expanded, "Activation errors fail open")
let suite = "Draplet.Tests.\(UUID().uuidString)"
let store = UserDefaults(suiteName: suite)!
defer { store.removePersistentDomain(forName: suite) }
let prefs = Preferences(store: store)
check(prefs.backgroundMode == .cached, "Static backgrounds use a one-shot cache by default")
prefs.backgroundMode = .live
check(Preferences(store: store).backgroundMode == .live, "Animated-wallpaper mode survives a restart")
let wallpaperFixture = FileManager.default.temporaryDirectory.appendingPathComponent("Draplet-wallpaper-\(UUID().uuidString)")
try Data([1, 2, 3]).write(to: wallpaperFixture)
let originalWallpaper = WallpaperFingerprint(url: wallpaperFixture, options: "fill", storeURL: nil)
try Data([4, 5, 6, 7]).write(to: wallpaperFixture)
let replacedWallpaper = WallpaperFingerprint(url: wallpaperFixture, options: "fill", storeURL: nil)
check(originalWallpaper != replacedWallpaper, "Replacing a wallpaper at the same URL invalidates its cache")
check(replacedWallpaper != WallpaperFingerprint(url: wallpaperFixture, options: "fit", storeURL: nil),
      "A wallpaper scaling change invalidates its cache even when the file is unchanged")
check(replacedWallpaper == WallpaperFingerprint(url: wallpaperFixture, options: "fill", storeURL: nil),
      "An unchanged wallpaper stays cached")
try FileManager.default.removeItem(at: wallpaperFixture)
let sceneBand = CGRect(x: 0, y: 0, width: 1470, height: 32)
let nearWindow = BackdropScene.Window(number: 1, layer: 0, frame: CGRect(x: 0, y: 32, width: 900, height: 600))
let farWindow = BackdropScene.Window(number: 2, layer: 0, frame: CGRect(x: 0, y: 300, width: 900, height: 500))
let curtainWindow = BackdropScene.Window(number: 3, layer: 25, frame: sceneBand)
let scene = BackdropScene(frontPID: 10, windows: [nearWindow, farWindow], band: sceneBand)
check(scene == BackdropScene(frontPID: 10, windows: [nearWindow, curtainWindow], band: sceneBand),
      "Curtain animation and windows far below the bar do not recapture a cached background")
check(scene != BackdropScene(frontPID: 11, windows: [nearWindow], band: sceneBand),
      "An app switch refreshes cached native appearance even when wallpaper metadata is unchanged")
let movedWindow = BackdropScene.Window(number: 1, layer: 0, frame: nearWindow.frame.offsetBy(dx: 20, dy: 0))
check(scene != BackdropScene(frontPID: 10, windows: [movedWindow], band: sceneBand),
      "Moving a window that contributes a menu-bar shadow invalidates its cached rendering")
check(prefs.sameAnimation && prefs.animation(for: .left) == .curtain && prefs.animation(for: .right) == .curtain,
      "Mirrored curtains are the shared default")
prefs.sharedAnimation = .fade; prefs.linkAnimations(false); prefs.rightAnimation = .hiddenBar
check(prefs.animation(for: .left) == .fade && prefs.animation(for: .right) == .hiddenBar,
      "Native Hidden Bar can be selected independently on the right")
prefs.linkAnimations(true)
check(prefs.animation(for: .right) == .fade && !BarAnimation.choices(for: .left).contains(.hiddenBar),
      "Relinking uses the left style and never offers native hiding on the left")
prefs.animationPace = .originalRight
check(Preferences(store: store).animationPace == .originalRight,
      "The shared A/B timing choice survives a restart")
check(prefs.sameIcons && prefs.icon(for: .left) == prefs.icon(for: .right), "Icons match by default")
check(prefs.sameTrigger && prefs.trigger(for: .left) == .hover && prefs.trigger(for: .right) == .hover, "Reveal defaults are consistent")
prefs.sharedIcon = .hiddenBar
prefs.linkIcons(false)
check(prefs.leftIcon == .hiddenBar && prefs.rightIcon == .hiddenBar, "Unlinking retains the selected artwork")
prefs.rightIcon = .triangle
check(prefs.icon(for: .left) == .hiddenBar && prefs.icon(for: .right) == .triangle, "Independent icon override")
prefs.linkIcons(true)
check(prefs.icon(for: .right) == .hiddenBar, "Relinking takes the left artwork")
prefs.sharedTrigger = .click
check(prefs.trigger(for: .left) == .click && prefs.trigger(for: .right) == .click, "Shared click mode")
prefs.linkTriggers(false)
prefs.leftTrigger = .hover
check(prefs.trigger(for: .left) == .hover && prefs.trigger(for: .right) == .click, "Independent reveal triggers")
prefs.linkTriggers(true)
check(prefs.trigger(for: .right) == .hover, "Relinking retains left reveal choice")

let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("Draplet-Icon-\(UUID().uuidString).png")
let artwork = IndicatorIcons.image(style: .triangle)
let bitmap = NSBitmapImageRep(data: artwork.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: fixture)
let imported = try IndicatorIcons.normalizedIcon(at: fixture)
try FileManager.default.removeItem(at: fixture)
prefs.setCustomIcon(imported, side: nil)
let restored = Preferences(store: store)
check(restored.sharedIcon == .custom && restored.sharedCustomIcon == imported, "Custom icon persists independently of its source file")
check(NSImage(data: restored.customIcon(for: .right)!) != nil, "Shared custom data reaches the right side")
let rendered = IndicatorIcons.image(for: .left, expanded: false, prefs: restored)
let renderedRep = rendered.representations.first as! NSBitmapImageRep
var opaque = 0, transparent = 0
for x in 0..<renderedRep.pixelsWide {
    for y in 0..<renderedRep.pixelsHigh {
        let color = renderedRep.colorAt(x: x, y: y)!
        if color.alphaComponent > 0.5 { opaque += 1 }
        if color.alphaComponent < 0.01 { transparent += 1 }
    }
}
check(opaque > 0 && transparent > 0, "Custom template keeps a real silhouette and transparent padding")
let invalid = IndicatorIcons.image(style: .custom, data: Data([0, 1, 2]))
check(invalid.isValid, "Corrupt stored artwork falls back to a usable indicator")
try Data([0, 1, 2]).write(to: fixture)
var rejected = false
do { _ = try IndicatorIcons.normalizedIcon(at: fixture) } catch { rejected = true }
try FileManager.default.removeItem(at: fixture)
check(rejected, "Invalid custom image is rejected before saving")
restored.removeCustomIcon(side: nil)
let removed = Preferences(store: store)
check(removed.sharedCustomIcon == nil && removed.sharedIcon == .chevron, "Removing custom artwork restores a working preset and persists")

func mask(_ style: BarAnimation, mirrored: Bool = false, progress: Double = 0.5) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 12, bitsPerSample: 8,
                              samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = NSRect(x: 0, y: 0, width: 100, height: 12)
    NSColor.clear.setFill(); rect.fill(using: .copy)
    MenuMaskDrawing.draw(in: rect, progress: progress, style: style, mirrored: mirrored)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}
let leftMask = mask(.curtain), rightMask = mask(.curtain, mirrored: true), fadeMask = mask(.fade)
check(leftMask.colorAt(x: 10, y: 6)!.alphaComponent < 0.01 && leftMask.colorAt(x: 90, y: 6)!.alphaComponent > 0.99,
      "The left curtain reveals toward the notch")
check(rightMask.colorAt(x: 10, y: 6)!.alphaComponent > 0.99 && rightMask.colorAt(x: 90, y: 6)!.alphaComponent < 0.01,
      "The right curtain mirrors the reveal toward the notch")
check(abs(fadeMask.colorAt(x: 10, y: 6)!.alphaComponent - 0.5) < 0.01 && abs(fadeMask.colorAt(x: 90, y: 6)!.alphaComponent - 0.5) < 0.01,
      "Fade changes opacity uniformly instead of wiping")
check(mask(.curtain, progress: 1).colorAt(x: 50, y: 6)!.alphaComponent == 0,
      "A fully revealed cover is completely transparent")
func nativeFixture(light: Bool, transparent: Bool = false) -> CGImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 33, bitsPerSample: 8,
                              samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    for y in 0..<33 {
        for x in 0..<200 {
            let glyph = (y >= 7 && y < 26) && ((x >= 16 && x < 35) || (x > 50 && x % 20 < 5))
            let shade = light ? 0.85 : (0.1 + Double(y) * 0.003)
            let value = glyph ? (light ? 0.0 : 1.0) : shade
            let color = NSColor(deviceRed: value, green: value, blue: value, alpha: glyph || !transparent ? 1 : 0)
            rep.setColor(color, atX: x, y: y)
        }
    }
    return rep.cgImage!
}
let opaqueTreatment = NativeBarTreatment(native: nativeFixture(light: false), logicalWidth: 200)!
let nativeRows = NSBitmapImageRep(cgImage: opaqueTreatment.image)
check(abs(nativeRows.colorAt(x: 0, y: 15)!.redComponent - 0.145) < 0.01,
      "The native opaque treatment is recovered without copying white menu glyphs")
check(nativeRows.colorAt(x: 0, y: 2)!.redComponent < nativeRows.colorAt(x: 0, y: 30)!.redComponent,
      "Native vertical shading keeps its orientation")
check(opaqueTreatment.foreground == .white && NativeBarTreatment(native: nativeFixture(light: true), logicalWidth: 200)!.foreground == .black,
      "Title contrast follows the native Apple glyph in light and dark bars")
let transparentTreatment = NativeBarTreatment(native: nativeFixture(light: false, transparent: true), logicalWidth: 200)!
check(NSBitmapImageRep(cgImage: transparentTreatment.image).colorAt(x: 0, y: 15)!.alphaComponent == 0,
      "A transparent native bar leaves the exact underlying wallpaper visible")
let colorMask = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 12, bitsPerSample: 8,
                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: colorMask)
NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: 100, height: 12).fill(using: .copy)
MenuMaskDrawing.draw(in: NSRect(x: 0, y: 0, width: 100, height: 12), progress: 0.5, style: .fade) {
    NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 100, height: 12).fill(using: .sourceIn)
}
NSGraphicsContext.restoreGraphicsState()
let fadedBackground = colorMask.colorAt(x: 50, y: 6)!
check(fadedBackground.redComponent > 0.99 && fadedBackground.greenComponent < 0.01 && abs(fadedBackground.alphaComponent - 0.5) < 0.01,
      "Fade applies its alpha to the actual background rather than blending in black")

final class TransitionEngine: MenuBarEngine {
    var state = MenuBarEngineState.expanded
    var isArrangementValid = true, isAlwaysHiddenSeparatorPlaced = true
    var pending: ((CollapseResult) -> Void)?
    var collapses = 0
    func collapse(completion: @escaping (CollapseResult) -> Void) { collapses += 1; state = .calibrating; pending = completion }
    func expand() { state = .expanded }
    func updateAlwaysHiddenSection(enabled: Bool, separatorHidden: Bool) {}
    func invalidateLayout() {}
    func finish(_ result: CollapseResult) { state = result == .collapsed ? .collapsed : .expanded; let callback = pending; pending = nil; callback?(result) }
}
final class TestCover: TransitionCover {
    var isVisible = false, progress = 1.0, target = 1.0, duration = 0.0
    var pending: (() -> Void)?
    func prepare(frame: NSRect, progress: Double, style: BarAnimation) { isVisible = true; self.progress = progress }
    func animate(to target: Double, duration: Double, completion: @escaping () -> Void) { self.target = target; self.duration = duration; pending = completion }
    func cancelAnimation() { pending = nil }
    func dismiss() { isVisible = false; cancelAnimation() }
    func finish() { progress = target; let callback = pending; pending = nil; callback?() }
}
var scheduled: [(Double, () -> Void)] = []
func runScheduled(_ delay: Double) {
    let matching = scheduled.filter { $0.0 == delay }; scheduled.removeAll { $0.0 == delay }
    matching.forEach { $0.1() }
}
let visualEngine = TransitionEngine(), visualCover = TestCover()
let transitions = RightMenuTransition(engine: visualEngine, cover: visualCover, schedule: { scheduled.append(($0, $1)) })
var completed = 0
transitions.collapse(style: .curtain, pace: .originalLeft, frame: cover) { _ in completed += 1 }
check(visualEngine.collapses == 0 && visualCover.isVisible && visualCover.duration == 0.16,
      "Icons stay native and stationary until the visual curtain finishes closing")
visualCover.finish()
let staleCollapse = visualEngine.pending
check(visualEngine.collapses == 1, "Native hiding starts only behind a completely opaque cover")
var starts = 0
transitions.expand(style: .fade, pace: .originalRight, frame: cover, onStart: { starts += 1 }) {}
staleCollapse?(.collapsed)
runScheduled(RightMenuTransition.revealPreparation)
check(transitions.expanded && visualCover.target == 1 && visualCover.duration == 0.55 && starts == 1,
      "Reversing a pending hide preserves the chosen style and synchronized reveal timing")
visualCover.finish(); runScheduled(RightMenuTransition.hideSettling)
check(!visualCover.isVisible && completed == 0, "A stale native completion cannot cover or re-hide a newer reveal")
transitions.collapse(style: .fade, pace: .originalRight, frame: cover) { _ in completed += 1 }
visualCover.finish(); visualEngine.finish(.unavailable)
check(transitions.expanded && !visualCover.isVisible && completed == 1, "Native errors fail open without leaving a black cover")
transitions.collapse(style: .curtain, pace: .originalLeft, frame: cover) { _ in completed += 1 }
visualCover.finish(); runScheduled(2)
check(transitions.expanded && visualEngine.state == .expanded && !visualCover.isVisible && completed == 2,
      "A stalled native hide times out, cancels its assertion, and restores the bar")
transitions.collapse(style: .hiddenBar, pace: .originalLeft, frame: cover) { _ in completed += 1 }
check(!visualCover.isVisible && visualEngine.state == .calibrating, "Hidden Bar bypasses every custom visual cover")
visualEngine.finish(.collapsed); runScheduled(0)
check(completed == 3, "Native Hidden Bar completes without a custom settling delay")
print("Passed \(assertions) lifecycle, preference, rendering, and animation checks")
