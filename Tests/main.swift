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
print("Passed \(assertions) lifecycle, preference, and custom-icon checks")
