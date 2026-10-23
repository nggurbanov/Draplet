import AppKit
import ScreenCaptureKit

// A one-shot visual fence prevents temporary capture reflows being shown.
// It owns only a menu-bar strip, never a screen-sized or persistent stream.
final class PocketCaptureShield {
    private final class Surface: NSImageView {
        var cancel: (() -> Void)?
        var matched = false
        override func draw(_ dirtyRect:NSRect) {
            if matched { MenuBarBackdrop.shared.draw(in:bounds,screenRect:window?.frame ?? .zero,operation:.sourceOver) }
            else { super.draw(dirtyRect) }
        }
        override func mouseDown(with event: NSEvent) {
            if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == PocketItemEvents.placementEventTag { return }
            cancel?()
        }
        override func rightMouseDown(with event: NSEvent) { cancel?() }
    }
    private var panel: NSPanel?
    var isVisible: Bool { panel?.isVisible == true }
    // During an owned native status move this visual fence must not receive
    // our tagged mouse-down and cancel the very operation it is covering.
    func passInput(_ enabled:Bool) { panel?.ignoresMouseEvents = enabled }
    func finish(restoring: (@escaping () -> Void) -> Void, completion: @escaping () -> Void = {}) {
        let previous = panel
        restoring { [weak self, weak previous] in
            let finish = {
                guard let self, self.panel === previous else { return }
                self.close(); completion()
            }
            if previous == nil { finish() }
            else { DispatchQueue.main.asyncAfter(deadline:.now()+RightMenuTransition.hideSettling,execute:finish) }
        }
    }
    // A fully closed curtain can take ownership of the exact idle prefix.
    // Keeping both masks would hide the entire reveal behind the old fence.
    @discardableResult func handoff(to coveringFrame:CGRect) -> Bool {
        guard let panel,(panel.contentView as? Surface)?.matched == true,
              coveringFrame.contains(panel.frame) else { return false }
        close(); return true
    }
    func show(_ image: CGImage, frame: CGRect, cancel: @escaping () -> Void) {
        close()
        if CommandLine.arguments.contains("--test-controls") {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Draplet-overflow-menubar.png")
            try? NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])?.write(to:url)
        }
        let panel = NSPanel(contentRect: frame, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.animationBehavior = .none
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.level = NSWindow.Level(rawValue: 26); panel.hasShadow = false
        let view = Surface(frame: CGRect(origin: .zero, size: frame.size))
        view.image = NSImage(cgImage: image, size: frame.size)
        view.imageScaling = .scaleAxesIndependently; view.cancel = cancel
        panel.contentView = view; self.panel = panel; panel.orderFrontRegardless()
    }
    func showMatched(frame:CGRect,cancel:@escaping ()->Void) {
        close()
        let panel = NSPanel(contentRect:frame,styleMask:[.nonactivatingPanel,.borderless],backing:.buffered,defer:false)
        panel.isReleasedWhenClosed = false;panel.animationBehavior = .none
        panel.collectionBehavior = [.transient,.ignoresCycle];panel.level = NSWindow.Level(rawValue:26);panel.hasShadow = false
        let view = Surface(frame:CGRect(origin:.zero,size:frame.size));view.matched = true;view.cancel = cancel
        panel.contentView = view;self.panel = panel;panel.orderFrontRegardless()
    }
    func refreshBackground() { panel?.contentView?.needsDisplay = true }
    func close() { panel?.orderOut(nil); panel?.close(); panel = nil }
}

enum PocketCapture {
    static func liveFrame(_ item: PocketItem, on display: CGRect) async -> CGRect? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                if #available(macOS 27, *) {
                    continuation.resume(returning:PocketInventory.hostedFrame(of:item,on:display))
                } else { continuation.resume(returning: PocketInventory.frame(item.element)) }
            }
        }
    }
    @MainActor static func strip(screen: NSScreen, content: SCShareableContent, endX: CGFloat? = nil) async throws -> (CGImage, CGRect)? {
        guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
              let display = content.displays.first(where: { $0.displayID == id }) else { return nil }
        let x = screen.auxiliaryTopRightArea?.minX ?? screen.frame.minX
        let height = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
        let frame = CGRect(x: x, y: screen.frame.maxY - height, width: min(screen.frame.maxX,endX ?? screen.frame.maxX) - x, height: height)
        guard frame.width > 0 else { return nil }
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: x - screen.frame.minX, y: 0, width: frame.width, height: height)
        config.width = Int(frame.width * screen.backingScaleFactor); config.height = Int(height * screen.backingScaleFactor)
        config.showsCursor = false; config.capturesAudio = false
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        return (try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config), frame)
    }
    @MainActor static func image(_ item: PocketItem, screen: NSScreen, content: SCShareableContent, diagnose: (String)->Void = { _ in }) async throws -> NSImage? {
        guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
              let display = content.displays.first(where: { $0.displayID == id }),
              let frame = await liveFrame(item,on:display.frame) else { diagnose("missing-live-frame-or-display"); return nil }
        let right = screen.auxiliaryTopRightArea.map { CGRect(x: $0.minX, y: display.frame.minY, width: $0.width, height: 80) }
        guard PocketGeometry.isUsable(frame, on: display.frame, rightArea: right) else { diagnose("unusable-frame:\(frame)"); return nil }
        let config = SCStreamConfiguration()
        config.sourceRect = frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        config.width = Int((frame.width * screen.backingScaleFactor).rounded()); config.height = Int((frame.height * screen.backingScaleFactor).rounded())
        config.showsCursor = false; config.capturesAudio = false
        let filter = SCContentFilter(display: display, excludingApplications: content.applications.filter { $0.processID == getpid() }, exceptingWindows: [])
        let raw = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        if CommandLine.arguments.contains("--test-controls"),
           let index = CommandLine.arguments.firstIndex(of:"--qa-capture-dir"), CommandLine.arguments.count > index+1 {
            let directory = URL(fileURLWithPath:CommandLine.arguments[index+1],isDirectory:true)
            try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            try? NSBitmapImageRep(cgImage:raw).representation(using:.png,properties:[:])?
                .write(to:directory.appendingPathComponent("\(item.id).png"))
        }
        guard let after = await liveFrame(item,on:display.frame), abs(after.minX - frame.minX) < 0.5, abs(after.minY - frame.minY) < 0.5,
              abs(after.width - frame.width) < 0.5, abs(after.height - frame.height) < 0.5 else { diagnose("frame-moved-after-capture"); return nil }
        guard let isolated = PocketImage.isolate(raw), let cropped = PocketImage.trim(isolated) else { diagnose("blank-capture"); return nil }
        let result = NSImage(cgImage: cropped, size: CGSize(width: CGFloat(cropped.width) / screen.backingScaleFactor, height: CGFloat(cropped.height) / screen.backingScaleFactor))
        result.isTemplate = PocketImage.isMonochrome(cropped)
        diagnose("ready"); return result
    }
}
