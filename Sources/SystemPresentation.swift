import AppKit

// Some games cover the native bar with a screen-sized status-level window while
// both AppKit visibility APIs still report a normal menu bar. Observe actual
// window geometry as well as native presentation flags; no pixel capture or AX.
enum SystemPresentation {
    private static var dock: NSRunningApplication?
    static func current() -> Bool {
        if dock == nil || dock?.isTerminated == true {
            dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        }
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let displays = NSScreen.screens.compactMap { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
                .map { CGDisplayBounds($0.uint32Value) }
        }
        return isActive(windows: windows, dockPID: dock?.processIdentifier ?? -1,
                        frontPID: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1,
                        displays: displays, menuBarDisplay: CGDisplayBounds(CGMainDisplayID()),
                        options: NSApp.currentSystemPresentationOptions)
    }
    static func isActive(windows: [[String: Any]], dockPID: pid_t, frontPID: pid_t,
                         displays: [CGRect], menuBarDisplay: CGRect,
                         options: NSApplication.PresentationOptions = []) -> Bool {
        if options.contains(.hideMenuBar) || options.contains([.fullScreen, .autoHideMenuBar]) { return true }
        if isOverview(windows: windows, dockPID: dockPID, displays: displays) { return true }
        guard frontPID > 0, !menuBarDisplay.isEmpty else { return false }
        return windows.contains { row in
            guard row[kCGWindowOwnerPID as String] as? pid_t == frontPID,
                  let layer = row[kCGWindowLayer as String] as? Int,
                  layer >= Int(CGWindowLevelForKey(.mainMenuWindow)),
                  let frame = visibleFrame(row) else { return false }
            return frame.contains(menuBarDisplay.insetBy(dx: 8, dy: 8))
        }
    }
    static func isOverview(windows: [[String: Any]], dockPID: pid_t, displays: [CGRect]) -> Bool {
        windows.contains { row in
            guard row[kCGWindowOwnerPID as String] as? pid_t == dockPID,
                  let layer = row[kCGWindowLayer as String] as? Int, (18...20).contains(layer),
                  let frame = visibleFrame(row) else { return false }
            return displays.contains { !$0.isEmpty && frame.contains($0.insetBy(dx: 8, dy: 8)) }
        }
    }
    private static func visibleFrame(_ row: [String: Any]) -> CGRect? {
        guard row[kCGWindowIsOnscreen as String] as? Bool != false,
              (row[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
              let bounds = row[kCGWindowBounds as String] as? [String: Any] else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }
}
