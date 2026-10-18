import AppKit
import ApplicationServices

struct PermissionState: Equatable {
    let accessibility: Bool
    let screenCapture: Bool
}

// TCC preflight can block on synchronous XPC. Keep it off animation/UI threads,
// coalesce slow replies, and never query once per frame.
final class PermissionMonitor {
    typealias Query = (@escaping (PermissionState) -> Void) -> Void
    private let query: Query
    private var lastCheck = -Double.infinity
    private var inFlight = false
    private var stopped = false
    private var state: PermissionState?
    var onChange: ((PermissionState) -> Void)?
    init(query: @escaping Query = PermissionMonitor.querySystem) { self.query = query }
    func poll(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard !stopped, !inFlight, time - lastCheck >= 1 else { return }
        inFlight = true; lastCheck = time
        query { [weak self] value in
            guard let self, !self.stopped else { return }
            self.inFlight = false
            guard self.state != value else { return }
            self.state = value; self.onChange?(value)
        }
    }
    func stop() { stopped = true; onChange = nil }
    private static func querySystem(completion: @escaping (PermissionState) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let state = PermissionState(accessibility: AXIsProcessTrusted(), screenCapture: CGPreflightScreenCaptureAccess())
            DispatchQueue.main.async { completion(state) }
        }
    }
}
