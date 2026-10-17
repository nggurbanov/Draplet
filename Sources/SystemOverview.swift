import AppKit

// Use public WindowServer metadata to identify the Dock's screen-sized overview
// canvas. Ordinary Dock windows and Stage Manager thumbnails do not match.
enum SystemOverview {
    private static var dock: NSRunningApplication?
    static func current() -> Bool {
        if dock == nil || dock?.isTerminated == true {
            dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        }
        guard let pid = dock?.processIdentifier else { return false }
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let displays = NSScreen.screens.compactMap { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
                .map { CGDisplayBounds($0.uint32Value) }
        }
        return isActive(windows: windows, dockPID: pid, displays: displays)
    }
    static func isActive(windows: [[String: Any]], dockPID: pid_t, displays: [CGRect]) -> Bool {
        windows.contains { row in
            guard row[kCGWindowOwnerPID as String] as? pid_t == dockPID,
                  let layer = row[kCGWindowLayer as String] as? Int, (18...20).contains(layer),
                  (row[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let bounds = row[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return displays.contains { !$0.isEmpty && frame.contains($0.insetBy(dx: 8, dy: 8)) }
        }
    }
}
