import AppKit

// Explicit QA mode only. Observe the native Command-drag of our disposable item;
// the optional intercept mode redirects only our TEST's confirmed target drop.
// Neither mode reads another application's pasteboard payload.
final class PocketDragProbe {
    private final class Target: NSView {
        var report: ((String) -> Void)?
        var highlighted = false { didSet { needsDisplay = true } }
        override func draw(_ dirtyRect: NSRect) {
            (highlighted ? NSColor.controlAccentColor.withAlphaComponent(0.22) : NSColor.controlBackgroundColor).setFill()
            bounds.fill()
            let text = "Drop TEST here\nNative drag probe · no real icons"
            (text as NSString).draw(in: bounds.insetBy(dx: 14, dy: 20), withAttributes: [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor
            ])
        }
        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            highlighted = true; report?("entered mask=\(sender.draggingSourceOperationMask.rawValue)")
            return .move
        }
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .move }
        override func draggingExited(_ sender: NSDraggingInfo?) { highlighted = false; report?("exited") }
        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            highlighted = false; report?("native-drop-delivered"); return true
        }
    }
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var anchor: NSStatusItem { item }
    private let popover = NSPopover()
    private let target = Target(frame: NSRect(x: 0, y: 0, width: 250, height: 80))
    private var global: Any?
    private var local: Any?
    private var armed = false
    private var dragging = false
    private var lastTypes: [NSPasteboard.PasteboardType] = []
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var policy = PocketDragDropPolicy()
    private var originalFrame: CGRect?
    private var redirectedDrop: CGPoint?
    private let intercept: Bool
    private let coordinateHeight = NSScreen.screens.first?.frame.maxY ?? 0
    init(intercept: Bool = false) {
        self.intercept = intercept
        item.button?.title = "TEST"
        item.button?.toolTip = "Disposable test icon · hold ⌘ and drag into the test target"
        item.behavior = [.removalAllowed]
        popover.behavior = .applicationDefined; popover.animates = false
        let controller = NSViewController(); controller.view = target
        popover.contentViewController = controller; popover.contentSize = target.frame.size
        target.report = { print("[DrapletDragProbe] \($0)"); fflush(stdout) }
        target.registerForDraggedTypes([.string, .tiff, .png])
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] in self?.observe($0) }
        local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in self?.observe(event); return event }
        if intercept {
            let eventMask = [CGEventType.leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown]
                .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
            tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: eventMask, callback: { _,type,event,context in
                    guard let context else { return Unmanaged.passUnretained(event) }
                    let probe = Unmanaged<PocketDragProbe>.fromOpaque(context).takeUnretainedValue()
                    probe.intercept(type, event)
                    return Unmanaged.passUnretained(event)
                }, userInfo: Unmanaged.passUnretained(self).toOpaque())
            guard let tap, let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                print("[DrapletDragProbe] active-tap-unavailable; no input changed; restoring daily app"); fflush(stdout)
                DispatchQueue.main.async { NSApp.terminate(nil) }; return
            }
            tapSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        print("[DrapletDragProbe] ready; only drag our TEST item; automatic exit in 120 seconds"); fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { NSApp.terminate(nil) }
    }
    private func cgFrame(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX,y: coordinateHeight-frame.maxY,width: frame.width,height: frame.height)
    }
    private func intercept(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            policy.cancel()
            if let tap { CGEvent.tapEnable(tap:tap,enable:true) }
            return
        }
        switch type {
        case .leftMouseDown:
            originalFrame = (item.button?.window?.frame).map(cgFrame)
            policy.begin(at:event.location,command:event.flags.contains(.maskCommand),source:originalFrame)
        case .leftMouseDragged:
            policy.moved(to:event.location)
            if popover.isShown, let window = target.window {
                target.highlighted = cgFrame(window.convertToScreen(target.convert(target.bounds,to:nil))).contains(event.location)
            }
        case .keyDown:
            if event.getIntegerValueField(.keyboardEventKeycode) == 53 { policy.cancel() }
        case .leftMouseUp:
            let targetFrame = popover.isShown ? target.window.map { cgFrame($0.convertToScreen(target.convert(target.bounds,to:nil))) } : nil
            if let origin = policy.end(at:event.location,target:targetFrame) {
                redirectedDrop = event.location
                event.location = origin
                print("[DrapletDragProbe] TEST-drop-redirected-to-original-slot"); fflush(stdout)
            }
        default: break
        }
    }
    private func observe(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            armed = event.modifierFlags.contains(.command) && item.button?.window?.frame.contains(NSEvent.mouseLocation) == true
        case .leftMouseDragged:
            guard armed else { return }
            let types = NSPasteboard(name: .drag).types ?? []
            if !dragging || types != lastTypes {
                dragging = true; lastTypes = types
                // Register types only; no payload or file names are read.
                target.registerForDraggedTypes(types.isEmpty ? [.string, .tiff, .png] : types)
                print("[DrapletDragProbe] native-drag types=\(types.map(\.rawValue))"); fflush(stdout)
            }
            if !popover.isShown, let button = anchor.button { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
        case .leftMouseUp:
            guard armed else { return }
            armed = false; dragging = false
            print("[DrapletDragProbe] mouse-up; native destination delivered separately if supported"); fflush(stdout)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                print("[DrapletDragProbe] test-item-visible=\(self.item.isVisible)"); fflush(stdout)
                if self.intercept {
                    let current = (self.item.button?.window?.frame).map(self.cgFrame)
                    print("[DrapletDragProbe] original=\(String(describing:self.originalFrame)) current=\(String(describing:current)) drop=\(String(describing:self.redirectedDrop)) cursor=\(String(describing:CGEvent(source:nil)?.location))")
                    fflush(stdout)
                }
                self.item.isVisible = true; self.popover.close()
                if self.intercept { NSApp.terminate(nil) }
            }
        default: break
        }
    }
    deinit {
        if let tap { CGEvent.tapEnable(tap:tap,enable:false); CFMachPortInvalidate(tap) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(),tapSource,.commonModes) }
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        popover.close()
        NSStatusBar.system.removeStatusItem(item)
    }
}
