import AppKit
import Darwin

// One real menu extra outside /Applications. Its menu delegate is the observer:
// a successful AX return code alone does not establish that a menu opened.
final class CompatibilityFixture: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem!
    private var window: NSWindow?
    private var openMenus = 0
    private var menuOpens = 0
    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "Draplet.CompatibilityFixture"
        item.button?.image = NSImage(systemSymbolName: "1.circle.fill", accessibilityDescription: "Draplet Compatibility Fixture")
        item.button?.image?.isTemplate = true
        item.button?.setAccessibilityLabel("Draplet Compatibility Fixture")
        let menu = NSMenu(); menu.delegate = self
        menu.addItem(withTitle: "Original compatibility fixture menu", action: nil, keyEquivalent: "")
        item.menu = menu
        Thread.detachNewThread { [weak self] in
            while let line = readLine() { DispatchQueue.main.async { self?.command(line) } }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 180) { NSApp.terminate(nil) }
    }
    func menuWillOpen(_ menu: NSMenu) { openMenus += 1; menuOpens += 1 }
    func menuDidClose(_ menu: NSMenu) { openMenus -= 1 }
    func applicationWillTerminate(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let item { NSStatusBar.system.removeStatusItem(item) }
        window?.close()
    }
    private func command(_ line: String) {
        switch line {
        case "status":
            let menus = (CGWindowListCopyWindowInfo(.optionOnScreenOnly,kCGNullWindowID) as? [NSDictionary] ?? []).filter {
                ($0[kCGWindowOwnerPID] as? pid_t) == getpid() && ($0[kCGWindowLayer] as? Int ?? 0) >= 100
                    && ($0[kCGWindowAlpha] as? Double ?? 1) > 0.01
            }.count
            print("{\"openMenus\":\(openMenus),\"menuOpens\":\(menuOpens),\"menuWindows\":\(menus),\"window\":\(window?.isVisible == true)}"); fflush(stdout)
        case "image":
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            if let image = item.button?.image, let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(image.size.width*scale),pixelsHigh:Int(image.size.height*scale),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
               let context = NSGraphicsContext(bitmapImageRep:bitmap) {
                NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current = context
                let rect = CGRect(x:0,y:0,width:bitmap.pixelsWide,height:bitmap.pixelsHigh)
                NSColor.clear.setFill();rect.fill(using:.copy);image.draw(in:rect)
                NSGraphicsContext.restoreGraphicsState();bitmap.size = image.size
                if let png = bitmap.representation(using:.png,properties:[:]),
               let data = try? JSONSerialization.data(withJSONObject: ["png": png.base64EncodedString(), "width": image.size.width,
                                                                        "height": image.size.height, "scale": scale]) {
                print(String(decoding:data,as:UTF8.self));fflush(stdout)
                }
            } else { print("{\"imageError\":true}");fflush(stdout) }
        case "image-two":
            item.button?.image = NSImage(systemSymbolName:"2.circle.fill",accessibilityDescription:"Draplet Compatibility Fixture")
            item.button?.image?.isTemplate = true
        case "window":
            if window == nil {
                window = NSWindow(contentRect: NSRect(x: 350, y: 250, width: 360, height: 180),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
                window?.title = "Draplet compatibility QA"
                window?.isReleasedWhenClosed = false
            }
            NSApp.setActivationPolicy(.regular); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        case "cancel-menu": item.menu?.cancelTracking()
        case "quit": NSApp.terminate(nil)
        default: break
        }
    }
}
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let fixture = CompatibilityFixture(); application.delegate = fixture; application.run()
