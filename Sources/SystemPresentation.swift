import AppKit

// Some games cover the native bar with a screen-sized status-level window while
// both AppKit visibility APIs still report a normal menu bar. Native fullscreen
// apps can do the same, so combine window geometry with their focused AX window.
// This uses existing Accessibility access, without pixel capture.
enum SystemPresentation {
    private static var dockPID: pid_t?
    static func forgetDock(pid: pid_t) { if dockPID == pid { dockPID = nil } }
    private static var geometry: (displays: [CGRect], menuBar: CGRect)?
    static func invalidateDisplays() { geometry = nil }
    static func current() -> Bool {
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let nativeFullscreen = ForegroundFullscreen.shared.current(pid: frontPID)
        if dockPID == nil {
            dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        }
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        if geometry == nil {
            let displays = NSScreen.screens.compactMap { screen in
                (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
                    .map { CGDisplayBounds($0.uint32Value) }
            }
            geometry = (displays, CGDisplayBounds(CGMainDisplayID()))
        }
        let geometry = geometry!
        return isActive(windows: windows, dockPID: dockPID ?? -1,
                        frontPID: frontPID,
                        displays: geometry.displays, menuBarDisplay: geometry.menuBar,
                        options: NSApp.currentSystemPresentationOptions, nativeFullscreen: nativeFullscreen)
    }
    static func isActive(windows: [[String: Any]], dockPID: pid_t, frontPID: pid_t,
                         displays: [CGRect], menuBarDisplay: CGRect,
                         options: NSApplication.PresentationOptions = [], nativeFullscreen: Bool = false) -> Bool {
        // Leave native fullscreen chrome entirely to macOS. A nonactivating
        // cover can otherwise keep its titlebar awake or leave our title behind.
        if nativeFullscreen { return true }
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
