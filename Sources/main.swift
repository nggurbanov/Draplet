import AppKit
import ApplicationServices
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    let prefs = Preferences.shared
    let left = LeftCurtain()
    var right: RightCurtain!
    var settings: SettingsController!
    var pulse: Timer?
    var observers: [NSObjectProtocol] = []
    var appearanceObserver: NSKeyValueObservation?
    var presentationObserver: NSKeyValueObservation?
    var hotkey: EventHotKeyRef?
    var eventHandler: EventHandlerRef?
    var wasAuthorized = false
    var hiddenBarWasRunning = false
    var terminating = false
    var previewGeneration = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let siblings = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.tyrell.Draplet")
        if siblings.count > 1 {
            siblings.first { $0.processIdentifier != getpid() }?.activate(options: [])
            exit(0)
        }
        makeMenus()
        AppUpdater.shared.start()
        // Packaging-only fixtures exercise the actual updater without starting
        // menu-bar engines or asking for hardware permissions.
        if Bundle.main.object(forInfoDictionaryKey: "DrapletUpdateTest") as? Bool == true {
            settings = SettingsController(prefs: prefs, requestPermission: {}, replaceHiddenBar: {},
                                          revealBoth: {}, pause: {}, previewAnimations: {})
            settings.show()
            if CommandLine.arguments.contains("--test-controls") { testControls() }
            return
        }
        right = RightCurtain()
        settings = SettingsController(prefs: prefs, requestPermission: { [weak self] in self?.requestPermission() },
                                      replaceHiddenBar: { [weak self] in self?.right.replaceHiddenBar() },
                                      revealBoth: { [weak self] in self?.revealBoth() }, pause: { [weak self] in self?.togglePause() },
                                      previewAnimations: { [weak self] in self?.previewAnimations() })
        right.onSettings = { [weak self] in self?.settings.show() }
        left.onSettings = { [weak self] in self?.settings.show() }
        right.onPause = { [weak self] in self?.togglePause() }
        right.onRevealAll = { [weak self] in self?.revealBoth() }
        right.isSettingsVisible = { [weak self] in self?.settings.window?.isVisible ?? false }
        observers.append(NotificationCenter.default.addObserver(forName: .drapletPreferencesChanged, object: nil, queue: .main) { [weak self] _ in self?.applyPreferences() })
        observers.append(NotificationCenter.default.addObserver(forName: MenuBarBackdrop.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.terminating else { return }
            let error = MenuBarBackdrop.shared.failure ?? ""
            if self.prefs.backgroundError != error { self.prefs.backgroundError = error }
            if self.prefs.backgroundReady != MenuBarBackdrop.shared.ready {
                self.prefs.backgroundReady = MenuBarBackdrop.shared.ready; self.applyPreferences()
            }
            self.left.refreshBackground(); self.right.refreshBackground()
            self.left.setPresentationSuppressed(MenuBarBackdrop.shared.presentationSuppressed)
            self.right.setPresentationSuppressed(MenuBarBackdrop.shared.presentationSuppressed)
        })
        observers.append(NotificationCenter.default.addObserver(forName: MenuBarBackdrop.presentationDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.left.setPresentationSuppressed(MenuBarBackdrop.shared.presentationSuppressed)
            self?.right.setPresentationSuppressed(MenuBarBackdrop.shared.presentationSuppressed)
        })
        ForegroundFullscreen.shared.onChange = { MenuBarBackdrop.shared.checkScene() }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                ForegroundFullscreen.shared.forget(pid: app.processIdentifier)
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in MenuBarBackdrop.shared.checkScene() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { MenuBarBackdrop.shared.refreshAppearance() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshDisplays() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshDisplays() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            ForegroundFullscreen.shared.invalidate()
            MenuBarBackdrop.shared.checkScene()
            self?.left.syncVisibility()
            MenuBarBackdrop.shared.refreshAppearance()
        })
        presentationObserver = NSApp.observe(\.currentSystemPresentationOptions, options: [.new]) { _, _ in
            DispatchQueue.main.async { MenuBarBackdrop.shared.checkScene() }
        }
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { _, _ in
            DispatchQueue.main.async { MenuBarBackdrop.shared.refreshAppearance() }
        }
        wasAuthorized = AXIsProcessTrusted()
        hiddenBarWasRunning = right.competingApp != nil
        applyPreferences()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        pulse = timer
        RunLoop.main.add(timer, forMode: .common)
        let firstRun = !UserDefaults.standard.bool(forKey: "hasLaunched")
        UserDefaults.standard.set(true, forKey: "hasLaunched")
        if firstRun || !wasAuthorized || !prefs.backgroundPermission || CommandLine.arguments.contains("--settings") { settings.show() }
        if CommandLine.arguments.contains("--test-controls") { testControls() }
        if let index = CommandLine.arguments.firstIndex(of: "--quit-after"), CommandLine.arguments.count > index + 1,
           let seconds = Double(CommandLine.arguments[index + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { NSApp.terminate(nil) }
        }
        NSLog("Draplet ready; accessibility=%d; nativeVisibility=%d", wasAuthorized, HBNativeVisibilityIsAvailable())
    }
    func applyPreferences() {
        guard !terminating else { return }
        previewGeneration += 1
        prefs.permissionGranted = AXIsProcessTrusted()
        if prefs.permissionGranted && prefs.needsBackground {
            ForegroundFullscreen.shared.prewarm(NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
                .map(\.processIdentifier))
        }
        prefs.backgroundPermission = MenuBarBackdrop.shared.permission
        if prefs.needsBackground { MenuBarBackdrop.shared.start(mode: prefs.backgroundMode) } else { MenuBarBackdrop.shared.stop() }
        if prefs.leftEnabled && !prefs.paused && prefs.permissionGranted && MenuBarBackdrop.shared.ready { left.start() }
        else { left.stop() }
        left.refreshPreferences()
        right.configure()
        registerShortcut()
    }
    func refreshDisplays() {
        left.stop()
        MenuBarBackdrop.shared.restart()
        applyPreferences()
        right.engine.invalidateLayout()
    }
    func tick() {
        let authorized = AXIsProcessTrusted()
        let competing = right.competingApp != nil
        if wasAuthorized != authorized || hiddenBarWasRunning != competing || prefs.backgroundPermission != MenuBarBackdrop.shared.permission {
            wasAuthorized = authorized; hiddenBarWasRunning = competing
            applyPreferences()
        }
        MenuBarBackdrop.shared.checkScene()
        right.tick()
    }
    @objc func togglePause() { prefs.paused.toggle(); applyPreferences() }
    @objc func revealBoth() { right.expand(all: true) { [weak self] in self?.left.revealForShortcut() } }
    func previewAnimations() {
        previewGeneration += 1; let token = previewGeneration
        left.manualUntil = Date().addingTimeInterval(5)
        left.setReveal(false, "preview", animated: false)
        right.collapse { [weak self] _ in
            guard let self, token == self.previewGeneration else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, token == self.previewGeneration else { return }
                self.right.expand { [weak self] in
                    guard let self, token == self.previewGeneration else { return }
                    self.left.revealForShortcut()
                    let hold = self.prefs.animationPace.duration(opening: true) + 1.2
                    DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in
                        guard let self, token == self.previewGeneration, !self.right.nativeMenuOpen else { return }
                        self.left.manualUntil = Date().addingTimeInterval(3)
                        self.left.setReveal(false, "preview")
                        self.right.collapse()
                    }
                }
            }
        }
    }
    @objc func showSettings() { settings?.show() }
    @objc func checkForUpdates() { AppUpdater.shared.check() }
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    private func makeMenus() {
        let bar = NSMenu()
        let item = bar.addItem(withTitle: "Draplet", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Draplet")
        let settings = menu.addItem(withTitle: "Draplet Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        let updates = menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Draplet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = menu
        let edit = bar.addItem(withTitle: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu
        NSApp.mainMenu = bar
    }
    func registerShortcut() {
        if let hotkey { UnregisterEventHotKey(hotkey); self.hotkey = nil }
        guard prefs.shortcut < 3 else { return }
        if eventHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let context = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().revealBoth()
                return noErr
            }, 1, &spec, context, &eventHandler)
        }
        let key = [UInt32(kVK_Space), UInt32(kVK_ANSI_D), UInt32(kVK_ANSI_B)][prefs.shortcut]
        let result = RegisterEventHotKey(key, UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x44524150, id: 1), GetApplicationEventTarget(), 0, &hotkey)
        if result != noErr { prefs.error = "The reveal shortcut is already in use. Choose another in General." }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { settings?.show(); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Let AppKit finish termination so Sparkle can install a staged update.
        // Cleanup stays idempotent and releases all native assertions.
        cleanup()
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) { cleanup() }
    func cleanup() {
        guard !terminating else { return }; terminating = true
        appearanceObserver = nil; presentationObserver = nil
        ForegroundFullscreen.shared.onChange = nil
        pulse?.invalidate(); left.stop(); right?.stop(); MenuBarBackdrop.shared.stop()
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        NSLog("Draplet cleanup complete")
    }
    private static func readControlLine() -> String? {
        // Swift readLine holds stdin's stdio lock while waiting. Foundation's
        // XML parser also asks for that lock, deadlocking Sparkle in test mode.
        var bytes: [UInt8] = []
        var byte: UInt8 = 0
        while read(STDIN_FILENO, &byte, 1) == 1 {
            if byte == 10 { return String(decoding: bytes, as: UTF8.self) }
            bytes.append(byte)
        }
        return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self)
    }
    private func testControls() {
        Thread.detachNewThread { [weak self] in
            while let line = Self.readControlLine() {
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch line {
                    case "status":
                        let status: [String: Any] = ["authorized": AXIsProcessTrusted(), "leftEnabled": self.left.enabled,
                            "right": self.prefs.rightStatus, "native": HBNativeVisibilityIsAvailable(),
                            "leftVisible": self.left.panel?.isVisible ?? false, "leftRevealed": self.left.revealed, "progress": (self.left.panel?.contentView as? LeftCurtain.CoverView)?.progress ?? 0,
                            "frame": self.left.frameJSON(self.left.coverFrame), "level": self.left.coverLevel.rawValue,
                            "leftTrigger": self.prefs.trigger(for: .left).rawValue, "rightTrigger": self.prefs.trigger(for: .right).rawValue,
                            "leftIcon": self.prefs.icon(for: .left).rawValue, "rightIcon": self.prefs.icon(for: .right).rawValue,
                            "pace": self.prefs.animationPace.rawValue, "leftAnimation": self.prefs.animation(for: .left).rawValue,
                            "backgroundMode": self.prefs.backgroundMode.rawValue, "streaming": MenuBarBackdrop.shared.streaming,
                            "backgroundSnapshots": MenuBarBackdrop.shared.snapshotCount, "backgroundFrames": MenuBarBackdrop.shared.frameCount,
                            "backgroundReady": MenuBarBackdrop.shared.ready, "backgroundPermission": MenuBarBackdrop.shared.permission,
                            "systemPresentationSuspended": MenuBarBackdrop.shared.systemPresentationSuspended,
                            "presentationSuppressed": MenuBarBackdrop.shared.presentationSuppressed,
                            "nativeFullscreen": ForegroundFullscreen.shared.isFullscreen,
                            "rightAnimation": self.right.animationStatus,
                            "hitWindow": self.left.clickPanel?.windowNumber ?? 0,
                            "hitVisible": self.left.clickPanel?.isVisible ?? false,
                            "leftArrowFrame": self.left.frameJSON(self.left.clickPanel?.frame ?? .zero),
                            "arrowFrame": self.left.frameJSON(self.right.toggleItem.button?.window?.frame ?? .zero)]
                        var output = status
                        output["dockVisible"] = NSApp.activationPolicy() == .regular
                        output["settingsVisible"] = self.settings.window?.isVisible ?? false
                        let data = try! JSONSerialization.data(withJSONObject: output, options: .sortedKeys)
                        print(String(data: data, encoding: .utf8)!, terminator: "\n"); fflush(stdout)
                    case "right-click": self.right.toggleItem.button?.performClick(nil)
                    case "expand": self.right.expand()
                    case "collapse": self.right.collapse()
                    case "reveal": self.revealBoth()
                    case "settings": self.settings.show()
                    case "settings-close": self.settings.window?.close()
                    case "appearance-light": self.settings.window?.appearance = NSAppearance(named: .aqua)
                    case "appearance-dark": self.settings.window?.appearance = NSAppearance(named: .darkAqua)
                    case "appearance-system": self.settings.window?.appearance = nil
                    case "left-toggle": self.left.indicatorClicked()
                    case "preview": self.previewAnimations()
                    case "pace-a": self.prefs.animationPace = .originalLeft
                    case "pace-b": self.prefs.animationPace = .originalRight
                    case "curtain": self.prefs.sameAnimation = true; self.prefs.sharedAnimation = .curtain
                    case "fade": self.prefs.sameAnimation = true; self.prefs.sharedAnimation = .fade
                    case "native-right": self.prefs.linkAnimations(false); self.prefs.rightAnimation = .hiddenBar
                    case "cached": self.prefs.backgroundMode = .cached
                    case "live": self.prefs.backgroundMode = .live
                    case "background-refresh": MenuBarBackdrop.shared.refreshAppearance()
                    case "background-save":
                        if let image = MenuBarBackdrop.shared.snapshot {
                            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/draplet-matched-background.png"))
                        }
                    case "both-click": self.prefs.sharedTrigger = .click; self.prefs.sameTrigger = true
                    case "both-hover": self.prefs.sharedTrigger = .hover; self.prefs.sameTrigger = true
                    case "default-icons":
                        self.prefs.removeCustomIcon(side: nil); self.prefs.removeCustomIcon(side: .left); self.prefs.removeCustomIcon(side: .right)
                        self.prefs.sharedIcon = .chevron; self.prefs.leftIcon = .chevron; self.prefs.rightIcon = .chevron; self.prefs.sameIcons = true
                    case "pause": self.togglePause()
                    case "quit": NSApp.terminate(nil)
                    default: break
                    }
                }
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
