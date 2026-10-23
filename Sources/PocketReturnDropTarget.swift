import AppKit

// Passive return regions for our process-local Command gesture. They never
// initiate system drag-and-drop or intercept the source control's mouse-up.
final class PocketReturnDropTarget {
    private var token = ""
    private var panels:[NSPanel] = []
    private final class Destination:NSView {
        var highlighted = false { didSet { if oldValue != highlighted { needsDisplay = true } } }
        override func draw(_ dirtyRect:NSRect) {
            NSColor.clear.setFill();bounds.fill(using:.copy)
            if highlighted { NSColor.controlAccentColor.withAlphaComponent(0.18).setFill();bounds.fill() }
        }
    }
    @discardableResult func show(token:String,frames:[CGRect]? = nil) -> Bool {
        close();self.token = token
        let regions = frames ?? NSScreen.screens.map { screen in
            let start = screen.auxiliaryTopRightArea?.minX ?? screen.frame.midX
            let height = max(NSStatusBar.system.thickness,screen.safeAreaInsets.top)
            return CGRect(x:start,y:screen.frame.maxY-height,width:screen.frame.maxX-start,height:height)
        }
        for frame in regions where !frame.isEmpty {
            let panel = NSPanel(contentRect:frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            panel.isReleasedWhenClosed = false;panel.isOpaque = false;panel.backgroundColor = .clear
            panel.hasShadow = false;panel.ignoresMouseEvents = true;panel.isMovable = false
            panel.level = NSWindow.Level(rawValue:NSWindow.Level.statusBar.rawValue+2)
            panel.collectionBehavior = [.transient,.ignoresCycle];panel.animationBehavior = .none
            panel.contentView = Destination(frame:CGRect(origin:.zero,size:frame.size))
            panels.append(panel);panel.orderFrontRegardless()
        }
        return !panels.isEmpty
    }
    @discardableResult func update(at point:NSPoint,command:Bool) -> Bool {
        var inside = false
        for panel in panels {
            let hit = command && panel.frame.contains(point)
            (panel.contentView as? Destination)?.highlighted = hit;inside = inside || hit
        }
        return inside
    }
    func accepts(token:String,at point:NSPoint,command:Bool) -> Bool {
        PocketReturnDropPolicy.matches(token,expected:self.token) && update(at:point,command:command)
    }
    func close() { for panel in panels { panel.orderOut(nil);panel.close() };panels = [];token = "" }
    deinit { close() }
}
