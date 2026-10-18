import AppKit

// Main-thread readers share one observation. The 20 Hz presentation watcher
// still gets a fresh sample on every tick; animation/capture/scene callbacks
// between ticks reuse it instead of repeating WindowServer IPC and bridging.
final class WindowServerSnapshot {
    struct Window {
        let number: Int
        let pid: pid_t
        let layer: Int
        let frame: CGRect
        let alpha: Double
        let onScreen: Bool
        init?(_ row: NSDictionary) {
            guard let bounds = row[kCGWindowBounds] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
            number = row[kCGWindowNumber] as? Int ?? 0
            pid = row[kCGWindowOwnerPID] as? pid_t ?? 0
            layer = row[kCGWindowLayer] as? Int ?? 0
            self.frame = frame
            alpha = row[kCGWindowAlpha] as? Double ?? 1
            onScreen = row[kCGWindowIsOnscreen] as? Bool ?? true
        }
        var visible: Bool { onScreen && alpha > 0.01 }
    }
    static let shared = WindowServerSnapshot()
    private let read: () -> [NSDictionary]
    private let readIDs: () -> [UInt32]?
    private let readWindow: (UInt32) -> NSDictionary?
    private var sampledAt = -Double.infinity
    private var detailedAt = -Double.infinity
    private var ids: [UInt32]?
    private var windows: [Window] = []
    init(read: @escaping () -> [NSDictionary] = {
        CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [NSDictionary] ?? []
    }, readIDs: @escaping () -> [UInt32]? = {
        DrapletOnScreenWindowIDs()?.map { $0.uint32Value }
    }, readWindow: @escaping (UInt32) -> NSDictionary? = { id in
        (CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [NSDictionary])?.first
    }) { self.read = read; self.readIDs = readIDs; self.readWindow = readWindow }
    func current(at time: TimeInterval = ProcessInfo.processInfo.systemUptime, freshGeometry: Bool = false) -> [Window] {
        guard time - sampledAt >= 0.04 else { return windows }
        sampledAt = time
        let nextIDs = readIDs()
        if nextIDs == nil || nextIDs != ids || time - detailedAt >= 0.25 || freshGeometry {
            windows = read().compactMap(Window.init)
            detailedAt = time; ids = nextIDs
        } else {
            // A Dock canvas may fade/resize without changing its window ID.
            // Refresh only these tiny metadata records at the original 20 Hz.
            // Existing status-level game canvases receive the same treatment.
            for index in windows.indices where (18...20).contains(windows[index].layer)
                || ((24...30).contains(windows[index].layer) && windows[index].frame.height > 100) {
                if let row = readWindow(UInt32(windows[index].number)), let value = Window(row) { windows[index] = value }
                else { detailedAt = -Double.infinity }
            }
        }
        return windows
    }
    func invalidate() { sampledAt = -Double.infinity; detailedAt = -Double.infinity }
}
