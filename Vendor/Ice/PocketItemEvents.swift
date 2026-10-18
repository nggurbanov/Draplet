// Adapted from Ice MenuBarItemManager.swift (Jordan Baird and contributors).
// GPL-3.0; upstream revision and modifications in Vendor/Ice/ORIGIN.md.
// Modified for Draplet 2026-10-18: namespaced helper, optional window routing
// for macOS 27's shared MenuBarAgent surface; no persistent event taps.
import AppKit

// The event's target-window fields are the same ones used by Ice. Call only
// after resolving a fresh visible frame; stale/offscreen coordinates must not
// deliver clicks to another application.
enum PocketItemEvents {
    static func event(type: CGEventType, point: CGPoint, windowID: CGWindowID?, pid: pid_t,
                      button: CGMouseButton, source: CGEventSource) -> CGEvent? {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: button) else { return nil }
        event.flags = []
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.setIntegerValueField(.eventSourceUserData, value: Int64(truncatingIfNeeded: Int(bitPattern: ObjectIdentifier(event))))
        if let windowID {
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
            event.setIntegerValueField(CGEventField(rawValue: 0x33)!, value: Int64(windowID))
        }
        return event
    }
    static func click(frame: CGRect, windowID: CGWindowID?, pid: pid_t, button: CGMouseButton) async -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        guard let down = event(type: button == .right ? .rightMouseDown : .leftMouseDown, point: point,
                               windowID: windowID, pid: pid, button: button, source: source),
              let up = event(type: button == .right ? .rightMouseUp : .leftMouseUp, point: point,
                             windowID: windowID, pid: pid, button: button, source: source) else { return false }
        source.localEventsSuppressionInterval = 0
        let cursor = CGEvent(source: nil)?.location
        down.post(tap: .cgSessionEventTap)
        // Give WindowServer a turn to route the event before restoring the
        // cursor. Ice waits for event-tap acknowledgements for the same reason.
        // Always send mouse-up, even when the operation is cancelled.
        try? await Task.sleep(for: .milliseconds(20))
        up.post(tap: .cgSessionEventTap)
        try? await Task.sleep(for: .milliseconds(60))
        if let cursor, let current = CGEvent(source: nil)?.location,
           abs(current.x - point.x) < 3 && abs(current.y - point.y) < 3 { CGWarpMouseCursorPosition(cursor) }
        return true
    }
}
