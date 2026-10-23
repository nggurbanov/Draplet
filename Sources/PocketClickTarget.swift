import AppKit
import SwiftUI

struct PocketClickTarget: NSViewRepresentable {
    let label: String
    let itemID: String
    let enabled: Bool
    let pinned: Bool
    let image: NSImage?
    let place: () -> Void
    let beginDrag: (String) -> Bool
    let endDrag: (NSPoint,Bool) -> Void
    let moveDrag: (NSPoint,Bool) -> Void
    let drop: (String,Bool,Bool) -> Bool
    let dropHover: (Bool?) -> Void
    let focus: (Bool) -> Void
    let move: (UInt16) -> String?
    let activate: (CGMouseButton) -> Void
    func makeNSView(context: Context) -> Target {
        let button = Target(); button.isBordered = false; button.isTransparent = true; button.title = ""
        button.target = button; button.action = #selector(Target.pressed)
        button.focusRingType = .exterior
        return button
    }
    func updateNSView(_ button: Target, context: Context) {
        button.setAccessibilityLabel(label); button.isEnabled = enabled; button.activate = activate
        button.itemID = itemID; button.focus = focus; button.move = move
        button.pinned = pinned; button.place = place
        button.dragImage = image; button.beginDrag = beginDrag; button.endDrag = endDrag
        button.drop = drop; button.dropHover = dropHover;button.moveDrag = moveDrag
    }
    class Target: NSButton {
        var activate: ((CGMouseButton) -> Void)?
        var itemID = ""
        var pinned = false
        var place: (() -> Void)?
        var dragImage: NSImage?
        var beginDrag: ((String) -> Bool)?
        var endDrag: ((NSPoint,Bool) -> Void)?
        var moveDrag: ((NSPoint,Bool) -> Void)?
        var drop: ((String,Bool,Bool) -> Bool)?
        var dropHover: ((Bool?) -> Void)?
        private var activeDrag = false
        private var dragOrigin: NSEvent?
        var focus: ((Bool) -> Void)?
        var move: ((UInt16) -> String?)?
        override var acceptsFirstResponder: Bool { isEnabled }
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event:NSEvent?) -> Bool { isEnabled }
        override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            dragOrigin = nil
            guard event.modifierFlags.contains(.command) else { super.mouseDown(with:event); return }
            window?.makeFirstResponder(self)
            dragOrigin = event
        }
        override func mouseDragged(with event:NSEvent) {
            if activeDrag {
                guard isEnabled,event.modifierFlags.contains(.command) else { finishDrag(at:screenPoint(event),command:false);return }
                moveDrag?(screenPoint(event),true);return
            }
            guard let origin = dragOrigin else { return }
            guard isEnabled,event.modifierFlags.contains(.command) else { dragOrigin = nil; return }
            guard hypot(event.locationInWindow.x-origin.locationInWindow.x,event.locationInWindow.y-origin.locationInWindow.y) >= 4 else { return }
            dragOrigin = nil
            let token = UUID().uuidString
            guard beginDrag?(token) == true else { return }
            activeDrag = true
            startDrag(token:token,event:event)
        }
        override func mouseUp(with event:NSEvent) {
            if activeDrag { finishDrag(at:screenPoint(event),command:event.modifierFlags.contains(.command));return }
            guard dragOrigin != nil else { return }
            dragOrigin = nil
            if isEnabled,bounds.contains(convert(event.locationInWindow,from:nil)) { activate?(.left) }
        }
        private func screenPoint(_ event:NSEvent) -> NSPoint {
            window?.convertPoint(toScreen:event.locationInWindow) ?? NSEvent.mouseLocation
        }
        // The entire gesture stays inside Draplet. A system NSDraggingSession
        // would expose this menu-bar return to the OS's top-edge drag handling.
        func startDrag(token:String,event:NSEvent) { moveDrag?(screenPoint(event),true) }
        private func finishDrag(at point:NSPoint,command:Bool) {
            guard activeDrag else { return }
            activeDrag = false;dragOrigin = nil;endDrag?(point,command)
        }
        func updateLocalDrop(at point:NSPoint,token:String,command:Bool,commit:Bool) -> Bool {
            guard let window else { dropHover?(nil);return false }
            let local = convert(window.convertPoint(fromScreen:point),from:nil)
            let after = local.x >= bounds.midX
            guard isEnabled,command,visibleRect.contains(local),drop?(token,after,commit) == true else { dropHover?(nil);return false }
            dropHover?(commit ? nil : after);return true
        }
        override func flagsChanged(with event:NSEvent) {
            if !event.modifierFlags.contains(.command) {
                dragOrigin = nil
                if activeDrag { finishDrag(at:NSEvent.mouseLocation,command:false) }
            }
            super.flagsChanged(with:event)
        }
        override func viewWillMove(toWindow newWindow:NSWindow?) {
            if newWindow == nil,activeDrag { finishDrag(at:NSEvent.mouseLocation,command:false) }
            super.viewWillMove(toWindow:newWindow)
        }
        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted { focus?(true) }
            return accepted
        }
        override func resignFirstResponder() -> Bool {
            let accepted = super.resignFirstResponder()
            if accepted { focus?(false) }
            return accepted
        }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53,dragOrigin != nil || activeDrag {
                dragOrigin = nil
                if activeDrag { finishDrag(at:NSEvent.mouseLocation,command:false) }
                return
            }
            guard isEnabled, event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { super.keyDown(with: event); return }
            if [123, 124, 125, 126].contains(event.keyCode), let id = move?(event.keyCode) {
                func target(in view: NSView) -> Target? {
                    if let button = view as? Target, button.itemID == id { return button }
                    for child in view.subviews { if let match = target(in: child) { return match } }
                    return nil
                }
                if let content = window?.contentView, let button = target(in: content) { window?.makeFirstResponder(button) }
                return
            }
            if event.keyCode == 36 || event.keyCode == 49 { activate?(.left); return }
            super.keyDown(with: event)
        }
        @objc func pressed() { activate?(.left) }
        override func rightMouseDown(with event: NSEvent) { }
        @objc private func applicationMenu() { activate?(.right) }
        @objc private func changePlacement() { place?() }
        override func rightMouseUp(with event: NSEvent) {
            guard isEnabled else { return }
            let menu = NSMenu()
            let native = menu.addItem(withTitle:"Open Application Menu",action:#selector(applicationMenu),keyEquivalent:""); native.target = self
            menu.addItem(.separator())
            let placement = menu.addItem(withTitle:pinned ? "Return to Menu Bar" : "Keep in Pocket",action:#selector(changePlacement),keyEquivalent:""); placement.target = self
            let note = menu.addItem(withTitle:"All status icons from this app move together",action:nil,keyEquivalent:""); note.isEnabled = false
            menu.popUp(positioning:nil,at:convert(event.locationInWindow,from:nil),in:self)
        }
    }
}
