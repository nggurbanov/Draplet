import AppKit

// NSRunningApplication scalar getters fetch dynamic LaunchServices metadata.
// Observe the KVO-compliant foreground property, then share plain PID/name.
// Workspace activation also invalidates this value; a 500 ms fallback covers
// missed notifications without performing expensive reads every 50 ms.
final class ForegroundApplication {
    struct Snapshot: Equatable {
        let pid: pid_t
        let name: String
    }
    static let shared = ForegroundApplication()
    private let read: () -> NSRunningApplication?
    private let resolve: (NSRunningApplication) -> Snapshot
    private var value: Snapshot?
    private var checkedAt = -Double.infinity
    private var observation: NSKeyValueObservation?
    init(read: @escaping () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication },
         resolve: @escaping (NSRunningApplication) -> Snapshot = {
             Snapshot(pid: $0.processIdentifier, name: $0.localizedName ?? "Application")
         }, observeSystem: Bool = true) {
        self.read = read; self.resolve = resolve
        if observeSystem {
            observation = NSWorkspace.shared.observe(\.frontmostApplication, options: [.initial, .new]) { [weak self] _, change in
                let app = change.newValue ?? nil
                if Thread.isMainThread { self?.observed(app) }
                else { DispatchQueue.main.async { guard let self else { return }; self.observed(self.read()) } }
            }
        }
    }
    func observed(_ application: NSRunningApplication?, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        value = application.map(resolve); checkedAt = time
    }
    func current(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Snapshot? {
        if time - checkedAt >= 0.5 { observed(read(), at: time) }
        return value
    }
    func invalidate() { checkedAt = -Double.infinity }
}
