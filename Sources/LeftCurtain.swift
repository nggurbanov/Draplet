import AppKit
import ApplicationServices

// The approved prototype, retained with its geometry, typography, and easing.
final class LeftCurtain: NSObject {
let started = Date()
let coverLevel = NSWindow.Level.statusBar
var panel: NSPanel?
var coverFrame = CGRect.zero
var currentPID: pid_t = 0
var currentApp = ""
var revealed = false
var paused = false
var lastInside = Date.distantPast
var lastMenuCheck = Date.distantPast
var menuIsTracking = false
var enteredAt: Date?
let accessibilityQueue = DispatchQueue(label: "local.menu-overlay.accessibility", qos: .userInitiated)
var queryInFlight = false
var menuBoundsCache: [pid_t: (CGFloat, CGFloat)] = [:]
var animationStart = 0.0
var animationFrom = 0.0
var animationTarget = 0.0
var animationDuration = 0.18
var animationRunning = false
var animationFrameCount = 0
var animationFirstFrameDelay: Double?
var manualUntil = Date.distantPast
var activationObserver: NSObjectProtocol?
var animationTimer: Timer?
var mouseMonitor: Any?
var enabled = false
var presentationSuppressed = false
var clickPanel: CoverPanel?
private struct IndicatorLayout: Equatable {
    let cover: CGRect
    let titleWidth: CGFloat
    let menuEnd: CGFloat
    let progress: Double
    let style: BarAnimation
    let revealed: Bool
}
private var indicatorLayout: IndicatorLayout?
var manuallyCollapsed = false
var onSettings: (() -> Void)?
private let prefs = Preferences.shared

func frameJSON(_ r: CGRect) -> [String: Double] {
    ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height]
}

func emit(_ event: String, _ extras: [String: Any] = [:]) {
    var value = extras
    value["event"] = event
    value["elapsed"] = Date().timeIntervalSince(started)
    value["frontApp"] = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
    value["frontPid"] = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
       let line = String(data: data, encoding: .utf8) { NSLog("Draplet: %@", line) }
}

final class CoverView: NSView {
    var applicationName = "" { didSet { measuredTitleWidth = nil; needsDisplay = true } }
    private var measuredTitleWidth: CGFloat?
    var titleWidth: CGFloat {
        if let width = measuredTitleWidth { return width }
        let width = (applicationName as NSString).size(withAttributes: [.font: font]).width
        measuredTitleWidth = width
        return width
    }
    var menuStart: CGFloat = 120 { didSet { needsDisplay = true } }
    var menuEnd: CGFloat = 420 { didSet { needsDisplay = true } }
    var progress = 0.0 { didSet { needsDisplay = true } }
    var animationStyle = BarAnimation.curtain { didSet { needsDisplay = true } }
    var screenFrame = NSRect.zero
    let font = NSFontManager.shared.convert(NSFont.menuBarFont(ofSize: 0), toHaveTrait: .boldFontMask)
    override var isOpaque: Bool { false }

    func estimatedMenuStart() -> CGFloat {
        min(bounds.width, titleWidth + 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        // The title never swaps with the native title. Only command menus are uncovered.
        let prefix = NSRect(x: 0, y: 0, width: menuStart, height: bounds.height)
        MenuBarBackdrop.shared.draw(in: prefix, screenRect: prefix.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY))
        let suffix = NSRect(x: menuStart, y: 0, width: max(0, bounds.width - menuStart), height: bounds.height)
        MenuMaskDrawing.draw(in: suffix, progress: progress, style: animationStyle, extent: max(0, menuEnd - menuStart)) {
            MenuBarBackdrop.shared.draw(in: suffix, screenRect: suffix.offsetBy(dx: self.screenFrame.minX, dy: self.screenFrame.minY), operation: .sourceIn)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: MenuBarBackdrop.shared.foreground, .paragraphStyle: paragraph
        ]
        let name = applicationName as NSString
        let size = name.size(withAttributes: attributes)
        let width = min(size.width, bounds.width - 45)
        // Native menu titles sit on this pixel-aligned baseline at 2× scale.
        name.draw(in: NSRect(x: 10.5, y: (bounds.height - size.height) / 2 + 0.5,
                             width: width + 1, height: size.height), withAttributes: attributes)
    }
}

final class CoverPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

func menuBar(_ pid: pid_t) -> AXUIElement? {
    let element = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(element, 0.1)
    var menu: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXMenuBarAttribute as CFString, &menu) == .success,
          let menu else { return nil }
    let bar = menu as! AXUIElement
    AXUIElementSetMessagingTimeout(bar, 0.04)
    return bar
}

func appleMenuFrame(_ pid: pid_t) -> CGRect? {
    guard let bar = menuBar(pid) else { return nil }
    var children: CFTypeRef?
    guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &children) == .success,
          let nodes = children as? [AXUIElement], let apple = nodes.first else { return nil }
    var position: CFTypeRef?
    var size: CFTypeRef?
    guard AXUIElementCopyAttributeValue(apple, kAXPositionAttribute as CFString, &position) == .success,
          AXUIElementCopyAttributeValue(apple, kAXSizeAttribute as CFString, &size) == .success,
          let position, let size else { return nil }
    var point = CGPoint.zero
    var extent = CGSize.zero
    AXValueGetValue(position as! AXValue, .cgPoint, &point)
    AXValueGetValue(size as! AXValue, .cgSize, &extent)
    guard extent.width > 0, extent.height > 0 else { return nil }
    return CGRect(origin: point, size: extent)
}

func menuState(_ pid: pid_t) -> (Bool, CGFloat?, CGFloat?) {
    guard let bar = menuBar(pid) else { return (false, nil, nil) }
    var tracking = false
    var selected: CFTypeRef?
    if AXUIElementCopyAttributeValue(bar, kAXSelectedChildrenAttribute as CFString, &selected) == .success,
       let children = selected as? [AXUIElement], !children.isEmpty { tracking = true }
    var all: CFTypeRef?
    guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &all) == .success,
          let children = all as? [AXUIElement] else { return (tracking, nil, nil) }
    var first: CGFloat?
    var end: CGFloat?
    for (index, child) in children.prefix(32).enumerated() {
        AXUIElementSetMessagingTimeout(child, 0.04)
        var active: CFTypeRef?
        if AXUIElementCopyAttributeValue(child, kAXSelectedAttribute as CFString, &active) == .success,
           active as? Bool == true { tracking = true }
        if index >= 2 {
            var position: CFTypeRef?
            var size: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &position) == .success,
               AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &size) == .success,
               let position, let size {
                var point = CGPoint.zero
                var extent = CGSize.zero
                AXValueGetValue(position as! AXValue, .cgPoint, &point)
                AXValueGetValue(size as! AXValue, .cgSize, &extent)
                if extent.width > 0 {
                    first = min(first ?? point.x, point.x)
                    end = max(end ?? point.x + extent.width, point.x + extent.width)
                }
            }
        }
    }
    return (tracking, first, end)
}

func setReveal(_ open: Bool, _ reason: String, animated: Bool = true) {
    guard let view = panel?.contentView as? CoverView else { return }
    let target = open ? 1.0 : 0.0
    if revealed == open && (animated || view.progress == target) { return }
    revealed = open
    animationFrom = view.progress
    animationTarget = target
    animationStart = ProcessInfo.processInfo.systemUptime
    animationDuration = prefs.animationPace.duration(opening: open)
    animationFrameCount = 0
    animationFirstFrameDelay = nil
    animationRunning = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && abs(target - view.progress) > 0.001
    if !animationRunning { view.progress = target; animationTimer?.invalidate(); animationTimer = nil }
    else if animationTimer == nil {
        let frames = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.animate() }
        animationTimer = frames
        RunLoop.main.add(frames, forMode: .common)
    }
    updateClickTarget()
    emit(open ? "revealing" : "covering", ["reason": reason, "animated": animationRunning,
         "from": animationFrom, "windowNumber": panel?.windowNumber ?? 0])
}

func animate() {
    guard animationRunning, let view = panel?.contentView as? CoverView else { return }
    let elapsed = ProcessInfo.processInfo.systemUptime - animationStart
    if animationFrameCount == 0 { animationFirstFrameDelay = elapsed }
    animationFrameCount += 1
    let t = min(1, elapsed / animationDuration)
    let eased = animationTarget > animationFrom ? 1 - pow(1 - t, 3) : t * t * (3 - 2 * t)
    view.progress = animationFrom + (animationTarget - animationFrom) * eased
    updateClickTarget()
    if t >= 1 {
        animationRunning = false
        animationTimer?.invalidate(); animationTimer = nil
        emit(revealed ? "revealed" : "covered", ["transitionSeconds": ProcessInfo.processInfo.systemUptime - animationStart,
             "frames": animationFrameCount, "firstFrameSeconds": animationFirstFrameDelay ?? 0,
             "panelVisible": panel?.isVisible ?? false, "windowNumber": panel?.windowNumber ?? 0])
    }
}

func updateTitle(presentationActive: () -> Bool = SystemPresentation.current) {
    guard let front = ForegroundApplication.shared.current(),
          front.pid != currentPID else { return }
    // Workspace observers can run in either order. Resolve a cached fullscreen
    // Space before drawing its title, even if our activation observer runs first.
    if presentationActive() {
        setPresentationSuppressed(true)
        MenuBarBackdrop.shared.checkScene()
        return
    }
    let wasVisible = panel?.isVisible ?? false
    currentPID = front.pid
    manuallyCollapsed = false
    currentApp = front.name
    if let view = panel?.contentView as? CoverView {
        view.applicationName = currentApp
        let cached = menuBoundsCache[currentPID]
        view.menuStart = cached?.0 ?? view.estimatedMenuStart()
        view.menuEnd = cached?.1 ?? min(coverFrame.width, view.menuStart + 320)
    }
    menuIsTracking = false
    lastMenuCheck = .distantPast
    if prefs.trigger(for: .left) == .hover && coverFrame.insetBy(dx: -3, dy: -3).contains(NSEvent.mouseLocation) {
        lastInside = Date()
        setReveal(true, "pointer-in-menu")
    } else if !paused {
        lastInside = .distantPast
        setReveal(false, "app-switch", animated: false)
    }
    updateClickTarget()
    panel?.displayIfNeeded()
    emit("title", ["title": currentApp, "fixedFrame": frameJSON(coverFrame),
                   "visibleBefore": wasVisible, "visibleAfter": panel?.isVisible ?? false,
                   "windowNumber": panel?.windowNumber ?? 0])
}

static func menuQueryInterval(revealed: Bool, nearMenu: Bool, tracking: Bool, popup: Bool) -> TimeInterval {
    // Keep interaction/keyboard menus responsive; hidden, unused menus don't
    // need their entire AX heading geometry read several times each second.
    revealed || nearMenu || tracking || popup ? 0.15 : 1
}

func tick() {
    guard enabled, !presentationSuppressed else { return }
    syncVisibility()
    guard panel?.isVisible == true else { return }
    updateTitle()
    guard !paused else { return }
    let now = Date()
    let nearMenu = coverFrame.insetBy(dx: -9, dy: -9).contains(NSEvent.mouseLocation)
    let popup = WindowServerSnapshot.shared.current().contains {
        $0.pid == currentPID && $0.visible && (101..<110).contains($0.layer)
    }
    let interval = Self.menuQueryInterval(revealed: revealed, nearMenu: nearMenu, tracking: menuIsTracking, popup: popup)
    if !queryInFlight && now.timeIntervalSince(lastMenuCheck) > interval {
        lastMenuCheck = now
        queryInFlight = true
        let pid = currentPID
        accessibilityQueue.async { [self] in
            let state = menuState(pid)
            DispatchQueue.main.async { [self] in
                queryInFlight = false
                guard pid == currentPID, !presentationSuppressed else { return }
                menuIsTracking = state.0
                if let start = state.1, let end = state.2, let view = panel?.contentView as? CoverView {
                    let bounds = (max(0, start - coverFrame.minX), min(coverFrame.width, end - coverFrame.minX + 8))
                    if menuBoundsCache[pid]?.0 != bounds.0 || menuBoundsCache[pid]?.1 != bounds.1 {
                        menuBoundsCache[pid] = bounds
                        view.menuStart = bounds.0
                        view.menuEnd = bounds.1
                        emit("menu-bounds", ["start": bounds.0, "end": bounds.1, "targetPid": pid])
                    }
                }
            }
        }
    }
    if now < manualUntil { return }
    let tolerance: CGFloat = revealed ? 9 : 3
    let inside = coverFrame.insetBy(dx: -tolerance, dy: -tolerance).contains(NSEvent.mouseLocation)
        || (clickPanel?.frame.contains(NSEvent.mouseLocation) == true)
    if !inside { manuallyCollapsed = false }
    if menuIsTracking && !manuallyCollapsed { lastInside = now; setReveal(true, "menu-open") }
    if inside {
        if enteredAt == nil { enteredAt = now }
        lastInside = now
        if !manuallyCollapsed && prefs.trigger(for: .left) == .hover && (now.timeIntervalSince(enteredAt!) >= 0.08 || NSEvent.pressedMouseButtons != 0) {
            setReveal(true, "pointer-in-menu")
        }
    } else {
        enteredAt = nil
        if menuIsTracking { lastInside = now; setReveal(true, "menu-open") }
        else if now.timeIntervalSince(lastInside) > 0.32 { setReveal(false, "pointer-left") }
    }
}

func syncVisibility() {
    guard enabled, let panel else { return }
    guard !presentationSuppressed else { panel.orderOut(nil); clickPanel?.orderOut(nil); return }
    if NSMenu.menuBarVisible() {
        if !panel.isVisible { panel.orderFrontRegardless() }
    } else if panel.isVisible { panel.orderOut(nil) }
    updateClickTarget()
}

func setPresentationSuppressed(_ suppressed: Bool) {
    guard presentationSuppressed != suppressed else { return }
    presentationSuppressed = suppressed
    guard enabled else { return }
    if suppressed {
        animationRunning = false; animationTimer?.invalidate(); animationTimer = nil
        menuIsTracking = false
        panel?.orderOut(nil); clickPanel?.orderOut(nil)
    } else if let view = panel?.contentView as? CoverView {
        updateTitle()
        let open = revealed || (prefs.trigger(for: .left) == .hover && coverFrame.contains(NSEvent.mouseLocation))
        // The real bar has already returned. Restore its title/arrow at full
        // opacity, then close the command menus with Draplet's normal animation.
        view.progress = 1; revealed = true
        syncVisibility()
        if !open { setReveal(false, "overview-ended") }
    }
}

func stop() {
    guard enabled || panel != nil else { return }
    enabled = false
    manuallyCollapsed = false
    revealed = false; animationRunning = false; enteredAt = nil
    animationTimer?.invalidate(); animationTimer = nil
    if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor); self.mouseMonitor = nil }
    if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    panel?.orderOut(nil)
    panel?.close()
    panel = nil
    clickPanel?.close(); clickPanel = nil
    emit("cleanup", ["remainingPanels": 0])
    currentPID = 0
}


func start() {
    guard !enabled, AXIsProcessTrusted() else { return }
    guard let screen = NSScreen.screens.first else { return }
    // Keep startup on the main thread free of AX round-trips too. These are the
    // measured geometry and typography of the approved demo on this Mac.
    let height = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
    let left = screen.frame.minX + 43
    let right = screen.auxiliaryTopLeftArea?.maxX ?? screen.frame.minX + screen.frame.width / 2
    coverFrame = NSRect(x: left, y: screen.frame.maxY - height, width: right - left, height: height)
    let cover = CoverPanel(contentRect: coverFrame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
    cover.isReleasedWhenClosed = false
    cover.level = coverLevel
    cover.animationBehavior = .none
    // Floating covers must disappear with the real menu bar in Mission Control.
    // Stationary windows instead remain pasted over the desktop and Spaces strip.
    cover.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    cover.backgroundColor = .clear
    cover.isOpaque = false
    cover.hasShadow = false
    cover.hidesOnDeactivate = false
    cover.ignoresMouseEvents = true
    let view = CoverView(frame: NSRect(origin: .zero, size: coverFrame.size))
    view.screenFrame = coverFrame
    cover.contentView = view
    panel = cover
    enabled = true
    presentationSuppressed = MenuBarBackdrop.shared.presentationSuppressed
    currentPID = 0
    emit("ready", ["pid": ProcessInfo.processInfo.processIdentifier, "mode": "fixed-cover",
                   "accessibilityTrusted": AXIsProcessTrusted(),
                   "fixedFrame": frameJSON(coverFrame), "level": coverLevel.rawValue])
    updateTitle()
    if !presentationSuppressed { cover.orderFrontRegardless() }
    refreshPreferences()
    activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.updateTitle() }
    mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.tick() }

}

final class IndicatorButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
final class IndicatorBackdrop: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        MenuBarBackdrop.shared.draw(in: bounds, screenRect: window?.frame ?? .zero)
    }
}

func refreshBackground() {
    panel?.contentView?.needsDisplay = true
    clickPanel?.contentView?.needsDisplay = true
    (clickPanel?.contentView?.subviews.first as? NSButton)?.contentTintColor = MenuBarBackdrop.shared.foreground
}

func refreshPreferences() {
    indicatorLayout = nil
    (panel?.contentView as? CoverView)?.animationStyle = prefs.animation(for: .left)
    panel?.contentView?.needsDisplay = true
    refreshBackground()
    enteredAt = nil
    manuallyCollapsed = false
    updateClickTarget()
}

static func indicatorFrame(cover: NSRect, titleWidth: CGFloat, menuEnd: CGFloat, expanded: Bool) -> NSRect {
    let remaining = cover.width - menuEnd
    let fitsAfterMenus = remaining >= 14
    let width: CGFloat = expanded && fitsAfterMenus ? min(18, remaining) : 18
    // Opening moves the control beyond Help rather than leaving it over File.
    // For menus filling the space up to the notch, use the empty padding before
    // the Apple glyph; never clamp the control onto a native menu heading.
    let x = expanded ? (fitsAfterMenus ? cover.minX + menuEnd : cover.minX - 43)
        : cover.minX + titleWidth + 17
    return NSRect(x: x, y: cover.minY, width: width, height: cover.height)
}

func updateClickTarget() {
    guard enabled, !presentationSuppressed, panel?.isVisible == true,
          let view = panel?.contentView as? CoverView else { clickPanel?.orderOut(nil); return }
    let width = min(view.titleWidth, coverFrame.width - 45)
    let layout = IndicatorLayout(cover: coverFrame, titleWidth: width, menuEnd: view.menuEnd,
                                 progress: view.progress, style: view.animationStyle, revealed: revealed)
    if indicatorLayout == layout, clickPanel?.isVisible == true { return }
    indicatorLayout = layout
    let closedFrame = Self.indicatorFrame(cover: coverFrame, titleWidth: width, menuEnd: view.menuEnd, expanded: false)
    let openFrame = Self.indicatorFrame(cover: coverFrame, titleWidth: width, menuEnd: view.menuEnd, expanded: true)
    let progress = min(1, max(0, view.progress))
    var frame: NSRect
    if view.animationStyle == .fade {
        // A moving opaque button would punch a black hole in fading headings.
        frame = progress > 0 ? openFrame : closedFrame
    } else if openFrame.minX >= closedFrame.minX {
        // Ride the wipe rather than teleporting onto File before it is covered.
        frame = NSRect(x: closedFrame.minX + (openFrame.minX - closedFrame.minX) * progress,
                       y: closedFrame.minY, width: closedFrame.width + (openFrame.width - closedFrame.width) * progress,
                       height: closedFrame.height)
    } else {
        // Never slide the full-width-menu fallback across the Apple/app title.
        frame = progress > 0 ? openFrame : closedFrame
    }
    // WindowServer stores these borderless windows at whole-point origins.
    // Comparing its rounded result to fractional text metrics otherwise moves
    // and paints an unchanged indicator on every 20 Hz poll.
    frame = NSRect(x: floor(frame.minX), y: floor(frame.minY),
                   width: floor(frame.width), height: floor(frame.height))
    if clickPanel == nil {
        let hit = CoverPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hit.level = coverLevel
        hit.animationBehavior = .none
        hit.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        // macOS hit-tests transparent panels through to the native File menu.
        // Paint the exact background crop into the opaque click target so it
        // intercepts the click without changing the visible backdrop.
        hit.isReleasedWhenClosed = false; hit.isOpaque = true; hit.backgroundColor = .windowBackgroundColor
        hit.hasShadow = false; hit.hidesOnDeactivate = false
        let content = IndicatorBackdrop(frame: NSRect(origin: .zero, size: frame.size))
        let button = IndicatorButton(frame: content.bounds.offsetBy(dx: 0, dy: -0.5))
        button.title = ""; button.target = self; button.action = #selector(indicatorClicked)
        button.autoresizingMask = [.width, .height]
        button.isBordered = false; button.focusRingType = .none
        button.imagePosition = .imageOnly; button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = MenuBarBackdrop.shared.foreground
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        content.addSubview(button)
        hit.contentView = content
        clickPanel = hit
    }
    if let button = clickPanel?.contentView?.subviews.first as? NSButton {
        let image = IndicatorIcons.image(for: .left, expanded: revealed)
        let label = revealed ? "Hide application menus" : "Reveal application menus"
        if button.image !== image { button.image = image }
        if button.accessibilityLabel() != label { button.setAccessibilityLabel(label) }
        if button.toolTip != label { button.toolTip = label }
    }
    if clickPanel?.frame != frame {
        clickPanel?.setFrame(frame, display: false)
        // Moving an NSWindow reuses its backing pixels. The background is
        // screen-aligned, so its old crop becomes wrong even on a still wallpaper.
        clickPanel?.contentView?.needsDisplay = true
        clickPanel?.displayIfNeeded()
    }
    if clickPanel?.isVisible != true { clickPanel?.orderFrontRegardless() }
}

@objc func indicatorClicked() {
    if NSApp.currentEvent?.type == .rightMouseUp { onSettings?(); return }
    manualUntil = .distantPast
    lastInside = Date()
    manuallyCollapsed = revealed
    setReveal(!revealed, "indicator-click")
}

func revealForShortcut() {
    manuallyCollapsed = false
    manualUntil = Date().addingTimeInterval(5)
    setReveal(true, "shortcut")
}
}
