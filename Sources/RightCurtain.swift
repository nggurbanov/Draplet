import AppKit
import ApplicationServices

// The hiding engines are vendored from Hidden Bar under MIT; see ThirdPartyNotices.md.
final class RightCurtain: NSObject, MenuBarItemProvider {
    let toggleItem = NSStatusBar.system.statusItem(withLength: 26)
    let separatorItem = NSStatusBar.system.statusItem(withLength: 20)
    private(set) var alwaysHiddenItem: NSStatusItem?
    lazy var engine = MenuBarEngineFactory.make(items: self)
    private let prefs = Preferences.shared
    private var collapseTimer: Timer?
    private var hoverEntered: Date?
    private var lastCollapse = Date.distantPast
    private var separatorsHidden = true
    private var revealAllMode = false
    private var stopped = false
    var onSettings: (() -> Void)?
    var onPause: (() -> Void)?
    var onRevealAll: (() -> Void)?
    var isSettingsVisible: () -> Bool = { false }
    var competingApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.dwarvesv.minimalbar").first
    }
    var canManage: Bool { prefs.rightEnabled && !prefs.paused && prefs.permissionGranted && competingApp == nil }
    override init() {
        super.init()
        toggleItem.autosaveName = "Draplet.Toggle"
        separatorItem.autosaveName = "Draplet.Separator"
        toggleItem.isVisible = true
        separatorItem.isVisible = true
        for item in [toggleItem, separatorItem] {
            item.button?.target = self
            item.button?.action = #selector(clicked(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        separatorItem.button?.title = "│"
        separatorItem.button?.toolTip = "Draplet · ⌘-drag icons to the left to hide them"
        _ = engine
        configure()
    }
    func configure() {
        collapseTimer?.invalidate()
        engine.expand()
        if prefs.alwaysHidden && alwaysHiddenItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: 20)
            item.autosaveName = "Draplet.AlwaysHidden"
            item.button?.title = "┆"
            item.button?.toolTip = "Always hidden · ⌥-click Draplet to reveal"
            alwaysHiddenItem = item
        } else if !prefs.alwaysHidden, let item = alwaysHiddenItem {
            NSStatusBar.system.removeStatusItem(item)
            alwaysHiddenItem = nil
        }
        engine.updateAlwaysHiddenSection(enabled: canManage && prefs.alwaysHidden, separatorHidden: separatorsHidden)
        updatePresentation()
        if canManage { scheduleCollapse() }
    }
    func updatePresentation() {
        let collapsed = engine.state == .collapsed
        toggleItem.button?.image = NSImage(systemSymbolName: collapsed ? "chevron.left" : "chevron.right", accessibilityDescription: "Draplet")
        toggleItem.button?.toolTip = "Draplet · Click to \(collapsed ? "reveal" : "hide") icons · Right-click for settings"
        if !prefs.rightEnabled || prefs.paused { prefs.rightStatus = "Paused" }
        else if competingApp != nil { prefs.rightStatus = "Waiting for Hidden Bar to quit" }
        else if !prefs.permissionGranted { prefs.rightStatus = "Accessibility permission needed" }
        else {
            switch engine.state {
            case .collapsed: prefs.rightStatus = "Hidden"
            case .calibrating: prefs.rightStatus = "Reading icon positions…"
            case .unavailable: prefs.rightStatus = "Hiding unavailable — icons remain visible"
            case .expanded: prefs.rightStatus = "Expanded"
            }
        }
    }
    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp || sender === separatorItem.button {
            let menu = NSMenu()
            func add(_ title: String, _ action: Selector) {
                let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
                item.target = self
            }
            add("Draplet Settings…", #selector(settings))
            add("Reveal Both Sides", #selector(revealBoth))
            add(prefs.paused ? "Resume Draplet" : "Pause Draplet", #selector(pause))
            if competingApp != nil { add("Quit Hidden Bar and Use Draplet", #selector(replaceHiddenBar)) }
            menu.addItem(.separator())
            add("Quit Draplet", #selector(quit))
            menu.popUp(positioning: nil, at: .zero, in: sender)
        } else if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            revealAllMode.toggle()
            separatorsHidden = !revealAllMode
            expand()
        } else if !canManage {
            onSettings?()
        } else {
            engine.state == .collapsed ? expand() : collapse()
        }
    }
    @objc private func settings() { onSettings?() }
    @objc private func pause() { onPause?() }
    @objc private func revealBoth() { onRevealAll?() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc func replaceHiddenBar() {
        // This action is explicitly selected by the user; it never disables its login item.
        competingApp?.terminate()
    }
    func collapse() {
        guard canManage, engine.state != .calibrating, engine.isArrangementValid else { return }
        if prefs.alwaysHidden && !engine.isAlwaysHiddenSeparatorPlaced {
            prefs.error = "⌘-drag the dotted separator to the left of Draplet’s arrow first."
            return
        }
        if prefs.fullWidth { NSApp.setActivationPolicy(.accessory); NSApp.deactivate() }
        revealAllMode = false
        separatorsHidden = true
        engine.updateAlwaysHiddenSection(enabled: prefs.alwaysHidden, separatorHidden: true)
        engine.collapse { [weak self] _ in
            guard let self else { return }
            if !self.canManage { self.engine.expand() }
            self.lastCollapse = Date()
            self.updatePresentation()
        }
        updatePresentation()
    }
    func expand(all: Bool = false) {
        collapseTimer?.invalidate()
        if all { revealAllMode = true; separatorsHidden = false }
        engine.updateAlwaysHiddenSection(enabled: canManage && prefs.alwaysHidden, separatorHidden: !revealAllMode)
        engine.expand()
        if prefs.fullWidth && canManage { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        updatePresentation()
        if canManage { scheduleCollapse() }
    }
    private func scheduleCollapse() {
        guard prefs.autoCollapse else { return }
        collapseTimer?.invalidate()
        let timer = Timer(timeInterval: max(1, prefs.collapseDelay), repeats: false) { [weak self] _ in
            guard let self, self.canManage else { return }
            if self.mouseInBar || self.isSettingsVisible() || self.nativeMenuOpen {
                self.scheduleCollapse()
            } else { self.collapse() }
        }
        collapseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    // An on-screen popup at menu level means a user is still operating a menu,
    // even when the pointer has left the menu-bar strip. No cross-process AX wait.
    var nativeMenuOpen: Bool {
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { row in
            let layer = row[kCGWindowLayer as String] as? Int ?? 0
            return layer >= Int(CGWindowLevelForKey(.popUpMenuWindow)) && layer < 110
        }
    }
    private var mouseInBar: Bool {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            p.x >= screen.frame.minX && p.x <= screen.frame.maxX && p.y >= screen.frame.maxY - max(24, screen.safeAreaInsets.top) - 3
        }
    }
    func tick() {
        guard canManage, prefs.hoverRight, engine.state == .collapsed else { hoverEntered = nil; return }
        guard let frame = toggleItem.button?.window?.frame,
              frame.insetBy(dx: -12, dy: -3).contains(NSEvent.mouseLocation) else { hoverEntered = nil; return }
        if hoverEntered == nil { hoverEntered = Date() }
        if Date().timeIntervalSince(hoverEntered!) > 0.35 && Date().timeIntervalSince(lastCollapse) > 0.5 { expand() }
    }
    func stop() {
        guard !stopped else { return }; stopped = true
        collapseTimer?.invalidate()
        engine.updateAlwaysHiddenSection(enabled: false, separatorHidden: false)
        engine.expand()
        for item in [toggleItem, separatorItem, alwaysHiddenItem].compactMap({ $0 }) { NSStatusBar.system.removeStatusItem(item) }
    }
}
