import AppKit

// A passive image follows a process-local gesture. It never receives input or
// starts a WindowServer/AppKit item drag, and exists only until release/cancel.
final class PocketDragImage {
    private var panel:NSPanel?
    func show(_ image:NSImage,at point:NSPoint) {
        close()
        let size = CGSize(width:max(22,image.size.width),height:max(22,image.size.height))
        let panel = NSPanel(contentRect:CGRect(origin:.zero,size:size),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isReleasedWhenClosed = false;panel.isOpaque = false;panel.backgroundColor = .clear
        panel.hasShadow = false;panel.ignoresMouseEvents = true;panel.isMovable = false
        panel.level = NSWindow.Level(rawValue:NSWindow.Level.popUpMenu.rawValue+1)
        panel.collectionBehavior = [.transient,.ignoresCycle];panel.animationBehavior = .none
        let view = NSImageView(frame:CGRect(origin:.zero,size:size));view.image = image
        view.imageScaling = .scaleNone;view.contentTintColor = MenuBarBackdrop.shared.foreground
        panel.contentView = view;self.panel = panel
        move(to:point);panel.orderFrontRegardless()
    }
    func move(to point:NSPoint) {
        guard let panel else { return }
        panel.setFrameOrigin(NSPoint(x:point.x-panel.frame.width/2,y:point.y-panel.frame.height/2))
    }
    func close() { panel?.orderOut(nil);panel?.close();panel = nil }
    deinit { close() }
}
