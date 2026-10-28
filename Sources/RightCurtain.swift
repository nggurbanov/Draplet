import AppKit
@preconcurrency import ApplicationServices

// The hiding engines are vendored from Hidden Bar under MIT; see ThirdPartyNotices.md.
final class RightCurtain: NSObject, MenuBarItemProvider {
    let toggleItem = NSStatusBar.system.statusItem(withLength: 26)
    let separatorItem = NSStatusBar.system.statusItem(withLength: 20)
    private(set) var alwaysHiddenItem: NSStatusItem?
    lazy var engine = MenuBarEngineFactory.make(items:self,inventory:HostedMenuBarInventory { [weak self] host,display in
        self?.observeArrow(in:host,on:display)
    })
    private let cover = RightMenuCover()
    private var pocket: MenuBarPocket?
    private let compatibility = CompatibilityMenuItems()
    private var compatibilityHost: [String: Any] = [:]
    private var observedArrow: (frame:CGRect,at:Date,backing:CGRect?)?
    private var clickRouter:StatusItemClickRouter?
    private var routingScanInFlight = false
    private var routingScanAt = Date.distantPast
    private var routingGeneration = 0
    var effectiveToggleFrame: CGRect? {
        if let observedArrow,observedArrow.backing == toggleItem.button?.window?.frame,
           Date().timeIntervalSince(observedArrow.at) < 6 { return observedArrow.frame }
        return toggleItem.button?.window?.frame
    }
    func statusItemFrame(_ item:NSStatusItem) -> CGRect? {
        guard item === toggleItem else { return item.button?.window?.frame }
        // MenuBarAgent can keep the backing window permanently offset. Native
        // section classification may use only the independently hosted arrow;
        // without it the engine fails open and retries instead of hiding a
        // language indicator which the user placed to the arrow's right.
        guard let observedArrow,observedArrow.backing == item.button?.window?.frame,
              Date().timeIntervalSince(observedArrow.at) < 6 else { return nil }
        return observedArrow.frame
    }
    private var pocketGeneration = 0
    private let overflowButton = PocketOverflowButton()
    private var overflowItems: [PocketItem] = []
    private var overflowScreen: NSScreen?
    private var scanInFlight = false
    private var lastScan = Date.distantPast
    private var overflowIdentity = ""
    private var overflowDiagnostics: [String:Any] = [:]
    private var nativeOwners: [String:[String]] = [:]
    private var nativeOwnerPIDs: [String:pid_t] = [:]
    private var previousPins: [String] = []
    private var inventoryKey = ""
    private var preparedLayout: (key:String,frame:CGRect?,extent:CGFloat)?
    private var lastWarmCheck = Date.distantPast
    private var revealLayoutKey: String {
        let displays = NSScreen.screens.map { "\($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? 0):\($0.frame):\($0.backingScaleFactor)" }
        return "\(animationFrame ?? .zero)|\(displays)|\(prefs.pinnedPocketBundles)|\(prefs.alwaysHidden)|\(revealAllMode)|\(inventoryKey)"
    }
    private var lastGlyph: NSImage?
    private var draggingToPocket = false
    private var dragAnchor: NSPanel?
    private var dragController: PocketDragController?
    private var pinningActive: Bool { canManage && prefs.rightRevealMode == .pocket && MenuBarBackdrop.shared.ready && !MenuBarBackdrop.shared.presentationSuppressed && engine is NativeVisibilityEngine }
    private func updatePinPolicy(completion: @escaping () -> Void = {}) {
        guard let native = engine as? NativeVisibilityEngine else { completion(); return }
        native.updatePocketPlacement(pinned: pinningActive && !revealAllMode ? Set(prefs.pinnedPocketBundles) : [], owners: nativeOwners, completion:completion)
    }
    func inventoryDidChange() { lastScan = .distantPast; preparedLayout = nil }
    func setPocketPin(_ bundle: String, pinned: Bool) {
        pocketGeneration += 1; pocket?.close(reason:"pin-change")
        if pinned { compatibility.remove(bundle: bundle) }
        prefs.setPocketPin(bundle, pinned: pinned)
        lastScan = .distantPast; updatePinPolicy(); updatePresentation(); refreshOverflow()
    }
    func returnFromPocket(_ bundle: String) {
        setPocketPin(bundle,pinned:false)
        expand()
    }
    var pocketStatus: [String:Any] {
        var status = pocket?.debugStatus ?? ["visible":false,"busy":false,"items":0,"images":0]
        status["overflow"] = overflowItems.map(\.name); status["buttonVisible"] = overflowButton.isVisible
        status["buttonX"] = overflowButton.frame?.minX ?? -1
        status["buttonMaxX"] = overflowButton.frame?.maxX ?? -1
        status["scan"] = overflowDiagnostics; status["scanInFlight"] = scanInFlight
        status["pointerHeld"] = containsInteraction
        status["outsideSince"] = autoHide.outsideSince ?? -1
        status["pins"] = prefs.pinnedPocketBundles
        status["pinningActive"] = pinningActive
        status["dragAvailable"] = dragController?.available == true
        status["dragging"] = draggingToPocket
        status["transitioning"] = transition.isTransitioning
        status["compatibility"] = compatibility.diagnostics
        status["compatibilityHost"] = compatibilityHost
        status["clickRouting"] = ["available":clickRouter?.available == true,"frame":clickRouter?.frame.map(NSStringFromRect) ?? "none"]
        status["autoHideEnabled"] = prefs.autoCollapse
        status["holdReasons"] = holdReasons
        return status
    }
    private lazy var transition = RightMenuTransition(engine: engine, cover: cover)
    private let prefs = Preferences.shared
    private var autoHide = RightAutoHidePolicy()
    private var lastCollapse = Date.distantPast
    private var separatorsHidden = true
    private var revealAllMode = false
    private var stopped = false
    private var presentationSuppressed = false
    private var presentationChangeCount = 0
    private var configuration = ""
    private var hoverTimer: Timer?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    var onSettings: (() -> Void)?
    var onPause: (() -> Void)?
    var onRevealAll: (() -> Void)?
    var isSettingsVisible: () -> Bool = { false }
    var competingApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.dwarvesv.minimalbar").first
    }
    var canManage: Bool { prefs.rightEnabled && !prefs.paused && prefs.permissionGranted && competingApp == nil }
    var canReturnStatusItem: Bool { canManage && transition.expanded }
    var returnPlacementReady: Bool { transition.expanded && !transition.isTransitioning }
    override init() {
        super.init()
        toggleItem.autosaveName = "Draplet.Toggle"
        toggleItem.button?.setAccessibilityIdentifier("Draplet.Toggle")
        separatorItem.autosaveName = "Draplet.Separator"
        toggleItem.isVisible = true
        separatorItem.isVisible = true
        for item in [toggleItem, separatorItem] {
            item.button?.target = self
            item.button?.action = #selector(clicked(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        toggleItem.button?.isBordered = false
        toggleItem.button?.focusRingType = .none
        (toggleItem.button?.cell as? NSButtonCell)?.highlightsBy = []
        (toggleItem.button?.cell as? NSButtonCell)?.showsStateBy = []
        separatorItem.button?.title = "│"
        separatorItem.button?.toolTip = "Draplet · ⌘-drag icons to the left to hide them"
        _ = engine
        overflowButton.onClick = { [weak self] in self?.togglePocket() }
        overflowButton.onRefresh = { [weak self] in self?.showPocket(refresh:true) }
        overflowButton.onSettings = { [weak self] in self?.settings() }
        compatibility.onActivate = { [weak self] item,button in
            guard let self, self.canManage else { return }
            if self.pocket == nil {
                self.pocket = MenuBarPocket(owner:self)
                self.pocket?.onChange = { [weak self] in self?.overflowButton.setExpanded(self?.pocket?.isVisible == true) }
            }
            self.pocket?.activateStatusItem(item,button:button)
        }
        configure()
    }
    func configure() {
        if prefs.rightRevealMode != .pocket || !canManage {
            cover.setRevealExtent(nil)
            pocketGeneration += 1; pocket?.close(reason:"configuration-disabled"); overflowButton.hide(); overflowItems = []
        }
        cover.setPresentationSuppressed(MenuBarBackdrop.shared.presentationSuppressed)
        if previousPins != prefs.pinnedPocketBundles { previousPins = prefs.pinnedPocketBundles; lastScan = .distantPast }
        updatePinPolicy()
        updateDragController()
        updateClickRouter()
        updateHoverMonitor()
        let next = "\(canManage)-\(prefs.alwaysHidden)-\(prefs.autoCollapse)-\(prefs.collapseDelay)-\(prefs.fullWidth)-\(MenuBarBackdrop.shared.ready)"
        guard next != configuration else { updatePresentation(); return }
        configuration = next
        pocketGeneration += 1; pocket?.close(reason:"configuration")
        autoHide.reset()
        transition.cancelAndExpand()
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
        compatibility.present(active:canManage && prefs.rightRevealMode == .pocket && !presentationSuppressed && !revealAllMode && (engine as? NativeVisibilityEngine)?.hasVisibilityRestriction == true && !MenuBarBackdrop.shared.presentationSuppressed && !SystemPresentation.current(),
                              expanded:transition.expanded || transition.isTransitioning,all:revealAllMode)
        let collapsed = !transition.expanded
        let glyph = IndicatorIcons.image(for: .right, expanded: !collapsed)
        if toggleItem.length != 26 { toggleItem.length = 26 }
        if lastGlyph !== glyph {
            lastGlyph = glyph; toggleItem.button?.image = glyph
        }
        if collapsed { overflowButton.hide() }
        toggleItem.button?.setAccessibilityLabel(collapsed ? "Reveal status icons" : "Hide status icons")
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
        if compatibility.isPlacing || NSApp.currentEvent?.cgEvent?.getIntegerValueField(.eventSourceUserData) == PocketItemEvents.placementEventTag { return }
        performToggleClick(rightMouse:NSApp.currentEvent?.type == .rightMouseUp || sender === separatorItem.button,
                           option:NSApp.currentEvent?.modifierFlags.contains(.option) == true,sender:sender)
    }
    private func performToggleClick(rightMouse:Bool,option:Bool,sender:NSStatusBarButton? = nil) {
        if rightMouse {
            let menu = NSMenu()
            func add(_ title: String, _ action: Selector) {
                let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
                item.target = self
            }
            add("Draplet Settings…", #selector(settings))
            if compatibility.hasItems {
                add("Refresh Icons", #selector(refreshCompatibilityIcons))
                menu.items.last?.isEnabled = canManage && !transition.isTransitioning && pocket?.isBusy != true && !presentationSuppressed
            }
            add("Reveal Both Sides", #selector(revealBoth))
            add(prefs.paused ? "Resume Hiding" : "Pause Hiding", #selector(pause))
            if competingApp != nil { add("Quit Hidden Bar and Use Draplet", #selector(replaceHiddenBar)) }
            menu.addItem(.separator())
            add("Quit Draplet", #selector(quit))
            if let sender { menu.popUp(positioning:nil,at:.zero,in:sender) }
            else if let frame = effectiveToggleFrame { menu.popUp(positioning:nil,at:CGPoint(x:frame.minX,y:frame.minY),in:nil) }
        } else if option {
            revealAllMode.toggle()
            separatorsHidden = !revealAllMode
            expand()
        } else if !canManage {
            onSettings?()
        } else {
            transition.expanded ? collapse() : expand()
        }
    }
    @objc private func settings() { pocket?.close(); onSettings?() }
    @objc private func refreshCompatibilityIcons() { refreshCompatibilityItems(compatibility.sources) }
    private func refreshCompatibilityItems(_ items:[PocketItem]) {
        guard canManage,!items.isEmpty,!transition.isTransitioning,!presentationSuppressed,
              let arrow = effectiveToggleFrame,let screen = NSScreen.screens.first(where:{ $0.frame.intersects(arrow) }) else { return }
        if pocket == nil {
            pocket = MenuBarPocket(owner:self)
            pocket?.onChange = { [weak self] in self?.overflowButton.setExpanded(self?.pocket?.isVisible == true) }
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.1) { [weak self] in
            guard let self,self.canManage,!self.presentationSuppressed else { return }
            self.pocket?.refreshStatusItems(items,screen:screen)
        }
    }
    @objc private func pause() { onPause?() }
    @objc private func revealBoth() { onRevealAll?() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc func replaceHiddenBar() {
        // This action is explicitly selected by the user; it never disables its login item.
        competingApp?.terminate()
    }
    private var animationStyle: BarAnimation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || !MenuBarBackdrop.shared.ready ? .hiddenBar : prefs.animation(for: .right)
    }
    private var animationFrame: NSRect? {
        guard NSMenu.menuBarVisible(), let arrow = effectiveToggleFrame,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(arrow) }) else { return nil }
        let start = screen.auxiliaryTopRightArea?.minX ?? screen.frame.midX
        let height = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
        guard arrow.minX > start else { return nil }
        return NSRect(x: start, y: screen.frame.maxY - height, width: arrow.minX - start, height: height)
    }
    var animationStatus: [String: Any] {
        ["style": animationStyle.rawValue, "expanded": transition.expanded,
         "coverVisible": cover.isVisible,"coverPresented":cover.isPresented,"progress": cover.progress,"transitioning":transition.isTransitioning,
         "draws": cover.drawCount,"displayRequests": cover.displayRequestCount,
         "timerActive": cover.animationTimerActive,"presentationChanges": presentationChangeCount]
    }
    func refreshBackground() { cover.refreshBackground();pocket?.refreshBackground() }
    func setPresentationSuppressed(_ suppressed: Bool) {
        // Live background frames still invalidate their pixels independently.
        // Only a presentation change needs policy, native-item and status work.
        cover.setPresentationSuppressed(suppressed)
        guard presentationSuppressed != suppressed else { return }
        presentationSuppressed = suppressed
        presentationChangeCount += 1
        if suppressed { preparedLayout = nil }
        if suppressed { cancelHover(); dragController?.cancel(); pocketGeneration += 1; pocket?.close(reason:"system-presentation"); overflowButton.hide() }
        updatePinPolicy()
        updatePresentation()
    }
    func collapse(completion: ((CollapseResult) -> Void)? = nil) {
        pocketGeneration += 1
        autoHide.reset(); overflowButton.hide()
        if pocket?.isVisible == true || pocket?.isBusy == true { pocketGeneration += 1; pocket?.close(reason:"strip-collapse") }
        guard canManage, engine.isArrangementValid else { completion?(.unavailable); return }
        if prefs.alwaysHidden && !engine.isAlwaysHiddenSeparatorPlaced {
            prefs.error = "⌘-drag the dotted separator to the left of Draplet’s arrow first."
            completion?(.unavailable)
            return
        }
        // Settings alone owns the Dock policy. Full-width mode only borrows
        // focus for Draplet's short menu and must not hide an open Settings app.
        if prefs.fullWidth && !isSettingsVisible() { NSApp.deactivate() }
        revealAllMode = false
        if let arrow = effectiveToggleFrame {
            for (key,raw) in compatibility.rememberSections(arrow:arrow,alwaysHidden:alwaysHiddenItem?.button?.window?.frame,isLTR:Constant.isUsingLTRLanguage) {
                prefs.setCompatibilityItem(key,section:MenuBarSection(rawValue:raw))
            }
        }
        updatePinPolicy()
        separatorsHidden = true
        engine.updateAlwaysHiddenSection(enabled: prefs.alwaysHidden, separatorHidden: true)
        transition.collapse(style: animationStyle, pace: prefs.animationPace, frame: animationFrame) { [weak self] result in
            guard let self else { return }
            if !self.canManage { self.transition.cancelAndExpand() }
            self.lastCollapse = Date()
            self.updatePresentation()
            completion?(result)
        }
        updatePresentation()
    }
    func expand(all: Bool = false, onStart: @escaping () -> Void = {}) {
        autoHide.reset()
        lastScan = .distantPast
        pocketGeneration += 1; pocket?.close(reason:"strip-expand"); overflowButton.hide()
        if all { revealAllMode = true; separatorsHidden = false }
        updatePinPolicy()
        engine.updateAlwaysHiddenSection(enabled: canManage && prefs.alwaysHidden, separatorHidden: !revealAllMode)
        if prefs.fullWidth && canManage { NSApp.activate(ignoringOtherApps: true) }
        let prepared = compatibility.hasItems ? nil : preparedLayout.flatMap { $0.key == revealLayoutKey ? $0 : nil }
        transition.expand(style: canManage ? animationStyle : .hiddenBar, pace: prefs.animationPace,
                          frame: animationFrame, layoutPrepared:prepared != nil || compatibility.hasItems, prepare:{ [weak self] done in
                              guard let self else { done(); return }
                              self.updatePresentation()
                              let preparationToken = self.pocketGeneration
                              self.prepareCompatibilitySlots(token:preparationToken,completion:{ [weak self] in
                              guard let self,self.pocketGeneration == preparationToken,self.transition.expanded,self.canManage,!SystemPresentation.current() else { done(); return }
                              self.cover.updateClosedFrame(self.animationFrame)
                              if let prepared {
                                  self.cover.setRevealExtent(prepared.extent)
                                  if let frame = prepared.frame, !self.overflowItems.isEmpty {
                                      self.overflowButton.show(at:frame,beneath:self.cover.maskingWindow)
                                  }
                                  done(); return
                              }
                              self.prepareOverflow(deadline:ProcessInfo.processInfo.systemUptime+1.5,token:self.pocketGeneration,completion:done)
                              })
                          }, onStart: onStart) { [weak self] in
                              self?.overflowButton.finishReveal(); self?.updatePresentation()
                          }
        if cover.isPresented,cover.progress == 0,let frame = animationFrame {
            pocket?.handoffCaptureShield(coveredBy:frame)
        }
        updatePresentation()
        refreshOverflow()
        if canManage { scheduleCollapse() }
    }
    private func scheduleCollapse() { autoHide.reset() }
    var containsInteraction: Bool {
        draggingToPocket || pocket?.containsPointer == true || pocket?.isBusy == true || (transition.expanded && (mouseInBar || overflowButton.containsPointer))
    }
    private var holdReasons: [String] {
        var reasons: [String] = []
        if draggingToPocket { reasons.append("drag") }
        if mouseInBar { reasons.append("menu-bar-pointer") }
        if isSettingsVisible() { reasons.append("settings") }
        if overflowButton.containsPointer { reasons.append("pocket-button-pointer") }
        if pocket?.containsPointer == true { reasons.append("pocket-pointer") }
        if pocket?.isBusy == true { reasons.append("pocket-work") }
        if nativeMenuOpen { reasons.append("native-menu") }
        if transition.isTransitioning { reasons.append("transition") }
        return reasons
    }
    private func checkAutoHide() {
        guard canManage, prefs.autoCollapse, transition.expanded || pocket?.isVisible == true else { autoHide.reset(); return }
        let held = !holdReasons.isEmpty
        guard autoHide.shouldHide(now: ProcessInfo.processInfo.systemUptime, held: held, delay: prefs.collapseDelay) else { return }
        if transition.expanded { collapse() }
        else { pocket?.close(); autoHide.reset() }
    }
    // An on-screen popup at menu level means a user is still operating a menu,
    // even when the pointer has left the menu-bar strip. No cross-process AX wait.
    var nativeMenuOpen: Bool {
        NativeMenuTrackingPolicy.isTracking(WindowServerSnapshot.shared.current(),ownPID:getpid(),pocketWindow:pocket?.windowNumber)
    }

    private var mouseInBar: Bool {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            p.x >= screen.frame.minX && p.x <= screen.frame.maxX && p.y >= screen.frame.maxY - max(24, screen.safeAreaInsets.top) - 3
        }
    }
    func tick() {
        refreshToggleClickGeometry()
        checkAutoHide()
        pocket?.tick()
        refreshOverflow()
        warmPocketIfIdle()
        guard !MenuBarBackdrop.shared.presentationSuppressed else { cancelHover(); return }
        if !NSMenu.menuBarVisible(), cover.isVisible { transition.cancelAndExpand(); updatePresentation() }
        if !transition.expanded { cover.updateClosedFrame(animationFrame) }
        guard canManage, prefs.trigger(for: .right) == .hover, engine.state == .collapsed else { cancelHover(); return }
        guard let frame = effectiveToggleFrame,
              frame.insetBy(dx: -3, dy: -3).contains(NSEvent.mouseLocation) else { cancelHover(); return }
        guard pocket?.isVisible != true, pocket?.isBusy != true, hoverTimer == nil, Date().timeIntervalSince(lastCollapse) > 0.5 else { return }
        let timer = Timer(timeInterval: 0.08, repeats: false) { [weak self] _ in
            guard let self else { return }; self.hoverTimer = nil
            guard self.canManage, self.prefs.trigger(for: .right) == .hover, self.engine.state == .collapsed,
                  let frame = self.effectiveToggleFrame,
                  frame.insetBy(dx: -3, dy: -3).contains(NSEvent.mouseLocation) else { return }
            self.expand()
        }
        hoverTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func setPocketAppearance(_ appearance: NSAppearance?) { pocket?.setAppearance(appearance) }
    func testPocketCacheFailure() { pocket?.testCacheFailure() }
    func testPocketReturnFixture(pinned:Bool = true) { pocket?.testReturnFixture(pinned:pinned) }
    func testCompatibilityClickFixture() { compatibility.testClickFixture() }
    func testCompatibilityRefreshFixture() {
        guard CommandLine.arguments.contains("--test-controls") else { return }
        refreshCompatibilityItems(compatibility.sources.filter { $0.bundle == "org.drapletqa.native" })
    }
    func setCompatibilityCaptureSuspended(_ suspended:Bool) {
        compatibility.captureSuspended = suspended;updatePresentation()
    }
    func installCompatibilityItem(_ item:PocketItem,image:NSImage) -> Bool {
        let installed = compatibility.install(item,image:image,placing:true)
        updatePresentation();return installed
    }
    func finishCompatibilityItem(_ item:PocketItem,success:Bool) {
        if success { compatibility.finishPlacement(item.imageIdentity);prefs.setCompatibilityItem(item.imageIdentity,section:.hidden) }
        else { compatibility.remove(item.imageIdentity) }
        inventoryDidChange()
    }
    @MainActor func compatibilityFrame(_ item:PocketItem,on display:CGRect) async -> CGRect? {
        await compatibilityPlacement(item,on:display)?.source
    }
    @MainActor func compatibilityPlacement(_ item:PocketItem,on display:CGRect) async -> (source:CGRect,arrow:CGRect)? {
        let bindings = compatibility.bindings
        guard bindings[item.id] != nil else { return nil }
        let result: (frames:[String: CGRect],host:PocketInventory.HostSnapshot?) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos:.userInitiated).async {
                let host = PocketInventory.hostSnapshot(on:display)
                let frames = CompatibilityMenuPolicy.frames(bindings:bindings,host:host,owner:getpid())
                continuation.resume(returning:(frames,host))
            }
        }
        compatibilityHost = ["slots":result.host?.items.filter { $0.owner == getpid() }.map { ["frame":NSStringFromRect($0.frame),"identifier":$0.identifier ?? ""] } ?? [],
                             "matches":result.frames.mapValues(NSStringFromRect)]
        compatibility.observe(result.frames)
        observeArrow(in:result.host,on:display)
        guard let source = result.frames[item.id],
              let arrow = CompatibilityMenuPolicy.frames(bindings:["toggle":"Draplet.Toggle"],host:result.host,owner:getpid())["toggle"] else { return nil }
        return (source,arrow)
    }
    struct ToggleAnchor {
        let neighbor:PocketInventory.HostedItem
        let before:Bool
    }
    @MainActor private func placementHost(on display:CGRect) async -> PocketInventory.HostSnapshot? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos:.userInitiated).async { continuation.resume(returning:PocketInventory.hostSnapshot(on:display)) }
        }
    }
    @MainActor func captureToggleAnchor(on display:CGRect,excluding source:PocketItem) async -> ToggleAnchor? {
        guard let host = await placementHost(on:display),
              let arrow = CompatibilityMenuPolicy.frames(bindings:["toggle":"Draplet.Toggle"],host:host,owner:getpid())["toggle"] else { return nil }
        let others = host.renderedItems.filter {
            !($0.owner == getpid() && $0.identifier == "Draplet.Toggle")
                && !($0.owner == source.pid && (CFEqual($0.element,source.element) || $0.name == source.name))
        }
        if let next = others.first(where:{ abs($0.frame.minX-arrow.maxX) <= 4 }) { return ToggleAnchor(neighbor:next,before:true) }
        if let prior = others.first(where:{ abs($0.frame.maxX-arrow.minX) <= 4 }) { return ToggleAnchor(neighbor:prior,before:false) }
        return nil
    }
    private func anchorNeighbor(_ anchor:ToggleAnchor,in host:PocketInventory.HostSnapshot,dragging:Bool = false) -> CGRect? {
        let matches = host.items.filter { $0.owner == anchor.neighbor.owner }
        let exact = matches.filter { CFEqual($0.element,anchor.neighbor.element) }
        let identified = matches.filter { $0.identifier != nil && $0.identifier == anchor.neighbor.identifier }
        let named = matches.filter { $0.name == anchor.neighbor.name && $0.name != nil }
        guard let chosen = exact.count == 1 ? exact.first : (identified.count == 1 ? identified.first : (matches.count == 1 ? matches.first : (named.count == 1 ? named.first : nil))) else { return nil }
        if !dragging {
            guard host.overflow.map({ chosen.frame.intersection($0).width <= 4 }) ?? true,
                  !host.items.contains(where:{ peer in
                      !CFEqual(peer.element,chosen.element) && peer.frame.intersection(chosen.frame).width > 4
                          && peer.frame.intersection(chosen.frame).height > 1
                  }) else { return nil }
        }
        return chosen.frame
    }
    @MainActor func restoreToggleAnchor(_ anchor:ToggleAnchor,on display:CGRect,valid:@escaping ()->Bool) async -> Bool {
        var previous:(CGRect,CGRect)?,stable = 0,moves = 0
        for _ in 0..<24 {
            guard valid() else { return false }
            if let host = await placementHost(on:display),valid(),
               let arrow = CompatibilityMenuPolicy.frames(bindings:["toggle":"Draplet.Toggle"],host:host,owner:getpid())["toggle"],
               let neighbor = anchorNeighbor(anchor,in:host) {
                stable = previous?.0 == arrow && previous?.1 == neighbor ? stable+1 : 0;previous = (arrow,neighbor)
                if stable >= 2 {
                    if abs(anchor.before ? arrow.maxX-neighbor.minX : arrow.minX-neighbor.maxX) <= 4 { return true }
                    guard moves < 2 else { return false };moves += 1
                    let point = CGPoint(x:neighbor.midX + (anchor.before ? -neighbor.width/4 : neighbor.width/4),y:neighbor.midY)
                    let moved = await PocketItemEvents.move(frame:arrow,to:point,retarget:{ [weak self] in
                        guard let self,valid(),let host = await self.placementHost(on:display),valid(),
                              let current = self.anchorNeighbor(anchor,in:host,dragging:true) else { return nil }
                        return CGPoint(x:current.midX + (anchor.before ? -current.width/4 : current.width/4),y:current.midY)
                    })
                    guard moved,valid() else { return false };previous = nil;stable = 0
                }
            } else { previous = nil;stable = 0 }
            try? await Task.sleep(for:.milliseconds(60))
        }
        return false
    }
    @MainActor func hostedToggleFrame(on display:CGRect,duringPlacement:Bool = false) async -> CGRect? {
        var previous:CGRect?,stable = 0
        for _ in 0..<8 {
            let host:PocketInventory.HostSnapshot? = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos:.userInitiated).async {
                    continuation.resume(returning:PocketInventory.hostSnapshot(on:display))
                }
            }
            guard !Task.isCancelled,!SystemPresentation.current() else { return nil }
            let candidate:CGRect?
            if duringPlacement && PocketItemEvents.isPlacing {
                // The dragged glyph temporarily overlaps the disclosure. Its
                // unique owned marker remains the target; that overlap must
                // not be mistaken for an unrelated parked status rectangle.
                let matches = host?.items.filter { $0.owner == getpid() && $0.identifier == "Draplet.Toggle"
                    && display.contains($0.frame) && $0.frame.height < 80 } ?? []
                candidate = matches.count == 1 ? matches.first?.frame : nil
            } else {
                _ = observeArrow(in:host,on:display)
                // Placement consumes CoreGraphics coordinates on every path.
                candidate = CompatibilityMenuPolicy.frames(bindings:["toggle":"Draplet.Toggle"],host:host,owner:getpid())["toggle"]
            }
            if let frame = candidate {
                stable = frame == previous ? stable+1 : 0;previous = frame
                if stable >= 2 { return frame }
            } else { stable = 0;previous = nil }
            try? await Task.sleep(for:.milliseconds(60))
        }
        return nil
    }
    @discardableResult private func observeArrow(in host:PocketInventory.HostSnapshot?,on display:CGRect) -> CGRect? {
        guard let frame = CompatibilityMenuPolicy.frames(bindings:["toggle":"Draplet.Toggle"],host:host,owner:getpid())["toggle"],
              let screen = NSScreen.screens.first(where:{
                  let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
                  return CGDisplayBounds(id) == display
              }) else { return nil }
        let result = CGRect(x:frame.minX,y:screen.frame.maxY-(frame.maxY-display.minY),width:frame.width,height:frame.height)
        observedArrow = (result,Date(),toggleItem.button?.window?.frame)
        compatibility.observe(CompatibilityMenuPolicy.frames(bindings:compatibility.bindings,host:host,owner:getpid()))
        let owned = CompatibilityMenuPolicy.frames(bindings:compatibility.visibleBindings,host:host,owner:getpid())
        let ownedMarkers = Set(compatibility.visibleBindings.filter { owned[$0.key] != nil }.values)
        let native = host?.renderedItems.filter { $0.owner != getpid() } ?? []
        let mirrors = host?.items.filter { $0.owner == getpid() && ownedMarkers.contains($0.identifier ?? "") } ?? []
        clickRouter?.nativeTargets = (native + mirrors).map(StatusItemClickRouter.Target.init)
        clickRouter?.managedOwners = Set(nativeOwnerPIDs.values)
        return result
    }
    private func updateClickRouter() {
        guard canManage,engine is NativeVisibilityEngine else {
            routingGeneration += 1;clickRouter?.stop();clickRouter = nil;return
        }
        if clickRouter == nil {
            let router = StatusItemClickRouter()
            router.onClick = { [weak self] target,button,flags in
                guard let self,self.canManage,!self.presentationSuppressed,!SystemPresentation.current() else { return }
                let secondary = button == .right || flags.contains(.maskControl)
                if target.isToggle { self.performToggleClick(rightMouse:secondary,option:flags.contains(.maskAlternate)) }
                else if target.owner == getpid(),let identifier = target.identifier,
                        let source = self.compatibility.sources.first(where:{ self.compatibility.bindings[$0.id] == identifier }) {
                    self.compatibility.onActivate?(source,secondary ? .right : .left)
                } else { self.activateHostedTarget(target,button:secondary ? .right : .left) }
            }
            router.onCommandChange = { [weak self] in
                self?.observedArrow = nil;self?.routingGeneration += 1;self?.routingScanAt = .distantPast
                self?.compatibility.observe([:])
            }
            clickRouter = router
        }
        refreshToggleClickGeometry()
    }
    private func refreshToggleClickGeometry() {
        guard let router = clickRouter else { return }
        guard canManage,!presentationSuppressed,!MenuBarBackdrop.shared.presentationSuppressed,
              !SystemPresentation.current(),NSMenu.menuBarVisible(),!NSEvent.modifierFlags.contains(.command),
              let backing = toggleItem.button?.window?.frame,
              let screen = NSScreen.screens.first(where:{ $0.frame.intersects(backing) }) else { router.frame = nil;router.nativeTargets = [];return }
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
        let display = CGDisplayBounds(id)
        if let observedArrow,observedArrow.backing == backing {
            let frame = observedArrow.frame
            router.frame = CGRect(x:frame.minX,y:display.minY+screen.frame.maxY-frame.maxY,width:frame.width,height:frame.height)
        } else { router.frame = nil;router.nativeTargets = [] }
        let age = observedArrow.map { Date().timeIntervalSince($0.at) } ?? .infinity
        let windows = WindowServerSnapshot.shared.current()
        let obstructed = windows.contains { $0.visible && (26...29).contains($0.layer) && $0.pid != getpid()
            && $0.frame.intersects(CGRect(x:display.minX,y:display.minY,width:display.width,height:50))
            && $0.frame.height <= 80 && $0.frame.width <= 600 }
        guard !routingScanInFlight,Date().timeIntervalSince(routingScanAt) > 0.15,
              router.frame == nil || age > (mouseInBar && obstructed ? 0.25 : 5) else { return }
        routingScanInFlight = true;routingScanAt = Date()
        let token = routingGeneration
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let host = PocketInventory.hostSnapshot(on:display)
            DispatchQueue.main.async {
                guard let self else { return };self.routingScanInFlight = false
                guard self.clickRouter === router,token == self.routingGeneration,self.canManage,
                      self.toggleItem.button?.window?.frame == backing,!self.presentationSuppressed,!SystemPresentation.current() else { return }
                if self.observeArrow(in:host,on:display) == nil { router.frame = nil;router.nativeTargets = [] }
                else { self.refreshToggleClickGeometry() }
            }
        }
    }
    private func activateHostedTarget(_ target:StatusItemClickRouter.Target,button:CGMouseButton) {
        guard let element = target.element,
              let screen = NSScreen.screens.first(where:{
                  let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
                  return CGDisplayBounds(id).contains(target.frame)
              }) else { return }
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
        let display = CGDisplayBounds(displayID),token = routingGeneration
        Task { @MainActor [weak self] in
            // Revalidate the SAME publisher/element/rectangle. A fresh hit test
            // must never retarget the user's release to a neighbour that moved.
            let valid:Bool = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos:.userInitiated).async {
                    let matches = PocketInventory.hostSnapshot(on:display)?.renderedItems.filter {
                        $0.owner == target.owner && CFEqual($0.element,element) && $0.frame == target.frame
                    } ?? []
                    continuation.resume(returning:matches.count == 1)
                }
            }
            guard let self,valid,token == self.routingGeneration,self.canManage,
                  !self.presentationSuppressed,!MenuBarBackdrop.shared.presentationSuppressed,!SystemPresentation.current() else { return }
            // AX targets the publisher's actual hosted button, bypassing the
            // foreign WindowServer hit surface. Never fall back to an unscoped
            // coordinate click: that would simply open the obstructing app.
            await withCheckedContinuation { (continuation:CheckedContinuation<Void,Never>) in
                DispatchQueue.global(qos:.userInitiated).async {
                    AXUIElementSetMessagingTimeout(element,0.5)
                    let result = AXUIElementPerformAction(element,(button == .right ? kAXShowMenuAction : kAXPressAction) as CFString)
                    // Standard NSStatusItem menus expose AXPress for both mouse
                    // buttons. Prefer an app's distinct menu action when offered.
                    if button == .right && result == .actionUnsupported {
                        _ = AXUIElementPerformAction(element,kAXPressAction as CFString)
                    }
                    continuation.resume()
                }
            }
        }
    }
    private func prepareCompatibilitySlots(token:Int,completion:@escaping ()->Void) {
        let bindings = compatibility.visibleBindings
        guard !bindings.isEmpty,let arrow = effectiveToggleFrame,
              let screen = NSScreen.screens.first(where:{ $0.frame.intersects(arrow) }) else { completion();return }
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
        let display = CGDisplayBounds(id)
        Task { @MainActor [weak self] in
            let deadline = ProcessInfo.processInfo.systemUptime+1.5
            var previous:[String:CGRect] = [:],stable = 0
            while let self, token == self.pocketGeneration, self.canManage, !SystemPresentation.current(), ProcessInfo.processInfo.systemUptime < deadline {
                let host: PocketInventory.HostSnapshot? = await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos:.userInitiated).async { continuation.resume(returning:PocketInventory.hostSnapshot(on:display)) }
                }
                let frames = CompatibilityMenuPolicy.frames(bindings:bindings,host:host,owner:getpid())
                guard token == self.pocketGeneration else { break }
                if frames.count == bindings.count {
                    stable = frames == previous ? stable+1 : 0;previous = frames
                    self.compatibility.observe(frames);self.observeArrow(in:host,on:display)
                    if stable >= 2 { break }
                } else { stable = 0;previous = [:] }
                try? await Task.sleep(for:.milliseconds(60))
            }
            completion()
        }
    }
    private func warmPocketIfIdle() {
        guard Date().timeIntervalSince(lastWarmCheck) >= 1 else { return }
        lastWarmCheck = Date()
        guard canManage,prefs.rightRevealMode == .pocket,MenuBarBackdrop.shared.ready,
              !MenuBarBackdrop.shared.presentationSuppressed,!SystemPresentation.current(),
              !transition.expanded,!transition.isTransitioning,!scanInFlight,!mouseInBar,!draggingToPocket,
              NSEvent.pressedMouseButtons == 0,!nativeMenuOpen,
              !overflowItems.isEmpty,let screen = overflowScreen else { return }
        if pocket == nil {
            pocket = MenuBarPocket(owner:self)
            pocket?.onChange = { [weak self] in self?.overflowButton.setExpanded(self?.pocket?.isVisible == true) }
        }
        pocket?.warm(items:overflowItems,screen:screen)
    }
    func activatePocketItem(_ name: String, button: CGMouseButton) { pocket?.activateNamed(name, button: button) }
    func togglePocket() {
        if pocket?.isVisible == true { pocket?.close() }
        else { showPocket() }
    }
    func showPocket(all: Bool = false, refresh: Bool = false) {
        guard canManage, transition.expanded, !transition.isTransitioning, !SystemPresentation.current(),
              let anchor = overflowButton.button, overflowButton.isVisible,
              let screen = overflowScreen, !overflowItems.isEmpty else { return }
        if pocket == nil {
            pocket = MenuBarPocket(owner:self)
            pocket?.onChange = { [weak self] in self?.overflowButton.setExpanded(self?.pocket?.isVisible == true) }
        }
        autoHide.reset()
        pocket?.open(items:overflowItems,anchor:anchor,screen:screen,refresh:refresh)
    }
    private func prepareOverflow(deadline: TimeInterval, token: Int, completion: @escaping () -> Void) {
        guard token == pocketGeneration, ProcessInfo.processInfo.systemUptime < deadline else { completion(); return }
        if scanInFlight {
            DispatchQueue.main.asyncAfter(deadline:.now()+0.05) { [weak self] in
                guard let self else { completion(); return }
                self.prepareOverflow(deadline:deadline,token:token,completion:completion)
            }
        } else { refreshOverflow(preparing:true,completion:completion) }
    }
    private func refreshOverflow(preparing: Bool = false, completion: @escaping () -> Void = {}) {
        guard canManage, prefs.rightRevealMode == .pocket, transition.expanded || !prefs.pinnedPocketBundles.isEmpty || !prefs.compatibilityMenuItems.isEmpty,
              !MenuBarBackdrop.shared.presentationSuppressed, !SystemPresentation.current() else {
            if pocket?.isBusy != true { overflowButton.hide() }
            completion(); return
        }
        guard pocket?.isBusy != true, pocket?.isVisible != true, !scanInFlight,
              (!transition.isTransitioning || preparing),
              (preparing || Date().timeIntervalSince(lastScan) >= (transition.expanded ? 1 : 5)),
              let arrow = effectiveToggleFrame,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(arrow) }) else { completion(); return }
        scanInFlight = true; lastScan = Date()
        let token = pocketGeneration
        var finished = false
        let finish = { [weak self] in
            guard !finished else { return }
            finished = true; self?.scanInFlight = false; completion()
        }
        // A superseded native layout request may omit its caller's callback.
        // Release this scan once; a late result must never publish afterward.
        DispatchQueue.main.asyncAfter(deadline:.now()+2.5,execute:finish)
        let revealed = transition.expanded
        let pins = prefs.pinnedPocketBundles
        let oldOwners = nativeOwners, oldPIDs = nativeOwnerPIDs
        let excluded = revealAllMode ? Set<String>() : Set((engine as? NativeVisibilityEngine)?.layout?.bundles(in: [.alwaysHidden]) ?? [])
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
        let display = CGDisplayBounds(displayID)
        let start = screen.auxiliaryTopRightArea?.minX ?? screen.frame.midX
        let band = CGRect(x:start,y:display.minY,width:screen.frame.maxX-start,height:80)
        PocketInventory.read { [weak self] inventory in
            DispatchQueue.global(qos:.userInitiated).async {
                var owners: [String:[String]] = [:], pids: [String:pid_t] = [:]
                for item in inventory where owners[item.bundle] == nil {
                    owners[item.bundle] = oldPIDs[item.bundle] == item.pid ? oldOwners[item.bundle] : PocketInventory.nativeIdentifiers(for:item.bundle)
                    pids[item.bundle] = item.pid
                }
                DispatchQueue.main.async {
                    guard let self, !finished, token == self.pocketGeneration,
                          self.canManage, self.transition.expanded == revealed,
                          self.pocket?.isBusy != true, self.pocket?.isVisible != true,
                          !SystemPresentation.current() else { finish(); return }
                    self.nativeOwners = owners; self.nativeOwnerPIDs = pids
                    self.compatibility.synchronize(inventory,saved:self.prefs.compatibilityMenuItems)
                    self.updatePresentation()
                    let compatibilityBindings = self.compatibility.bindings
                    self.inventoryKey = inventory.map { "\($0.id):\($0.frame.width)" }.sorted().joined(separator:"|")
                    if !revealed {
                        let known = Set(self.overflowItems.map(\.id))
                        self.overflowItems = inventory.filter { pins.contains($0.bundle) || known.contains($0.id) }
                        self.overflowScreen = screen
                    }
                    // Applying new owner aliases/pins can move every icon. The
                    // host read must follow that activation, not precede it.
                    self.updatePinPolicy {
                        guard !finished, token == self.pocketGeneration else { finish(); return }
                        if !revealed {
                            guard self.compatibility.hasItems else { finish();return }
                            // Refresh the hosted arrow during the existing idle
                            // scan; a status item's backing window can stay at
                            // an obsolete position after its copied slot moves.
                            DispatchQueue.global(qos:.utility).async {
                                let host = PocketInventory.hostSnapshot(on:display)
                                DispatchQueue.main.async {
                                    defer { finish() }
                                    guard !finished, token == self.pocketGeneration, self.canManage,
                                          !self.transition.expanded, !SystemPresentation.current() else { return }
                                    self.observeArrow(in:host,on:display)
                                    self.cover.updateClosedFrame(self.animationFrame)
                                }
                            }
                            return
                        }
                        let pinnedOwners = Set(inventory.filter { pins.contains($0.bundle) }.map(\.pid))
                        PocketInventory.readSettledHost(on:display,awaitingAbsenceOf:pinnedOwners) { host in
                            let candidates = inventory.filter { !excluded.contains($0.bundle) }
                            let rendered = host.map { PocketInventory.HostSnapshot(items:$0.renderedItems,overflow:$0.overflow) }
                            let matches = candidates.compactMap { item in rendered.flatMap { PocketInventory.matchFrame(item,among:candidates,host:$0) }.map { (item.id,$0) } }
                            let compatibilityFrames = CompatibilityMenuPolicy.frames(bindings:compatibilityBindings,host:host,owner:getpid())
                            let originalFrames = Dictionary(uniqueKeysWithValues:matches)
                            let recovered = candidates.filter { compatibilityBindings[$0.id] != nil && originalFrames[$0.id].map { PocketGeometry.isUsable($0,on:display,rightArea:band) } == true }
                            let drawn = originalFrames.merging(compatibilityFrames,uniquingKeysWith:{ original,_ in original })
                            let unresolvedOwners = Set(candidates.filter { candidate in
                                let count = host?.renderedItems.filter { $0.owner == candidate.pid }.count ?? 0
                                let matched = candidates.filter { $0.pid == candidate.pid && drawn[$0.id] != nil }.count
                                return count > matched
                            }.map(\.pid))
                            let required = candidates.reduce(CGFloat(0)) { $0 + $1.frame.width + 8 }
                            let missingIDs = PocketOverflowMembership.resolve(candidates.map { ($0.id,$0.frame.width) },drawn:drawn,display:display,area:band,capacity:max(0,arrow.minX-start),nativeOverflow:host?.overflow != nil,revealed:revealed,hostAvailable:host != nil)
                            let automatic = candidates.filter { missingIDs.contains($0.id) && !pins.contains($0.bundle) }
                            let pinned = pins.flatMap { bundle in inventory.filter { $0.bundle == bundle } }
                            let missing = pinned + automatic
                            var buttonFrame = host?.overflow
                            if !missing.isEmpty, buttonFrame == nil {
                                let system = AXUIElementCreateSystemWide()
                                for offset in stride(from:4,through:72,by:4) {
                                    var element:AXUIElement?
                                    if AXUIElementCopyElementAtPosition(system,Float(start + CGFloat(offset)),Float(display.minY+16),&element) == .success,
                                       let element, (PocketInventory.attribute(element,kAXRoleAttribute) as? String) == kAXButtonRole {
                                        var pid:pid_t = 0; AXUIElementGetPid(element,&pid)
                                        if NSRunningApplication(processIdentifier:pid)?.bundleIdentifier == "com.apple.MenuBarAgent" { buttonFrame = PocketInventory.frame(element); break }
                                    }
                                }
                            }
                            let slots = (host?.renderedItems.map(\.frame) ?? Array(drawn.values))
                                + [CGRect(x:arrow.minX,y:display.minY,width:arrow.width,height:arrow.height)]
                            let visibleSlots = slots.filter { slot in
                                PocketGeometry.isUsable(slot,on:display,rightArea:band)
                                    && (buttonFrame.map { !slot.intersects($0) } ?? true)
                            }
                            DispatchQueue.main.async {
                                defer { finish() }
                                guard !finished, token == self.pocketGeneration, self.canManage, self.prefs.rightRevealMode == .pocket,
                                      self.transition.expanded == revealed, (!self.transition.isTransitioning || preparing),
                                      self.pocket?.isBusy != true, self.pocket?.isVisible != true, !SystemPresentation.current() else { return }
                                self.overflowDiagnostics = ["host":host?.renderedItems.count ?? -1,"rawHost":host?.items.count ?? -1,"matched":drawn.count,"candidates":candidates.count,"required":required,"capacity":max(0,arrow.minX-start),"nativeOverflow":buttonFrame?.minX ?? -1,"firstVisibleX":visibleSlots.map(\.minX).min() ?? -1,"hostNames":host?.renderedItems.compactMap(\.name) ?? [],"ambiguous":missing.filter { unresolvedOwners.contains($0.pid) }.map(\.name)]
                                self.updatePresentation()
                                if !recovered.isEmpty, !self.revealAllMode, (self.engine as? NativeVisibilityEngine)?.hasVisibilityRestriction == true {
                                    for item in recovered {
                                        self.compatibility.remove(item.imageIdentity)
                                        self.prefs.setCompatibilityItem(item.imageIdentity,section:nil)
                                    }
                                    self.inventoryDidChange();return
                                }
                                self.compatibility.observe(compatibilityFrames)
                                self.observeArrow(in:host,on:display)
                                let readableHost = host?.renderedItems.isEmpty == false
                                    && (!drawn.isEmpty || candidates.allSatisfy { pins.contains($0.bundle) })
                                guard buttonFrame != nil || readableHost else { self.overflowButton.hide(); return }
                                guard !pinned.isEmpty || (host != nil && !automatic.contains(where:{ unresolvedOwners.contains($0.pid) }) && (!drawn.isEmpty || candidates.isEmpty)) else { return }
                                if missing.isEmpty {
                                    if let first = visibleSlots.map(\.minX).min() {
                                        let extent = max(0,arrow.minX-first)
                                        self.cover.setRevealExtent(extent)
                                        self.preparedLayout = (self.revealLayoutKey,nil,extent)
                                    }
                                    self.overflowItems = []; self.overflowButton.hide(); self.overflowIdentity = ""; return
                                }
                                self.overflowItems = missing
                                self.overflowScreen = screen
                                let height = max(NSStatusBar.system.thickness,screen.safeAreaInsets.top)
                                // Empty leading space is trustworthy only with a complete
                                // physical host snapshot; missing AX data is not a vacancy.
                                guard host != nil || buttonFrame != nil,
                                    let frame = PocketGeometry.overflowButtonFrame(expanded:revealed,native:buttonFrame,
                                    slots:visibleSlots,area:band,height:height) else { self.overflowButton.hide(); return }
                                let appKit = CGRect(x:frame.minX,y:screen.frame.maxY-height,width:frame.width,height:height)
                                self.cover.setRevealExtent(max(0,arrow.minX-frame.minX))
                                self.preparedLayout = (self.revealLayoutKey,appKit,max(0,arrow.minX-frame.minX))
                                self.overflowButton.show(at:appKit,beneath:self.cover.maskingWindow)
                                self.overflowIdentity = missing.map(\.id).joined(separator:",")
                            }
                        }
                    }
                }
            }
        }
    }
    private func updateDragController() {
        guard pinningActive else {
            cancelDropTarget(); dragController?.stop(); dragController = nil; return
        }
        guard dragController == nil else { return }
        let controller = PocketDragController()
        guard controller.available else { controller.stop(); return }
        controller.targetFrame = { [weak self] in self?.pocket?.dropFrame }
        controller.ownedSources = { [weak self] in self?.compatibility.sources ?? [] }
        controller.onStart = { [weak self] item,origin in self?.showDropTarget(item,origin:origin) }
        controller.onMove = { [weak self] point in self?.pocket?.updateDropPoint(point) }
        controller.onCancel = { [weak self] in self?.cancelDropTarget() }
        controller.onDrop = { [weak self] item in
            guard let self else { return }
            self.cancelDropTarget()
            if self.pinningActive { self.setPocketPin(item.bundle,pinned:true) }
        }
        dragController = controller
    }
    func showDropTarget(_ item:PocketItem,origin:CGPoint? = nil) {
        let source = origin ?? CGPoint(x:item.frame.midX,y:item.frame.midY)
        let cocoaSource = CGPoint(x:source.x,y:(NSScreen.screens.first?.frame.maxY ?? 0)-source.y)
        guard pinningActive, !SystemPresentation.current(),
              let screen = NSScreen.screens.first(where:{ $0.frame.contains(cocoaSource) }) else { dragController?.cancel(); return }
        draggingToPocket = true; autoHide.reset()
        if pocket == nil {
            pocket = MenuBarPocket(owner:self)
            pocket?.onChange = { [weak self] in self?.overflowButton.setExpanded(self?.pocket?.isVisible == true) }
        }
        let height = max(NSStatusBar.system.thickness,screen.safeAreaInsets.top)
        guard let frame = PocketGeometry.dropAnchor(source:cocoaSource,screen:screen.frame,menuBarHeight:height) else { cancelDropTarget();return }
        let panel = NSPanel(contentRect:frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue:25); panel.collectionBehavior = [.transient,.ignoresCycle]
        panel.ignoresMouseEvents = true; panel.isReleasedWhenClosed = false
        let anchor = NSView(frame:CGRect(x:0,y:0,width:1,height:1))
        panel.contentView = anchor; dragAnchor?.close(); dragAnchor = panel
        panel.orderFrontRegardless()
        pocket?.openDropTarget(for:item,anchor:anchor)
    }
    func cancelDropTarget() {
        guard draggingToPocket || dragAnchor != nil else { return }
        draggingToPocket = false; pocket?.close(); dragAnchor?.close(); dragAnchor = nil; autoHide.reset()
    }
    func focusDropPreview() { pocket?.focusPreview() }
    private func cancelHover() { hoverTimer?.invalidate(); hoverTimer = nil }
    private func updateHoverMonitor() {
        if canManage && prefs.trigger(for: .right) == .hover {
            if mouseMonitor == nil { mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in self?.tick() } }
            if localMouseMonitor == nil { localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in self?.tick(); return event } }
        } else {
            cancelHover()
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor); self.mouseMonitor = nil }
            if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor); self.localMouseMonitor = nil }
        }
    }
    func stop() {
        PocketItemEvents.cancelPlacement()
        guard !stopped else { return }; stopped = true
        routingGeneration += 1;clickRouter?.stop();clickRouter = nil
        compatibility.stop()
        dragController?.stop(); dragController = nil
        draggingToPocket = false; dragAnchor?.close(); dragAnchor = nil
        (engine as? NativeVisibilityEngine)?.updatePocketPlacement(pinned:[],owners:[:])
        pocketGeneration += 1; pocket?.close(); overflowButton.stop(); pocket = nil
        cancelHover()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        autoHide.reset()
        engine.updateAlwaysHiddenSection(enabled: false, separatorHidden: false)
        transition.cancelAndExpand(); cover.stop()
        for item in [toggleItem, separatorItem, alwaysHiddenItem].compactMap({ $0 }) { NSStatusBar.system.removeStatusItem(item) }
    }
}
