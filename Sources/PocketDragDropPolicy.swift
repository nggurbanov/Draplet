import Foundation

enum PocketReturnDropPolicy {
    static func canBegin(pinned: Bool, commandAtMouseDown: Bool, commandNow: Bool) -> Bool {
        pinned && commandAtMouseDown && commandNow
    }
    static func matches(_ received: String?, expected: String) -> Bool { !expected.isEmpty && received == expected }
    static func shouldReturn(accepted: Bool, moved: Bool, active: Bool, command: Bool) -> Bool { accepted && moved && active && command }
}

// A drop can redirect native completion only after a Command-drag began on
// the explicitly supplied source and finished inside a current target.
struct PocketDragDropPolicy {
    private(set) var origin: CGPoint?
    private(set) var dragging = false
    mutating func begin(at point: CGPoint, command: Bool, source: CGRect?) {
        cancel()
        guard command, point.x.isFinite, point.y.isFinite,
              let source, !source.isEmpty, source.contains(point) else { return }
        origin = point
    }
    @discardableResult mutating func moved(to point: CGPoint) -> Bool {
        guard let origin else { return false }
        if hypot(point.x-origin.x, point.y-origin.y) >= 4 { dragging = true }
        return dragging
    }
    mutating func end(at point: CGPoint, target: CGRect?) -> CGPoint? {
        defer { cancel() }
        guard dragging, point.x.isFinite, point.y.isFinite,
              let target, !target.isEmpty, target.contains(point) else { return nil }
        return origin
    }
    mutating func cancel() { origin = nil; dragging = false }
}
