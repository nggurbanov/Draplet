import AppKit

enum Constant { static let isUsingLTRLanguage = true }
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
print("Passed \(assertions) section and assertion lifecycle checks")
