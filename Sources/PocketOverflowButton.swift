import AppKit

// Lives at the revealed strip's leading edge, using the native overflow slot
// or empty space before all icons. It never changes status-item ordering.
final class PocketOverflowButton {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
    private final class Background: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.clear.setFill(); bounds.fill(using: .copy)
            MenuBarBackdrop.shared.draw(in: bounds, screenRect: window?.frame ?? .zero, operation: .sourceOver)
        }
    }
    private var panel: NSPanel?
    private let canPresent: () -> Bool
    init(canPresent: @escaping () -> Bool = { !SystemPresentation.current() && MenuBarBackdrop.shared.ready }) {
        self.canPresent = canPresent
    }
    private(set) var button: NSButton?
    var onClick: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onSettings: (() -> Void)?
    var isVisible: Bool { panel?.isVisible == true }
    var frame: CGRect? { panel?.isVisible == true ? panel?.frame : nil }
    var windowNumber: Int? { panel?.isVisible == true ? panel?.windowNumber : nil }
    var parentWindowNumber: Int? { panel?.parent?.windowNumber }
    var containsPointer: Bool { frame?.insetBy(dx: -3, dy: -3).contains(NSEvent.mouseLocation) == true }

    func show(at frame: CGRect, beneath cover: NSWindow? = nil) {
        guard canPresent() else { hide(); return }
        if panel == nil {
            let panel = Panel(contentRect: frame, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            panel.level = NSWindow.Level(rawValue: 25)
            panel.collectionBehavior = [.transient, .ignoresCycle]
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.isReleasedWhenClosed = false; panel.animationBehavior = .none
            panel.title = "Draplet Overflow"
            let background = Background(frame: CGRect(origin: .zero, size: frame.size))
            let button = NSButton(frame: background.bounds)
            button.autoresizingMask = [.width, .height]
            button.bezelStyle = .regularSquare; button.isBordered = false
            button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Show more status icons")
            button.image?.isTemplate = true
            button.imageScaling = .scaleProportionallyDown
            button.setAccessibilityLabel("Show more status icons")
            button.toolTip = "Pocket · Pinned apps and icons that don’t fit.\n⌘-drag a status icon into Pocket to pin it."
            button.target = self; button.action = #selector(clicked)
            button.sendAction(on:[.leftMouseUp,.rightMouseUp])
            background.addSubview(button); panel.contentView = background
            self.panel = panel; self.button = button
        }
        button?.contentTintColor = MenuBarBackdrop.shared.foreground
        // Apps such as Crisp retain transparent status hit windows at level26.
        // During reveal the disclosure stays under its level25 curtain; once
        // unmasked it must own both the pixels and the click at its small slot.
        panel?.level = cover?.level ?? NSWindow.Level(rawValue:NSWindow.Level.statusBar.rawValue+2)
        if panel?.frame != frame { panel?.setFrame(frame, display: true) }
        panel?.contentView?.needsDisplay = true
        // The disclosure is part of the strip. Keep it under the same moving
        // mask as the native icons, including the fully covered preparation.
        if let panel, panel.parent !== cover {
            panel.parent?.removeChildWindow(panel)
            cover?.addChildWindow(panel,ordered:.below)
        }
        if panel?.isVisible != true { panel?.orderFrontRegardless() }
    }
    func finishReveal() {
        guard canPresent(),let panel,panel.isVisible,panel.parent == nil else { return }
        panel.level = NSWindow.Level(rawValue:NSWindow.Level.statusBar.rawValue+2)
        panel.orderFrontRegardless()
    }
    func setExpanded(_ expanded: Bool) {
        button?.state = expanded ? .on : .off
        button?.image = NSImage(systemSymbolName: expanded ? "chevron.up" : "chevron.down", accessibilityDescription: expanded ? "Hide more status icons" : "Show more status icons")
        button?.image?.isTemplate = true
        button?.setAccessibilityLabel(expanded ? "Hide more status icons" : "Show more status icons")
    }
    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp, let button {
            let menu = NSMenu()
            let refresh = menu.addItem(withTitle:"Refresh Icon Images",action:#selector(refresh),keyEquivalent:""); refresh.target = self
            menu.addItem(.separator())
            let settings = menu.addItem(withTitle:"Arrange Icons…",action:#selector(settings),keyEquivalent:""); settings.target = self
            menu.popUp(positioning:nil,at:NSPoint(x:0,y:button.bounds.minY),in:button)
        } else { onClick?() }
    }
    @objc private func refresh() { onRefresh?() }
    @objc private func settings() { onSettings?() }
    func hide() {
        if let panel { panel.parent?.removeChildWindow(panel); panel.orderOut(nil) }
    }
    func stop() { hide(); panel?.close(); panel = nil; button = nil }
}
