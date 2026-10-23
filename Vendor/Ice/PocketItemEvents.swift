// Adapted from Ice MenuBarItemManager.swift (Jordan Baird and contributors).
// GPL-3.0; upstream revision and modifications in Vendor/Ice/ORIGIN.md.
// Modified for Draplet 2026-10-18: namespaced helper, optional window routing
// for macOS 27's shared MenuBarAgent surface; no persistent event taps.
// 2026-10-23: tagged HID placement keeps Command through release, retargets
// after native reflow and retains a balancing release for cancellation/quit.
import AppKit

// The event's target-window fields are the same ones used by Ice. Call only
// after resolving a fresh visible frame; stale/offscreen coordinates must not
// deliver clicks to another application.
enum PocketItemEvents {
    static let placementEventTag:Int64 = 0x445241504C4554
    // Owned only by the main-thread placement task. Quit/cancellation must be
    // able to balance its down even if the awaiting task will never resume.
    private static var placementRelease:CGEvent?
    static var isPlacing:Bool { placementRelease != nil }
    static func cancelPlacement() {
        guard let release = placementRelease else { return }
        placementRelease = nil;release.post(tap:.cghidEventTap)
    }
    static func placementEvent(_ type:CGEventType,point:CGPoint,source:CGEventSource) -> CGEvent? {
        guard let event = CGEvent(mouseEventSource:source,mouseType:type,mouseCursorPosition:point,mouseButton:.left) else { return nil }
        event.flags = .maskCommand
        event.setIntegerValueField(.eventSourceUserData,value:placementEventTag)
        event.setIntegerValueField(.mouseEventClickState,value:1)
        return event
    }
    // A verified native status-item move, never an AppKit window/image drag.
    // Always release the button, including when the surrounding task cancels.
    @MainActor static func move(frame:CGRect,to point:CGPoint,retarget:(@MainActor () async -> CGPoint?)? = nil) async -> Bool {
        guard !isPlacing,!frame.isEmpty,point.x.isFinite,point.y.isFinite,
              NSEvent.pressedMouseButtons & 1 == 0,
              let source = CGEventSource(stateID:.hidSystemState) else { return false }
        let origin = CGPoint(x:frame.midX,y:frame.midY)
        guard let down = placementEvent(.leftMouseDown,point:origin,source:source),
              let drag = placementEvent(.leftMouseDragged,point:point,source:source),
              let up = placementEvent(.leftMouseUp,point:point,source:source) else { return false }
        source.localEventsSuppressionInterval = 0
        let cursor = CGEvent(source:nil)?.location
        var destination = point,hasTarget = retarget == nil
        up.location = origin;placementRelease = up
        defer { if placementRelease === up { cancelPlacement() } }
        // macOS 27's native status host handles this at the HID boundary. Keep
        // Command down through release, just as in a real menu-item drag.
        down.post(tap:.cghidEventTap)
        try? await Task.sleep(for:.milliseconds(100))
        guard placementRelease === up,!Task.isCancelled else { return false }
        up.location = point
        drag.post(tap:.cghidEventTap)
        try? await Task.sleep(for:.milliseconds(100))
        if !Task.isCancelled,let retarget,let target = await retarget(),target.x.isFinite,target.y.isFinite,
           let adjusted = placementEvent(.leftMouseDragged,point:target,source:source) {
            // Pulling the source out repacks its neighbours. Resolve the same
            // disclosure again while dragging rather than dropping at its old
            // location, which may now belong to a different item.
            guard placementRelease === up,!Task.isCancelled else { return false }
            destination = target;hasTarget = true;up.location = target;adjusted.post(tap:.cghidEventTap)
            try? await Task.sleep(for:.milliseconds(100))
        }
        guard placementRelease === up else { return false }
        up.location = destination;up.post(tap:.cghidEventTap);placementRelease = nil
        try? await Task.sleep(for:.milliseconds(60))
        if let cursor,let current = CGEvent(source:nil)?.location,
           hypot(current.x-destination.x,current.y-destination.y)<3 { CGWarpMouseCursorPosition(cursor) }
        return hasTarget && !Task.isCancelled
    }
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
