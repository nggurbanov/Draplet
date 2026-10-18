import Foundation

// Persist only a version-scoped deadline. A newer update earns its own reminder.
struct UpdateReminderPolicy {
    var version: String?
    var deferredUntil: Date?

    mutating func receive(_ version: String) {
        if self.version != version { self.version = version; deferredUntil = nil }
    }
    mutating func deferOneHour(from now: Date) { deferredUntil = now.addingTimeInterval(3600) }
    func isDue(at now: Date, presentationSuppressed: Bool) -> Bool {
        version != nil && !presentationSuppressed && (deferredUntil == nil || now >= deferredUntil!)
    }
}
