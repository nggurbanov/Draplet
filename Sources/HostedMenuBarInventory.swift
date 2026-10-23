import AppKit

enum HostedMenuBarInventoryPolicy {
    static func reconcile(_ clients:[MenuBarInventoryItem],rendered:[MenuBarInventoryItem]) -> [MenuBarInventoryItem] {
        let hosted = Set(rendered.map(\.bundleIdentifier))
        // Native hiding is per publisher. Use all of its physically rendered
        // siblings together; retain the existing source metadata for overflow.
        return clients.filter { !hosted.contains($0.bundleIdentifier) } + rendered
    }
}

// A publisher's AXExtrasMenuBar can retain old backing-window positions after
// MenuBarAgent repacks the native bar. Classify visible publishers and our
// boundary from the same hosted layout, not from two different coordinate maps.
final class HostedMenuBarInventory:MenuBarInventoryProviding {
    private let clients:MenuBarInventoryProviding
    private let observe:(PocketInventory.HostSnapshot,CGRect)->Void
    var isAuthorized:Bool { clients.isAuthorized }
    init(clients:MenuBarInventoryProviding = AccessibilityMenuBarInventory(),
         observe:@escaping (PocketInventory.HostSnapshot,CGRect)->Void) {
        self.clients = clients;self.observe = observe
    }
    func requestAuthorization() { clients.requestAuthorization() }
    func snapshot(completion:@escaping ([MenuBarInventoryItem])->Void) {
        clients.snapshot { [weak self] inventory in
            guard let self,!inventory.isEmpty else { completion([]);return }
            let displayID = CGMainDisplayID(),display = CGDisplayBounds(displayID)
            DispatchQueue.global(qos:.userInitiated).async {
                let host = PocketInventory.hostSnapshot(on:display)
                let physical = host?.renderedItems.compactMap { item -> MenuBarInventoryItem? in
                    guard let bundle = NSRunningApplication(processIdentifier:item.owner)?.bundleIdentifier else { return nil }
                    return MenuBarInventoryItem(bundleIdentifier:bundle,frame:item.frame)
                } ?? []
                DispatchQueue.main.async {
                    guard let host,!physical.isEmpty,
                          let screen = NSScreen.screens.first(where:{
                              ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
                          }) else { completion([]);return }
                    let rendered = physical.map { item in
                        MenuBarInventoryItem(bundleIdentifier:item.bundleIdentifier,
                            frame:CGRect(x:item.frame.minX,y:screen.frame.maxY-(item.frame.maxY-display.minY),
                                         width:item.frame.width,height:item.frame.height))
                    }
                    self.observe(host,display)
                    completion(HostedMenuBarInventoryPolicy.reconcile(inventory,rendered:rendered))
                }
            }
        }
    }
}
