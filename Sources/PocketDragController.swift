import AppKit
import ApplicationServices

// One narrow event tap: only a verified Command-drag from a third-party status
// extra can redirect a release inside the currently visible Pocket target.
final class PocketDragController {
    var onStart: ((PocketItem,CGPoint) -> Void)?
    var onMove: ((CGPoint) -> Void)?
    var onDrop: ((PocketItem) -> Void)?
    var onCancel: (() -> Void)?
    var targetFrame: (() -> CGRect?)?
    var ownedSources: (() -> [PocketItem])?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []
    private var policy = PocketDragDropPolicy()
    private var generation = 0
    private var downPoint: CGPoint?
    private var latestPoint = CGPoint.zero
    private var item: PocketItem?
    private var shown = false
    private var areas: [CGRect] = []
    var available: Bool { tap != nil }
    init() {
        refreshGeometry()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in self?.cancel() })
        }
        observers.append(NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in self?.cancel(); self?.refreshGeometry() })
        let mask = [CGEventType.leftMouseDown,.leftMouseDragged,.leftMouseUp,.keyDown].reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        tap = CGEvent.tapCreate(tap:.cgSessionEventTap,place:.headInsertEventTap,options:.defaultTap,eventsOfInterest:mask,callback: { _,type,event,context in
            guard let context else { return Unmanaged.passUnretained(event) }
            Unmanaged<PocketDragController>.fromOpaque(context).takeUnretainedValue().handle(type,event)
            return Unmanaged.passUnretained(event)
        },userInfo:Unmanaged.passUnretained(self).toOpaque())
        if let tap, let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0) {
            self.source = source; CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes)
            CGEvent.tapEnable(tap:tap,enable:true)
        }
    }
    private func refreshGeometry() {
        areas = NSScreen.screens.compactMap { screen in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
            let display = CGDisplayBounds(id), start = screen.auxiliaryTopRightArea?.minX ?? screen.frame.midX
            return CGRect(x:start,y:display.minY,width:display.maxX-start,height:max(24,max(screen.safeAreaInsets.top,NSStatusBar.system.thickness)))
        }
    }
    private func handle(_ type: CGEventType, _ event: CGEvent) {
        // Do not interpret Draplet's verified native return as another pin drag.
        if event.getIntegerValueField(.eventSourceUserData) == PocketItemEvents.placementEventTag { return }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancel(); if let tap { CGEvent.tapEnable(tap:tap,enable:true) }; return
        }
        switch type {
        case .leftMouseDown:
            cancel()
            let point = event.location
            guard event.flags.contains(.maskCommand), let area = areas.first(where: { $0.contains(point) }) else { return }
            downPoint = point; latestPoint = point
            let owned = ownedSources?() ?? []
            let token = generation
            DispatchQueue.global(qos:.userInitiated).async { [weak self] in
                var resolved: (PocketItem,CGRect)?
                if !owned.isEmpty {
                    var displayID = CGMainDisplayID(),count: UInt32 = 0
                    if CGGetDisplaysWithPoint(point,1,&displayID,&count) == .success,count > 0 {
                        let host = PocketInventory.hostSnapshot(on:CGDisplayBounds(displayID))
                        let bindings = Dictionary(uniqueKeysWithValues:owned.map { ($0.id,CompatibilityMenuPolicy.identifier($0.imageIdentity)) })
                        let frames = CompatibilityMenuPolicy.frames(bindings:bindings,host:host,owner:getpid())
                        let matches = owned.compactMap { item in frames[item.id].flatMap { $0.contains(point) ? (item,$0) : nil } }
                        if matches.count == 1 { resolved = matches[0] }
                    }
                }
                if resolved == nil { resolved = PocketInventory.dragSource(at:point,area:area) }
                let selected = resolved
                DispatchQueue.main.async { [weak self] in
                    guard let self, token == self.generation, self.downPoint != nil,
                          NSEvent.pressedMouseButtons & 1 != 0, NSEvent.modifierFlags.contains(.command), let resolved = selected else { return }
                    self.item = resolved.0
                    self.policy.begin(at:point,command:true,source:resolved.1)
                    self.policy.moved(to:self.latestPoint)
                    self.presentIfDragging()
                }
            }
        case .leftMouseDragged:
            guard downPoint != nil else { return }
            guard event.flags.contains(.maskCommand) else { cancel(); return }
            latestPoint = event.location; policy.moved(to:event.location)
            presentIfDragging()
            if shown { onMove?(event.location) }
        case .leftMouseUp:
            guard event.flags.contains(.maskCommand) else { cancel(); return }
            let selected = item
            let origin = policy.end(at:event.location,target:shown ? targetFrame?() : nil)
            if let origin, let selected {
                event.location = origin
                generation += 1; downPoint = nil; item = nil; shown = false
                let token = generation
                // Let WindowServer finish the native drag at its original slot
                // before saving a placement that reflows the real bar.
                DispatchQueue.main.asyncAfter(deadline:.now()+0.1) { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.onDrop?(selected)
                }
            } else { cancel() }
        case .keyDown:
            // Ignore every key unless this controller owns an item drag.
            if downPoint != nil && event.getIntegerValueField(.keyboardEventKeycode) == 53 { cancel() }
        default: break
        }
    }
    private func presentIfDragging() {
        guard !shown, policy.dragging, let item,let origin = downPoint else { return }
        shown = true
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.shown, self.generation == token else { return }
            self.onStart?(item,origin)
        }
    }
    func cancel() {
        let wasShown = shown
        generation += 1; downPoint = nil; item = nil; shown = false; policy.cancel()
        if wasShown { DispatchQueue.main.async { [weak self] in self?.onCancel?() } }
    }
    func stop() {
        cancel()
        if let tap { CGEvent.tapEnable(tap:tap,enable:false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(),source,.commonModes) }
        tap = nil; source = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer); NotificationCenter.default.removeObserver(observer) }
        observers = []
    }
    deinit { stop() }
}
