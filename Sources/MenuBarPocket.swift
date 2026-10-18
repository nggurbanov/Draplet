import AppKit
import SwiftUI
import ScreenCaptureKit
import ApplicationServices

final class PocketModel: ObservableObject {
    @Published var items: [PocketItem] = []
    @Published var appIcons: [String: NSImage] = [:]
    @Published var images: [String: NSImage] = [:]
    @Published var loading = false
    @Published var readingInventory = false
    @Published var message = ""
    @Published var layoutWidths: [String: CGFloat] = [:]
    @Published var selected = 0
    @Published var focusedID: String?
    @Published var hovered: String?
}

private final class PocketPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// Exists lazily, captures only while opening/refreshing the pocket, and releases
// its hosting hierarchy and event monitors on close. No idle image timer.
final class MenuBarPocket {
    let model = PocketModel()
    private(set) var panel: NSPanel?
    private weak var owner: RightCurtain?
    private var work: Task<Void, Never>?
    private var generation = 0
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var attemptedIDs = Set<String>()
    private var lastInside = Date()
    private var capturedAt = Date.distantPast
    private var exposed = false
    private var watchdog: Timer?
    private var actionStarted: Date?
    private var actionPID: pid_t?
    private var openFrontPID: pid_t?
    private var initialWindows = Set<Int>()
    var isVisible: Bool { panel?.isVisible == true }
    var isBusy: Bool { work != nil || exposed }
    var debugStatus: [String: Any] { ["visible": isVisible, "busy": isBusy, "items": model.items.count, "images": model.images.count, "message": model.message, "width": panel?.frame.width ?? 0, "height": panel?.frame.height ?? 0] }
    var onChange: (() -> Void)?
    init(owner: RightCurtain) {
        self.owner = owner
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self else { return }
            let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            if PocketActionPolicy.shouldDismiss(for: pid, origin: self.openFrontPID, target: self.actionPID, own: getpid()) && (self.isVisible || self.actionPID != nil) { self.close() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.close() })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.close(); self?.model.images = [:] })
    }
    deinit {
        work?.cancel(); watchdog?.invalidate()
        for m in monitors { NSEvent.removeMonitor(m) }
        for o in observers { NSWorkspace.shared.notificationCenter.removeObserver(o); NotificationCenter.default.removeObserver(o) }
    }
    func open(all: Bool = false) {
        close()
        guard let owner, owner.canManage, !SystemPresentation.current(),
              let anchor = owner.toggleItem.button?.window?.frame,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) else { return }
        openFrontPID = ForegroundApplication.shared.current()?.pid
        generation += 1
        let token = generation
        lastInside = Date()
        model.message = ""; model.loading = true; model.readingInventory = true; model.selected = 0
        let panel = PocketPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) - 1)
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false; panel.hasShadow = true; panel.isReleasedWhenClosed = false
        panel.title = "Draplet Pocket"
        let hosting = NSHostingView(rootView: PocketView(model: model, activate: { [weak self] item, button in self?.activate(item, button: button) },
            refresh: { [weak self] in self?.attemptedIDs = []; self?.capturedAt = .distantPast; self?.open(all: all) }, reveal: { [weak self] in self?.close(); self?.owner?.expand() }))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrame(PocketGeometry.panelFrame(anchor: anchor, size: CGSize(width: 286, height: 160), screen: screen.frame,
                                                menuHeight: max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)), display: false)
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 12
        panel.contentView?.layer?.masksToBounds = true
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
        startWatchdog()
        onChange?()
        PocketInventory.read { [weak self] items in
            guard let self, token == self.generation, self.isVisible, let owner = self.owner else { return }
            let wanted = (owner.engine as? NativeVisibilityEngine)?.layout?.bundles(in: all ? [.hidden, .alwaysHidden] : [.hidden])
            self.model.items = items.filter { item in
                if let wanted { return wanted.contains(item.bundle) }
                let boundary = owner.separatorItem.button?.window?.frame ?? anchor
                return MenuBarLayoutResolver.section(of: item.frame, separatorFrame: boundary,
                    alwaysHiddenSeparatorFrame: all ? nil : owner.alwaysHiddenItem?.button?.window?.frame,
                    isLTR: Constant.isUsingLTRLanguage) == .hidden
            }.sorted {
                let saved = (owner.engine as? NativeVisibilityEngine)?.layoutInventory ?? []
                func x(_ item: PocketItem) -> CGFloat { saved.first { $0.bundleIdentifier == item.bundle }?.frame.minX ?? item.frame.minX }
                return x($0) == x($1) ? $0.id < $1.id : x($0) < x($1)
            }
            // Freeze hit-target topology for this opening. Newly captured wide
            // artwork can use a spanning cell next time, without moving a cell
            // beneath the pointer while an image is arriving.
            self.model.layoutWidths = Dictionary(uniqueKeysWithValues: self.model.items.map { ($0.id, self.model.images[$0.id]?.size.width ?? 24) })
            self.model.selected = 0
            self.model.readingInventory = false
            let oldArtwork = self.model.appIcons
            var byPID: [pid_t: NSImage] = [:]
            self.model.appIcons = Dictionary(uniqueKeysWithValues: self.model.items.map { item in
                if let cached = oldArtwork[item.id] { return (item.id, cached) }
                let icon = byPID[item.pid] ?? PocketImage.appArtwork(NSRunningApplication(processIdentifier: item.pid)?.icon ?? NSImage(named: NSImage.applicationIconName)!)
                byPID[item.pid] = icon
                return (item.id, icon)
            })
            let ids = Set(self.model.items.map(\.id))
            self.model.images = self.model.images.filter { ids.contains($0.key) }
            self.resize(anchor: anchor, screen: screen)
            if self.model.items.isEmpty {
                self.model.loading = false
                self.model.message = "No hidden icons yet. ⌘-drag icons to the left of Draplet’s arrow."
                return
            }
            if !Preferences.shared.backgroundPermission {
                self.model.loading = false
                self.model.message = "Using app icons. Enable menu-bar capture in Settings for status icons."
                self.resize(anchor: anchor, screen: screen); return
            }
            if ids.isSubset(of: self.attemptedIDs), Date().timeIntervalSince(self.capturedAt) < 120 {
                self.model.loading = false
                if self.model.images.count < self.model.items.count { self.model.message = "Some status icons use app artwork. Refresh to try again."; self.resize(anchor: anchor, screen: screen) }
                return
            }
            self.work = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { if token == self.generation { self.work = nil } }
                var content: SCShareableContent?
                let batches = PocketLayout.batches(self.model.items.map { ($0.id, $0.bundle, $0.frame.width) }, widthLimit: max(60, min(240, anchor.minX - (screen.auxiliaryTopRightArea?.minX ?? screen.frame.minX) - 16)))
                for batch in batches {
                    guard self.valid(token) else { break }
                    let batchItems = self.model.items.filter { batch.contains($0.id) }
                    if let native = owner.engine as? NativeVisibilityEngine {
                        self.exposed = true
                        let shown = await withCheckedContinuation { continuation in
                            native.showPocketBundles(Array(Set(batchItems.map(\.bundle)))) { continuation.resume(returning: $0) }
                        }
                        guard shown, self.valid(token) else {
                            if !shown && native.state == .expanded { owner.expand(); Preferences.shared.error = "Pocket couldn’t expose the selected icons. They remain available in the menu bar." }
                            break
                        }
                        // The native host's AX geometry settles before its pixels.
                        // A bounded 1 s wait avoids saving the previous bundle's icon.
                        try? await Task.sleep(for: .seconds(1))
                    }
                    for item in batchItems {
                        guard self.valid(token) else { break }
                        if let id = item.windowID, let image = DrapletPocketCopyImage(id), let icon = PocketImage.isolate(image) {
                            let image = NSImage(cgImage: icon, size: item.frame.size); image.isTemplate = PocketImage.isMonochrome(icon)
                            self.model.images[item.id] = image
                            continue
                        }
                        guard let frame = await self.currentFrame(item), self.valid(token) else { continue }
                        if content == nil { content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
                        guard self.valid(token), let content else { continue }
                        if let image = try? await self.capture(item, frame: frame, content: content, screen: screen), self.valid(token) {
                            self.model.images[item.id] = image
                        } else { self.model.images.removeValue(forKey: item.id) }
                    }
                }
                guard token == self.generation else { return }
                self.restoreExposure()
                self.model.loading = false
                self.capturedAt = Date()
                self.attemptedIDs = Set(self.model.items.map(\.id))
                if self.model.images.count < self.model.items.count {
                    self.model.message = "Some status icons use app artwork. Refresh to try again."
                }
                self.work = nil
                self.resize(anchor: anchor, screen: screen)
            }
        }
    }
    private func valid(_ token: Int) -> Bool {
        token == generation && !Task.isCancelled && isVisible && owner?.canManage == true && !SystemPresentation.current()
    }
    private func resize(anchor: CGRect, screen: NSScreen) {
        let rows = PocketLayout.rows(model.items.map { ($0.id, model.layoutWidths[$0.id] ?? 24) }).count
        let height = CGFloat(min(4, max(1, rows))) * 66 + 104 + (model.message.isEmpty ? 0 : 48)
        panel?.setFrame(PocketGeometry.panelFrame(anchor: anchor, size: CGSize(width: 286, height: height), screen: screen.frame,
                                                 menuHeight: max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)), display: true)
    }
    private func expose(_ engine: NativeVisibilityEngine, bundle: String) async -> Bool {
        await withCheckedContinuation { continuation in
            engine.showPocketBundle(bundle) { continuation.resume(returning: $0) }
        }
    }
    private func currentFrame(_ item: PocketItem) async -> CGRect? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // macOS 27 can keep the original AX proxy's cached position
                // after a visibility reflow. Resolve the extras bar afresh.
                let app = AXUIElementCreateApplication(item.pid)
                AXUIElementSetMessagingTimeout(app, 0.1)
                if let value = PocketInventory.attribute(app, "AXExtrasMenuBar") {
                    let bar = value as! AXUIElement
                    AXUIElementSetMessagingTimeout(bar, 0.1)
                    if let children = PocketInventory.attribute(bar, kAXChildrenAttribute) as? [AXUIElement],
                       let index = Int(item.id.split(separator: ":").last ?? ""), children.indices.contains(index) {
                        AXUIElementSetMessagingTimeout(children[index], 0.1)
                        continuation.resume(returning: PocketInventory.frame(children[index])); return
                    }
                }
                continuation.resume(returning: nil)
            }
        }
    }
    private func capture(_ item: PocketItem, frame: CGRect, content: SCShareableContent, screen: NSScreen) async throws -> NSImage? {
        guard let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
              let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
        let rightArea = screen.auxiliaryTopRightArea.map { CGRect(x: $0.minX, y: display.frame.minY, width: $0.width, height: 80) }
        guard PocketGeometry.isUsable(frame, on: display.frame, rightArea: rightArea) else {
            if CommandLine.arguments.contains("--test-controls") { NSLog("Pocket unavailable frame %@ %@", item.name, NSStringFromRect(frame)) }
            return nil
        }
        let config = SCStreamConfiguration()
        config.sourceRect = frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        config.width = max(1, Int(frame.width * screen.backingScaleFactor)); config.height = max(1, Int(frame.height * screen.backingScaleFactor))
        config.showsCursor = false; config.capturesAudio = false
        let filter = SCContentFilter(display: display, excludingApplications: content.applications.filter { $0.processID == getpid() }, exceptingWindows: [])
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let icon = PocketImage.isolate(image) else {
            if CommandLine.arguments.contains("--test-controls") { NSLog("Pocket blank snapshot %@ %@", item.name, NSStringFromRect(frame)) }
            return nil
        }
        let result = NSImage(cgImage: icon, size: frame.size); result.isTemplate = PocketImage.isMonochrome(icon)
        return result
    }
    func close(restore: Bool = true) {
        generation += 1; work?.cancel(); work = nil
        watchdog?.invalidate(); watchdog = nil
        panel?.orderOut(nil); panel?.contentView = nil; panel?.close(); panel = nil
        for monitor in monitors { NSEvent.removeMonitor(monitor) }; monitors.removeAll()
        model.loading = false; model.readingInventory = false
        if restore { restoreExposure() }
        onChange?()
    }
    private func restoreExposure() {
        guard exposed else { return }
        exposed = false; actionStarted = nil; actionPID = nil
        (owner?.engine as? NativeVisibilityEngine)?.showPocketBundle(nil) { [weak self] success in
            guard let self, !success, let owner = self.owner, owner.engine.state == .expanded else { return }
            owner.expand()
        }
    }
    func tick() {
        if !isVisible && !isBusy { watchdog?.invalidate(); watchdog = nil; return }
        if (isVisible || isBusy) && (SystemPresentation.current() || owner?.canManage != true) { close(); return }
        if isVisible {
            let pointer = NSEvent.mouseLocation
            if model.loading || panel?.frame.insetBy(dx: -6, dy: -6).contains(pointer) == true || owner?.toggleItem.button?.window?.frame.contains(pointer) == true { lastInside = Date() }
            else if Preferences.shared.autoCollapse && Date().timeIntervalSince(lastInside) > max(1, Preferences.shared.collapseDelay) { close(); return }
        }
        guard let started = actionStarted, Date().timeIntervalSince(started) > 3 else { return }
        let windows = WindowServerSnapshot.shared.current()
        let hostPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first?.processIdentifier
        let interfaceOpen = windows.contains { $0.visible && $0.layer > 0 && !initialWindows.contains($0.number) && ($0.pid == actionPID || $0.pid == hostPID) }
        if !interfaceOpen && owner?.nativeMenuOpen != true { restoreExposure(); watchdog?.invalidate(); watchdog = nil }
    }
    func setAppearance(_ appearance: NSAppearance?) { panel?.appearance = appearance }
    func activateNamed(_ name: String, button: CGMouseButton) {
        guard let item = model.items.first(where: { $0.name == name }) else { return }
        activate(item, button: button)
    }
    private func activate(_ item: PocketItem, button: CGMouseButton) {
        guard !model.readingInventory, let owner, owner.canManage else { return }
        close(restore: false)
        let token = generation
        actionPID = item.pid
        startWatchdog()
        work = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if token == self.generation { self.work = nil } }
            if let native = owner.engine as? NativeVisibilityEngine {
                self.exposed = true
                guard await self.expose(native, bundle: item.bundle) else {
                    self.restoreExposure()
                    if native.state == .expanded { owner.expand() }
                    return
                }
            } else {
                // Legacy engines must expose the native bar before addressing
                // an item. If its frame is still inaccessible, fail open below.
                owner.expand()
            }
            guard token == self.generation, !Task.isCancelled, owner.canManage, !SystemPresentation.current() else { self.restoreExposure(); return }
            WindowServerSnapshot.shared.invalidate()
            self.initialWindows = Set(WindowServerSnapshot.shared.current().filter(\.visible).map(\.number))
            self.actionPID = item.pid; self.actionStarted = Date()
            // A successful AX action may open a tracking menu and time out
            // before the menu closes. That is an unknown outcome, not permission
            // to send a second click. Only a definite unsupported action can fall
            // back to mouse routing.
            let result: AXError = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    AXUIElementSetMessagingTimeout(item.element, 5)
                    continuation.resume(returning: AXUIElementPerformAction(item.element,
                        (button == .left ? kAXPressAction : kAXShowMenuAction) as CFString))
                }
            }
            guard token == self.generation, !Task.isCancelled else { return }
            if PocketActionPolicy.shouldUseMouse(after: result) {
                try? await Task.sleep(for: .seconds(1))
                guard token == self.generation, !Task.isCancelled, !SystemPresentation.current() else { self.restoreExposure(); return }
                guard let frame = await self.currentFrame(item),
                      NSScreen.screens.contains(where: { screen in
                          let display = CGDisplayBounds((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID())
                          let right = screen.auxiliaryTopRightArea.map { CGRect(x: $0.minX, y: display.minY, width: $0.width, height: 80) }
                          return PocketGeometry.isUsable(frame, on: display, rightArea: right)
                      }) else {
                    self.restoreExposure(); owner.expand()
                    Preferences.shared.error = "That action isn’t available from Pocket. Use its native menu-bar icon."
                    return
                }
                guard token == self.generation, !Task.isCancelled else { return }
                if await PocketItemEvents.click(frame: frame, windowID: item.windowID, pid: item.pid, button: button) == false {
                    self.restoreExposure(); Preferences.shared.error = "Couldn’t open that status icon. Reveal it in the menu bar and try again."
                }
            } else if result == .apiDisabled || result == .invalidUIElement {
                self.restoreExposure(); Preferences.shared.error = "That icon is no longer available. Refresh Pocket or check Accessibility access."
            }
            self.work = nil
            self.watchdog?.invalidate(); self.watchdog = nil
        }
    }
    private func startWatchdog() {
        watchdog?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        watchdog = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func installMonitors() {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in self?.close() }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.type == .keyDown, NSApp.keyWindow === panel {
                if event.keyCode == 53 { self.close(); return nil }

            } else if event.window !== panel && event.window !== self.owner?.toggleItem.button?.window { self.close() }
            return event
        }) { monitors.append(monitor) }
    }
}

private struct PocketView: View {
    @ObservedObject var model: PocketModel
    let activate: (PocketItem, CGMouseButton) -> Void
    let refresh: () -> Void
    let reveal: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pocket").font(.system(size: 13, weight: .semibold))
                Spacer()
                if model.loading { ProgressView().controlSize(.small).accessibilityLabel("Reading status icons") }
                Button(action: refresh) { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("Refresh icons").accessibilityLabel("Refresh icons").disabled(model.loading)
            }
            if model.items.isEmpty {
                Text(model.loading ? "Reading hidden icons…" : model.message).font(.system(size: 12)).foregroundStyle(SettingsPalette.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                            let rows = PocketLayout.rows(model.items.map { ($0.id, model.layoutWidths[$0.id] ?? 24) })
                            ForEach(rows.indices, id: \.self) { row in
                                GridRow {
                                    ForEach(rows[row], id: \.id) { cell in
                                        if let item = model.items.first(where: { $0.id == cell.id }) {
                                            PocketCell(model: model, item: item, image: model.images[item.id] ?? model.appIcons[item.id], selected: model.focusedID == item.id,
                                                       loading: model.loading, activate: activate)
                                                .gridCellColumns(cell.span).id(item.id)
                                        }
                                    }
                                    let remaining = 3 - rows[row].reduce(0) { $0 + $1.span }
                                    if remaining > 0 { Color.clear.frame(height: 60).gridCellColumns(remaining).gridCellUnsizedAxes(.vertical) }
                                }
                            }
                        }
                    }.onChange(of: model.selected) { _, index in
                        if model.items.indices.contains(index) { proxy.scrollTo(model.items[index].id) }
                    }
                }
                if !model.message.isEmpty { Text(model.message).font(.system(size: 11)).foregroundStyle(SettingsPalette.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Divider()
            Button("Reveal in Menu Bar", action: reveal).buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(SettingsPalette.accent)
        }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: SettingsPalette.background))
    }
}

private struct PocketCell: View {
    @ObservedObject var model: PocketModel
    let item: PocketItem
    let image: NSImage?
    let selected: Bool
    let loading: Bool
    let activate: (PocketItem, CGMouseButton) -> Void
    var body: some View {
        VStack(spacing: 5) {
            if let image { Image(nsImage: image).renderingMode(image.isTemplate ? .template : .original).resizable().scaledToFit().frame(height: 27).accessibilityHidden(true) }
            else { Image(systemName: "menubar.rectangle").font(.system(size: 20)).foregroundStyle(SettingsPalette.secondary).frame(height: 27) }
            Text(item.name).font(.system(size: 10)).lineLimit(1).truncationMode(.tail).accessibilityHidden(true)
        }.padding(.horizontal, 6).frame(minWidth: 72, maxWidth: .infinity).frame(height: 60)
            .background(model.hovered == item.id || selected ? SettingsPalette.surface : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay(PocketClickTarget(label: item.name, itemID: item.id, enabled: !model.readingInventory,
                focus: { focused in
                    if focused { model.focusedID = item.id; model.selected = model.items.firstIndex(where: { $0.id == item.id }) ?? 0 }
                    else if model.focusedID == item.id { model.focusedID = nil }
                }, move: { key in
                    PocketLayout.neighbor(of: item.id, keyCode: key, items: model.items.map { ($0.id, model.layoutWidths[$0.id] ?? 24) })
                }, activate: { activate(item, $0) }))
            .onHover { model.hovered = $0 ? item.id : nil }.help(model.images[item.id] == nil ? "\(item.name) · Application artwork; status image unavailable" : item.name)
    }
}

private struct PocketClickTarget: NSViewRepresentable {
    let label: String
    let itemID: String
    let enabled: Bool
    let focus: (Bool) -> Void
    let move: (UInt16) -> String?
    let activate: (CGMouseButton) -> Void
    func makeNSView(context: Context) -> Target {
        let button = Target(); button.isBordered = false; button.isTransparent = true; button.title = ""
        button.target = button; button.action = #selector(Target.pressed)
        button.focusRingType = .exterior
        return button
    }
    func updateNSView(_ button: Target, context: Context) {
        button.setAccessibilityLabel(label); button.isEnabled = enabled; button.activate = activate
        button.itemID = itemID; button.focus = focus; button.move = move
    }
    final class Target: NSButton {
        var activate: ((CGMouseButton) -> Void)?
        var itemID = ""
        var focus: ((Bool) -> Void)?
        var move: ((UInt16) -> String?)?
        override var acceptsFirstResponder: Bool { isEnabled }
        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted { focus?(true) }
            return accepted
        }
        override func resignFirstResponder() -> Bool {
            let accepted = super.resignFirstResponder()
            if accepted { focus?(false) }
            return accepted
        }
        override func keyDown(with event: NSEvent) {
            guard isEnabled, event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { super.keyDown(with: event); return }
            if [123, 124, 125, 126].contains(event.keyCode), let id = move?(event.keyCode) {
                func target(in view: NSView) -> Target? {
                    if let button = view as? Target, button.itemID == id { return button }
                    for child in view.subviews { if let match = target(in: child) { return match } }
                    return nil
                }
                if let content = window?.contentView, let button = target(in: content) { window?.makeFirstResponder(button) }
                return
            }
            if event.keyCode == 36 || event.keyCode == 49 { activate?(.left); return }
            super.keyDown(with: event)
        }
        @objc func pressed() { activate?(.left) }
        override func rightMouseDown(with event: NSEvent) { }
        override func rightMouseUp(with event: NSEvent) { if isEnabled { activate?(.right) } }
    }
}
