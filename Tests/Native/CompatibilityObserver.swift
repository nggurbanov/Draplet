import AppKit
import ApplicationServices

// Independent black-box observation of the physical menu-bar host. It does not
// use Draplet's matching code or trust a publisher's cached backing-window frame.
func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element,key as CFString,&value) == .success ? value : nil
}
func frame(_ element: AXUIElement) -> CGRect? {
    guard let p = attribute(element,kAXPositionAttribute),let s = attribute(element,kAXSizeAttribute),
          CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero,size = CGSize.zero
    guard AXValueGetValue(p as! AXValue,.cgPoint,&point), AXValueGetValue(s as! AXValue,.cgSize,&size) else { return nil }
    return CGRect(origin:point,size:size)
}
let identifier = CommandLine.arguments[1], publisher = pid_t(CommandLine.arguments[2])!
let display = CGDisplayBounds(CGMainDisplayID())
var proxyFrames = Set<String>(),original = false
if let own = NSRunningApplication.runningApplications(withBundleIdentifier:"com.tyrell.Draplet").first?.processIdentifier,
   let broker = NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.MenuBarAgent").first?.processIdentifier {
    let app = AXUIElementCreateApplication(broker);AXUIElementSetMessagingTimeout(app,0.1)
    for window in attribute(app,kAXWindowsAttribute) as? [AXUIElement] ?? [] {
        guard let bounds = frame(window),abs(bounds.minX-display.minX) < 1,abs(bounds.minY-display.minY) < 1,
              abs(bounds.width-display.width) < 1,bounds.height <= 50 else { continue }
        var rows: [(pid_t,String,CGRect)] = []
        for child in attribute(window,kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            guard let bounds = frame(child),bounds.width > 0,bounds.height > 0 else { continue }
            var leaf = child
            for _ in 0..<8 {
                var owner: pid_t = 0;AXUIElementGetPid(leaf,&owner)
                let role = attribute(leaf,kAXRoleAttribute) as? String
                if role == kAXButtonRole || role == kAXMenuBarItemRole {
                    rows.append((owner,attribute(leaf,kAXIdentifierAttribute) as? String ?? "",bounds));break
                }
                guard let next = (attribute(leaf,kAXChildrenAttribute) as? [AXUIElement])?.first else { break }
                leaf = next
            }
        }
        for (index,row) in rows.enumerated() {
            let tolerance: CGFloat = row.0 == own && row.1 == identifier ? 4 : 1
            guard display.contains(row.2), row.2.height <= 50,
                  !rows.enumerated().contains(where:{ other,peer in
                      other != index && row.2.intersection(peer.2).width > tolerance && row.2.intersection(peer.2).height > 1
                  }) else { continue }
            if row.0 == own && row.1 == identifier { proxyFrames.insert(NSStringFromRect(row.2)) }
            if row.0 == publisher { original = true }
        }
    }
}
let data = try! JSONSerialization.data(withJSONObject:["proxyFrames":Array(proxyFrames),"originalRendered":original])
print(String(decoding:data,as:UTF8.self))
