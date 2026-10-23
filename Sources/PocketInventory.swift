import AppKit
import ApplicationServices
import Security

struct PocketItem: Identifiable {
    let id: String
    let bundle: String
    let pid: pid_t
    let name: String
    let element: AXUIElement
    let frame: CGRect // CoreGraphics coordinates, including for secondary displays
    let windowID: CGWindowID?
    var cacheKey: String? = nil
    var imageIdentity: String { cacheKey ?? "\(bundle)|slot:\(id.split(separator:":").last.map(String.init) ?? id)" }
}

// AX remains the source of identity on macOS 27: status items no longer have
// individual WindowServer windows there. Ice's individual-window capture is
// used where the OS still supplies those windows.
enum PocketInventory {
    static func read(completion: @escaping ([PocketItem]) -> Void) {
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> (pid_t, String, String)? in
            guard let bundle = app.bundleIdentifier, bundle != Bundle.main.bundleIdentifier,
                  app.bundleURL?.pathExtension == "app", !MenuBarLayoutResolver.systemItemOwners.contains(bundle) else { return nil }
            return (app.processIdentifier, bundle, app.localizedName ?? bundle)
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let disallowed = MenuBarAvailability.currentDisallowed()
            let windows = DrapletPocketWindows()
            var result: [PocketItem] = []
            for (pid, bundle, name) in apps {
                guard !disallowed.contains(bundle) else { continue }
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.1)
                guard let bar = attribute(app, "AXExtrasMenuBar") else { continue }
                let element = bar as! AXUIElement
                AXUIElementSetMessagingTimeout(element, 0.1)
                guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { continue }
                let keys = imageCacheKeys(bundle:bundle,identifiers:children.map { attribute($0,kAXIdentifierAttribute) as? String })
                for (index, child) in children.enumerated() {
                    AXUIElementSetMessagingTimeout(child, 0.1)
                    guard let frame = frame(child), frame.width > 0, frame.height > 0 else { continue }
                    let title = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
                        .compactMap { attribute(child, $0) as? String }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    let window = windows.first { row in
                        guard (row[kCGWindowOwnerPID] as? pid_t) == pid,
                              let bounds = row[kCGWindowBounds] as? NSDictionary,
                              let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
                        return abs(rect.midX - frame.midX) < 2 && abs(rect.midY - frame.midY) < 2
                    }
                    result.append(PocketItem(id: "\(pid):\(index)", bundle: bundle, pid: pid,
                                             name: title ?? name, element: child, frame: frame,
                                             windowID: window?[kCGWindowNumber] as? CGWindowID,cacheKey:keys[index]))
                }
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
    static func imageCacheKeys(bundle:String,identifiers:[String?]) -> [String] {
        let counts = Dictionary(grouping:identifiers.compactMap { $0 }.filter { !$0.isEmpty },by:{ $0 }).mapValues(\.count)
        return identifiers.enumerated().map { index,id in
            if let id,!id.isEmpty,counts[id] == 1 { return "\(bundle)|id:\(id)" }
            return "\(bundle)|slot:\(index)/\(identifiers.count)"
        }
    }
    struct HostedItem {
        let owner: pid_t
        let element: AXUIElement
        let frame: CGRect
        var name: String? = nil
        var identifier: String? = nil
    }
    struct HostSnapshot {
        let items: [HostedItem]
        let overflow: CGRect?
        var renderedItems: [HostedItem] {
            // On macOS 27 parked extras may still be AXButtons. Their host
            // rectangles overlap the overflow control or each other; they are
            // identity metadata, not separate visible pixels.
            items.enumerated().compactMap { index,item in
                guard overflow.map({ !item.frame.intersects($0) }) ?? true,
                      !items.enumerated().contains(where: { other,peer in
                          other != index && item.frame.intersection(peer.frame).width > 1
                              && item.frame.intersection(peer.frame).height > 1
                      }) else { return nil }
                return item
            }
        }
        func hasSameLayout(as other: HostSnapshot) -> Bool {
            let visible = renderedItems, otherVisible = other.renderedItems
            guard overflow == other.overflow, visible.count == otherVisible.count else { return false }
            // Broker child order is unstable; publisher identity and physical
            // rectangles are what can invalidate a disclosure position.
            return visible.allSatisfy { item in
                otherVisible.contains { $0.owner == item.owner && $0.frame == item.frame }
            }
        }
    }
    static func preferredHostSnapshot(_ candidates: [HostSnapshot]) -> HostSnapshot? {
        // MenuBarAgent may expose two windows with identical display bounds.
        // One contains rendered AXButtons, the other parked AXApplications.
        // Window ordering changes between reads; geometry alone cannot pick it.
        candidates.filter { !$0.items.isEmpty || $0.overflow != nil }.max {
            $0.items.count * 2 + ($0.overflow == nil ? 0 : 1)
                < $1.items.count * 2 + ($1.overflow == nil ? 0 : 1)
        }
    }
    // Adapted from Thaw's MenuBarAgentWindow.swift / AXPrimitives.swift,
    // Copyright (Thaw) 2026 Toni Förster, GPL-3.0. See Vendor/Thaw/ORIGIN.md.
    static func hostSnapshot(on display: CGRect = CGDisplayBounds(CGMainDisplayID())) -> HostSnapshot? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first?.processIdentifier else { return nil }
        let agent = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(agent, 0.1)
        guard let windows = attribute(agent,kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        var snapshots: [HostSnapshot] = []
        for window in windows {
            guard let windowBounds = frame(window),
                  abs(windowBounds.minX-display.minX) < 2 && abs(windowBounds.minY-display.minY) < 2 && abs(windowBounds.width-display.width) < 2,
                  let children = attribute(window,kAXChildrenAttribute) as? [AXUIElement] else { continue }
            var result: [HostedItem] = []
            var overflow: CGRect?
            for child in children {
                AXUIElementSetMessagingTimeout(child, 0.1)
                guard let bounds = frame(child), bounds.width > 0, bounds.height > 0 else { continue }
                // Resolve overflow in this display's window, not the global
                // extras bar, which may describe a different virtual display.
                var childPID:pid_t = 0; AXUIElementGetPid(child,&childPID)
                if childPID == pid, (attribute(child,kAXRoleAttribute) as? String) == kAXButtonRole,
                   bounds.width < 80 { overflow = bounds; continue }
                var leaf = child
                for _ in 0..<8 {
                    var owner: pid_t = 0
                    guard AXUIElementGetPid(leaf, &owner) == .success else { break }
                    if owner != pid {
                        let role = attribute(leaf,kAXRoleAttribute) as? String
                        // A parked AXApplication is identity metadata, not ink.
                        guard role == kAXButtonRole || role == kAXMenuBarItemRole else { break }
                        var entry = HostedItem(owner:owner,element:leaf,frame:bounds)
                        if owner == getpid() { entry.identifier = attribute(leaf,kAXIdentifierAttribute) as? String }
                        if owner != getpid() {
                            entry.name = [kAXTitleAttribute,kAXDescriptionAttribute,kAXHelpAttribute].compactMap { attribute(leaf,$0) as? String }.first { !$0.isEmpty }
                        }
                        result.append(entry); break
                    }
                    guard let next = (attribute(leaf, kAXChildrenAttribute) as? [AXUIElement])?.first else { break }
                    leaf = next; AXUIElementSetMessagingTimeout(leaf, 0.1)
                }
            }
            snapshots.append(HostSnapshot(items:result,overflow:overflow))
        }
        guard let selected = preferredHostSnapshot(snapshots) else { return nil }
        var overflow = selected.overflow
        if overflow == nil, let raw = attribute(agent, "AXExtrasMenuBar"), CFGetTypeID(raw) == AXUIElementGetTypeID() {
            let bar = raw as! AXUIElement; AXUIElementSetMessagingTimeout(bar, 0.1)
            if let rawButton = attribute(bar, "AXOverflowButton"), CFGetTypeID(rawButton) == AXUIElementGetTypeID() {
                let button = rawButton as! AXUIElement
                var owner:pid_t = 0; AXUIElementGetPid(button,&owner)
                if owner == pid, let value = frame(button), value.minX >= display.minX, value.maxX <= display.maxX { overflow = value }
            }
        }
        return HostSnapshot(items:selected.items,overflow:overflow)
    }
    static func readSettledHost(on display: CGRect, awaitingAbsenceOf owners: Set<pid_t> = [], completion: @escaping (HostSnapshot?) -> Void) {
        let queue = DispatchQueue.global(qos:.userInitiated)
        let deadline = ProcessInfo.processInfo.systemUptime + (owners.isEmpty ? 1 : 1.5)
        var settlement = PocketHostSettlement()
        func sample() {
            let host = hostSnapshot(on:display)
            let now = ProcessInfo.processInfo.systemUptime
            if settlement.accepts(host,at:now,awaitingAbsenceOf:owners) { completion(host); return }
            guard now < deadline else { completion(nil); return }
            queue.asyncAfter(deadline:.now()+0.06,execute:sample)
        }
        queue.async(execute:sample)
    }
    static func matchFrame(_ item: PocketItem, among items: [PocketItem], host: HostSnapshot) -> CGRect? {
        // Identity joining is also used during explicitly staged capture.
        // Layout/drag callers must pass or select rendered slots separately:
        // an unrelated parked owner's stale rectangle can overlap live ink.
        let entries = host.items.filter { $0.owner == item.pid }
        if let exact = entries.first(where: { CFEqual($0.element,item.element) }) { return exact.frame }
        // The host wraps the client's AXMenuBarItem in a different AX element.
        // Geometry can join them only if there is one matching owner/rectangle.
        let siblings = items.filter { $0.pid == item.pid }
        let named = entries.filter { $0.name == item.name }
        if named.count == 1 && siblings.filter({ $0.name == item.name }).count == 1 { return named[0].frame }
        if siblings.count == 1 && entries.count == 1 { return entries[0].frame }
        let possible = entries.filter { abs($0.frame.midX-item.frame.midX) < 2 && abs($0.frame.midY-item.frame.midY) < 8 }
        guard possible.count == 1,
              siblings.filter({ abs($0.frame.midX-item.frame.midX) < 2 && abs($0.frame.midY-item.frame.midY) < 8 }).count == 1 else { return nil }
        return possible[0].frame
    }
    static func hostedFrame(of item: PocketItem, on display: CGRect = CGDisplayBounds(CGMainDisplayID())) -> CGRect? {
        guard let host = hostSnapshot(on:display) else { return nil }
        let app = AXUIElementCreateApplication(item.pid); AXUIElementSetMessagingTimeout(app,0.1)
        guard let raw = attribute(app,"AXExtrasMenuBar"), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let bar = raw as! AXUIElement; AXUIElementSetMessagingTimeout(bar,0.1)
        guard let children = attribute(bar,kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        let keys = imageCacheKeys(bundle:item.bundle,identifiers:children.map { attribute($0,kAXIdentifierAttribute) as? String })
        let siblings = children.enumerated().compactMap { index,child -> PocketItem? in
            AXUIElementSetMessagingTimeout(child,0.1)
            guard let frame = frame(child) else { return nil }
            let name = [kAXTitleAttribute,kAXDescriptionAttribute,kAXHelpAttribute].compactMap { attribute(child,$0) as? String }.first { !$0.isEmpty } ?? NSRunningApplication(processIdentifier:item.pid)?.localizedName ?? item.name
            return PocketItem(id:"\(item.pid):\(index)",bundle:item.bundle,pid:item.pid,name:name,element:child,frame:frame,windowID:nil,cacheKey:keys[index])
        }
        guard let fresh = siblings.first(where:{ candidate in
            if let key = item.cacheKey { return candidate.cacheKey == key }
            return candidate.id == item.id
        }) else { return nil }
        guard let result = matchFrame(fresh,among:siblings,host:host), host.overflow.map({ !result.intersects($0) }) ?? true else { return nil }
        return result
    }
    // Resolve only the extra under the original mouse-down, off the event tap.
    // Ambiguous siblings never turn a normal native rearrangement into a pin.
    static func hostedDragCandidate(at point: CGPoint, host: HostSnapshot, area: CGRect) -> HostedItem? {
        guard point.x.isFinite, point.y.isFinite, area.contains(point), host.overflow?.contains(point) != true else { return nil }
        let candidates = host.renderedItems.filter { item in
            !item.frame.isEmpty && item.frame.width <= 600 && item.frame.height <= 80 && area.contains(item.frame) && item.frame.contains(point)
                && (host.overflow.map { !item.frame.intersects($0) } ?? true)
        }
        return candidates.count == 1 ? candidates[0] : nil
    }
    static func dragSource(at point: CGPoint, area: CGRect? = nil) -> (PocketItem,CGRect)? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system,0.1)
        var raw: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system,Float(point.x),Float(point.y),&raw) == .success, let raw else { return nil }
        AXUIElementSetMessagingTimeout(raw,0.1)
        let role = attribute(raw,kAXRoleAttribute) as? String
        let hit: AXUIElement, physical: CGRect
        if (role == kAXMenuBarItemRole || role == kAXButtonRole), let bounds = frame(raw), bounds.contains(point), bounds.height <= 80, bounds.width <= 600 {
            hit = raw; physical = bounds
        } else {
            // macOS 27's system-wide hit test returns the foreground app's
            // generic menu bar over hosted extras. The broker's unique, fully
            // visible slot is the source of identity in that one case.
            guard role == kAXMenuBarRole, let area, let host = hostSnapshot(),
                  let candidate = hostedDragCandidate(at:point,host:host,area:area) else { return nil }
            hit = candidate.element; physical = candidate.frame
        }
        var pid:pid_t = 0
        guard AXUIElementGetPid(hit,&pid) == .success, pid != getpid(),
              let app = NSRunningApplication(processIdentifier:pid), let bundle = app.bundleIdentifier,
              app.bundleURL?.pathExtension == "app", Preferences.canPinPocketBundle(bundle) else { return nil }
        AXUIElementSetMessagingTimeout(hit,0.1)
        let owner = AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(owner,0.1)
        guard let rawBar = attribute(owner,"AXExtrasMenuBar"), CFGetTypeID(rawBar) == AXUIElementGetTypeID() else { return nil }
        let bar = rawBar as! AXUIElement; AXUIElementSetMessagingTimeout(bar,0.1)
        guard let children = attribute(bar,kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        func name(_ element:AXUIElement) -> String? {
            [kAXTitleAttribute,kAXDescriptionAttribute,kAXHelpAttribute].compactMap { attribute(element,$0) as? String }.first { !$0.isEmpty }
        }
        let named = name(hit)
        let matches = children.enumerated().filter { _,child in
            AXUIElementSetMessagingTimeout(child,0.1)
            return CFEqual(child,hit) || (named != nil && name(child) == named)
        }
        let match: (offset:Int,element:AXUIElement)
        if matches.count == 1 { match = matches[0] }
        else if children.count == 1 { match = (0,children[0]) }
        else { return nil }
        return (PocketItem(id:"\(pid):\(match.offset)",bundle:bundle,pid:pid,name:name(match.element) ?? app.localizedName ?? bundle,element:match.element,frame:physical,windowID:nil),physical)
    }

    static func nativeIdentifiers(for bundle: String) -> [String] {
        var result = [bundle]
        guard let url = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.bundleURL else { return result }
        var code: SecStaticCode?
        var info: CFDictionary?
        if SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
           SecCodeCopySigningInformation(code, [], &info) == errSecSuccess,
           let identifier = (info as? [String: Any])?[kSecCodeInfoIdentifier as String] as? String,
           identifier != bundle { result.append(identifier) }
        return result
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let point = attribute(element, kAXPositionAttribute), CFGetTypeID(point) == AXValueGetTypeID(),
              let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(point as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s),
              p.x.isFinite, p.y.isFinite, s.width.isFinite, s.height.isFinite else { return nil }
        return CGRect(origin: p, size: s)
    }
}

// Accepted native visibility is not yet presented layout. Read again across
// a quiet interval after pin policy completes, before unveiling its slot.
struct PocketHostSettlement {
    static let confirmationInterval: TimeInterval = 0.12
    private var sampled = false
    private var previous: PocketInventory.HostSnapshot?
    private var stableSince: TimeInterval = 0
    mutating func accepts(_ host: PocketInventory.HostSnapshot?, at time: TimeInterval, awaitingAbsenceOf owners: Set<pid_t> = []) -> Bool {
        // A newly excluded status owner can retain an ordinary, nonoverlapping
        // AXButton after its pixels disappear. Quiet coordinates alone cannot
        // make that ghost a valid leading slot for the Pocket disclosure.
        if host?.items.contains(where:{ owners.contains($0.owner) }) == true {
            sampled = false; previous = nil
            return false
        }
        let same = previous.flatMap { old in host.map { old.hasSameLayout(as:$0) } } ?? (previous == nil && host == nil)
        guard sampled, same else {
            sampled = true; previous = host; stableSince = time
            return false
        }
        return time - stableSince >= Self.confirmationInterval
    }
}

enum PocketGeometry {
    static func dropAnchor(source:CGPoint,screen:CGRect,menuBarHeight:CGFloat) -> CGRect? {
        guard source.x.isFinite,source.y.isFinite,screen.contains(source),
              menuBarHeight.isFinite,menuBarHeight > 0,menuBarHeight <= screen.height else { return nil }
        let x = min(screen.maxX-0.5,max(screen.minX+0.5,source.x))
        return CGRect(x:x-0.5,y:screen.maxY-menuBarHeight,width:1,height:1)
    }
    // Pocket is a disclosure for the revealed strip. Use the system overflow
    // slot when present; otherwise borrow only empty space BEFORE every icon.
    // Never create a second button beside the main accordion or paint an icon.
    static func overflowButtonFrame(expanded: Bool, native: CGRect?, slots: [CGRect], area: CGRect, height: CGFloat) -> CGRect? {
        guard expanded, height > 0, height <= area.height else { return nil }
        let first = slots.filter { !$0.isEmpty && area.contains($0) }.map(\.minX).min()
        if let native {
            guard !native.isEmpty, area.contains(native), native.width <= 80 else { return nil }
            // Native double-chevron ink extends outside its AX rectangle.
            let x = max(area.minX,native.minX-6)
            let width = max(24,native.maxX-x)
            guard x+width <= (first ?? area.maxX) else { return nil }
            return CGRect(x:x,y:area.minY,width:width,height:height)
        }
        guard let first, first-26 >= area.minX else { return nil }
        return CGRect(x:first-26,y:area.minY,width:26,height:height)
    }
    static func isUsable(_ frame: CGRect, on display: CGRect, rightArea: CGRect?) -> Bool {
        guard !frame.isEmpty, frame.width.isFinite, frame.height.isFinite,
              display.insetBy(dx: -1, dy: -1).contains(frame), frame.height <= 80 else { return false }
        if let rightArea { return frame.minX >= rightArea.minX && frame.maxX <= rightArea.maxX }
        return true
    }
    static func panelFrame(anchor: CGRect, size: CGSize, screen: CGRect, menuHeight: CGFloat) -> CGRect {
        let width = min(size.width, screen.width - 16)
        let height = min(size.height, max(60, screen.height - menuHeight - 16))
        return CGRect(x: min(max(anchor.midX - width / 2, screen.minX + 8), screen.maxX - width - 8),
                      y: screen.maxY - menuHeight - height - 6, width: width, height: height)
    }
}

enum PocketLayout {
    static func batches(_ items: [(id: String, bundle: String, width: CGFloat)], widthLimit: CGFloat) -> [[String]] {
        var result: [[String]] = [], batch: [String] = [], width: CGFloat = 0
        // Bundle siblings must be exposed together by the native API.
        var ordered: [String] = []; var groups: [String: [(String, CGFloat)]] = [:]
        for item in items {
            if groups[item.bundle] == nil { ordered.append(item.bundle) }
            groups[item.bundle, default: []].append((item.id, item.width))
        }
        for bundle in ordered {
            let group = groups[bundle]!
            let size = group.reduce(CGFloat(0)) { $0 + $1.1 + 12 }
            if !batch.isEmpty && (width + size > widthLimit || batch.count + group.count > 3) {
                result.append(batch); batch = []; width = 0
            }
            batch += group.map(\.0); width += size
        }
        if !batch.isEmpty { result.append(batch) }
        return result
    }

    // Navigate the actual spanning grid, and stop at its edges instead of wrapping.
    static func neighbor(of id: String, keyCode: UInt16, items: [(String, CGFloat)]) -> String? {
        let grid = rows(items)
        guard let row = grid.firstIndex(where: { $0.contains(where: { $0.id == id }) }),
              let column = grid[row].firstIndex(where: { $0.id == id }) else { return nil }
        if keyCode == 123 || keyCode == 124 {
            let next = column + (keyCode == 123 ? -1 : 1)
            return grid[row].indices.contains(next) ? grid[row][next].id : id
        }
        guard keyCode == 125 || keyCode == 126 else { return nil }
        let nextRow = row + (keyCode == 125 ? 1 : -1)
        guard grid.indices.contains(nextRow) else { return id }
        let center = Double(grid[row].prefix(column).reduce(0) { $0 + $1.span }) + Double(grid[row][column].span) / 2
        var used = 0
        let candidates = grid[nextRow].map { cell -> (String, Double) in
            defer { used += cell.span }
            return (cell.id, abs(Double(used) + Double(cell.span) / 2 - center))
        }
        return candidates.min(by: { $0.1 < $1.1 })?.0
    }

    static func rows(_ items: [(String, CGFloat)]) -> [[(id: String, span: Int)]] {
        var result: [[(id: String, span: Int)]] = [], row: [(id: String, span: Int)] = []
        var used = 0
        for (id, width) in items {
            let span = width.isFinite ? Int(min(3, max(1, ceil(width / 66)))) : 1
            if used + span > 3 { result.append(row); row = []; used = 0 }
            row.append((id, span)); used += span
        }
        if !row.isEmpty { result.append(row) }
        return result
    }
}


enum PocketActionPolicy {
    static func shouldDismiss(for activated: pid_t?, origin: pid_t?, target: pid_t?, own: pid_t) -> Bool {
        guard let activated else { return false }
        return activated != origin && activated != target && activated != own
    }

    // Timeout/cannotComplete are unknown outcomes: never duplicate an action.
    static func shouldUseMouse(after error: AXError) -> Bool {
        error == .actionUnsupported || error == .notImplemented
    }
}

// Membership is item-level and is evaluated against a settled expanded host.
enum PocketOverflowMembership {
    static func resolve(_ items: [(id:String,width:CGFloat)], drawn:[String:CGRect], display:CGRect,
                        area:CGRect, capacity:CGFloat, nativeOverflow:Bool, revealed:Bool, hostAvailable:Bool = true) -> Set<String> {
        // A failed broker read says nothing about which extras are parked.
        // Explicit pins remain separate from automatic overflow membership.
        // Proxy widths are not a visibility guarantee. A native restriction can
        // leave an eligible publisher unrendered even with room to spare and no
        // system overflow button. Keep it reachable instead of dropping it from
        // both surfaces. The caller already excludes explicit always-hidden and
        // macOS-disallowed publishers; unreadable/collapsed hosts remain unknown.
        guard hostAvailable, revealed else { return [] }
        return Set(items.compactMap { item in
            guard let frame = drawn[item.id], PocketGeometry.isUsable(frame,on:display,rightArea:area) else { return item.id }
            return nil
        })
    }
}
