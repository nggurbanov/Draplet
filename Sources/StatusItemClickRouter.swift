import AppKit

// A foreign transparent hit window can sit above MenuBarAgent's native button.
// Claim balanced clicks in our native toggle (without the system press bezel),
// or in a rendered status slot obstructed by a different managed publisher.
// Native Command drags and placement always pass through.
struct StatusItemClickPolicy {
    enum Result { case pass, consume, click(CGMouseButton, CGEventFlags) }
    private struct Press { let button:CGMouseButton;let frame:CGRect;let identity:String;var cancelled = false }
    private var press:Press?
    mutating func invalidate() { press?.cancelled = true }
    static func obstructed(_ point:CGPoint,windows:[WindowServerSnapshot.Window],owner:pid_t,
                           routerOwner:pid_t? = nil,eligibleOwners:Set<pid_t>? = nil) -> Bool {
        // WindowServer supplies front-to-back order. A publisher's own native
        // hit surface, our Pocket button, and a higher popup keep their input.
        guard let top = windows.first(where:{ $0.visible && $0.layer > 25 && $0.frame.contains(point) }),
              top.pid != owner,top.pid != routerOwner,(26...29).contains(top.layer),
              top.frame.height <= 80,top.frame.width <= 600 else { return false }
        return eligibleOwners.map { $0.contains(top.pid) } ?? true
    }
    static func canClaimToggle(_ point:CGPoint,windows:[WindowServerSnapshot.Window],owner:pid_t) -> Bool {
        guard let top = windows.first(where:{ $0.visible && $0.layer > 25 && $0.frame.contains(point) }) else { return true }
        return top.pid != owner && (26...29).contains(top.layer) && top.frame.height <= 80 && top.frame.width <= 600
    }
    mutating func route(_ type:CGEventType,point:CGPoint,flags:CGEventFlags,programmatic:Bool,
                        frame:CGRect?,identity:String = "toggle",obstructed:Bool) -> Result {
        if programmatic { return .pass }
        let button:CGMouseButton
        switch type {
        case .leftMouseDown,.leftMouseUp,.leftMouseDragged:button = .left
        case .rightMouseDown,.rightMouseUp,.rightMouseDragged:button = .right
        default:return .pass
        }
        if type == .leftMouseDown || type == .rightMouseDown {
            guard press == nil,!flags.contains(.maskCommand),obstructed,let frame,!frame.isEmpty,frame.contains(point) else { return .pass }
            press = Press(button:button,frame:frame,identity:identity);return .consume
        }
        guard let press,press.button == button else { return .pass }
        if type == .leftMouseDragged || type == .rightMouseDragged { return .consume }
        self.press = nil
        guard !press.cancelled,!flags.contains(.maskCommand),identity == press.identity,
              frame == press.frame,press.frame.contains(point) else { return .consume }
        return .click(button,flags)
    }
}

final class StatusItemClickRouter {
    struct Target {
        let identity:String
        let owner:pid_t
        let frame:CGRect
        let element:AXUIElement?
        let identifier:String?
        var isToggle:Bool { element == nil }
        init(_ item:PocketInventory.HostedItem) {
            identifier = item.identifier
            identity = "\(item.owner):\(item.identifier ?? String(CFHash(item.element)))";owner = item.owner;frame = item.frame;element = item.element
        }
        init(toggle frame:CGRect) { identity = "toggle";owner = getpid();self.frame = frame;element = nil;identifier = nil }
    }
    var frame:CGRect?
    var nativeTargets:[Target] = []
    var managedOwners = Set<pid_t>()
    var onClick:((Target,CGMouseButton,CGEventFlags)->Void)?
    var onCommandChange:(()->Void)?
    private var pressedTarget:Target?
    private var policy = StatusItemClickPolicy()
    private var tap:CFMachPort?
    private var source:CFRunLoopSource?
    private var commandDown = NSEvent.modifierFlags.contains(.command)
    var available:Bool { tap != nil }
    init() {
        let mask = [CGEventType.leftMouseDown,.leftMouseUp,.leftMouseDragged,.rightMouseDown,.rightMouseUp,.rightMouseDragged,.flagsChanged]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        tap = CGEvent.tapCreate(tap:.cgSessionEventTap,place:.headInsertEventTap,options:.defaultTap,eventsOfInterest:mask,callback:{ _,type,event,context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<StatusItemClickRouter>.fromOpaque(context).takeUnretainedValue().handle(type,event)
        },userInfo:Unmanaged.passUnretained(self).toOpaque())
        if let tap {
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0)
            CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes)
            CGEvent.tapEnable(tap:tap,enable:true)
        }
    }
    private func handle(_ type:CGEventType,_ event:CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            policy.invalidate();frame = nil;nativeTargets = []
            if let tap { CGEvent.tapEnable(tap:tap,enable:true) }
            onCommandChange?();return Unmanaged.passUnretained(event)
        }
        if type == .flagsChanged {
            let down = event.flags.contains(.maskCommand)
            if down != commandDown {
                commandDown = down;policy.invalidate();frame = nil;nativeTargets = [];onCommandChange?()
            }
            return Unmanaged.passUnretained(event)
        }
        let programmatic = event.getIntegerValueField(.eventSourceUserData) == PocketItemEvents.placementEventTag
        let target:Target?
        if let frame,frame.contains(event.location) { target = Target(toggle:frame) }
        else {
            let matches = nativeTargets.filter { $0.frame.contains(event.location) }
            target = matches.count == 1 ? matches.first : nil
        }
        // A custom hit window can move without changing its window ID. Only a
        // down in a known status slot forces fresh geometry; idle consumers
        // and subsequent drag/up events keep sharing the existing snapshot.
        if !programmatic,target != nil,type == .leftMouseDown || type == .rightMouseDown {
            WindowServerSnapshot.shared.invalidate()
        }
        let blocked = !programmatic && target.map {
            let windows = WindowServerSnapshot.shared.current()
            if $0.isToggle { return StatusItemClickPolicy.canClaimToggle(event.location,windows:windows,owner:getpid()) }
            return StatusItemClickPolicy.obstructed(event.location,windows:windows,owner:$0.owner,
                                                   routerOwner:getpid(),eligibleOwners:managedOwners)
        } == true
        switch policy.route(type,point:event.location,flags:event.flags,programmatic:programmatic,frame:target?.frame,
                            identity:target?.identity ?? "",obstructed:blocked) {
        case .pass:return Unmanaged.passUnretained(event)
        case .consume:
            if type == .leftMouseDown || type == .rightMouseDown { pressedTarget = target }
            if type == .leftMouseUp || type == .rightMouseUp { pressedTarget = nil }
            return nil
        case let .click(button,flags):
            let original = pressedTarget;pressedTarget = nil
            if let original { DispatchQueue.main.async { [weak self] in self?.onClick?(original,button,flags) } }
            return nil
        }
    }
    func stop() {
        frame = nil;nativeTargets = [];pressedTarget = nil;policy.invalidate()
        if let tap { CGEvent.tapEnable(tap:tap,enable:false);CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(),source,.commonModes) }
        source = nil;tap = nil
    }
    deinit { stop() }
}
