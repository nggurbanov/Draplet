import AppKit
import ApplicationServices
import Darwin

private final class StatusBlockerView:NSView {
    var onClick:(()->Void)?
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true }
    override func mouseDown(with event:NSEvent) {}
    override func mouseUp(with event:NSEvent) { onClick?() }
    override func rightMouseDown(with event:NSEvent) {}
    override func rightMouseUp(with event:NSEvent) { onClick?() }
}
// Disposable native status items and an optional desktop/fullscreen QA window.
// Accessory activation is restored on cleanup. EOF/watchdog terminate it too.
final class Fixture: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var items: [NSStatusItem] = []
    var window: NSWindow?
    var wantsFullscreen = false
    var changingFullscreen = false
    var keepsWindow = false
    var blocker:NSPanel?
    var blockerClicks = 0
    var targetFrame:CGRect?
    var pendingUp:CGEvent?
    @objc func blockedClick() { blockerClicks += 1 }
    func clickBlocker(button:CGMouseButton = .left) {
        // Fixture-only WindowServer input: no arbitrary coordinates or user
        // controls. AXPress bypasses the hit-window interception being tested.
        guard let blocker,blocker.isVisible,let screen=blocker.screen else { return }
        postClick(CGPoint(x:blocker.frame.midX,y:screen.frame.maxY-blocker.frame.midY),button:button)
    }
    private func postClick(_ point:CGPoint,button:CGMouseButton = .left,hold:TimeInterval = 0.08) {
        guard NSEvent.pressedMouseButtons == 0,!NSEvent.modifierFlags.contains(.command),
              let source=CGEventSource(stateID:.hidSystemState),
              let down=CGEvent(mouseEventSource:source,mouseType:button == .left ? .leftMouseDown : .rightMouseDown,mouseCursorPosition:point,mouseButton:button),
              let up=CGEvent(mouseEventSource:source,mouseType:button == .left ? .leftMouseUp : .rightMouseUp,mouseCursorPosition:point,mouseButton:button) else { return }
        source.localEventsSuppressionInterval=0
        down.flags=[];up.flags=[]
        down.setIntegerValueField(.mouseEventClickState,value:1);up.setIntegerValueField(.mouseEventClickState,value:1)
        let cursor=CGEvent(source:nil)?.location
        pendingUp = up
        down.post(tap:.cghidEventTap)
        DispatchQueue.global().asyncAfter(deadline:.now()+hold) {
            up.post(tap:.cghidEventTap)
            DispatchQueue.main.asyncAfter(deadline:.now()+0.06) {
                self.pendingUp = nil
                if let cursor,let now=CGEvent(source:nil)?.location,hypot(now.x-point.x,now.y-point.y)<3 { CGWarpMouseCursorPosition(cursor) }
            }
        }
    }
    func blockToggle(targetBundle:String = "com.tyrell.Draplet",identifier:String? = "Draplet.Toggle",createBlocker:Bool = true) {
        targetFrame = nil
        func attr(_ element:AXUIElement,_ key:String) -> CFTypeRef? {
            var value:CFTypeRef?
            return AXUIElementCopyAttributeValue(element,key as CFString,&value) == .success ? value : nil
        }
        func frame(_ element:AXUIElement) -> CGRect? {
            guard let p=attr(element,kAXPositionAttribute),let s=attr(element,kAXSizeAttribute),
                  CFGetTypeID(p)==AXValueGetTypeID(),CFGetTypeID(s)==AXValueGetTypeID() else { return nil }
            var point=CGPoint.zero,size=CGSize.zero
            guard AXValueGetValue(p as! AXValue,.cgPoint,&point),AXValueGetValue(s as! AXValue,.cgSize,&size) else { return nil }
            return CGRect(origin:point,size:size)
        }
        guard let owner=NSRunningApplication.runningApplications(withBundleIdentifier:targetBundle).first?.processIdentifier,
              let broker=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.MenuBarAgent").first?.processIdentifier else { return }
        let app=AXUIElementCreateApplication(broker);AXUIElementSetMessagingTimeout(app,0.1)
        let display=CGDisplayBounds(CGMainDisplayID())
        for window in attr(app,kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            guard let bounds=frame(window),abs(bounds.minX-display.minX)<1,abs(bounds.minY-display.minY)<1,
                  abs(bounds.width-display.width)<1,bounds.height<50 else { continue }
            for child in attr(window,kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                var leaf=child
                for _ in 0..<8 {
                    var pid:pid_t=0;AXUIElementGetPid(leaf,&pid)
                    if pid==owner,identifier == nil || attr(leaf,kAXIdentifierAttribute) as? String == identifier,let rect=frame(child),
                       let screen=NSScreen.screens.first {
                        targetFrame = rect
                        if !createBlocker { return }
                        blocker?.close()
                        let cocoa=CGRect(x:rect.minX,y:screen.frame.maxY-rect.maxY,width:rect.width,height:rect.height)
                        let panel=NSPanel(contentRect:cocoa,styleMask:[.nonactivatingPanel,.borderless],backing:.buffered,defer:false)
                        panel.title="Draplet hit blocker";panel.level=NSWindow.Level(rawValue:26)
                        panel.collectionBehavior=[.transient,.ignoresCycle];panel.hasShadow=false
                        panel.isOpaque=false;panel.backgroundColor = NSColor.white.withAlphaComponent(0.001);panel.isReleasedWhenClosed=false
                        panel.hidesOnDeactivate=false
                        let view=StatusBlockerView(frame:CGRect(origin:.zero,size:rect.size))
                        view.setAccessibilityLabel("QA status click blocker")
                        view.onClick={ [weak self] in self?.blockedClick() }
                        panel.contentView=view;blocker=panel;panel.orderFrontRegardless();return
                    }
                    guard let next=(attr(leaf,kAXChildrenAttribute) as? [AXUIElement])?.first else { break };leaf=next
                }
            }
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        for index in 1...8 {
            let item = NSStatusBar.system.statusItem(withLength:34)
            item.autosaveName = "Draplet.NativeQA.\(index)"
            item.button?.image = NSImage(systemSymbolName:"\(index).circle.fill",accessibilityDescription:"Draplet QA \(index)")
            item.button?.image?.isTemplate = true
            item.button?.setAccessibilityLabel("Draplet QA \(index)")
            let menu = NSMenu()
            let entry = menu.addItem(withTitle:"Draplet QA \(index) · native menu",action:nil,keyEquivalent:"")
            entry.isEnabled = false
            item.menu = menu; items.append(item)
        }
        Thread.detachNewThread { [weak self] in
            var line = [UInt8](), byte: UInt8 = 0
            while Darwin.read(STDIN_FILENO,&byte,1) == 1 {
                if byte != 10 { line.append(byte); continue }
                let command = String(decoding:line,as:UTF8.self); line = []
                DispatchQueue.main.async { self?.command(command) }
            }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+900) { NSApp.terminate(nil) }
    }
    func command(_ value:String) {
        switch value {
        case "block-arrow":blockToggle()
        case "block-target":blockToggle(targetBundle:"org.drapletqa.clicktarget",identifier:nil)
        case "click-arrow":clickBlocker()
        case "right-click-target":clickBlocker(button:.right)
        case "arrow-geometry":
            blockToggle(createBlocker:false)
            let data=try! JSONSerialization.data(withJSONObject:["frame":targetFrame.map { [$0.minX,$0.minY,$0.width,$0.height] } ?? []])
            let output=data+Data([10]);output.withUnsafeBytes { _ = Darwin.write(STDOUT_FILENO,$0.baseAddress!,output.count) }
        case "press-arrow":
            blockToggle(createBlocker:false)
            if let rect=targetFrame { postClick(CGPoint(x:rect.midX,y:rect.midY),hold:1.2) }
        case "clear-blocker":blocker?.close();blocker=nil
        case "overflow":
            // Independent black-box observation. Production's cached scan can
            // agree with itself while its cover misses the actual native button.
            func attr(_ element:AXUIElement,_ key:String) -> CFTypeRef? {
                var value:CFTypeRef?
                return AXUIElementCopyAttributeValue(element,key as CFString,&value) == .success ? value : nil
            }
            func frame(_ element:AXUIElement) -> CGRect? {
                guard let p=attr(element,kAXPositionAttribute),let s=attr(element,kAXSizeAttribute),
                      CFGetTypeID(p)==AXValueGetTypeID(),CFGetTypeID(s)==AXValueGetTypeID() else { return nil }
                var point=CGPoint.zero,size=CGSize.zero
                guard AXValueGetValue(p as! AXValue,.cgPoint,&point),AXValueGetValue(s as! AXValue,.cgSize,&size) else { return nil }
                return CGRect(origin:point,size:size)
            }
            let display=CGDisplayBounds(CGMainDisplayID())
            var rectangles:[[String:CGFloat]]=[]
            if let pid=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.MenuBarAgent").first?.processIdentifier {
                let agent=AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(agent,0.1)
                for window in attr(agent,kAXWindowsAttribute) as? [AXUIElement] ?? [] {
                    guard let bounds=frame(window),abs(bounds.minX-display.minX)<2,
                          abs(bounds.minY-display.minY)<2,abs(bounds.width-display.width)<2,bounds.height<=50 else { continue }
                    for child in attr(window,kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                        var owner:pid_t=0; AXUIElementGetPid(child,&owner)
                        guard owner==pid,attr(child,kAXRoleAttribute) as? String == kAXButtonRole,
                              let bounds=frame(child),bounds.width>0,bounds.width<80 else { continue }
                        rectangles.append(["x":bounds.minX,"maxX":bounds.maxX,"width":bounds.width])
                    }
                }
            }
            let data=try! JSONSerialization.data(withJSONObject:["overflow":rectangles,"trusted":AXIsProcessTrusted()])
            let output=data+Data([10]); output.withUnsafeBytes { _ = Darwin.write(STDOUT_FILENO,$0.baseAddress!,output.count) }
        case "status":
            let status:[String:Any] = ["fullscreen":window?.styleMask.contains(.fullScreen) == true,"changing":changingFullscreen,"desired":wantsFullscreen,
                                      "blocker":blocker?.isVisible == true,"blockerClicks":blockerClicks,"blockerWindow":blocker?.windowNumber ?? 0,
                                      "postEventsAllowed":CGPreflightPostEventAccess()]
            let data = try! JSONSerialization.data(withJSONObject:status)
            let output = data + Data([10]); output.withUnsafeBytes { _ = Darwin.write(STDOUT_FILENO,$0.baseAddress!,output.count) }
        case "window": keepsWindow = true; showWindow()
        case "fullscreen":
            showWindow()
            wantsFullscreen.toggle(); applyFullscreen()
        case "cancel-menu": for item in items { item.menu?.cancelTracking() }
        case "quit": NSApp.terminate(nil)
        default: break
        }
    }
    func showWindow() {
        if window == nil {
            let window = NSWindow(contentRect:NSRect(x:300,y:200,width:600,height:400),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
            window.title = "Draplet native fullscreen QA"
            window.collectionBehavior = [.fullScreenPrimary]
            window.delegate = self
            window.contentView?.addSubview(NSTextField(labelWithString:"Disposable Draplet fullscreen fixture"))
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    func applyFullscreen() {
        guard let window, !changingFullscreen, window.styleMask.contains(.fullScreen) != wantsFullscreen else { return }
        changingFullscreen = true; window.toggleFullScreen(nil)
    }
    func settledFullscreen() {
        DispatchQueue.main.asyncAfter(deadline:.now()+0.25) { self.changingFullscreen = false; self.applyFullscreen() }
    }
    func windowDidEnterFullScreen(_ notification:Notification) { settledFullscreen() }
    func windowDidExitFullScreen(_ notification:Notification) {
        if keepsWindow { showWindow() } else { NSApp.setActivationPolicy(.accessory) }
        settledFullscreen()
    }
    func applicationWillTerminate(_ notification:Notification) {
        NSApp.setActivationPolicy(.accessory)
        pendingUp?.post(tap:.cghidEventTap);pendingUp = nil
        blocker?.close()
        for item in items { NSStatusBar.system.removeStatusItem(item) }
    }
}
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = Fixture(); application.delegate = delegate; application.run()
