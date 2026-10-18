import Foundation

// Retry transient capture interruptions, never an unlimited recording loop.
struct CaptureRetryPolicy {
    private var attempts = 0
    mutating func failed(permissionGranted: Bool) -> TimeInterval? {
        guard permissionGranted, attempts < 2 else { return nil }
        let delay: TimeInterval = attempts == 0 ? 0.5 : 1.5
        attempts += 1
        return delay
    }
    mutating func reset() { attempts = 0 }
}
