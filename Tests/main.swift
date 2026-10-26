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
    var readFrame:((NSStatusItem)->CGRect?)?
    func statusItemFrame(_ item:NSStatusItem) -> CGRect? {
        if let readFrame { return readFrame(item) }
        return item.button?.window?.frame
    }
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
    var systemItems: [Int] = []
    var activations = 0
    func activate(allowedSystemItems: [Int], allowedBundleIdentifiers: [String], completion: @escaping (Result<NativeVisibilityAssertion, Error>) -> Void) {
        activations += 1
        allowed = allowedBundleIdentifiers; callback = completion
        systemItems = allowedSystemItems
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
invalidPrefs.rightRevealMode = .menuBar
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
    curtain.setPresentationSuppressed(false, presentationActive: { false })
    check(testPanel.isVisible && curtain.clickPanel?.isVisible == true,
          "Restoring the desktop returns both left windows after presentation is allowed")
    curtain.stop()
}
let emptyItems = Items(), emptyReader = Inventory(), emptyBridge = Visibility()
do {
    let slot = CGRect(x:600,y:0,width:42,height:33),point = CGPoint(x:621,y:16)
    var policy = StatusItemClickPolicy()
    func route(_ type:CGEventType,_ point:CGPoint,flags:CGEventFlags = [],programmatic:Bool = false,frame:CGRect? = slot,blocked:Bool = true) -> StatusItemClickPolicy.Result {
        policy.route(type,point:point,flags:flags,programmatic:programmatic,frame:frame,obstructed:blocked)
    }
    if case .pass = route(.leftMouseDown,point,blocked:false) {} else { preconditionFailure("Unobstructed native down intercepted") }
    check({ if case .pass = route(.leftMouseUp,point) { return true };return false }(),"Unobstructed foreign native status icons retain their original delivery")
    check({ if case .pass = route(.leftMouseDown,CGPoint(x:650,y:16)) { return true };return false }(),"A neighbouring status icon is never claimed")
    check({ if case .consume = route(.leftMouseDown,point) { return true };return false }(),"An obstructed owned arrow claims its down before the foreign window")
    check({ if case let .click(.left,flags) = route(.leftMouseUp,point,flags:.maskAlternate) { return flags.contains(.maskAlternate) };return false }(),"The balanced release opens Draplet once and preserves Option")
    check({ if case .pass = route(.leftMouseUp,point) { return true };return false }(),"A second release cannot toggle the arrow again")
    check({ if case .pass = route(.leftMouseDown,point,flags:.maskCommand) { return true };return false }(),"Command status-item drags keep their native mouse-down")
    check({ if case .pass = route(.leftMouseUp,point,flags:.maskCommand) { return true };return false }(),"Command status-item drags keep their native release")
    check({ if case .pass = route(.leftMouseDown,point,programmatic:true) { return true };return false }(),"Tagged native placement cannot become an ordinary arrow click")
    _ = route(.leftMouseDown,point);_ = route(.leftMouseDragged,CGPoint(x:700,y:60))
    check({ if case .consume = route(.leftMouseUp,CGPoint(x:700,y:60)) { return true };return false }(),"Dragging off the arrow cancels its action without leaking an orphan release")
    _ = route(.rightMouseDown,point)
    check({ if case .click(.right,_) = route(.rightMouseUp,point) { return true };return false }(),"Right-click retains the Draplet context-menu action")
    _ = route(.leftMouseDown,point);policy.invalidate()
    check({ if case .consume = route(.leftMouseUp,point) { return true };return false }(),"Presentation or Command changes cancel a pending click")
    _ = route(.leftMouseDown,point)
    check({ if case .consume = route(.leftMouseUp,point,frame:nil) { return true };return false }(),"A vanished native arrow never activates another control on release")
    func window(_ pid:pid_t,_ layer:Int) -> WindowServerSnapshot.Window {
        WindowServerSnapshot.Window([kCGWindowOwnerPID:pid,kCGWindowNumber:1,kCGWindowLayer:layer,
                                     kCGWindowBounds:slot.dictionaryRepresentation,kCGWindowAlpha:1] as NSDictionary)!
    }
    check(StatusItemClickPolicy.obstructed(point,windows:[window(43,26)],owner:42),"A foreign status hit window is recognized above the native bar")
    check(!StatusItemClickPolicy.obstructed(point,windows:[window(42,27),window(43,24)],owner:42),"Own covers and lower windows do not steal native delivery")
    check(!StatusItemClickPolicy.obstructed(point,windows:[window(43,26)],owner:43,routerOwner:42,eligibleOwners:[43]),
          "A visible publisher keeps clicks on its own custom hit window")
    check(StatusItemClickPolicy.obstructed(point,windows:[window(43,26)],owner:44,routerOwner:42,eligibleOwners:[43]),
          "A managed foreign publisher cannot intercept another rendered status icon")
    check(!StatusItemClickPolicy.obstructed(point,windows:[window(43,26)],owner:44,routerOwner:42,eligibleOwners:[45]),
          "Unrelated application overlays are not treated as hidden status-item windows")
    check(!StatusItemClickPolicy.obstructed(point,windows:[window(42,27),window(43,26)],owner:44,routerOwner:42,eligibleOwners:[43]),
          "Pocket's own frontmost down-arrow receives its click instead of the native item below")
    check(!StatusItemClickPolicy.obstructed(point,windows:[window(45,101),window(43,26)],owner:44,routerOwner:42,eligibleOwners:[43]),
          "An actual popup above the menu bar retains native input")
    check(StatusItemClickPolicy.canClaimToggle(point,windows:[],owner:42),
          "The owned toggle can handle an ordinary press without the system bezel")
    check(StatusItemClickPolicy.canClaimToggle(point,windows:[window(43,26)],owner:42),
          "A stale foreign hit window does not restore the toggle's native press bezel")
    check(!StatusItemClickPolicy.canClaimToggle(point,windows:[window(42,27)],owner:42),
          "The toggle's cached rectangle cannot steal input from a frontmost owned control")
    check(!StatusItemClickPolicy.canClaimToggle(point,windows:[window(43,101)],owner:42),
          "The toggle cannot steal input from an actual popup above it")
    _ = policy.route(.leftMouseDown,point:point,flags:[],programmatic:false,frame:slot,identity:"first",obstructed:true)
    check({ if case .consume = policy.route(.leftMouseUp,point:point,flags:[],programmatic:false,frame:slot,identity:"second",obstructed:true) { return true };return false }(),
          "A different publisher in the same rectangle cannot inherit a swallowed mouse-down")
    _ = policy.route(.leftMouseDown,point:point,flags:[],programmatic:false,frame:slot,identity:"first",obstructed:true)
    check({ if case .consume = policy.route(.leftMouseUp,point:point,flags:[],programmatic:false,frame:slot.offsetBy(dx:1,dy:0),identity:"first",obstructed:true) { return true };return false }(),
          "A reflow during the held click cancels activation even when the two slots overlap")
}
let settlingItems = Items(), settlingReader = Inventory(), settlingVisibility = Visibility()
var settlingBoundary = frame(900)
let startupBoundaryEngine = NativeVisibilityEngine(items:settlingItems,inventory:settlingReader,visibility:settlingVisibility,
                                           ownBundleIdentifier:"own",itemFrame:{ _ in settlingBoundary },isLTR:{ true })
startupBoundaryEngine.collapse { _ in }
settlingBoundary = frame(600)
settlingReader.finish([MenuBarInventoryItem(bundleIdentifier:"com.apple.TextInputMenuAgent",frame:frame(700)),
                       MenuBarInventoryItem(bundleIdentifier:"hidden",frame:frame(500))])
check(settlingVisibility.allowed.contains("com.apple.TextInputMenuAgent") && !settlingVisibility.allowed.contains("hidden"),
      "Startup reflow keeps the language item right of the settled arrow visible")
settlingVisibility.finish(.success(Handle()))
startupBoundaryEngine.expand()
do {
    let providerItems = Items(),providerReader = Inventory(),providerBridge = Visibility()
    providerItems.readFrame = { _ in frame(610) }
    let providerEngine = NativeVisibilityEngine(items:providerItems,inventory:providerReader,visibility:providerBridge,
                                               ownBundleIdentifier:"own",isLTR:{ true })
    providerEngine.collapse { _ in }
    providerReader.finish([MenuBarInventoryItem(bundleIdentifier:"com.apple.TextInputMenuAgent",frame:frame(650)),
                           MenuBarInventoryItem(bundleIdentifier:"hidden",frame:frame(500))])
    check(providerBridge.allowed.contains("com.apple.TextInputMenuAgent") && !providerBridge.allowed.contains("hidden"),
          "The production engine uses the controller's hosted boundary instead of the stale NSStatusItem backing window")
    providerBridge.finish(.success(Handle()));providerEngine.expand()
    providerItems.readFrame = { _ in nil }
    var result:CollapseResult?
    providerEngine.collapse { result = $0 }
    providerReader.finish([MenuBarInventoryItem(bundleIdentifier:"com.apple.TextInputMenuAgent",frame:frame(650))])
    check(result == .unavailable && providerBridge.callback == nil,
          "Missing verified hosting geometry fails open rather than guessing the language item's section")
}
do {
    let reconciled = HostedMenuBarInventoryPolicy.reconcile([
        MenuBarInventoryItem(bundleIdentifier:"input",frame:frame(1196)),
        MenuBarInventoryItem(bundleIdentifier:"overflow",frame:frame(800)),
        MenuBarInventoryItem(bundleIdentifier:"siblings",frame:frame(900)),
        MenuBarInventoryItem(bundleIdentifier:"siblings",frame:frame(1000))
    ],rendered:[MenuBarInventoryItem(bundleIdentifier:"input",frame:frame(1404)),
                MenuBarInventoryItem(bundleIdentifier:"siblings",frame:frame(1200)),
                MenuBarInventoryItem(bundleIdentifier:"siblings",frame:frame(1450))])
    let resolved = MenuBarLayoutResolver.resolve(inventory:reconciled,separatorFrame:frame(1321),alwaysHiddenSeparatorFrame:nil,isLTR:true,excludingBundle:nil)
    check(resolved.bundles(in:[.visible]).contains("input"),"The input source is classified by its rendered slot even when its own AX backing position is on the other side")
    check(resolved.bundles(in:[.visible]).contains("siblings") && reconciled.filter { $0.bundleIdentifier == "siblings" }.count == 2,
          "Physical sibling positions replace the publisher's stale coordinate map as a group")
    check(resolved.bundles(in:[.hidden]).contains("overflow"),"An unrendered overflow publisher retains its existing section metadata")
}
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
// A pocket must borrow exposure without teaching the layout resolver that
// temporarily reflowed icons were rearranged by the user.
engine.collapse { _ in }; reader.finish(); bridge.finish(.success(Handle()))
let pocketLayout = engine.layout
var pocketSucceeded: Bool?
engine.showPocketBundle("hidden") { pocketSucceeded = $0 }
check(bridge.allowed.contains("hidden") && bridge.allowed.contains("visible") && bridge.allowed.contains("own"),
      "Pocket exposes the selected bundle while preserving visible items and its own arrow")
let pocketAssertion = Handle(); bridge.finish(.success(pocketAssertion))
check(pocketSucceeded == true && engine.state == .collapsed && engine.layout == pocketLayout,
      "Temporary exposure retains the collapsed state and original section arrangement")
engine.showPocketBundle(nil) { _ in }
check(!bridge.allowed.contains("hidden") && bridge.allowed.contains("visible"), "Closing Pocket restores the original visible section")
bridge.finish(.success(Handle()))
check(pocketAssertion.invalidated && reader.callback == nil, "Restoring Pocket releases its assertion without reading temporary AX positions")
var cancelledPocket: Bool?
engine.showPocketBundle("hidden") { cancelledPocket = $0 }
let delayedPocket = bridge.callback
engine.expand()
let stalePocket = Handle(); delayedPocket?(.success(stalePocket))
check(cancelledPocket == false && stalePocket.invalidated && engine.state == .expanded,
      "A pending pocket exposure answers cancellation and cannot re-hide icons after pause/expand")
engine.collapse { _ in }; reader.finish(); bridge.finish(.success(Handle()))
engine.showPocketBundle("hidden") { _ in }; bridge.finish(.failure(NSError(domain: "PocketTest", code: 1)))
check(engine.state == .expanded, "A failed temporary exposure releases restrictions and reports the actual expanded state")
let pinSuite = "Draplet.PocketPlacement.\(UUID().uuidString)"
let pinStore = UserDefaults(suiteName:pinSuite)!
let compatibilityKey = "org.drapletqa.compatibility|slot:0/1"
check(CompatibilityMenuPolicy.validated([compatibilityKey:1,"bad":1,"com.apple.MenuBarAgent|slot:0/1":1,"org.example|slot:0/1":99]) == [compatibilityKey:1], "Compatibility placements reject invalid identities and shared system controls")
let compatibilityIdentifier = CompatibilityMenuPolicy.identifier(compatibilityKey)
check(compatibilityIdentifier != CompatibilityMenuPolicy.identifier(compatibilityKey + "-other"), "Compatibility slots have separate stable native identities")
let compatibilitySlot = CGRect(x:900,y:0,width:32,height:33)
let compatibilityElement = AXUIElementCreateSystemWide()
let compatibilityHost = PocketInventory.HostedItem(owner:42,element:compatibilityElement,frame:compatibilitySlot,identifier:compatibilityIdentifier)
let compatibilityBindings = ["source":compatibilityIdentifier]
check(CompatibilityMenuPolicy.frames(bindings:compatibilityBindings,host:.init(items:[compatibilityHost],overflow:nil),owner:42) == ["source":compatibilitySlot], "Only an actually rendered owned slot can replace the original frame")
check(CompatibilityMenuPolicy.frames(bindings:compatibilityBindings,host:.init(items:[compatibilityHost],overflow:nil),owner:43).isEmpty, "An unrelated publisher cannot impersonate a compatibility slot")
check(CompatibilityMenuPolicy.frames(bindings:compatibilityBindings,host:.init(items:[compatibilityHost],overflow:compatibilitySlot),owner:42).isEmpty, "A compatibility slot behind native overflow remains in Pocket")
let paddedNeighbour = PocketInventory.HostedItem(owner:42,element:compatibilityElement,frame:CGRect(x:928.5,y:0,width:42,height:33),identifier:"Draplet.Toggle")
check(CompatibilityMenuPolicy.frames(bindings:compatibilityBindings,host:.init(items:[compatibilityHost,paddedNeighbour],overflow:nil),owner:42) == ["source":compatibilitySlot], "Owned hit padding can overlap by 3.5pt without hiding a real compatibility glyph")
let parkedNeighbour = PocketInventory.HostedItem(owner:42,element:compatibilityElement,frame:compatibilitySlot,identifier:"another-control")
check(CompatibilityMenuPolicy.frames(bindings:compatibilityBindings,host:.init(items:[compatibilityHost,parkedNeighbour],overflow:nil),owner:42).isEmpty, "A parked compatibility slot over another control is never treated as rendered")
let compatibilityPrefs = Preferences(store:pinStore)
compatibilityPrefs.setCompatibilityItem(compatibilityKey,section:.hidden)
check(Preferences(store:pinStore).compatibilityMenuItems[compatibilityKey] == MenuBarSection.hidden.rawValue, "Compatibility returns survive relaunch with their original source identity")
compatibilityPrefs.setPocketPin("org.drapletqa.compatibility",pinned:true)
check(compatibilityPrefs.compatibilityMenuItems.isEmpty, "Pinning removes that app's compatibility slots instead of leaving duplicates")
pinStore.set(["fixture","fixture","","com.apple.controlcenter"],forKey:"pinnedPocketBundles")
let pinPrefs = Preferences(store:pinStore)
check(pinPrefs.pinnedPocketBundles == ["fixture"], "Saved Pocket pins deduplicate and exclude native system controls")
pinPrefs.setPocketPin("second",pinned:true); pinPrefs.setPocketPin("second",pinned:true)
check(Preferences(store:pinStore).pinnedPocketBundles == ["fixture","second"], "Pin order and application identities persist across restart without PID keys")
pinPrefs.setPocketPin("fixture",pinned:false)
check(Preferences(store:pinStore).pinnedPocketBundles == ["second"], "Returning an app removes only its explicit pin")
pinPrefs.setPocketPin("com.apple.controlcenter",pinned:true)
pinPrefs.setPocketPin("com.apple.TextInputMenuAgent",pinned:true)
check(pinPrefs.pinnedPocketBundles == ["second"], "Shared system controls cannot be pinned through the preference API")
pinPrefs.setPocketPin("com.apple.Spotlight",pinned:true)
pinPrefs.setPocketPin("com.apple.campo",pinned:true)
check(pinPrefs.pinnedPocketBundles == ["second","com.apple.Spotlight","com.apple.campo"],
      "Individually hosted Spotlight items support the same pin path as other status extras")
check(Preferences(store:pinStore).pinnedPocketBundles == pinPrefs.pinnedPocketBundles,
      "Spotlight and Campo pins survive a fresh preferences instance")
pinPrefs.setPocketPin("com.apple.Spotlight",pinned:false); pinPrefs.setPocketPin("com.apple.campo",pinned:false)
check(pinPrefs.pinnedPocketBundles == ["second"], "Returning Spotlight preserves unrelated saved pins")
pinStore.removePersistentDomain(forName:pinSuite)
let pinItems = Items(), pinReader = Inventory(), pinBridge = Visibility()
let pinEngine = NativeVisibilityEngine(items:pinItems,inventory:pinReader,visibility:pinBridge,ownBundleIdentifier:"own",itemFrame:{ _ in frame(600) },isLTR:{true})
pinEngine.collapse { _ in }; pinReader.finish(); pinBridge.finish(.success(Handle()))
let originalPinLayout = pinEngine.layout
var pinOwners = ["visible":["visible","signed-visible"],"hidden":["hidden"],"always":["always"],"siblings":["siblings"]]
// Display/backdrop reconfiguration can expand before a fresh placement read
// answers. That expansion must not install a restriction with no section map.
let resetItems = Items(), resetReader = Inventory(), resetBridge = Visibility()
let resetEngine = NativeVisibilityEngine(items:resetItems,inventory:resetReader,visibility:resetBridge,ownBundleIdentifier:"own",itemFrame:{ _ in frame(600) },isLTR:{true})
resetEngine.updatePocketPlacement(pinned:["visible"],owners:pinOwners)
resetEngine.expand()
resetReader.finish(); resetBridge.finish(.success(Handle()))
check(resetEngine.layout != nil, "A pinned expansion keeps the fresh section read across display/backdrop reconfiguration")
var resetResult: CollapseResult?
resetEngine.collapse { resetResult = $0 }; resetBridge.finish(.success(Handle()))
check(resetResult == .collapsed, "The original arrow still collapses after display/backdrop reconfiguration with saved pins")
resetEngine.expand();resetBridge.finish(.success(Handle()));resetEngine.updatePocketPlacement(pinned:[],owners:[:])
var failedPlacementReady = false, repeatedFailedPlacementReady = false
resetEngine.invalidateLayout()
resetEngine.updatePocketPlacement(pinned:["visible"],owners:pinOwners) { failedPlacementReady = true }
resetEngine.expand();resetReader.finish([])
check(failedPlacementReady && resetEngine.layout == nil && resetEngine.state == .expanded,
      "A failed fresh section read fails open and completes pending pin-placement readers")
resetEngine.updatePocketPlacement(pinned:["visible"],owners:pinOwners) { repeatedFailedPlacementReady = true }
check(repeatedFailedPlacementReady, "An unchanged placement reader cannot remain trapped behind a failed section read")
resetEngine.updatePocketPlacement(pinned:[],owners:[:])
var placementReady = false, repeatedPlacementReady = false
pinEngine.updatePocketPlacement(pinned:["visible"],owners:pinOwners) { placementReady = true }
pinEngine.updatePocketPlacement(pinned:["visible"],owners:pinOwners) { repeatedPlacementReady = true }
check(!placementReady && !repeatedPlacementReady,
      "Both new and unchanged pin-policy readers wait for the same in-flight native activation")
check(!pinBridge.allowed.contains("visible") && !pinBridge.allowed.contains("signed-visible") && pinBridge.allowed.contains("own"), "Pinning excludes both bundle and signing aliases while preserving Draplet")
pinBridge.finish(.success(Handle()))
check(placementReady && repeatedPlacementReady,
      "Native acceptance releases both pin-policy readers before they sample the rebuilt overflow slot")
pinEngine.expand()
check(pinBridge.allowed.contains("hidden") && !pinBridge.allowed.contains("visible"), "The original accordion reveals other icons while pinned apps stay in Pocket")
pinBridge.finish(.success(Handle()))
pinOwners["new-app"] = ["new-app"]
pinEngine.updatePocketPlacement(pinned:["visible"],owners:pinOwners)
check(pinBridge.allowed.contains("new-app") && pinEngine.layout == originalPinLayout, "New unpinned apps are shown without reclassifying a restricted native layout")
pinBridge.finish(.success(Handle()))
var pinCaptureShown = false
pinEngine.stagePocketCapture(["visible","signed-visible"]) { pinCaptureShown = $0 }
check(pinBridge.allowed.contains("visible") && pinBridge.allowed.contains("signed-visible"), "Image capture may temporarily expose the pinned app itself")
let captureOnlyRestriction = Handle(); pinBridge.finish(.success(captureOnlyRestriction))
check(pinCaptureShown, "Pinned exposure completion is delivered")
check(pinEngine.stageUnrestrictedPocketCapture() && captureOnlyRestriction.invalidated && pinEngine.layout == originalPinLayout,
      "A bounded unrestricted capture fallback drops only its temporary assertion and preserves the original native sections")
pinEngine.finishPocketCapture()
check(!pinBridge.allowed.contains("visible") && pinBridge.allowed.contains("new-app"), "Capture cleanup restores pins and the current unpinned owners")
let pinnedRestriction = Handle(); pinBridge.finish(.success(pinnedRestriction))
pinEngine.updatePocketPlacement(pinned:[],owners:pinOwners)
check(pinnedRestriction.invalidated && pinEngine.layout == originalPinLayout, "Unpin or presentation suspension releases the added restriction without changing native sections")
// A placement changed during an in-flight collapse must take effect before
// the collapse reports success, not wait indefinitely for another preference edit.
pinEngine.collapse { _ in }; pinReader.finish()
pinEngine.updatePocketPlacement(pinned:["visible"],owners:pinOwners)
let obsoletePlacement = Handle(); pinBridge.finish(.success(obsoletePlacement))
check(obsoletePlacement.invalidated && !pinBridge.allowed.contains("visible"), "An obsolete in-flight allow-list is discarded and retried with the new pin")
pinBridge.finish(.success(Handle()))
check(pinEngine.state == .collapsed, "The retried collapse completes with the new placement")
pinEngine.updatePocketPlacement(pinned:[],owners:[:]); pinEngine.expand()
var sessionReads = 0
var activeSession = true
let sessionVisibility = SessionVisibilityCache(read: { sessionReads += 1; return activeSession })
check(sessionVisibility.isActive(at: 100), "An unlocked console session permits overlays")
activeSession = false
check(sessionVisibility.isActive(at: 100.1) && sessionReads == 1, "Presentation ticks reuse session metadata without repeated IPC")
check(!sessionVisibility.isActive(at: 100.25), "Locking or leaving the console suppresses overlays and Pocket capture")
activeSession = true
check(sessionVisibility.isActive(at: 100.5), "Unlocking restores presentation eligibility")
let dragSource = CGRect(x: 1000,y: 0,width: 30,height: 33)
let dragTarget = CGRect(x: 900,y: 40,width: 180,height: 100)
let dragStart = CGPoint(x:1015,y:16), dragDrop = CGPoint(x:950,y:80)
var dragPolicy = PocketDragDropPolicy()
dragPolicy.begin(at:dragStart,command:false,source:dragSource)
dragPolicy.moved(to:dragDrop)
check(dragPolicy.end(at:dragDrop,target:dragTarget) == nil, "Ordinary clicks and file drags never redirect native mouse-up")
dragPolicy.begin(at:CGPoint(x:700,y:16),command:true,source:dragSource)
dragPolicy.moved(to:dragDrop)
check(dragPolicy.end(at:dragDrop,target:dragTarget) == nil, "Command-drags starting outside the exact test source remain untouched")
dragPolicy.begin(at:dragStart,command:true,source:dragSource)
check(dragPolicy.end(at:dragDrop,target:dragTarget) == nil, "A mouse-up without a confirmed drag cannot become a Pocket drop")
dragPolicy.begin(at:dragStart,command:true,source:dragSource)
check(!dragPolicy.moved(to:CGPoint(x:1017,y:17)), "Minor pointer jitter does not arm drop interception")
dragPolicy.cancel()
dragPolicy.begin(at:dragStart,command:true,source:dragSource)
check(dragPolicy.moved(to:dragDrop) && dragPolicy.end(at:dragDrop,target:dragTarget) == dragStart, "Only a confirmed target drop returns the original native completion point")
check(dragPolicy.end(at:dragDrop,target:dragTarget) == nil, "A completed drop cannot intercept another mouse-up")
dragPolicy.begin(at:dragStart,command:true,source:dragSource); dragPolicy.moved(to:dragDrop)
check(dragPolicy.end(at:CGPoint(x:300,y:500),target:dragTarget) == nil, "Dropping outside Pocket preserves the native drag outcome")
dragPolicy.begin(at:dragStart,command:true,source:dragSource); dragPolicy.moved(to:dragDrop); dragPolicy.cancel()
check(dragPolicy.end(at:dragDrop,target:dragTarget) == nil, "Escape or a disabled event tap cancels interception immediately")
dragPolicy.begin(at:dragStart,command:true,source:dragSource); dragPolicy.moved(to:dragDrop)
check(dragPolicy.end(at:dragDrop,target:nil) == nil, "A closed or absent target cannot accept a stale drop")
dragPolicy.begin(at:dragStart,command:true,source:dragSource); dragPolicy.moved(to:dragDrop)
check(dragPolicy.end(at:dragDrop,target:CGRect(x:200,y:200,width:100,height:100)) == nil, "Drop membership uses the current target position")
dragPolicy.begin(at:dragStart,command:true,source:nil); dragPolicy.moved(to:dragDrop)
check(dragPolicy.end(at:dragDrop,target:dragTarget) == nil, "Unknown source geometry fails open without changing input")
dragPolicy.begin(at:dragStart,command:true,source:dragSource); dragPolicy.moved(to:dragDrop)
check(dragPolicy.end(at:CGPoint(x:CGFloat.nan,y:80),target:dragTarget) == nil, "Nonfinite event coordinates never route a native drop")
var rightHide = RightAutoHidePolicy()
check(!rightHide.shouldHide(now: 100, held: true, delay: 5) && !rightHide.shouldHide(now: 120, held: true, delay: 5),
      "Hovering the expanded bar or Pocket holds reveal indefinitely")
check(!rightHide.shouldHide(now: 121, held: false, delay: 5) && !rightHide.shouldHide(now: 125.99, held: false, delay: 5) && rightHide.shouldHide(now: 126, held: false, delay: 5),
      "Auto-hide waits five full seconds after departing the combined hover region")
check(!rightHide.shouldHide(now: 127, held: true, delay: 5) && !rightHide.shouldHide(now: 130, held: false, delay: 5) && !rightHide.shouldHide(now: 134.9, held: false, delay: 5),
      "Re-entering either region resets the entire departure delay")
let pocketDisplay = CGRect(x: 0, y: 0, width: 1470, height: 956)
check(PocketReturnDropPolicy.matches("own-token",expected:"own-token") && !PocketReturnDropPolicy.matches("foreign",expected:"own-token") && !PocketReturnDropPolicy.matches(nil,expected:"own-token"),
      "Only the active Pocket return drag token is accepted; unrelated files and drag payloads fail closed")
check(PocketReturnDropPolicy.canBegin(pinned:true,commandAtMouseDown:true,commandNow:true)
      && !PocketReturnDropPolicy.canBegin(pinned:true,commandAtMouseDown:false,commandNow:true)
      && !PocketReturnDropPolicy.canBegin(pinned:true,commandAtMouseDown:true,commandNow:false)
      && !PocketReturnDropPolicy.canBegin(pinned:false,commandAtMouseDown:true,commandNow:true),
      "Pocket return drags require a pinned icon and Command held from mouse-down through the drag threshold")
check(PocketReturnDropPolicy.shouldReturn(accepted:true,moved:true,active:true,command:true) && !PocketReturnDropPolicy.shouldReturn(accepted:false,moved:true,active:true,command:true),
      "A return requires a successful drop on Draplet’s native menu-bar destination")
check(!PocketReturnDropPolicy.shouldReturn(accepted:true,moved:false,active:true,command:true) && !PocketReturnDropPolicy.shouldReturn(accepted:true,moved:true,active:false,command:true),
      "Escape, outside drops and stale or suppressed drag sessions never remove a pin")
check(!PocketReturnDropPolicy.shouldReturn(accepted:true,moved:true,active:true,command:false),
      "Releasing Command before a successful return drop leaves the pin intact")
func popup(_ pid:pid_t,_ number:Int,_ size:CGFloat = 100) -> WindowServerSnapshot.Window {
    WindowServerSnapshot.Window([kCGWindowOwnerPID:pid,kCGWindowNumber:number,kCGWindowLayer:101,
        kCGWindowBounds:CGRect(x:900,y:33,width:size,height:size).dictionaryRepresentation,kCGWindowIsOnscreen:true] as NSDictionary)!
}
check(!NativeMenuTrackingPolicy.isTracking([popup(10,20),popup(11,21,2)],ownPID:10,pocketWindow:nil),
      "Draplet popover shadows and tiny helper windows do not hold the right bar open forever")
check(NativeMenuTrackingPolicy.isTracking([popup(11,22)],ownPID:10,pocketWindow:nil),
      "A real third-party native menu retains the full right-side interaction")
let notchRight = CGRect(x: 824, y: 0, width: 646, height: 80)
let nativeOverflowSlot = CGRect(x:830,y:0,width:20,height:33)
let revealedSlots = [CGRect(x:1000,y:0,width:34,height:33),CGRect(x:1200,y:0,width:42,height:33)]
// Replayed physical layout: MenuBarAgent owns Sound (AirPods) itself, while
// third-party extras are reached through the same broker-owned wrappers.
let airPodsSlot = CGRect(x:1093.5,y:0,width:22,height:33)
let airPodsHostSlots: [(owner:pid_t,role:String,frame:CGRect)] = [
    (42,kAXMenuBarItemRole,airPodsSlot),
    (777,kAXButtonRole,CGRect(x:1123.5,y:0,width:34,height:33)),
    (778,kAXButtonRole,CGRect(x:1157.5,y:0,width:40,height:33))
]
let occupiedAirPodsSlots = airPodsHostSlots.filter {
    PocketInventory.isHostedLeaf(owner:$0.owner,broker:42,role:$0.role)
}.map(\.frame)
let airPodsDisclosure = PocketGeometry.overflowButtonFrame(expanded:true,native:nil,
    slots:occupiedAirPodsSlots,area:notchRight,height:33)
check(airPodsDisclosure?.maxX == airPodsSlot.minX,
      "A broker-owned AirPods/Sound slot stays occupied when placing the leading Pocket button")
check(!PocketInventory.isHostedLeaf(owner:42,broker:42,role:kAXButtonRole)
      && !PocketInventory.isHostedLeaf(owner:42,broker:42,role:kAXGroupRole)
      && !PocketInventory.isHostedLeaf(owner:777,broker:42,role:kAXApplicationRole),
      "Broker overflow buttons, wrappers and parked applications are not rendered status-item leaves")
check(PocketGeometry.overflowButtonFrame(expanded:false,native:nativeOverflowSlot,slots:revealedSlots,area:notchRight,height:33) == nil,
      "The Pocket chevron stays hidden when the right strip is collapsed, even with native overflow")
check(PocketGeometry.overflowButtonFrame(expanded:false,native:nil,slots:revealedSlots,area:notchRight,height:33) == nil,
      "Pinned apps never create a permanent second button beside the collapsed accordion")
let leadingPocket = PocketGeometry.overflowButtonFrame(expanded:true,native:nil,slots:revealedSlots,area:notchRight,height:33)
check(leadingPocket == CGRect(x:974,y:0,width:26,height:33),
      "Without native overflow, the Pocket chevron sits before every revealed icon rather than beside the main arrow")
check(PocketGeometry.overflowButtonFrame(expanded:true,native:nativeOverflowSlot,slots:revealedSlots,area:notchRight,height:33) == CGRect(x:824,y:0,width:26,height:33),
      "The leading Pocket chevron covers the system double-arrow ink within the notch's usable area")
check(PocketGeometry.overflowButtonFrame(expanded:true,native:nil,slots:[CGRect(x:835,y:0,width:34,height:33)],area:notchRight,height:33) == nil,
      "A Pocket button without enough leading room never covers an existing status icon or the notch")
check(PocketGeometry.overflowButtonFrame(expanded:true,native:nil,slots:[],area:notchRight,height:33) == nil,
      "Unresolved native geometry never guesses a Pocket button position")
check(!PocketGeometry.isUsable(CGRect(x: 710, y: 0, width: 26, height: 33), on: pocketDisplay, rightArea: notchRight),
      "A coordinate under the notch never receives a pocket click")
let disclosureMask = RightMenuCover()
disclosureMask.prepare(frame:CGRect(x:-4000,y:0,width:373,height:33),progress:0,style:.curtain)
let maskedDisclosure = PocketOverflowButton(canPresent:{true})
maskedDisclosure.show(at:CGRect(x:-3800,y:0,width:26,height:33),beneath:disclosureMask.maskingWindow)
check(NSApp.windows.first { $0.windowNumber == maskedDisclosure.windowNumber }!.level == disclosureMask.maskingWindow!.level, "The Pocket control stays below the shared curtain while revealing")
check(maskedDisclosure.parentWindowNumber == disclosureMask.windowNumber,
      "The actual disclosure belongs to the curtain's ordered window group during native layout preparation")
disclosureMask.dismiss()
maskedDisclosure.finishReveal()
let disclosureWindow = NSApp.windows.first { $0.windowNumber == maskedDisclosure.windowNumber }!
check(disclosureWindow.level.rawValue > 26, "The unmasked Pocket control owns clicks above transparent third-party status windows")
check(maskedDisclosure.isVisible && maskedDisclosure.parentWindowNumber == nil,
      "Completing the reveal leaves its existing disclosure visible without a hide/show handoff")
disclosureMask.prepare(frame:CGRect(x:-4000,y:0,width:373,height:33),progress:0,style:.curtain)
maskedDisclosure.show(at:CGRect(x:-3800,y:0,width:26,height:33),beneath:disclosureMask.maskingWindow)
maskedDisclosure.hide()
disclosureMask.prepare(frame:CGRect(x:-4000,y:0,width:373,height:33),progress:0,style:.curtain)
check(!maskedDisclosure.isVisible && maskedDisclosure.parentWindowNumber == nil,
      "A hidden disclosure detaches so another curtain transition cannot resurrect it")
maskedDisclosure.stop();disclosureMask.stop()
let occupiedMask = RightMenuCover.View(frame:CGRect(x:0,y:0,width:373,height:33))
occupiedMask.progress = 0.35;occupiedMask.revealExtent = 208
let occupiedBitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:373,pixelsHigh:33,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:occupiedBitmap)
occupiedMask.draw(occupiedMask.bounds);NSGraphicsContext.restoreGraphicsState()
check(occupiedBitmap.colorAt(x:248,y:16)!.alphaComponent > 0.95 && occupiedBitmap.colorAt(x:350,y:16)!.alphaComponent < 0.05,
      "The right mask animates through occupied icons instead of spending the reveal on empty notch-side space")
check(!PocketGeometry.isUsable(CGRect(x: -20, y: 0, width: 26, height: 33), on: pocketDisplay, rightArea: nil),
      "Offscreen legacy items fail open instead of clicking an unrelated app")
check(PocketGeometry.isUsable(CGRect(x: 1200, y: 0, width: 26, height: 33), on: pocketDisplay, rightArea: notchRight),
      "A fully visible right-side icon is safe to capture and activate")
let ownerProxy = AXUIElementCreateApplication(777)
let hostProxy = AXUIElementCreateSystemWide()
let ownerFrame = CGRect(x:1000,y:4,width:24,height:24)
let dragHost = PocketInventory.HostedItem(owner:777,element:hostProxy,frame:ownerFrame)
let dragPoint = CGPoint(x:1012,y:16)
check(PocketInventory.hostedDragCandidate(at:dragPoint,host:.init(items:[dragHost],overflow:nil),area:notchRight)?.owner == 777,
      "A broker-hosted status drag resolves through its sole fully visible slot when the global hit test returns a generic menu bar")
check(PocketInventory.hostedDragCandidate(at:dragPoint,host:.init(items:[dragHost,dragHost],overflow:nil),area:notchRight) == nil,
      "Overlapping broker slots never guess which status item is being dragged")
check(PocketInventory.hostedDragCandidate(at:dragPoint,host:.init(items:[dragHost],overflow:ownerFrame),area:notchRight) == nil,
      "The system overflow control cannot become an application pin drag")
check(PocketInventory.hostedDragCandidate(at:CGPoint(x:1002,y:16),host:.init(items:[dragHost],overflow:CGRect(x:1020,y:0,width:20,height:33)),area:notchRight) == nil,
      "A partly covered native slot cannot start a Pocket drag outside its overlapping overflow button")
check(PocketInventory.hostedDragCandidate(at:CGPoint(x:900,y:100),host:.init(items:[dragHost],overflow:nil),area:notchRight) == nil,
      "A drag outside the physical menu bar never uses hosted status identity")
check(PocketInventory.hostedDragCandidate(at:dragPoint,host:.init(items:[dragHost],overflow:nil),area:CGRect(x:1010,y:0,width:460,height:80)) == nil,
      "A slot clipped by the notch or display edge is not a safe drag source")
let ownerItem = PocketItem(id:"777:0",bundle:"fixture",pid:777,name:"one",element:ownerProxy,frame:ownerFrame,windowID:nil)
let peerItem = PocketItem(id:"777:1",bundle:"fixture",pid:777,name:"two",element:AXUIElementCreateApplication(778),frame:CGRect(x:1050,y:4,width:24,height:24),windowID:nil)
let hostFixture = PocketInventory.HostSnapshot(items:[PocketInventory.HostedItem(owner:777,element:hostProxy,frame:ownerFrame),PocketInventory.HostedItem(owner:777,element:hostProxy,frame:peerItem.frame)],overflow:nil)
let parkedHost = PocketInventory.HostSnapshot(items:[],overflow:nil)
check(PocketInventory.preferredHostSnapshot([parkedHost,hostFixture])?.items.count == 2,
      "A parked duplicate MenuBarAgent window with identical bounds cannot hide the rendered physical status slots")
check(PocketInventory.preferredHostSnapshot([hostFixture,parkedHost])?.items.count == 2,
      "Reversing duplicate host-window order preserves the physical glyph catalog")
check(PocketInventory.preferredHostSnapshot([parkedHost]) == nil,
      "An entirely parked host catalog is unavailable, never evidence that all status space is empty")
check(PocketInventory.preferredHostSnapshot([.init(items:[],overflow:ownerFrame)])?.overflow == ownerFrame,
      "A real native overflow control remains reachable when all foreign status slots are parked")
check(PocketInventory.matchFrame(ownerItem,among:[ownerItem,peerItem],host:hostFixture) == ownerFrame,
      "Different publisher and host AX wrappers join through unique owner geometry")
let ambiguousItem = PocketItem(id:"777:2",bundle:"fixture",pid:777,name:"ambiguous",element:AXUIElementCreateApplication(779),frame:ownerFrame,windowID:nil)
check(PocketInventory.matchFrame(ownerItem,among:[ownerItem,ambiguousItem],host:hostFixture) == nil,
      "Ambiguous same-owner geometry cannot capture a neighboring icon")
let movedSingle = PocketInventory.HostSnapshot(items:[PocketInventory.HostedItem(owner:777,element:hostProxy,frame:peerItem.frame)],overflow:nil)
check(PocketInventory.matchFrame(ownerItem,among:[ownerItem],host:movedSingle) == peerItem.frame,
      "A single real item follows its sole host entry even when its publisher frame is stale")
let parkedSlot = CGRect(x:857.5,y:0,width:50,height:33)
let parkedButtons = PocketInventory.HostSnapshot(items:[
    .init(owner:777,element:ownerProxy,frame:parkedSlot,name:"one"),
    .init(owner:777,element:hostProxy,frame:parkedSlot,name:"two")
],overflow:CGRect(x:890.5,y:1,width:17.5,height:30))
check(PocketInventory.matchFrame(ownerItem,among:[ownerItem,peerItem],host:.init(items:parkedButtons.renderedItems,overflow:parkedButtons.overflow)) == nil,
      "The real parked AXButton pattern cannot classify hidden siblings as drawn or photograph the overflow arrow")
let overlappingButtons = PocketInventory.HostSnapshot(items:parkedButtons.items,overflow:nil)
check(PocketInventory.matchFrame(ownerItem,among:[ownerItem,peerItem],host:.init(items:overlappingButtons.renderedItems,overflow:nil)) == nil,
      "Identical parked physical rectangles remain unavailable even when the overflow attribute is transiently absent")
let stagedIdentityHost = PocketInventory.HostSnapshot(items:[
    .init(owner:777,element:ownerProxy,frame:ownerFrame),
    .init(owner:778,element:hostProxy,frame:ownerFrame)
],overflow:nil)
check(PocketInventory.matchFrame(ownerItem,among:[ownerItem],host:stagedIdentityHost) == ownerFrame,
      "A capture-staged owner's exact identity survives unrelated parked rectangles without weakening visible-layout classification")
var hostSettlement = PocketHostSettlement()
var pinnedSettlement = PocketHostSettlement()
check(!pinnedSettlement.accepts(hostFixture,at:0,awaitingAbsenceOf:[777])
      && !pinnedSettlement.accepts(hostFixture,at:0.5,awaitingAbsenceOf:[777]),
      "Stable ghost AXButtons from pinned owners cannot establish a visible strip's leading edge")
check(!pinnedSettlement.accepts(.init(items:[],overflow:nil),at:0.6,awaitingAbsenceOf:[777])
      && pinnedSettlement.accepts(.init(items:[],overflow:nil),at:0.73,awaitingAbsenceOf:[777]),
      "The host must settle again after the pinned owner finally disappears")
check(!pinnedSettlement.accepts(hostFixture,at:0.8,awaitingAbsenceOf:[777])
      && !pinnedSettlement.accepts(.init(items:[],overflow:nil),at:0.9,awaitingAbsenceOf:[777]),
      "A late pinned-owner ghost resets the quiet interval instead of retaining a stale accepted layout")
check(!hostSettlement.accepts(parkedButtons,at:0) && !hostSettlement.accepts(parkedButtons,at:0.10),
      "A single pre-reflow host read never unveils the overflow disclosure")
let reflowedHost = PocketInventory.HostSnapshot(items:hostFixture.items,overflow:CGRect(x:890.5,y:1,width:17.5,height:30))
check(!hostSettlement.accepts(reflowedHost,at:0.11) && !hostSettlement.accepts(reflowedHost,at:0.20),
      "Moving native geometry restarts the quiet interval instead of publishing the previous overflow location")
check(hostSettlement.accepts(.init(items:Array(reflowedHost.items.reversed()),overflow:reflowedHost.overflow),at:0.24),
      "Stable physical slots settle even when MenuBarAgent reorders its AX children")
check(!hostSettlement.accepts(nil,at:0.25) && hostSettlement.accepts(nil,at:0.38),
      "An unreadable host is bounded and never reuses a stale physical overflow location")
let overflowArea = CGRect(x:824,y:0,width:646,height:80)
let fittedFrame = CGRect(x:1000,y:4,width:24,height:24)
check(PocketOverflowMembership.resolve([("a",24)],drawn:["a":fittedFrame],display:pocketDisplay,area:overflowArea,capacity:300,nativeOverflow:false,revealed:true).isEmpty,
      "A fitting bar has no overflow pocket")
check(PocketOverflowMembership.resolve([("a",24)],drawn:[:],display:pocketDisplay,area:overflowArea,capacity:300,nativeOverflow:false,revealed:true) == ["a"],
      "An eligible unrendered icon stays reachable in Pocket even when proxy widths fit and the native overflow button is absent")
check(PocketOverflowMembership.resolve([("shown",34),("missing",24)],drawn:["shown":fittedFrame],display:pocketDisplay,area:overflowArea,capacity:372.5,nativeOverflow:false,revealed:true) == ["missing"],
      "A partially populated expanded host cannot silently lose an unpinned publisher after QA pressure is removed")
check(PocketOverflowMembership.resolve([("a",24)],drawn:[:],display:pocketDisplay,area:overflowArea,capacity:10,nativeOverflow:true,revealed:false).isEmpty,
      "Intentionally collapsed items never become overflow membership")
check(PocketOverflowMembership.resolve([("a",24),("b",24)],drawn:[:],display:pocketDisplay,area:overflowArea,capacity:10,nativeOverflow:true,revealed:true,hostAvailable:false).isEmpty,
      "A transient missing host snapshot cannot classify every running status item as overflow")
check(PocketOverflowMembership.resolve([("same:1",24),("same:2",24)],drawn:["same:1":fittedFrame],display:pocketDisplay,area:overflowArea,capacity:30,nativeOverflow:true,revealed:true) == ["same:2"],
      "Only the nonfitting sibling enters Pocket, never every item from its app")
check(PocketOverflowMembership.resolve([("a",24),("b",24)],drawn:["a":fittedFrame,"b":CGRect(x:790,y:4,width:42,height:24)],display:pocketDisplay,area:overflowArea,capacity:30,nativeOverflow:true,revealed:true) == ["b"],
      "An item crossing the notch boundary overflows while its fitting neighbor stays in the bar")
let placedPocket = PocketGeometry.panelFrame(anchor: CGRect(x: -3, y: 930, width: 20, height: 26), size: CGSize(width: 286, height: 380), screen: pocketDisplay, menuHeight: 33)
check(placedPocket.minX == 8 && placedPocket.maxY < 923 && pocketDisplay.contains(placedPocket),
      "Pocket stays below the bar and clamps to the screen edge")
let packed = PocketLayout.rows([("a",26), ("b",26), ("wide",110), ("c",26), ("full",180)])
check(packed.count == 3 && packed[1].map(\.span) == [2,1] && packed[2][0].span == 3,
      "Wide status text receives spanning cells without losing icon order")
let navigationItems: [(String, CGFloat)] = [("a", 26), ("b", 26), ("wide", 110), ("c", 26), ("full", 180)]
check(PocketLayout.neighbor(of: "b", keyCode: 125, items: navigationItems) == "wide",
      "Down follows the next spanning row instead of a fixed three-item offset")
check(PocketLayout.neighbor(of: "c", keyCode: 126, items: navigationItems) == "b",
      "Up chooses the nearest cell center in the preceding short row")
check(PocketLayout.neighbor(of: "full", keyCode: 125, items: navigationItems) == "full" && PocketLayout.neighbor(of: "a", keyCode: 123, items: navigationItems) == "a",
      "Grid keyboard navigation stops at outer edges")
let captureBatches = PocketLayout.batches([("a", "same", 26), ("b", "other", 26), ("c", "same", 26), ("d", "last", 110)], widthLimit: 150)
check(captureBatches == [["a", "c", "b"], ["d"]], "Capture batches keep bundle siblings together and respect the available band")
check(PocketLayout.rows([("huge", CGFloat.greatestFiniteMagnitude)])[0][0].span == 3,
      "Untrusted AX widths are clamped before integer conversion")
func pocketPixelImage(_ pixels: [UInt8]) -> CGImage {
    CGImage(width: 3, height: 3, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 12,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}
var pocketPixels = [UInt8](repeating: 0, count: 36)
for i in stride(from: 3, to: 36, by: 4) { pocketPixels[i] = 255 }
check(PocketImage.isolate(pocketPixelImage(pocketPixels)) == nil, "A blank native snapshot is not presented as an available icon")
for i in [12,16] { pocketPixels[i] = 255; pocketPixels[i+1] = 255; pocketPixels[i+2] = 255 }
let isolatedPocket = PocketImage.isolate(pocketPixelImage(pocketPixels))!
let pocketData = isolatedPocket.dataProvider!.data!
let pocketBytes = CFDataGetBytePtr(pocketData)!
check(pocketBytes[3] == 0 && pocketBytes[15] == 255 && PocketImage.isMonochrome(isolatedPocket),
      "Icon extraction removes a black native background while preserving template glyphs")
var transparentPocket = pocketPixels
for i in [0,4,8,20,24,28,32] { for c in 0..<4 { transparentPocket[i+c] = 0 } }
check(PocketImage.isolate(pocketPixelImage(transparentPocket)) != nil,
      "Already transparent Ice window captures retain their original silhouette")
func pocketRimFixture(background: UInt8, noise: Bool, color: [UInt8]? = nil) -> CGImage {
    let width = 100, height = 66
    var bytes = [UInt8](repeating:0,count:width*height*4)
    for y in 0..<height { for x in 0..<width {
        let glyph = (35..<65).contains(x) && (19..<47).contains(y)
        let rim = noise && x == 96 && (10..<56).contains(y)
        let value: UInt8 = glyph ? (background < 128 ? 255 : 0) : rim ? (background < 128 ? 0 : 255) : background
        let offset = (y*width+x)*4
        for c in 0..<3 { bytes[offset+c] = glyph ? (color?[c] ?? value) : value }
        bytes[offset+3] = 255
    } }
    return CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,
        space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),
        provider:CGDataProvider(data:Data(bytes) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
}
for background: UInt8 in [1,254] {
    let clean = PocketImage.trim(PocketImage.isolate(pocketRimFixture(background:background,noise:false))!)!
    let noisy = PocketImage.trim(PocketImage.isolate(pocketRimFixture(background:background,noise:true))!)!
    check(noisy.width == clean.width && noisy.height == clean.height,
          "One-level native background noise cannot become opaque ink or widen a captured status glyph")
    check(PocketImage.isMonochrome(clean),
          "A cropped native glyph remains a template even when its provider omits the last row's trailing stride padding")
}
// Native images survive both soft expiry and failed/restarted captures.
let availabilityInner = try! PropertyListSerialization.data(fromPropertyList:[
    ["location":["bundle":["_0":"blocked"]],"isAllowed":false],
    ["location":["bundle":["_0":"active"]],"isAllowed":true],
    ["bundle":["_0":"marker-only"]]
],format:.binary,options:0)
let availabilityPlist = try! PropertyListSerialization.data(fromPropertyList:["trackedApplications":availabilityInner],format:.binary,options:0)
check(MenuBarAvailability.disallowed(in:availabilityPlist) == ["blocked"], "Only explicit macOS denial excludes an unpublished status item; saved pins are independent")
check(MenuBarAvailability.disallowed(in:Data()) == [], "Unavailable or changed Control Center metadata cannot hide unrelated native icons")
let repeatedImageKeys = PocketInventory.imageCacheKeys(bundle:"fixture",identifiers:["same","same"])
check(Set(repeatedImageKeys).count == 2, "Repeated AX identifiers cannot alias different native glyphs in the persistent cache")
check(PocketInventory.imageCacheKeys(bundle:"fixture",identifiers:["first","second"]).reversed().map { $0 }
      == PocketInventory.imageCacheKeys(bundle:"fixture",identifiers:["second","first"]), "Unique AX identities survive sibling reordering")
let glyphCacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("DrapletGlyphCache-"+UUID().uuidString)
let glyphCache = PocketImageCache(directory:glyphCacheURL)
let glyphDate = Date(timeIntervalSince1970:1000)
let glyphKey = "fixture|slot:0/1"
let glyphImage = NSImage(cgImage:pocketPixelImage(transparentPocket),size:NSSize(width:2,height:2))
glyphImage.isTemplate = true
glyphCache.succeeded(glyphImage,key:glyphKey,pid:777,scale:2,now:glyphDate)
check(!glyphCache.needsRefresh(glyphKey,pid:777,scale:2,now:glyphDate.addingTimeInterval(1)), "Fresh native glyphs need no repeat screenshot")
check(glyphCache.needsRefresh(glyphKey,pid:777,scale:2,now:glyphDate.addingTimeInterval(121)) && glyphCache.image(glyphKey) != nil,
      "Soft image expiry requests background work without removing last-good pixels")
glyphCache.failed(glyphKey,pid:777,now:glyphDate.addingTimeInterval(122))
check(glyphCache.image(glyphKey) != nil && !glyphCache.unavailable(glyphKey), "A failed refresh preserves the actual native glyph instead of showing an error cell")
check(!glyphCache.needsRefresh(glyphKey,pid:777,scale:2,now:glyphDate.addingTimeInterval(123)), "Failed background captures back off instead of running on every open")
glyphCache.flush()
let relaunchedGlyphCache = PocketImageCache(directory:glyphCacheURL)
check(relaunchedGlyphCache.image(glyphKey)?.isTemplate == true && relaunchedGlyphCache.image(glyphKey)?.size == glyphImage.size,
      "A fresh process restores native glyph pixels, logical size and template tint from disk")
check(relaunchedGlyphCache.needsRefresh(glyphKey,pid:778,scale:2,now:glyphDate.addingTimeInterval(123)) && relaunchedGlyphCache.image(glyphKey) != nil,
      "A restarted publisher refreshes in the background while its last-good glyph remains available")
relaunchedGlyphCache.appearanceChanged()
check(relaunchedGlyphCache.image(glyphKey) != nil, "Display changes retain the previous image until a replacement succeeds")
let missingGlyph = "fixture|slot:1/2"
relaunchedGlyphCache.failed(missingGlyph,pid:777,now:glyphDate)
check(relaunchedGlyphCache.unavailable(missingGlyph) && !relaunchedGlyphCache.needsRefresh(missingGlyph,pid:777,scale:2,now:glyphDate.addingTimeInterval(10)),
      "An unpublished native icon is temporarily dormant rather than repeatedly recaptured")
let idleMissing = "fixture|slot:idle"
relaunchedGlyphCache.failed(idleMissing,pid:777,now:glyphDate,background:true)
check(!relaunchedGlyphCache.unavailable(idleMissing) && relaunchedGlyphCache.needsRefresh(idleMissing,pid:777,scale:2,now:glyphDate.addingTimeInterval(1),foreground:true),
      "An idle capture miss still permits the safe foreground fallback on first use")
relaunchedGlyphCache.requestRefresh([missingGlyph])
check(relaunchedGlyphCache.needsRefresh(missingGlyph,pid:777,scale:2,now:glyphDate.addingTimeInterval(10)), "Explicit refresh bypasses the retry backoff")
relaunchedGlyphCache.flush()
try? FileManager.default.removeItem(at:glyphCacheURL)
let coloredPocketCrop = PocketImage.trim(PocketImage.isolate(pocketRimFixture(background:1,noise:false,color:[255,80,40]))!)!
check(!PocketImage.isMonochrome(coloredPocketCrop),
      "A real colored cropped status icon keeps its artwork instead of becoming a template")
invalidPrefs.rightRevealMode = .pocket
check(invalidPrefs.requiresSetup && invalidPrefs.needsIconCapture && invalidPrefs.needsBackground,
      "Real overflow imagery and its native-bar button require capture permission; no app artwork masks a missing grant")
let pocketSource = CGEventSource(stateID: .privateState)!
let pocketEvent = PocketItemEvents.event(type: .rightMouseUp, point: CGPoint(x: 1200, y: 16), windowID: 77, pid: 55, button: .right, source: pocketSource)!
let placementRelease = PocketItemEvents.placementEvent(.leftMouseUp,point:CGPoint(x:1200,y:16),source:pocketSource)!
check(placementRelease.flags.contains(.maskCommand) && placementRelease.getIntegerValueField(.eventSourceUserData) == PocketItemEvents.placementEventTag,
      "A native placement releases the mouse while Command is still held, and retains its synthetic-placement identity")
check(pocketEvent.type == .rightMouseUp && pocketEvent.flags.isEmpty && pocketEvent.getIntegerValueField(.eventTargetUnixProcessID) == 55 && pocketEvent.getIntegerValueField(.mouseEventWindowUnderMousePointer) == 77,
      "Ice-derived native clicks retain the target window and never inherit Command-drag flags")
check(!PocketActionPolicy.shouldUseMouse(after: .cannotComplete) && !PocketActionPolicy.shouldUseMouse(after: .success),
      "A timed-out or accepted AX action is never replayed as another click")
check(PocketActionPolicy.shouldUseMouse(after: .actionUnsupported) && !PocketActionPolicy.shouldUseMouse(after: .apiDisabled),
      "Only unsupported AX actions can use verified mouse routing; permission failure cannot")
check(!PocketActionPolicy.shouldDismiss(for: 10, origin: 10, target: nil, own: 20) && !PocketActionPolicy.shouldDismiss(for: 20, origin: 10, target: nil, own: 20),
      "Repeated foreground/own-app activation does not dismiss a nonactivating pocket")
check(PocketActionPolicy.shouldDismiss(for: 30, origin: 10, target: nil, own: 20) && !PocketActionPolicy.shouldDismiss(for: 30, origin: 10, target: 30, own: 20),
      "Changing to another app dismisses Pocket, while its selected native action may activate its owner")
let suite = "Draplet.Tests.\(UUID().uuidString)"
let store = UserDefaults(suiteName: suite)!
defer { store.removePersistentDomain(forName: suite) }
let prefs = Preferences(store: store)
check(prefs.rightRevealMode == .pocket, "Overflow assistance is enabled by default independently of the native arrow")
prefs.rightRevealMode = .pocket
check(Preferences(store: store).rightRevealMode == .pocket, "Overflow assistance preference survives restart")
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

// Drive the actual AppKit control with process-local events. The test subclass
// stops at the native session boundary; no global pointer input is synthesized.
final class PocketDragControlFixture: PocketClickTarget.Target {
    var starts = 0
    override func startDrag(token:String,event:NSEvent) { starts += 1 }
}
let dragControlWindow = NSWindow(contentRect:NSRect(x:-3500,y:0,width:100,height:80),styleMask:[.borderless],backing:.buffered,defer:false)
let dragControl = PocketDragControlFixture(frame:NSRect(x:20,y:20,width:34,height:34))
dragControlWindow.contentView!.addSubview(dragControl)
var dragAdmissions = 0, dragClicks = 0, localReleases = 0
var localCommandAtRelease = false
dragControl.endDrag = { _,command in localReleases += 1;localCommandAtRelease = command }
dragControl.beginDrag = { _ in dragAdmissions += 1;return true };dragControl.activate = { _ in dragClicks += 1 }
func pocketMouse(_ type:NSEvent.EventType,_ x:CGFloat,_ command:Bool) -> NSEvent {
    NSEvent.mouseEvent(with:type,location:NSPoint(x:x,y:30),modifierFlags:command ? .command : [],timestamp:1,windowNumber:dragControlWindow.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
}
dragControl.pinned = true
dragControl.mouseDown(with:pocketMouse(.leftMouseDown,30,true));dragControl.mouseDragged(with:pocketMouse(.leftMouseDragged,32,true))
check(dragControl.starts == 0, "Command-click jitter does not start a Pocket drag")
dragControl.mouseDragged(with:pocketMouse(.leftMouseDragged,38,true));dragControl.mouseUp(with:pocketMouse(.leftMouseUp,38,true))
check(dragControl.starts == 1 && dragAdmissions == 1 && dragClicks == 0 && localReleases == 1 && localCommandAtRelease, "A real pinned cell starts its local drag without firing its menu action")
dragControl.pinned = false
dragControl.mouseDown(with:pocketMouse(.leftMouseDown,30,true));dragControl.mouseDragged(with:pocketMouse(.leftMouseDragged,38,true))
check(dragControl.starts == 2, "Automatic-overflow cells can start Command-reordering without being pinned")
dragControl.mouseDown(with:pocketMouse(.leftMouseDown,30,true));dragControl.mouseDragged(with:pocketMouse(.leftMouseDragged,38,false));dragControl.mouseDragged(with:pocketMouse(.leftMouseDragged,42,true));dragControl.mouseUp(with:pocketMouse(.leftMouseUp,42,true))
check(dragControl.starts == 2 && dragClicks == 0, "Releasing Command cancels an armed drag permanently and cannot click through")
dragControl.mouseDown(with:pocketMouse(.leftMouseDown,30,true));dragControl.mouseUp(with:pocketMouse(.leftMouseUp,30,true))
check(dragClicks == 1, "A Command-click without movement still invokes the native item once")
dragControl.isEnabled = false
dragControl.mouseDown(with:pocketMouse(.leftMouseDown,30,true));dragControl.mouseDragged(with:pocketMouse(.leftMouseDragged,38,true))
check(dragControl.starts == 2, "Unavailable Pocket controls cannot initiate native drags")
check(!(dragControl is any NSDraggingSource), "Pocket's local control does not launch a system item drag at the Mission Control edge")
let localReturn = PocketReturnDropTarget()
let dropScreen = CGRect(x:0,y:0,width:1470,height:956)
check(PocketGeometry.dropAnchor(source:CGPoint(x:1210,y:940),screen:dropScreen,menuBarHeight:33)?.midX == 1210,
      "Pin drop target is anchored at the gesture origin rather than beside the notch")
check(PocketGeometry.dropAnchor(source:CGPoint(x:-300,y:920),screen:CGRect(x:-1920,y:0,width:1920,height:1080),menuBarHeight:24)?.midX == -300,
      "Pin drop target keeps its source on a secondary screen with negative coordinates")
check(PocketGeometry.dropAnchor(source:CGPoint(x:CGFloat.nan,y:940),screen:dropScreen,menuBarHeight:33) == nil,
      "Invalid drag origins cannot spawn a detached drop target")
let localRegion = CGRect(x:-3800,y:10,width:300,height:33)
check(localReturn.show(token:"local-session",frames:[localRegion]), "A local return gesture creates a bounded passive menu-bar target")
check(localReturn.accepts(token:"local-session",at:NSPoint(x:-3700,y:20),command:true), "Command-release inside the target accepts the current local gesture")
check(!localReturn.accepts(token:"stale-session",at:NSPoint(x:-3700,y:20),command:true) && !localReturn.accepts(token:"local-session",at:NSPoint(x:-3700,y:20),command:false), "Stale sessions and releasing Command cannot return an item")
check(!localReturn.accepts(token:"local-session",at:NSPoint(x:-3700,y:0),command:true), "Dropping outside the local menu-bar target cancels return")
localReturn.close()
check(!localReturn.accepts(token:"local-session",at:NSPoint(x:-3700,y:20),command:true), "Closing Pocket invalidates all previously shown local return regions")
dragControlWindow.close()

let pocketKeys = ["app|first","app|second","other|only"]
check(PocketItemOrder.ordered(pocketKeys,saved:[]) == pocketKeys, "Pocket keeps native inventory order until a user rearranges it")
check(PocketItemOrder.moving("other|only",relativeTo:"app|first",after:false,visible:pocketKeys,saved:[]) == ["other|only","app|first","app|second"], "Dropping before a Pocket cell moves the exact item, including same-app siblings")
check(PocketItemOrder.moving("app|first",relativeTo:"other|only",after:true,visible:pocketKeys,saved:[]) == ["app|second","other|only","app|first"], "Dropping after a Pocket cell respects the destination side")
check(PocketItemOrder.moving("gone",relativeTo:"app|first",after:false,visible:pocketKeys,saved:[]) == nil, "A stale drag source cannot mutate Pocket order")
check(PocketItemOrder.moving("app|first",relativeTo:"app|first",after:false,visible:pocketKeys,saved:[]) == nil, "Dropping onto the source does not commit a move")
let savedPocketOrder = ["other|only","sleeping|slot","app|second","app|first"]
check(PocketItemOrder.ordered(pocketKeys,saved:savedPocketOrder) == ["other|only","app|second","app|first"], "Temporarily absent publishers do not reset saved Pocket order")
check(prefs.movePocketItem("other|only",relativeTo:"app|first",after:false,visible:pocketKeys) && Preferences(store:store).pocketItemOrder == ["other|only","app|first","app|second"], "Pocket rearrangement survives a fresh preferences instance without changing pins")

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
let warmEngine = TransitionEngine(), warmCover = TestCover()
warmEngine.state = .collapsed
var warmDelays: [Double] = []
let warmTransition = RightMenuTransition(engine:warmEngine,cover:warmCover,schedule:{ delay,_ in warmDelays.append(delay) })
warmTransition.expand(style:.curtain,pace:.originalLeft,frame:cover,layoutPrepared:true) {}
check(warmCover.pending != nil && warmCover.duration == 0.18 && !warmDelays.contains(RightMenuTransition.revealPreparation),
      "A verified prepared layout begins its curtain without the cold native-geometry pause")
warmCover.finish()
let transitions = RightMenuTransition(engine: visualEngine, cover: visualCover, schedule: { scheduled.append(($0, $1)) })
let settlingEngine = TransitionEngine(), settlingCover = TestCover()
settlingEngine.state = .collapsed
var settlingWork: [(Double,()->Void)] = [], sampledLayouts = 0
let settlingTransition = RightMenuTransition(engine:settlingEngine,cover:settlingCover,schedule:{ settlingWork.append(($0,$1)) })
settlingTransition.expand(style:.curtain,pace:.originalLeft,frame:cover,prepare:{ done in sampledLayouts += 1; done() }) {}
check(sampledLayouts == 0 && settlingCover.pending == nil,
      "Disclosure geometry is sampled after the native settling tail, not before it can reflow")
let settleForGeometry = settlingWork.filter { $0.0 == RightMenuTransition.revealPreparation }
settlingWork.removeAll { $0.0 == RightMenuTransition.revealPreparation }; settleForGeometry.forEach { $0.1() }
check(sampledLayouts == 1 && settlingCover.pending != nil && settlingCover.duration == 0.18,
      "Settled geometry proceeds directly into the chosen animation without another stale-layout pause")
settlingCover.finish(); settlingEngine.state = .collapsed
settlingTransition.expand(style:.curtain,pace:.originalLeft,frame:cover,prepare:{ done in sampledLayouts += 1; done() }) {}
settlingTransition.cancelAndExpand()
let cancelledGeometry = settlingWork.filter { $0.0 == RightMenuTransition.revealPreparation }
cancelledGeometry.forEach { $0.1() }
check(sampledLayouts == 1 && !settlingCover.isVisible,
      "A cancelled reveal cannot publish delayed disclosure geometry or resurrect its mask")
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
let idleShield = PocketCaptureShield()
let shieldFrame = CGRect(x:-4000,y:0,width:300,height:32)
idleShield.showMatched(frame:shieldFrame,cancel:{})
check(!idleShield.handoff(to:CGRect(x:-4000,y:0,width:150,height:32)) && idleShield.isVisible,
      "An idle capture fence remains until a curtain covers its entire region")
check(idleShield.handoff(to:shieldFrame) && !idleShield.isVisible,
      "A closed curtain atomically takes over the idle capture prefix before reveal animation")
actualRightCover.prepare(frame: NSRect(x: -4000, y: 0, width: 300, height: 32), progress: 0, style: .curtain)
let actualRightPanel = NSApp.windows.first(where: { $0.windowNumber == actualRightCover.windowNumber })!
check(actualRightPanel.animationBehavior == NSWindow.AnimationBehavior.none,
      "The actual right panel disables AppKit ordering fades that compete with fast curtain reversals")
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
// Exercise the real native engine + visual coordinator together. Native pin
// activation may outlive the old fixed 300 ms reveal delay.
let delayedItems = Items(), delayedReader = Inventory(), delayedBridge = Visibility()
let delayedEngine = NativeVisibilityEngine(items:delayedItems,inventory:delayedReader,visibility:delayedBridge,ownBundleIdentifier:"own",itemFrame:{ _ in frame(600) },isLTR:{true})
delayedEngine.collapse { _ in }; delayedReader.finish(); delayedBridge.finish(.success(Handle()))
delayedEngine.updatePocketPlacement(pinned:["visible"],owners:pinOwners); delayedBridge.finish(.success(Handle()))
let delayedCover = TestCover()
var delayedWork: [(Double,()->Void)] = []
let delayedTransition = RightMenuTransition(engine:delayedEngine,cover:delayedCover,schedule:{ delayedWork.append(($0,$1)) })
delayedTransition.expand(style:.curtain,pace:.originalLeft,frame:cover) {}
let prematureReveal = delayedWork.filter { $0.0 == RightMenuTransition.revealPreparation }
delayedWork.removeAll { $0.0 == RightMenuTransition.revealPreparation }; prematureReveal.forEach { $0.1() }
check(delayedCover.pending == nil && delayedCover.progress == 0,
      "A pin-restricted reveal waits for the actual native activation before unveiling, even past 300 ms")
delayedBridge.finish(.success(Handle()))
let preparedReveal = delayedWork.filter { $0.0 == RightMenuTransition.revealPreparation }
delayedWork.removeAll { $0.0 == RightMenuTransition.revealPreparation }; preparedReveal.forEach { $0.1() }
check(delayedCover.pending != nil, "Accepted native reveal proceeds through the settling tail and visual animation")
delayedCover.finish()
delayedEngine.stagePocketCapture(["hidden"],preservingVisible:true) { _ in }
check(delayedBridge.systemItems == NativeVisibilityEngine.systemItemsToKeep && delayedBridge.allowed.contains("visible"),
      "Idle glyph preparation keeps fixed system controls and the user's visible applications in place")
delayedBridge.finish(.success(Handle()));delayedEngine.finishPocketCapture();delayedBridge.finish(.success(Handle()))
delayedEngine.stagePocketCapture(["visible"]) { _ in }
let captureActivations = delayedBridge.activations
var newerOwners = pinOwners; newerOwners["late-app"] = ["late-app"]
delayedEngine.updatePocketPlacement(pinned:["visible"],owners:newerOwners)
check(delayedBridge.activations == captureActivations,
      "Inventory changes during Pocket capture cannot supersede its native exposure or flash the unrestricted bar")
delayedBridge.finish(.success(Handle())); delayedEngine.finishPocketCapture(); delayedBridge.finish(.success(Handle()))
delayedEngine.updatePocketPlacement(pinned:[],owners:[:]); delayedEngine.expand()
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
