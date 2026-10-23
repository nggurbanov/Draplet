import AppKit

enum NativeMenuTrackingPolicy {
    static func isTracking(_ windows: [WindowServerSnapshot.Window], ownPID: pid_t, pocketWindow: Int?) -> Bool {
        windows.contains {
            $0.visible && $0.pid != ownPID && $0.number != pocketWindow
                && $0.frame.width > 2 && $0.frame.height > 2
                && $0.layer >= Int(CGWindowLevelForKey(.popUpMenuWindow)) && $0.layer < 110
        }
    }
}

// The delay begins on departure, never on expansion or a periodic timer tick.
struct RightAutoHidePolicy {
    private(set) var outsideSince: TimeInterval?

    mutating func reset() { outsideSince = nil }

    mutating func shouldHide(now: TimeInterval, held: Bool, delay: TimeInterval) -> Bool {
        guard !held else { reset(); return false }
        guard let start = outsideSince else { outsideSince = now; return false }
        return now - start >= max(1, delay.isFinite ? delay : 5)
    }
}
