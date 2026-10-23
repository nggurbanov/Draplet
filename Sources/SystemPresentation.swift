import AppKit

// Some games cover the native bar with a screen-sized status-level window while
// both AppKit visibility APIs still report a normal menu bar. Native fullscreen
// apps can do the same, so combine window geometry with their focused AX window.
// This uses existing Accessibility access, without pixel capture.
final class PresentationOptionsCache {
    private let read: () -> NSApplication.PresentationOptions
    private var pid: pid_t = -1
    private var sampledAt = -Double.infinity
    private var value: NSApplication.PresentationOptions = []
    init(read: @escaping () -> NSApplication.PresentationOptions = { NSApp.currentSystemPresentationOptions }) { self.read = read }
    func current(pid: pid_t, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> NSApplication.PresentationOptions {
        if self.pid != pid || time - sampledAt >= 0.25 {
            self.pid = pid; sampledAt = time; value = read()
        }
        return value
    }
    func invalidate() { sampledAt = -Double.infinity }
}

final class SessionVisibilityCache {
    private let read: () -> Bool
    private var sampledAt = -Double.infinity
    private var active = true
    init(read: @escaping () -> Bool = {
        guard let session = CGSessionCopyCurrentDictionary() as? [String:Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) != true
            && (session[kCGSessionOnConsoleKey as String] as? Bool) == true
    }) { self.read = read }
    func isActive(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        if time - sampledAt >= 0.25 { active = read(); sampledAt = time }
        return active
    }
}

enum SystemPresentation {
    private static let options = PresentationOptionsCache()
    private static let session = SessionVisibilityCache()
    static func invalidateOptions() { options.invalidate() }
    private static var dockPID: pid_t?
    static func forgetDock(pid: pid_t) { if dockPID == pid { dockPID = nil } }
    private static var geometry: (displays: [CGRect], menuBar: CGRect)?
    static func invalidateDisplays() { geometry = nil; WindowServerSnapshot.shared.invalidate() }
    static func current() -> Bool {
        guard session.isActive() else { return true }
        let frontPID = ForegroundApplication.shared.current()?.pid ?? 0
        let nativeFullscreen = ForegroundFullscreen.shared.current(pid: frontPID)
        if nativeFullscreen { return true }
        if dockPID == nil {
            dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        }
        let windows = WindowServerSnapshot.shared.current()
        if geometry == nil {
            let displays = NSScreen.screens.compactMap { screen in
                (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
                    .map { CGDisplayBounds($0.uint32Value) }
            }
            geometry = (displays, CGDisplayBounds(CGMainDisplayID()))
        }
        let geometry = geometry!
        return isActive(records: windows, dockPID: dockPID ?? -1,
                        frontPID: frontPID,
                        displays: geometry.displays, menuBarDisplay: geometry.menuBar,
                        options: options.current(pid: frontPID), nativeFullscreen: nativeFullscreen)
    }
    static func isActive(windows: [[String: Any]], dockPID: pid_t, frontPID: pid_t,
                         displays: [CGRect], menuBarDisplay: CGRect,
                         options: NSApplication.PresentationOptions = [], nativeFullscreen: Bool = false) -> Bool {
        isActive(records: windows.compactMap { WindowServerSnapshot.Window($0 as NSDictionary) },
                 dockPID: dockPID, frontPID: frontPID, displays: displays, menuBarDisplay: menuBarDisplay,
                 options: options, nativeFullscreen: nativeFullscreen)
    }
    static func isActive(records: [WindowServerSnapshot.Window], dockPID: pid_t, frontPID: pid_t,
                         displays: [CGRect], menuBarDisplay: CGRect,
                         options: NSApplication.PresentationOptions = [], nativeFullscreen: Bool = false) -> Bool {
        // Leave native fullscreen chrome entirely to macOS.
        if nativeFullscreen { return true }
        if options.contains(.hideMenuBar) || options.contains([.fullScreen, .autoHideMenuBar]) { return true }
        if isOverview(records: records, dockPID: dockPID, displays: displays) { return true }
        guard frontPID > 0, !menuBarDisplay.isEmpty else { return false }
        return records.contains { row in
            row.pid == frontPID && row.layer >= Int(CGWindowLevelForKey(.mainMenuWindow)) && row.visible
                && row.frame.contains(menuBarDisplay.insetBy(dx: 8, dy: 8))
        }
    }
    static func isOverview(windows: [[String: Any]], dockPID: pid_t, displays: [CGRect]) -> Bool {
        isOverview(records: windows.compactMap { WindowServerSnapshot.Window($0 as NSDictionary) }, dockPID: dockPID, displays: displays)
    }
    private static func isOverview(records: [WindowServerSnapshot.Window], dockPID: pid_t, displays: [CGRect]) -> Bool {
        records.contains { row in
            row.pid == dockPID && (18...20).contains(row.layer) && row.visible
                && displays.contains { !$0.isEmpty && row.frame.contains($0.insetBy(dx: 8, dy: 8)) }
        }
    }
}
