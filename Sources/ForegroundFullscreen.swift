import AppKit
import ApplicationServices

// The accessory app's own presentationOptions do not describe another app's
// native fullscreen window. Read its focused window through existing AX access.
// One bounded request at a time; callbacks and stored state stay on main.
final class ForegroundFullscreen {
    typealias Query = (pid_t, @escaping (Bool) -> Void) -> Void
    static let shared = ForegroundFullscreen()
    static let interval: TimeInterval = 0.25
    private static let queue = DispatchQueue(label: "Draplet.FullscreenState", qos: .userInitiated)
    private let query: Query
    private var pid: pid_t = 0
    private var generation = 0
    private var inFlight = false
    private var lastQuery = -Double.infinity
    private var cached: [pid_t: Bool] = [:]
    private var warming = Set<pid_t>()
    private(set) var isFullscreen = false
    var onChange: (() -> Void)?

    init(query: @escaping Query = ForegroundFullscreen.queryWindow) { self.query = query }

    func current(pid nextPID: pid_t, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        if pid != nextPID {
            pid = nextPID; generation += 1; lastQuery = -Double.infinity
            if let known = cached[pid] { isFullscreen = known }
        }
        guard pid > 0 else { isFullscreen = false; return false }
        if !inFlight && time - lastQuery >= Self.interval {
            inFlight = true; lastQuery = time
            let token = generation, target = pid
            query(target) { [weak self] value in
                guard let self else { return }
                self.inFlight = false
                guard token == self.generation, target == self.pid else { return }
                self.cached[target] = value
                guard self.isFullscreen != value else { return }
                self.isFullscreen = value
                self.onChange?()
            }
        }
        // Keep a cover suppressed while the next app is being checked.
        return isFullscreen
    }

    func invalidate() { generation += 1; lastQuery = -Double.infinity }

    // Read already-running apps once, before the user first switches into a
    // fullscreen Space. These requests share queryWindow's serial AX queue.
    func prewarm(_ pids: [pid_t]) {
        for target in pids where target > 0 && cached[target] == nil && warming.insert(target).inserted {
            query(target) { [weak self] value in
                guard let self, self.warming.remove(target) != nil, self.cached[target] == nil else { return }
                self.cached[target] = value
                if self.pid == target && self.isFullscreen != value {
                    self.isFullscreen = value
                    self.onChange?()
                }
            }
        }
    }

    func forget(pid: pid_t) { cached.removeValue(forKey: pid); warming.remove(pid) }

    private static func queryWindow(pid: pid_t, completion: @escaping (Bool) -> Void) {
        queue.async {
            let value: Bool = {
                guard AXIsProcessTrusted() else { return false }
                let application = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(application, 0.05)
                var focused: CFTypeRef?
                guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focused) == .success,
                      let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
                let window = focused as! AXUIElement
                AXUIElementSetMessagingTimeout(window, 0.05)
                var fullscreen: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullscreen) == .success else { return false }
                return fullscreen as? Bool ?? false
            }()
            DispatchQueue.main.async { completion(value) }
        }
    }
}
