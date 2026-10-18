import AppKit
import ApplicationServices

struct PocketItem: Identifiable {
    let id: String
    let bundle: String
    let pid: pid_t
    let name: String
    let element: AXUIElement
    let frame: CGRect // CoreGraphics coordinates, including for secondary displays
    let windowID: CGWindowID?
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
            let windows = DrapletPocketWindows()
            var result: [PocketItem] = []
            for (pid, bundle, name) in apps {
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.1)
                guard let bar = attribute(app, "AXExtrasMenuBar") else { continue }
                let element = bar as! AXUIElement
                AXUIElementSetMessagingTimeout(element, 0.1)
                guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { continue }
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
                                             windowID: window?[kCGWindowNumber] as? CGWindowID))
                }
            }
            DispatchQueue.main.async { completion(result) }
        }
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

enum PocketGeometry {
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
