import AppKit

var assertions = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message); assertions += 1
}
func frame(_ x: CGFloat) -> CGRect { CGRect(x: x, y: 0, width: 20, height: 24) }
// One OS observation serves presentation, backdrop, popup and capture checks.
var snapshotReads = 0, idReads = 0, targetedReads = 0
var observedIDs: [UInt32] = [91]
var dockAlpha = 1.0
let dockRow: () -> NSDictionary = {
    [kCGWindowNumber: 91, kCGWindowOwnerPID: 42, kCGWindowLayer: 20,
     kCGWindowBounds: CGRect(x: 0, y: 0, width: 1470, height: 956).dictionaryRepresentation,
     kCGWindowIsOnscreen: true, kCGWindowAlpha: dockAlpha] as NSDictionary
}
let snapshots = WindowServerSnapshot(read: { snapshotReads += 1; return [dockRow()] },
    readIDs: { idReads += 1; return observedIDs }, readWindow: { _ in targetedReads += 1; return dockRow() })
let sharedWindows = snapshots.current(at: 0)
_ = snapshots.current(at: 0.01); _ = snapshots.current(at: 0.039)
check(snapshotReads == 1 && idReads == 1 && sharedWindows.first?.pid == 42 && sharedWindows.first?.visible == true,
      "Nearby consumers share typed window metadata without duplicate WindowServer reads")
dockAlpha = 0
let fadedDock = snapshots.current(at: 0.05)
check(snapshotReads == 1 && idReads == 2 && targetedReads == 1 && fadedDock.first?.visible == false,
      "A Dock fade with unchanged IDs is observed at 20 Hz without redescribing every window")
observedIDs = [91,92]; _ = snapshots.current(at: 0.1)
check(snapshotReads == 2, "A newly visible window triggers full discovery on the next 50 ms tick")
_ = snapshots.current(at: 0.36)
check(snapshotReads == 3, "Geometry changes without ID changes still have a bounded fallback")
snapshots.invalidate(); _ = snapshots.current(at: 0.361)
check(snapshotReads == 4, "App/Space/display changes invalidate observations immediately")
_ = snapshots.current(at: 0.411, freshGeometry: true)
check(snapshotReads == 5, "The cached-background scene can request current shadow geometry")
var optionReads = 0
var systemOptions: NSApplication.PresentationOptions = []
let optionsCache = PresentationOptionsCache { optionReads += 1; return systemOptions }
_ = optionsCache.current(pid: 10, at: 0); _ = optionsCache.current(pid: 10, at: 0.05)
check(optionReads == 1, "Presentation option metadata is not copied at animation/presentation-watch frequency")
systemOptions = [.hideMenuBar]; optionsCache.invalidate()
check(optionsCache.current(pid: 10, at: 0.06).contains(.hideMenuBar) && optionReads == 2,
      "An AppKit presentation notification bypasses the options cache immediately")
_ = optionsCache.current(pid: 11, at: 0.07)
check(optionReads == 3, "Switching applications never reuses another application's presentation options")
_ = optionsCache.current(pid: 11, at: 0.33)
check(optionReads == 4, "Unannounced presentation changes retain a bounded fallback")
let foregroundA = NSRunningApplication.current
let foregroundB = NSWorkspace.shared.runningApplications.first { $0.processIdentifier != getpid() }!
var foregroundObject: NSRunningApplication? = foregroundA
var resolvedForeground = 0
let foreground = ForegroundApplication(read: { foregroundObject }, resolve: { app in
    resolvedForeground += 1
    return ForegroundApplication.Snapshot(pid: app === foregroundA ? 10 : 20, name: "Fixture")
}, observeSystem: false)
_ = foreground.current(at: 0); _ = foreground.current(at: 0.05); _ = foreground.current(at: 0.1)
check(resolvedForeground == 1, "Fast polling shares foreground scalar properties instead of fetching LaunchServices metadata per frame")
foregroundObject = foregroundB; foreground.observed(foregroundB, at: 0.11)
check(foreground.current(at: 0.11)?.pid == 20 && resolvedForeground == 2, "A foreground KVO event publishes the new PID immediately")
foreground.invalidate(); _ = foreground.current(at: 0.12)
check(resolvedForeground == 3, "Activation notifications refresh foreground metadata immediately")
foreground.observed(nil, at: 0.13)
check(foreground.current(at: 0.14) == nil, "A missing foreground process never returns stale app metadata")
foregroundObject = foregroundA
check(foreground.current(at: 0.64)?.pid == 10 && resolvedForeground == 4, "Missed foreground notifications retain a bounded fallback")
var gate = FrameDeliveryGate()
let firstFrame = gate.begin()!
check(gate.begin() == nil, "A busy main thread cannot accumulate converted capture frames")
gate.reset(); let replacementFrame = gate.begin()!
gate.finish(firstFrame)
check(gate.begin() == nil, "A stale delivery cannot unlock a new stream's pending frame")
gate.finish(replacementFrame)
check(gate.begin() != nil, "Finishing delivery admits the next live frame")
check(LeftCurtain.menuQueryInterval(revealed: false, nearMenu: false, tracking: false, popup: false) == 1,
      "Unused hidden menu geometry is queried at most once per second")
for state in [(true,false,false,false),(false,true,false,false),(false,false,true,false),(false,false,false,true)] {
    check(LeftCurtain.menuQueryInterval(revealed: state.0, nearMenu: state.1, tracking: state.2, popup: state.3) == 0.15,
          "Pointer, revealed, selected and keyboard popup menus retain fast AX queries")
}
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
    func finish(_ value: [MenuBarInventoryItem] = inventory) { let completion = callback; callback = nil; completion?(value) }
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
let invalidSuite = "Draplet.InvalidPreferences.\(UUID().uuidString)"
let invalidStore = UserDefaults(suiteName: invalidSuite)!
invalidStore.set(-1, forKey: "shortcut")
let invalidPrefs = Preferences(store: invalidStore)
check(invalidPrefs.shortcut == 3, "An invalid saved shortcut is disabled before it can index the hotkey table")
invalidPrefs.leftEnabled = false
invalidPrefs.rightEnabled = true
invalidPrefs.sameAnimation = false
invalidPrefs.rightAnimation = .curtain
invalidPrefs.permissionGranted = false
check(!invalidPrefs.needsBackground, "Without Accessibility no hiding engine needs background capture")
invalidPrefs.permissionGranted = true
invalidPrefs.backgroundPermission = false
invalidPrefs.rightAnimation = .hiddenBar
check(!invalidPrefs.requiresSetup, "Native right-only hiding does not demand unused screen-capture permission on every launch")
invalidStore.removePersistentDomain(forName: invalidSuite)
var permissionReplies: [(PermissionState) -> Void] = []
let permissionMonitor = PermissionMonitor { permissionReplies.append($0) }
var permissionChanges: [PermissionState] = []
permissionMonitor.onChange = { permissionChanges.append($0) }
permissionMonitor.poll(at: 0); permissionMonitor.poll(at: 0.25); permissionMonitor.poll(at: 2)
check(permissionReplies.count == 1, "Slow permission checks are single-flight without blocking the UI")
let grantedPermissions = PermissionState(accessibility: true, screenCapture: true)
permissionReplies[0](grantedPermissions)
permissionMonitor.poll(at: 2.1)
check(permissionReplies.count == 2 && permissionChanges == [grantedPermissions], "A completed permission check publishes the current state")
permissionReplies[1](grantedPermissions)
permissionMonitor.poll(at: 2.5)
check(permissionReplies.count == 2 && permissionChanges.count == 1, "Unchanged permissions neither flood queries nor reconfigure the app")
permissionMonitor.poll(at: 3.2)
permissionReplies[2](PermissionState(accessibility: false, screenCapture: true))
check(permissionChanges.count == 2 && !permissionChanges[1].accessibility, "Revoking Accessibility is delivered to the hiding engines")
permissionMonitor.poll(at: 4.3); permissionMonitor.stop(); permissionReplies[3](grantedPermissions)
permissionMonitor.poll(at: 6)
check(permissionChanges.count == 2 && permissionReplies.count == 4, "Termination discards late permission replies and stops polling")
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
var fullscreenQueries: [(pid_t, (Bool) -> Void)] = []
let foregroundFullscreen = ForegroundFullscreen { pid, completion in fullscreenQueries.append((pid, completion)) }
check(!foregroundFullscreen.current(pid: 85836, at: 0) && fullscreenQueries.count == 1,
      "Reading another app's fullscreen state starts one asynchronous AX request")
fullscreenQueries[0].1(true)
check(foregroundFullscreen.current(pid: 85836, at: 0.2) && fullscreenQueries.count == 1,
      "Native fullscreen remains known without querying AX on every animation frame")
check(foregroundFullscreen.current(pid: 9309, at: 0.21) && fullscreenQueries.count == 2,
      "Switching apps retains fullscreen suppression until the new window is checked")
fullscreenQueries[1].1(false)
check(!foregroundFullscreen.current(pid: 9309, at: 0.24),
      "A confirmed desktop window releases fullscreen suppression")
check(foregroundFullscreen.current(pid: 85836, at: 0.3) && fullscreenQueries.count == 3,
      "Returning to a known fullscreen app suppresses covers before a fresh AX response arrives")
_ = foregroundFullscreen.current(pid: 9309, at: 0.31)
check(fullscreenQueries.count == 3, "Rapid switches cannot queue parallel AX requests")
fullscreenQueries[2].1(true)
check(!foregroundFullscreen.current(pid: 9309, at: 0.32) && fullscreenQueries.count == 4,
      "An old app's late fullscreen response cannot suppress the current desktop")
fullscreenQueries[3].1(false)
foregroundFullscreen.invalidate()
_ = foregroundFullscreen.current(pid: 9309, at: 0.33)
fullscreenQueries[4].1(true)
check(foregroundFullscreen.current(pid: 9309, at: 0.34),
      "A Space change refreshes fullscreen state even when the foreground PID stays the same")
var warmQueries: [(pid_t, (Bool) -> Void)] = []
let warmedFullscreen = ForegroundFullscreen { pid, completion in warmQueries.append((pid, completion)) }
warmedFullscreen.prewarm([5400, 5400]); warmedFullscreen.prewarm([5400])
check(warmQueries.count == 1, "Startup background fullscreen checks are deduplicated")
warmQueries[0].1(true)
check(warmedFullscreen.current(pid: 5400, at: 0) && warmQueries.count == 2,
      "An app already fullscreen at startup is suppressed on its first activation, before revalidation")
warmQueries[1].1(false)
warmedFullscreen.prewarm([86020])
_ = warmedFullscreen.current(pid: 86020, at: 0.1)
warmQueries[3].1(true); warmQueries[2].1(false)
check(warmedFullscreen.current(pid: 86020, at: 0.2),
      "A late startup snapshot cannot overwrite a newer foreground fullscreen result")
_ = warmedFullscreen.current(pid: 5400, at: 0.3)
warmQueries[4].1(false)
warmedFullscreen.forget(pid: 86020)
check(!warmedFullscreen.current(pid: 86020, at: 0.4),
      "Terminated processes cannot leave a fullscreen cache entry for a reused PID")
let mainDisplay = CGRect(x: 0, y: 0, width: 1470, height: 956)
let secondDisplay = CGRect(x: -1920, y: -124, width: 1920, height: 1080)
func overviewWindow(pid: pid_t = 42, layer: Int = 20, frame: CGRect = mainDisplay, alpha: Double = 1) -> [String: Any] {
    [kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer,
     kCGWindowBounds as String: frame.dictionaryRepresentation, kCGWindowAlpha as String: alpha]
}
func overview(_ windows: [[String: Any]]) -> Bool {
    SystemPresentation.isOverview(windows: windows, dockPID: 42, displays: [mainDisplay, secondDisplay])
}
check(overview([overviewWindow()]), "A real screen-sized layer-20 Dock canvas suspends background capture")
check(overview([overviewWindow(layer: 18)]), "The layer-18 overview canvas is also recognized")
check(overview([overviewWindow(frame: secondDisplay)]), "Overview detection handles a display with negative global coordinates")
check(!overview([overviewWindow(frame: CGRect(x: 16, y: 300, width: 110, height: 140))]),
      "Stage Manager thumbnails do not suspend background matching")
check(!overview([overviewWindow(frame: CGRect(x: 0, y: 880, width: 1470, height: 76))]),
      "The ordinary Dock does not suspend background matching")
check(!overview([overviewWindow(pid: 43), overviewWindow(layer: 24), overviewWindow(alpha: 0)]),
      "Other apps, menu-bar layers and invisible Dock windows cannot impersonate an overview")
check(!overview([]), "Dismissing the Dock overview allows background capture to resume")
// Replay the actual game's WindowServer state. Its status-level canvas covers
// Menubar, although menuBarVisible is true and systemPresentationOptions is 0.
let gameFixture = try! JSONSerialization.jsonObject(with: Data(contentsOf:
    URL(fileURLWithPath: "Tests/Fixtures/fullscreen-game.json"))) as! [String: Any]
let gamePID = gameFixture["frontPID"] as! pid_t
let gameWindows = (gameFixture["windows"] as! [[String: Any]]).map { row in
    [kCGWindowOwnerPID as String: row["pid"]!, kCGWindowLayer as String: row["layer"]!,
     kCGWindowBounds as String: row["frame"]!, kCGWindowAlpha as String: row["alpha"]!,
     kCGWindowIsOnscreen as String: row["onScreen"]!]
}
func suppress(_ windows: [[String: Any]], frontPID: pid_t = gamePID,
              options: NSApplication.PresentationOptions = []) -> Bool {
    SystemPresentation.isActive(windows: windows, dockPID: 42, frontPID: frontPID,
                                displays: [mainDisplay, secondDisplay], menuBarDisplay: mainDisplay, options: options)
}
check(gameFixture["appKitMenuBarVisible"] as? Bool == true && gameFixture["systemPresentationOptions"] as? Int == 0 && suppress(gameWindows),
      "The captured Minecraft canvas suppresses overlays even when both AppKit hints miss the fullscreen game")
check(!suppress(gameWindows, frontPID: 9309),
      "An inactive fullscreen game does not suppress Draplet over the foreground desktop app")
check(!suppress([overviewWindow(pid: gamePID, layer: 0)]),
      "An ordinary maximized foreground window below Menubar keeps Draplet available")
check(!suppress([overviewWindow(pid: gamePID, layer: 25, frame: CGRect(x: 824, y: 0, width: 373, height: 32))]),
      "A notch or menu-bar overlay is not mistaken for a fullscreen game")
check(!suppress([overviewWindow(pid: gamePID, layer: 25, frame: secondDisplay)]),
      "A fullscreen window on another display does not suppress the primary display's menu bar")
var hiddenGame = overviewWindow(pid: gamePID, layer: 25)
hiddenGame[kCGWindowIsOnscreen as String] = false
check(!suppress([hiddenGame, overviewWindow(pid: gamePID, layer: 25, alpha: 0)]),
      "Invisible and offscreen fullscreen windows cannot suppress presentation")
check(suppress([], options: [.hideDock, .hideMenuBar]) && suppress([], options: [.fullScreen, .autoHideMenuBar]),
      "Native hidden-menu presentation modes also suppress Draplet without requiring a game canvas")
check(!suppress([], options: [.fullScreen]),
      "The accessory process's fullscreen hint alone does not suppress Draplet")
let nativeFixture = try! JSONSerialization.jsonObject(with: Data(contentsOf:
    URL(fileURLWithPath: "Tests/Fixtures/fullscreen-fladder.json"))) as! [String: Any]
let nativeWindows = (nativeFixture["windows"] as! [[String: Any]]).map { row in
    [kCGWindowOwnerPID as String: row["pid"]!, kCGWindowLayer as String: row["layer"]!,
     kCGWindowBounds as String: row["frame"]!, kCGWindowAlpha as String: row["alpha"]!,
     kCGWindowIsOnscreen as String: row["onScreen"]!]
}
let nativeSuppressed = SystemPresentation.isActive(windows: nativeWindows, dockPID: 42,
    frontPID: nativeFixture["frontPID"] as! pid_t, displays: [mainDisplay, secondDisplay],
    menuBarDisplay: mainDisplay, options: [], nativeFullscreen: nativeFixture["axFullScreen"] as! Bool)
check(nativeFixture["appKitMenuBarVisible"] as? Bool == true && nativeSuppressed,
      "The captured Fladder AX fullscreen state withdraws all overlays despite normal accessory-process menu hints")
check(!SystemPresentation.isActive(windows: nativeWindows, dockPID: 42,
    frontPID: nativeFixture["frontPID"] as! pid_t, displays: [mainDisplay, secondDisplay], menuBarDisplay: mainDisplay),
      "Returning from native fullscreen releases suppression without mistaking ordinary Fladder windows for a game")
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
    // Capture the real setter, not a dirty flag cleared by displayIfNeeded.
    final class RedrawCounter: NSView {
        var requests = 0
        override var needsDisplay: Bool {
            get { super.needsDisplay }
            set { if newValue { requests += 1 }; super.needsDisplay = newValue }
        }
    }
    let oldContent = curtain.clickPanel!.contentView!
    let counter = RedrawCounter(frame: oldContent.bounds)
    curtain.clickPanel!.contentView = counter
    let normalized = curtain.clickPanel!.frame
    curtain.clickPanel!.setFrame(NSRect(x: floor(normalized.minX), y: floor(normalized.minY), width: normalized.width, height: normalized.height), display: false)
    let beforeRequests = counter.requests
    curtain.updateClickTarget()
    check(counter.requests == beforeRequests,
          "WindowServer-rounded coordinates must not schedule another indicator repaint while stationary")
    curtain.clickPanel!.contentView = oldContent
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
    curtain.currentPID = 0
    curtain.updateTitle(presentationActive: { nativeSuppressed })
    check(curtain.presentationSuppressed && !testPanel.isVisible && curtain.clickPanel?.isVisible == false,
          "The left activation callback withdraws title and arrow before painting a fullscreen app, even before the shared observer")
    curtain.setPresentationSuppressed(nativeSuppressed)
    curtain.syncVisibility(); curtain.updateClickTarget(); curtain.tick()
    check(!testPanel.isVisible && curtain.clickPanel?.isVisible == false,
          "Native fullscreen removes both the drawn app title and its toggle; visibility polling cannot bring them back")
    curtain.setPresentationSuppressed(false)
    check(testPanel.isVisible && curtain.clickPanel?.isVisible == true,
          "Restoring the desktop returns both left windows after presentation is allowed")
    curtain.stop()
}
let emptyItems = Items(), emptyReader = Inventory(), emptyBridge = Visibility()
let emptyEngine = NativeVisibilityEngine(items: emptyItems, inventory: emptyReader, visibility: emptyBridge,
    ownBundleIdentifier: "own", itemFrame: { _ in frame(600) }, isLTR: { true })
var emptyResult: CollapseResult?
emptyEngine.collapse { emptyResult = $0 }
emptyReader.finish([])
check(emptyResult == .unavailable && emptyBridge.callback == nil && emptyEngine.state == .expanded,
      "An empty AX inventory fails open instead of hiding every third-party icon")
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
// The histogram median must preserve the original sampled, upper-median rule.
for values: [UInt8] in [[3,250,80,160,40], [20,190]] {
    let width = values.count * 4 - 1
    var bytes = [UInt8](repeating: 0, count: width * 4)
    for x in 0..<width { bytes[x*4] = values[x/4]; bytes[x*4+1] = 36; bytes[x*4+2] = 72; bytes[x*4+3] = 255 }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let source = CGImage(width: width, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width*4,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let treatment = NativeBarTreatment(native: source, logicalWidth: CGFloat(width))!
    let output = CFDataGetBytePtr(treatment.image.dataProvider!.data!)!
    check(output[0] == values.sorted()[values.count/2] && output[1] == 36 && output[2] == 72 && output[3] == 255,
          "Histogram reconstruction exactly preserves sampled medians for odd/even counts and partial scanlines")
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
let transitionalNativeBar = NSBitmapImageRep(data: try! Data(contentsOf:
    URL(fileURLWithPath: "Tests/Fixtures/transitional-native-bar.png")))!.cgImage!
let transitionalTreatment = NativeBarTreatment(native: transitionalNativeBar, logicalWidth: 1470)!
check(transitionalTreatment.isClear,
      "The captured fullscreen treatment is valid transparency; recovery must distinguish it from the returned desktop")
var nativeRecovery = NativeBarRecovery()
// Replay the measured native fullscreen fade. A complete first frame at 167 ms
// had alpha 30; the bar did not reach 255 until roughly 1.28 seconds.
let recoveryTrace: [(Double, UInt8)] = [(0.1672, 30), (0.2269, 48), (0.2897, 60), (0.4, 78),
                                      (0.4949, 107), (0.6246, 141), (0.7165, 170), (0.8885, 213), (1.2777, 255)]
check(recoveryTrace.allSatisfy { !nativeRecovery.accepts(opacity: Data([$0.1]), at: $0.0) },
      "No changing frame in the measured fullscreen return fade can be frozen into Cached mode")
check(!nativeRecovery.accepts(opacity: Data([255]), at: 1.3) && nativeRecovery.accepts(opacity: Data([255]), at: 1.4),
      "Recovery requires stable native opacity across separate rendered frames, then permits presentation")
var transparentRecovery = NativeBarRecovery()
check(!transparentRecovery.accepts(opacity: transitionalTreatment.opacitySignature, at: 0)
      && transparentRecovery.accepts(opacity: transitionalTreatment.opacitySignature, at: 0.11),
      "Genuinely transparent native bars remain supported once their opacity settles")
check(opaqueTreatment.opacitySignature == NativeBarTreatment(native: nativeFixture(light: true), logicalWidth: 200)!.opacitySignature,
      "Recovery ignores changing background colors and foreground contrast, preserving Live wallpaper support")
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
let actualRightCover = RightMenuCover()
actualRightCover.prepare(frame: NSRect(x: -4000, y: 0, width: 300, height: 32), progress: 0, style: .curtain)
check(NSApp.windows.first(where: { $0.contentView is RightMenuCover.View })?.animationBehavior == NSWindow.AnimationBehavior.none,
      "The actual right panel disables AppKit ordering fades that compete with fast curtain reversals")
let actualRightPanel = NSApp.windows.first(where: { $0.contentView is RightMenuCover.View })!
// A fullscreen game can be ordered above a still-logically-visible cover.
// A background refresh repeats the unchanged `false` suppression state; it
// must not order that cover above the game again.
actualRightPanel.orderOut(nil)
actualRightCover.setPresentationSuppressed(false)
check(!actualRightPanel.isVisible,
      "Repeating the current presentation state does not raise a retained cover over another app")
actualRightCover.setPresentationSuppressed(true)
check(actualRightCover.isVisible && !actualRightPanel.isVisible,
      "The right transition retains its logical cover while its real window is absent from Mission Control")
actualRightCover.prepare(frame: NSRect(x: -4000, y: 0, width: 300, height: 32), progress: 0, style: .curtain)
check(!actualRightPanel.isVisible, "A pending native transition cannot order a suppressed right cover back in")
actualRightCover.setPresentationSuppressed(false)
check(actualRightPanel.isVisible, "The retained right cover returns only after desktop presentation resumes")
actualRightCover.setPresentationSuppressed(true); actualRightCover.dismiss(); actualRightCover.setPresentationSuppressed(false)
check(!actualRightCover.isVisible && !actualRightPanel.isVisible,
      "A cover dismissed during Mission Control is not resurrected on exit")
actualRightCover.stop()
// A native assertion callback is not a WindowServer presentation fence. Reversing
// an expansion can finish the assertion while the previous native show is still
// queued. The fully closed cover must outlive that late presentation.
transitions.expand(style: .curtain, pace: .originalLeft, frame: cover) {}
runScheduled(RightMenuTransition.revealPreparation); visualCover.finish()
transitions.collapse(style: .curtain, pace: .originalLeft, frame: cover) { _ in }
visualCover.finish(); visualEngine.finish(.collapsed)
runScheduled(RightMenuTransition.hideSettling)
check(!transitions.expanded && visualCover.isVisible && visualCover.progress == 0,
      "A closed curtain keeps late native show/hide frames covered after the assertion completes")
transitions.expand(style: .curtain, pace: .originalLeft, frame: cover) {}
check(visualCover.isVisible && visualCover.progress == 0,
      "Reopening reuses the opaque closed cover before releasing native hiding")
runScheduled(RightMenuTransition.revealPreparation); visualCover.finish()
check(!visualCover.isVisible && transitions.expanded,
      "The retained curtain is removed after a completed reveal")
transitions.collapse(style: .curtain, pace: .originalLeft, frame: cover) { _ in }
visualCover.finish(); visualEngine.finish(.collapsed); runScheduled(RightMenuTransition.hideSettling)
transitions.cancelAndExpand()
check(!visualCover.isVisible && visualEngine.state == .expanded,
      "Pausing or reconfiguring still removes a retained closed curtain and releases native hiding")
var captureRetry = CaptureRetryPolicy()
check(captureRetry.failed(permissionGranted: false) == nil, "Denied capture permission never triggers an automatic retry")
check(captureRetry.failed(permissionGranted: true) == 0.5, "A transient interruption gets a short first retry")
check(captureRetry.failed(permissionGranted: true) == 1.5, "Consecutive capture failures back off")
check(captureRetry.failed(permissionGranted: true) == nil, "Repeated failures stop instead of creating an infinite capture loop")
captureRetry.reset()
check(captureRetry.failed(permissionGranted: true) == 0.5, "A successful capture or explicit restart resets retry allowance")
let updateSelectors = ["supportsGentleScheduledUpdateReminders", "standardUserDriverShouldHandleShowingScheduledUpdate:andInImmediateFocus:",
    "standardUserDriverWillHandleShowingUpdate:forUpdate:state:", "standardUserDriverDidReceiveUserAttentionForUpdate:", "standardUserDriverWillFinishUpdateSession"]
check(updateSelectors.allSatisfy { AppUpdater.shared.responds(to: NSSelectorFromString($0)) },
      "Sparkle can reach every native scheduled-update reminder delegate callback")
// Reminder deferral survives restarts, but never suppresses a newer build.
let reminderNow = Date(timeIntervalSince1970: 1_800_000_000)
var reminder = UpdateReminderPolicy()
check(!reminder.isDue(at: reminderNow, presentationSuppressed: false), "No reminder without a staged version")
reminder.receive("11")
check(reminder.isDue(at: reminderNow, presentationSuppressed: false), "A staged update prompts immediately")
check(!reminder.isDue(at: reminderNow, presentationSuppressed: true), "Fullscreen and overview defer update prompts")
reminder.deferOneHour(from: reminderNow)
check(!reminder.isDue(at: reminderNow.addingTimeInterval(3599), presentationSuppressed: false), "Remind later means a full hour")
check(reminder.isDue(at: reminderNow.addingTimeInterval(3600), presentationSuppressed: false), "Reminder becomes due at one hour")
reminder.receive("11")
check(reminder.deferredUntil != nil, "Resuming the same update preserves deferral")
reminder.receive("12")
check(reminder.isDue(at: reminderNow, presentationSuppressed: false), "A newer build gets its own prompt")
// Exercise the real Settings window, including delegate delivery on close.
// Keep it offscreen so the test does not put a second Settings window on the desktop.
let settings = SettingsController(prefs: prefs, requestPermission: {}, replaceHiddenBar: {},
                                  revealBoth: {}, pause: {}, previewAnimations: {})
check(settings.window == nil, "Background startup does not instantiate Settings hosting views")
settings.prepareWindow()
settings.window?.setFrameOrigin(NSPoint(x: -4000, y: 0))
check(app.activationPolicy() == .accessory, "Constructing Settings alone does not add a Dock icon")
settings.show()
check(app.activationPolicy() == .regular, "Opening Settings adds the app to the Dock")
settings.window?.miniaturize(nil)
check(app.activationPolicy() == .regular, "Minimized Settings keeps its Dock icon so it can be restored")
settings.window?.close()
check(app.activationPolicy() == .accessory, "Closing minimized Settings removes its Dock icon")
check(settings.window == nil, "Closing Settings releases its hidden window and hosting hierarchy")
settings.navigation.page = .right
settings.prepareWindow(); settings.window?.setFrameOrigin(NSPoint(x: -4000, y: 0))
settings.show()
check(settings.navigation.page == .right, "Recreating Settings retains navigation state")
check(app.activationPolicy() == .regular, "Reopening Settings restores the Dock icon")
settings.window?.close()
check(app.activationPolicy() == .accessory, "Closing reopened Settings returns Draplet to menu-bar-only mode")
print("Passed \(assertions) lifecycle, preference, rendering, and animation checks")
