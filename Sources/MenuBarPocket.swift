import AppKit
import SwiftUI
import ScreenCaptureKit
import ApplicationServices
import CryptoKit

final class PocketModel: ObservableObject {
    @Published var items: [PocketItem] = []
    @Published var images: [String: NSImage] = [:]
    @Published var unavailableIDs = Set<String>()
    @Published var loading = false
    @Published var focusedID: String?
    @Published var hovered: String?
    @Published var dragName: String?
    @Published var dragHighlighted = false
    @Published var returning = false
    @Published var draggedID: String?
    @Published var dropTargetID: String?
    @Published var dropAfter = false
    var displayedItems: [PocketItem] { items.filter { !unavailableIDs.contains($0.id) } }
    var columnWidth: CGFloat { max(34, ceil((images.values.map { $0.size.width + 12 }.max() ?? 34) / 3)) }
    var rows: [[(id: String, span: Int)]] {
        PocketLayout.rows(displayedItems.map { ($0.id, (images[$0.id]?.size.width ?? 22) + 12) }.map { ($0.0, $0.1 * 66 / columnWidth) })
    }
    var size: CGSize {
        if dragName != nil { return CGSize(width:240,height:112) }
        if rows.isEmpty { return CGSize(width:200,height:76) }
        let columns = rows.map { $0.reduce(0) { $0 + $1.span } }.max() ?? 1
        return CGSize(width: CGFloat(columns) * columnWidth + CGFloat(max(0,columns-1)) * 4 + 20,
                      height: CGFloat(min(5,max(1,rows.count))) * 34 + CGFloat(max(0,min(5,rows.count)-1)) * 4 + 20)
    }
}

final class MenuBarPocket: NSObject, NSPopoverDelegate {
    let model = PocketModel()
    private weak var owner: RightCurtain?
    private let popover = NSPopover()
    private let shield = PocketCaptureShield()
    private let returnTarget = PocketReturnDropTarget()
    private let dragImage = PocketDragImage()
    private var returnToken: String?
    private var lastReturnResult = ""
    private var lastReturnStage = ""
    private var returnAccepted = false
    private var reorderDestination: (key:String,after:Bool)?
    private var work: Task<Void,Never>?
    private var generation = 0
    private let cache = PocketImageCache.shared
    private var warming = false
    private var captureRequests = 0
    private var captureDiagnostics: [String:String] = [:]
    private var lastDismissal = ""
    private var observers: [NSObjectProtocol] = []
    private var keyMonitor: Any?
    private var originPID: pid_t?
    private var actionPID: pid_t?
    private var actionStarted: TimeInterval?
    private var initialWindows = Set<Int>()
    private var heldForQA: Bool {
        CommandLine.arguments.contains("--test-controls") && CommandLine.arguments.contains("--qa-hold-pocket")
    }
    var onChange: (() -> Void)?
    var windowNumber: Int? { popover.contentViewController?.view.window?.windowNumber }
    var isVisible: Bool { popover.isShown }
    var isBusy: Bool { work != nil || actionPID != nil || model.dragName != nil || model.returning }
    var dropFrame: CGRect? {
        guard isVisible, model.dragName != nil, let view = popover.contentViewController?.view, let window = view.window else { return nil }
        let rect = window.convertToScreen(view.convert(view.bounds,to:nil))
        let height = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x:rect.minX,y:height-rect.maxY,width:rect.width,height:rect.height)
    }
    func updateDropPoint(_ point:CGPoint) {
        let highlight = dropFrame?.contains(point) == true
        if model.dragHighlighted != highlight { model.dragHighlighted = highlight }
    }
    func focusPreview() {
        guard CommandLine.arguments.contains("--test-controls"), model.dragName != nil else { return }
        popover.contentViewController?.view.window?.makeKey()
    }
    func openDropTarget(for item:PocketItem,anchor:NSView) {
        close(); model.dragName = item.name
        model.items = []; originPID = ForegroundApplication.shared.current()?.pid
        let controller = NSHostingController(rootView:PocketView(model:model,activate:{_,_ in},place:{_ in},beginDrag:{_,_ in false},endDrag:{_,_,_ in},moveDrag:{_,_ in},drop:{_,_,_,_ in false}))
        controller.title = "Draplet Pocket"
        popover.contentViewController = controller; popover.contentSize = model.size
        popover.behavior = .applicationDefined; popover.animates = false
        popover.show(relativeTo:anchor.bounds,of:anchor,preferredEdge:.minY)
        onChange?()
    }
    var containsPointer: Bool { isVisible && popover.contentViewController?.view.window?.frame.insetBy(dx: -7,dy: -7).contains(NSEvent.mouseLocation) == true }
    var debugStatus: [String:Any] {
        ["visible":isVisible,"busy":isBusy,"items":model.items.count,"images":model.items.filter { model.images[$0.id] != nil }.count,
         "names":model.items.map(\.name),"capture":captureDiagnostics,"window":windowNumber ?? 0,"width":popover.contentSize.width,"height":popover.contentSize.height,
         "loading":model.loading,"returning":model.returning,"shield":shield.isVisible,"dismissedBy":lastDismissal,
         "lastReturn":lastReturnResult,"returnStage":lastReturnStage,"warming":warming,"captureRequests":captureRequests,"cacheDiskHits":cache.diskHits,"unavailable":Array(model.unavailableIDs),
         "glyphs":Dictionary(model.items.compactMap { item -> (String,String)? in
             guard let data = model.images[item.id]?.tiffRepresentation else { return nil }
             return (item.name,SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined())
         },uniquingKeysWith:{ first,_ in first }),
         "glyphSizes":Dictionary(model.items.compactMap { item -> (String,[CGFloat])? in
             guard let image = model.images[item.id] else { return nil }
             return (item.name,[image.size.width,image.size.height])
         },uniquingKeysWith:{ first,_ in first })]
    }
    init(owner: RightCurtain) {
        self.owner = owner
        super.init()
        popover.behavior = .transient; popover.delegate = self
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object:nil, queue:.main) { [weak self] _ in self?.close(reason:"space-change") })
        observers.append(center.addObserver(forName:NSWorkspace.didActivateApplicationNotification, object:nil, queue:.main) { [weak self] note in
            guard let self, !self.heldForQA else { return }
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            if PocketActionPolicy.shouldDismiss(for:pid,origin:self.originPID,target:self.actionPID,own:getpid()) { self.close(reason:"app-activation:\(pid ?? 0)") }
        })
        observers.append(NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in self?.close(reason:"display-change"); self?.cache.appearanceChanged() })
    }
    deinit {
        work?.cancel()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer); NotificationCenter.default.removeObserver(observer) }
    }
    func open(items: [PocketItem], anchor: NSView, screen: NSScreen, refresh: Bool = false) {
        close()
        guard !items.isEmpty, owner?.canManage == true, !SystemPresentation.current() else { return }
        originPID = ForegroundApplication.shared.current()?.pid
        adopt(items); model.focusedID = nil
        // UI-capture fixtures may keep the real native surface open while the
        // desktop is in use. Normal launches always retain transient dismissal.
        popover.behavior = heldForQA ? .applicationDefined : .transient
        if refresh { cache.requestRefresh(items.map(\.imageIdentity)) }
        let controller = NSHostingController(rootView: PocketView(model:model,activate:{ [weak self] item,button in self?.activate(item,button:button) },place:{ [weak self] item in self?.owner?.setPocketPin(item.bundle,pinned:!Preferences.shared.pinnedPocketBundles.contains(item.bundle)) },beginDrag:{ [weak self] item,token in self?.beginReturnDrag(item,token:token) ?? false },endDrag:{ [weak self] item,point,command in self?.endReturnDrag(item,at:point,command:command) },moveDrag:{ [weak self] point,command in self?.moveReturnDrag(at:point,command:command) },drop:{ [weak self] item,token,after,commit in self?.acceptReorder(at:item,token:token,after:after,commit:commit) ?? false }))
        controller.title = "Draplet Pocket"
        popover.contentViewController = controller
        let lightInk = (MenuBarBackdrop.shared.foreground.usingColorSpace(.deviceRGB)?.redComponent ?? 1) > 0.5
        popover.appearance = NSAppearance(named:lightInk ? .darkAqua : .aqua)
        popover.contentSize = model.size
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.show(relativeTo:anchor.bounds,of:anchor,preferredEdge:.minY)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            if event.keyCode == 53, self?.model.returning != true, self?.isVisible == true { self?.close(reason:"escape"); return nil }
            return event
        }
        onChange?()
        let missing = items.filter { item in
            (refresh || model.images[item.id] == nil) && cache.needsRefresh(item.imageIdentity,pid:item.pid,scale:screen.backingScaleFactor,foreground:true)
        }
        guard !missing.isEmpty else { return }
        capture(missing,screen:screen,background:false)
    }
    private func adopt(_ items:[PocketItem]) {
        model.items = ordered(items)
        model.images = Dictionary(uniqueKeysWithValues:items.compactMap { item in cache.image(item.imageIdentity).map { (item.id,$0) } })
        model.unavailableIDs = Set(items.filter { cache.unavailable($0.imageIdentity) }.map(\.id))
    }
    private func ordered(_ items:[PocketItem]) -> [PocketItem] {
        let keys = PocketItemOrder.ordered(items.map(\.imageIdentity),saved:Preferences.shared.pocketItemOrder)
        let ranks = Dictionary(uniqueKeysWithValues:keys.enumerated().map { ($0.element,$0.offset) })
        return items.sorted { ranks[$0.imageIdentity,default:Int.max] < ranks[$1.imageIdentity,default:Int.max] }
    }
    func warm(items:[PocketItem],screen:NSScreen) {
        guard !isVisible,!isBusy,!items.isEmpty,owner?.canManage == true,!SystemPresentation.current() else { return }
        let missing = items.filter { cache.needsRefresh($0.imageIdentity,pid:$0.pid,scale:screen.backingScaleFactor) }
        guard !missing.isEmpty else { return }
        adopt(items);capture(missing,screen:screen,background:true)
    }
    func refreshStatusItems(_ items:[PocketItem],screen:NSScreen) {
        guard owner?.canManage == true,!SystemPresentation.current() else { return }
        close(reason:"icon-refresh",afterCaptureRestore:{ [weak self] in
            guard let self,self.owner?.canManage == true,!SystemPresentation.current() else { return }
            self.cache.requestRefresh(items.map(\.imageIdentity))
            self.capture(items,screen:screen,background:true,allowUnrestricted:true)
        })
    }
    private func store(_ image:NSImage,for item:PocketItem,screen:NSScreen) {
        cache.succeeded(image,key:item.imageIdentity,pid:item.pid,scale:screen.backingScaleFactor)
        model.images[item.id] = image;model.unavailableIDs.remove(item.id)
    }
    private func capture(_ missing:[PocketItem],screen:NSScreen,background:Bool,allowUnrestricted:Bool = false) {
        guard Preferences.shared.backgroundPermission else { Preferences.shared.error = "Enable menu-bar capture in Settings to show overflow icons."; return }
        let token = generation
        warming = background;captureRequests += 1
        model.loading = true
        work = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if token == self.generation {
                    let restored: (@escaping () -> Void) -> Void = { done in
                        self.owner?.setCompatibilityCaptureSuspended(false)
                        if let native = self.owner?.engine as? NativeVisibilityEngine { native.finishPocketCapture { _ in self.owner?.updatePresentation();done() } }
                        else { done() }
                    }
                    self.shield.finish(restoring:restored)
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for:.milliseconds(350))
                        guard let self, token == self.generation else { return }
                        self.work = nil; self.warming = false; self.model.loading = false
                        if allowUnrestricted { self.owner?.inventoryDidChange() }
                        self.popover.contentSize = self.model.size
                        self.onChange?()
                    }
                }
            }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:false)
                guard self.valid(token) else { return }
                if background && !allowUnrestricted {
                    guard let end = self.owner?.effectiveToggleFrame?.minX else { return }
                    let start = screen.auxiliaryTopRightArea?.minX ?? screen.frame.minX
                    let height = max(NSStatusBar.system.thickness,screen.safeAreaInsets.top)
                    guard end > start else { return }
                    self.shield.showMatched(frame:CGRect(x:start,y:screen.frame.maxY-height,width:end-start,height:height)) { [weak self] in self?.close(reason:"bar-click") }
                } else {
                    guard let frozen = try await PocketCapture.strip(screen:screen,content:content) else { return }
                    let arrow = self.owner?.effectiveToggleFrame
                    self.shield.show(frozen.0,frame:frozen.1) { [weak self] in
                        let collapse = arrow?.contains(NSEvent.mouseLocation) == true
                        self?.close(reason:"bar-click",afterCaptureRestore:collapse ? { [weak self] in self?.owner?.collapse() } : nil)
                    }
                }
                try? await Task.sleep(for:.milliseconds(40))
                self.owner?.setCompatibilityCaptureSuspended(true)
                // Native AX slots can report their future position before the
                // compositor has actually exposed the pinned owner. Always
                // stage native captures; otherwise a stable rectangle can
                // still photograph an unrelated neighbour on a cold open.
                var refreshed = Set<String>()
                if !(self.owner?.engine is NativeVisibilityEngine) {
                    for item in missing {
                        guard self.valid(token) else { return }
                        if let image = try? await PocketCapture.image(item,screen:screen,content:content) {
                            self.store(image,for:item,screen:screen)
                            refreshed.insert(item.id)
                        }
                    }
                }
                var bundles: [String] = []
                for item in missing where !refreshed.contains(item.id) && !bundles.contains(item.bundle) { bundles.append(item.bundle) }
                for bundle in bundles {
                    guard self.valid(token) else { return }
                    if let native = self.owner?.engine as? NativeVisibilityEngine {
                        let identifiers = PocketInventory.nativeIdentifiers(for:bundle)
                        let reject = CommandLine.arguments.contains("--test-controls") && CommandLine.arguments.contains("--qa-reject-pocket-stage") && bundle == "org.drapletqa.native"
                        let shown = reject ? false : await withCheckedContinuation { continuation in
                            native.stagePocketCapture(identifiers,preservingVisible:background) { continuation.resume(returning:$0) }
                        }
                        self.captureDiagnostics[bundle] = shown ? "staged" : "staging-superseded-or-failed"
                        guard self.valid(token) else { return }
                        // A valid staging failure must reach the common backoff;
                        // cancellation/supersession must not poison the cache.
                        guard shown else { continue }
                        try? await Task.sleep(for:.seconds(1))
                    }
                    for item in missing where item.bundle == bundle && !refreshed.contains(item.id) {
                        guard self.valid(token) else { return }
                        var image: NSImage?
                        for _ in 0..<3 {
                            image = try? await PocketCapture.image(item,screen:screen,content:content,diagnose:{ self.captureDiagnostics[item.id] = $0 })
                            if image != nil { break }
                            try? await Task.sleep(for:.milliseconds(120))
                            guard self.valid(token) else { return }
                        }
                        guard self.valid(token) else { return }
                        if let image { self.store(image,for:item,screen:screen);refreshed.insert(item.id) }
                    }
                }
                let failed = missing.filter { !refreshed.contains($0.id) }
                if (!background || allowUnrestricted),!failed.isEmpty, self.valid(token),
                   (self.owner?.engine as? NativeVisibilityEngine)?.stageUnrestrictedPocketCapture() == true {
                    try? await Task.sleep(for:.milliseconds(500))
                    for item in failed {
                        guard self.valid(token) else { return }
                        if let image = try? await PocketCapture.image(item,screen:screen,content:content,diagnose:{ self.captureDiagnostics[item.id] = "unrestricted:\($0)" }) {
                            self.store(image,for:item,screen:screen);refreshed.insert(item.id)
                        }
                    }
                }
                for item in missing where !refreshed.contains(item.id) {
                    self.cache.failed(item.imageIdentity,pid:item.pid,background:background)
                    if self.cache.unavailable(item.imageIdentity) { self.model.unavailableIDs.insert(item.id) }
                }
            } catch {
                if self.valid(token) {
                    for item in missing {
                        self.cache.failed(item.imageIdentity,pid:item.pid,background:background)
                        if self.cache.unavailable(item.imageIdentity) { self.model.unavailableIDs.insert(item.id) }
                    }
                }
            }
        }
    }
    private func valid(_ token:Int) -> Bool { token == generation && !Task.isCancelled && (isVisible || warming) && owner?.canManage == true && !SystemPresentation.current() }
    private func beginReturnDrag(_ item: PocketItem, token: String) -> Bool {
        guard isVisible,model.images[item.id] != nil,!model.returning,owner?.canManage == true,
              model.items.contains(where:{ $0.id == item.id }),!SystemPresentation.current() else { return false }
        if model.loading { cancelCaptureWork() }
        returnToken = token; returnAccepted = false; reorderDestination = nil
        model.returning = true;model.draggedID = item.id
        popover.behavior = .applicationDefined
        guard returnTarget.show(token:token) else { clearDrag();return false }
        if let image = model.images[item.id] { dragImage.show(image,at:NSEvent.mouseLocation) }
        return true
    }
    private func cellTargets() -> [PocketClickTarget.Target] {
        func collect(_ view:NSView) -> [PocketClickTarget.Target] {
            (view as? PocketClickTarget.Target).map { [$0] } ?? view.subviews.flatMap(collect)
        }
        return popover.contentViewController.map { collect($0.view) } ?? []
    }
    private func moveReturnDrag(at point:NSPoint,command:Bool) {
        guard model.returning,let token = returnToken else { return }
        dragImage.move(to:point);returnAccepted = returnTarget.update(at:point,command:command)
        for target in cellTargets() { _ = target.updateLocalDrop(at:point,token:token,command:command,commit:false) }
    }
    private func acceptReorder(at item:PocketItem,token:String,after:Bool,commit:Bool) -> Bool {
        guard isVisible,model.returning,owner?.canManage == true,!SystemPresentation.current(),
              NSEvent.modifierFlags.contains(.command),PocketReturnDropPolicy.matches(token,expected:returnToken ?? ""),
              let source = model.draggedID,source != item.id,
              model.items.contains(where:{ $0.id == source }),model.displayedItems.contains(where:{ $0.id == item.id }) else { return false }
        if commit { reorderDestination = (item.imageIdentity,after) }
        return true
    }
    private func endReturnDrag(_ item:PocketItem,at point:NSPoint,command:Bool) {
        let active = returnToken != nil && model.returning && owner?.canManage == true && !SystemPresentation.current()
        let token = returnToken ?? ""
        let accepted = active && returnTarget.accepts(token:token,at:point,command:command)
        if active,command,!accepted {
            for target in cellTargets() { _ = target.updateLocalDrop(at:point,token:token,command:true,commit:true) }
        }
        let reorder = accepted ? nil : reorderDestination
        clearDrag()
        if accepted {
            let pinned = Preferences.shared.pinnedPocketBundles.contains(item.bundle)
            if pinned { returnPinnedItem(item) }
            else { returnAutomaticItem(item) }
        }
        else if active,command,let reorder,
                Preferences.shared.movePocketItem(item.imageIdentity,relativeTo:reorder.key,after:reorder.after,visible:model.items.map(\.imageIdentity)) {
            model.items = ordered(model.items)
        }
    }
    private func clearDrag() {
        dragImage.close();returnTarget.close();returnToken = nil;returnAccepted = false;reorderDestination = nil
        model.returning = false;model.draggedID = nil;model.dropTargetID = nil
        popover.behavior = .transient
    }
    private func returnAutomaticItem(_ item:PocketItem,preservePosition:Bool = false) {
        guard let owner,let native = owner.engine as? NativeVisibilityEngine,
              let arrow = owner.effectiveToggleFrame,
              let screen = NSScreen.screens.first(where:{ $0.frame.intersects(arrow) }) else { return }
        close(reason:"return-automatic");lastReturnResult = "moving"
        lastReturnStage = "preparing"
        let token = generation
        let display = CGDisplayBounds((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID())
        let band = CGRect(x:screen.auxiliaryTopRightArea?.minX ?? screen.frame.midX,y:display.minY,
                          width:screen.frame.maxX-(screen.auxiliaryTopRightArea?.minX ?? screen.frame.midX),height:max(NSStatusBar.system.thickness,screen.safeAreaInsets.top))
        work = Task { @MainActor [weak self] in
            guard let self else { return }
            var bridged = false
            defer {
                if bridged, Preferences.shared.compatibilityMenuItems[item.imageIdentity] == nil {
                    owner.finishCompatibilityItem(item,success:false)
                }
                if token == self.generation {
                    self.work = nil
                    if self.lastReturnResult == "moving" {
                        self.lastReturnResult = "failed"
                        Preferences.shared.error = "Couldn’t prepare the menu bar for that move. Please try again."
                    }
                }
            }
            do {
                guard let anchor = await owner.captureToggleAnchor(on:display,excluding:item),self.validReturn(token) else { return }
                if preservePosition {
                    for _ in 0..<60 {
                        guard self.validReturn(token) else { return }
                        if owner.returnPlacementReady { break }
                        try? await Task.sleep(for:.milliseconds(50))
                    }
                    guard owner.returnPlacementReady else { return }
                }
                let content = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
                guard token == self.generation,!Task.isCancelled,owner.canManage,!SystemPresentation.current(),
                      let strip = try await PocketCapture.strip(screen:screen,content:content) else { return }
                guard token == self.generation,!Task.isCancelled else { return }
                self.shield.show(strip.0,frame:strip.1) { [weak self] in self?.close(reason:"return-cancel") }
                // An automatic overflow item has no usable native slot to
                // drag. Reuse the owned-slot fallback rather than synthesizing
                // a Command drag on another publisher's menu button: some
                // native menu extras open their menu instead of moving.
                if native.hasVisibilityRestriction,let image = self.model.images[item.id],
                   owner.installCompatibilityItem(item,image:image) {
                    bridged = true;self.lastReturnStage = "compatibility-source"
                    // The new owned item can itself start under overflow in a
                    // crowded bar. Expose only our publisher while positioning
                    // it, then restore the normal layout and disclosure anchor.
                    let isolated = await withCheckedContinuation { continuation in
                        native.stagePocketCapture([]) { continuation.resume(returning:$0) }
                    }
                    guard self.validReturn(token),isolated else {
                        await self.finishAutomaticReturn(native,item:item,display:display,band:band,token:token,
                            success:false,compatibility:true,anchor:anchor);return
                    }
                    var replacement:CGRect?,previous:CGRect?,stable = 0
                    for _ in 0..<18 {
                        guard self.validReturn(token) else { return }
                        if let frame = await owner.compatibilityFrame(item,on:display),PocketGeometry.isUsable(frame,on:display,rightArea:band) {
                            stable = frame == previous ? stable+1 : 0;previous = frame
                            if stable >= 2 { replacement = frame;break }
                        } else { previous = nil;stable = 0 }
                        try? await Task.sleep(for:.milliseconds(60))
                    }
                    var moved = false
                    if let replacement,let target = await owner.hostedToggleFrame(on:display),self.validReturn(token) {
                        self.lastReturnStage = "native-placement";self.shield.passInput(true)
                        try? await Task.sleep(for:.milliseconds(40))
                        if self.validReturn(token) {
                            moved = await PocketItemEvents.move(frame:replacement,
                                to:CGPoint(x:target.midX + (Constant.isUsingLTRLanguage ? -1 : 1),y:target.midY),retarget:{
                                    guard self.validReturn(token),let current = await owner.hostedToggleFrame(on:display,duringPlacement:true),self.validReturn(token) else { return nil }
                                    return CGPoint(x:current.midX + (Constant.isUsingLTRLanguage ? -1 : 1),y:current.midY)
                                })
                        }
                    }
                    guard self.validReturn(token) else { return }
                    await self.finishAutomaticReturn(native,item:item,display:display,band:band,token:token,
                        success:moved,compatibility:true,anchor:anchor)
                    return
                }
                self.lastReturnStage = "native-source"
                let staged = await withCheckedContinuation { continuation in
                    native.stagePocketCapture(PocketInventory.nativeIdentifiers(for:item.bundle)) { continuation.resume(returning:$0) }
                }
                guard self.validReturn(token),staged else { await self.finishAutomaticReturn(native,item:item,display:display,band:band,token:token,success:false,unpinOnly:preservePosition,anchor:anchor);return }
                var previous:CGRect?,frame:CGRect?,stable = 0
                for _ in 0..<18 {
                    let candidate = await PocketCapture.liveFrame(item,on:display)
                    guard self.validReturn(token) else { return }
                    if let candidate,PocketGeometry.isUsable(candidate,on:display,rightArea:band) {
                        stable = candidate == previous ? stable+1 : 0;previous = candidate
                        if stable >= 2 { frame = candidate;break }
                    } else { stable = 0;previous = nil }
                    try? await Task.sleep(for:.milliseconds(60))
                }
                // A native allow-list can suppress an otherwise fitting extra
                // outside /Applications. Prove that distinction by observing it
                // unrestricted before installing an owned compatibility slot.
                if frame == nil, self.validReturn(token), native.stageUnrestrictedPocketCapture() {
                    self.lastReturnStage = "unrestricted-source"
                    var originalFrame:CGRect?
                    for _ in 0..<12 {
                        try? await Task.sleep(for:.milliseconds(80))
                        guard self.validReturn(token) else { return }
                        if let original = await PocketCapture.liveFrame(item,on:display),
                           PocketGeometry.isUsable(original,on:display,rightArea:band) { originalFrame = original;break }
                    }
                    if let originalFrame,!native.pocketCaptureRestoresRestriction {
                        frame = originalFrame
                    } else if originalFrame != nil,let image = self.model.images[item.id] {
                        self.lastReturnStage = "compatibility-source"
                        let isolated = await withCheckedContinuation { continuation in
                            native.stagePocketCapture([]) { continuation.resume(returning:$0) }
                        }
                        guard self.validReturn(token) else { return }
                        if isolated,owner.installCompatibilityItem(item,image:image) {
                            bridged = true
                            var previousReplacement:CGRect?,replacementStability = 0
                            for _ in 0..<18 {
                                try? await Task.sleep(for:.milliseconds(60))
                                guard self.validReturn(token) else { return }
                                if let replacement = await owner.compatibilityFrame(item,on:display),
                                   PocketGeometry.isUsable(replacement,on:display,rightArea:band) {
                                    replacementStability = replacement == previousReplacement ? replacementStability+1 : 0
                                    previousReplacement = replacement
                                    if replacementStability >= 2 { frame = replacement;break }
                                } else { previousReplacement = nil;replacementStability = 0 }
                            }
                        }
                    }
                }
                guard let frame,self.validReturn(token),let currentArrow = await owner.hostedToggleFrame(on:display),self.validReturn(token) else {
                    await self.finishAutomaticReturn(native,item:item,display:display,band:band,token:token,success:false,compatibility:bridged,unpinOnly:preservePosition && !bridged,anchor:anchor);return
                }
                // The closest hidden-side slot fits before the original accordion
                // arrow. macOS displaces the least fitting item into overflow.
                let point = CGPoint(x:currentArrow.midX-1,y:display.minY+band.height/2)
                self.lastReturnStage = "native-placement"
                self.shield.passInput(true)
                // Let WindowServer apply the panel's input region before
                // routing the native down; AppKit updates it asynchronously.
                try? await Task.sleep(for:.milliseconds(40))
                guard self.validReturn(token) else { return }
                let moved = preservePosition && !bridged ? true : await PocketItemEvents.move(frame:frame,to:point,retarget:{
                    guard self.validReturn(token),let current = await owner.hostedToggleFrame(on:display,duringPlacement:true),self.validReturn(token) else { return nil }
                    return CGPoint(x:current.midX + (Constant.isUsingLTRLanguage ? -1 : 1),y:current.midY)
                })
                guard self.validReturn(token) else { return }
                await self.finishAutomaticReturn(native,item:item,display:display,band:band,token:token,success:moved,compatibility:bridged,unpinOnly:preservePosition && !bridged,anchor:anchor)
            } catch {
                if token == self.generation { await self.finishAutomaticReturn(native,item:item,display:display,band:band,token:token,success:false,compatibility:bridged,unpinOnly:preservePosition && !bridged) }
            }
        }
    }
    private func validReturn(_ token:Int) -> Bool {
        token == generation && !Task.isCancelled && owner?.canReturnStatusItem == true && !SystemPresentation.current()
    }
    private func returnPinnedItem(_ item:PocketItem) {
        guard let owner else { return }
        owner.returnFromPocket(item.bundle)
        lastReturnResult = "moving";lastReturnStage = "unpin-layout"
        let token = generation
        // Do not occupy capture work while the ordinary unpin transition reads
        // its layout. Compatible apps keep their existing position and speed.
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if token == self.generation,self.lastReturnResult == "moving" {
                    self.lastReturnResult = "unpinned";self.lastReturnStage = "complete-unpin"
                }
            }
            for _ in 0..<60 {
                guard self.validReturn(token) else { return }
                if owner.returnPlacementReady { break }
                try? await Task.sleep(for:.milliseconds(50))
            }
            guard self.validReturn(token),owner.returnPlacementReady,
                  let arrow = owner.effectiveToggleFrame,let screen = NSScreen.screens.first(where:{ $0.frame.intersects(arrow) }) else { return }
            let display = CGDisplayBounds((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID())
            let band = screen.auxiliaryTopRightArea.map { CGRect(x:$0.minX,y:display.minY,width:$0.width,height:80) }
            if let frame = await PocketCapture.liveFrame(item,on:display),PocketGeometry.isUsable(frame,on:display,rightArea:band) { return }
            guard self.validReturn(token) else { return }
            self.returnAutomaticItem(item,preservePosition:true)
        }
    }
    @MainActor private func finishAutomaticReturn(_ native:NativeVisibilityEngine,item:PocketItem,display:CGRect,band:CGRect,token:Int,success:Bool,compatibility:Bool = false,unpinOnly:Bool = false,anchor:RightCurtain.ToggleAnchor? = nil) async {
        let restored = await withCheckedContinuation { continuation in
            native.finishPocketCapture { continuation.resume(returning:$0) }
        }
        guard validReturn(token) else { return }
        var anchored = true
        if let anchor {
            anchored = await owner?.restoreToggleAnchor(anchor,on:display,valid:{ [weak self] in self?.validReturn(token) == true }) == true
        }
        guard validReturn(token) else { return }
        if success { lastReturnStage = compatibility ? "verify-compatibility" : "verify-original" }
        var landed = false
        var previous:CGRect?,stable = 0
        if success,restored,anchored,compatibility {
            // Assessment restoration repacks native slots. A move made in the
            // isolated capture layout can consequently land on the visible
            // side in the normal bar. Verify the restored source AND arrow in
            // one host snapshot before calling the return complete.
            var previousArrow:CGRect?,corrections = 0
            for _ in 0..<24 {
                guard validReturn(token) else { return }
                if let placement = await owner?.compatibilityPlacement(item,on:display),
                   PocketGeometry.isUsable(placement.source,on:display,rightArea:band) {
                    guard validReturn(token) else { return }
                    stable = placement.source == previous && placement.arrow == previousArrow ? stable+1 : 0
                    previous = placement.source;previousArrow = placement.arrow
                    if stable >= 2 {
                        if MenuBarLayoutResolver.section(of:placement.source,separatorFrame:placement.arrow,
                              alwaysHiddenSeparatorFrame:nil,isLTR:Constant.isUsingLTRLanguage) == .hidden {
                            landed = true;break
                        }
                        guard corrections < 2 else { break };corrections += 1
                        lastReturnStage = "restored-native-placement"
                        let point = CGPoint(x:placement.arrow.midX + (Constant.isUsingLTRLanguage ? -1 : 1),y:placement.arrow.midY)
                        shield.passInput(true)
                        _ = await PocketItemEvents.move(frame:placement.source,to:point,retarget:{
                            guard self.validReturn(token),let current = await self.owner?.hostedToggleFrame(on:display,duringPlacement:true),self.validReturn(token) else { return nil }
                            return CGPoint(x:current.midX + (Constant.isUsingLTRLanguage ? -1 : 1),y:current.midY)
                        })
                        previous = nil;previousArrow = nil;stable = 0
                    }
                } else { previous = nil;previousArrow = nil;stable = 0 }
                try? await Task.sleep(for:.milliseconds(60))
            }
        } else if success,restored,anchored {
            for _ in 0..<12 {
                let frame = await PocketCapture.liveFrame(item,on:display)
                if let frame,PocketGeometry.isUsable(frame,on:display,rightArea:band) {
                    stable = frame == previous ? stable+1 : 0;previous = frame
                    if stable >= 2 { landed = true;break }
                } else { previous = nil;stable = 0 }
                guard validReturn(token) else { return }
                try? await Task.sleep(for:.milliseconds(60))
            }
        }
        guard validReturn(token) else { return }
        if let anchor {
            let preserved = await owner?.restoreToggleAnchor(anchor,on:display,valid:{ [weak self] in self?.validReturn(token) == true }) == true
            guard validReturn(token) else { return }
            landed = landed && preserved
            if landed,compatibility,let placement = await owner?.compatibilityPlacement(item,on:display) {
                landed = MenuBarLayoutResolver.section(of:placement.source,separatorFrame:placement.arrow,
                    alwaysHiddenSeparatorFrame:nil,isLTR:Constant.isUsingLTRLanguage) == .hidden
            }
        }
        guard validReturn(token) else { return }
        if compatibility { owner?.finishCompatibilityItem(item,success:landed) }
        try? await Task.sleep(for:.milliseconds(35))
        guard validReturn(token) else { return }
        shield.close();owner?.inventoryDidChange()
        lastReturnResult = landed ? "returned" : (unpinOnly ? "unpinned" : "failed")
        if landed { lastReturnStage = "complete" }
        if !landed && !unpinOnly { Preferences.shared.error = "macOS couldn’t place that icon in the menu bar. Try a different position or free some space." }
    }
    private func cancelCaptureWork(afterRestore:(() -> Void)? = nil) {
        generation += 1; work?.cancel(); work = nil
        PocketItemEvents.cancelPlacement()
        let token = generation
        warming = false; model.loading = false
        owner?.setCompatibilityCaptureSuspended(false)
        shield.finish(restoring:{ [weak self] done in
            if let native = self?.owner?.engine as? NativeVisibilityEngine { native.finishPocketCapture { _ in self?.owner?.updatePresentation();done() } }
            else { done() }
        },completion:{ [weak self] in if self?.generation == token { afterRestore?() } })
    }
    func close(reason:String = "explicit",afterCaptureRestore:(() -> Void)? = nil) {
        if lastReturnResult == "moving" { lastReturnResult = "cancelled" }
        if isVisible || isBusy { lastDismissal = reason }
        cancelCaptureWork(afterRestore:afterCaptureRestore)
        clearDrag()
        model.dragName = nil; model.dragHighlighted = false
        actionPID = nil; actionStarted = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        if popover.isShown { popover.close() }
        onChange?()
    }
    func popoverDidShow(_ notification:Notification) {
        popover.contentViewController?.view.window?.title = "Draplet Pocket"
        if model.dragName == nil {
            popover.contentViewController?.view.window?.isMovable = false
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    func popoverDidClose(_ notification:Notification) {
        // Explicit close starts the return task before AppKit delivers this
        // notification. Do not let that delayed notification cancel the move.
        if lastReturnResult == "moving" || warming { onChange?();return }
        guard actionPID == nil else { return }
        guard work != nil || keyMonitor != nil else { onChange?(); return }
        close(reason:"native-popover")
    }
    func tick() {
        guard isVisible || isBusy else { return }
        if SystemPresentation.current() || owner?.canManage != true { close(reason:"system-presentation"); return }
        if let started = actionStarted, ProcessInfo.processInfo.systemUptime - started > 3,
           owner?.nativeMenuOpen != true {
            let open = WindowServerSnapshot.shared.current().contains { $0.visible && $0.pid == actionPID && $0.layer > 0 && !initialWindows.contains($0.number) }
            if !open { actionStarted = nil; actionPID = nil }
        }
    }
    func setAppearance(_ appearance:NSAppearance?) { popover.appearance = appearance }
    func testCacheFailure() {
        guard CommandLine.arguments.contains("--test-controls") else { return }
        for item in model.items where item.bundle == "org.drapletqa.native" { cache.failed(item.imageIdentity,pid:item.pid) }
    }
    // Exercise the actual SwiftUI cell across a run-loop turn, never a user's
    // publisher. Source events are local; automatic return uses the production
    // tagged native status-item placement path on this fixture alone.
    func testReturnFixture(pinned:Bool = true) {
        guard CommandLine.arguments.contains("--test-controls"),isVisible,
              let item = model.items.filter({ $0.bundle == "org.drapletqa.native" }).last,
              Preferences.shared.pinnedPocketBundles.contains(item.bundle) == pinned,
              let target = cellTargets().first(where:{ $0.itemID == item.id }),
              let window = target.window,let screen = window.screen else { return }
        let origin = target.convert(NSPoint(x:target.bounds.midX,y:target.bounds.midY),to:nil)
        func event(_ type:NSEvent.EventType,_ point:NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with:type,location:point,modifierFlags:.command,timestamp:ProcessInfo.processInfo.systemUptime,
                              windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
        }
        target.mouseDown(with:event(.leftMouseDown,origin))
        target.mouseDragged(with:event(.leftMouseDragged,NSPoint(x:origin.x+8,y:origin.y)))
        DispatchQueue.main.asyncAfter(deadline:.now()+0.1) {
            let right = screen.auxiliaryTopRightArea ?? CGRect(x:screen.frame.midX,y:screen.frame.maxY-24,width:screen.frame.width/2,height:24)
            let point = window.convertPoint(fromScreen:NSPoint(x:right.midX,y:right.midY))
            target.mouseDragged(with:event(.leftMouseDragged,point))
            target.mouseUp(with:event(.leftMouseUp,point))
        }
    }
    func refreshBackground() { shield.refreshBackground() }
    func handoffCaptureShield(coveredBy frame:CGRect) { shield.handoff(to:frame) }
    func activateNamed(_ name:String,button:CGMouseButton) { if let item = model.items.first(where:{ $0.name == name }) { activate(item,button:button) } }
    func activateStatusItem(_ item:PocketItem,button:CGMouseButton) { activate(item,button:button) }
    private func activate(_ item:PocketItem,button:CGMouseButton) {
        guard (!model.loading || model.images[item.id] != nil), owner?.canManage == true else { return }
        close(); let token = generation
        actionPID = item.pid; actionStarted = ProcessInfo.processInfo.systemUptime
        WindowServerSnapshot.shared.invalidate()
        initialWindows = Set(WindowServerSnapshot.shared.current().filter(\.visible).map(\.number))
        work = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if token == self.generation { self.work = nil } }
            let result:AXError = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos:.userInitiated).async {
                    AXUIElementSetMessagingTimeout(item.element,5)
                    continuation.resume(returning:AXUIElementPerformAction(item.element,(button == .left ? kAXPressAction : kAXShowMenuAction) as CFString))
                }
            }
            guard token == self.generation, !Task.isCancelled else { return }
            if PocketActionPolicy.shouldUseMouse(after:result) {
                guard let screen = NSScreen.screens.first(where:{ $0.frame.contains(NSEvent.mouseLocation) }) else { self.unavailableAction(); return }
                let display = CGDisplayBounds((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID())
                guard let frame = await PocketCapture.liveFrame(item,on:display) else { self.unavailableAction(); return }
                let right = screen.auxiliaryTopRightArea.map { CGRect(x:$0.minX,y:display.minY,width:$0.width,height:80) }
                guard PocketGeometry.isUsable(frame,on:display,rightArea:right) else { self.unavailableAction(); return }
                _ = await PocketItemEvents.click(frame:frame,windowID:item.windowID,pid:item.pid,button:button)
            } else if result == .apiDisabled || result == .invalidUIElement { self.unavailableAction() }
        }
    }
    private func unavailableAction() { actionPID = nil; actionStarted = nil; Preferences.shared.error = "That action isn’t available from Pocket. Return the app to the menu bar in Right settings, or Option-click Draplet’s right arrow to reveal every section." }
}

private struct PocketView: View {
    @ObservedObject var model:PocketModel
    let activate:(PocketItem,CGMouseButton)->Void
    let place:(PocketItem)->Void
    let beginDrag:(PocketItem,String)->Bool
    let endDrag:(PocketItem,NSPoint,Bool)->Void
    let moveDrag:(NSPoint,Bool)->Void
    let drop:(PocketItem,String,Bool,Bool)->Bool
    var body:some View {
        if let name = model.dragName {
            VStack(spacing:5) {
                Image(systemName:"pin.fill").font(.system(size:19))
                Text("Keep in Pocket").font(.system(size:13,weight:.semibold))
                Text(name).font(.system(size:12)).lineLimit(1).truncationMode(.middle)
                Text("Release to pin this app’s icons").font(.system(size:11)).foregroundStyle(.secondary)
            }.padding(12).frame(width:240,height:112)
                .background(model.dragHighlighted ? Color.accentColor.opacity(0.18) : .clear)
                .accessibilityElement(children:.ignore)
                .accessibilityLabel("Keep \(name) in Pocket. Release to pin this app’s icons.")
        } else if model.rows.isEmpty && !model.loading {
            VStack(spacing:5) {
                Text("No active menu icons").font(.system(size:12,weight:.medium))
                Text("Apps appear here when their menu icons are available.")
                    .font(.system(size:11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(12).frame(width:200,height:76)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment:.leading,spacing:4) {
                        ForEach(model.rows.indices,id:\.self) { row in
                            HStack(spacing:4) {
                                ForEach(model.rows[row],id:\.id) { cell in
                                    if let item = model.items.first(where:{ $0.id == cell.id }) {
                                        PocketCell(model:model,item:item,activate:activate,place:place,beginDrag:beginDrag,endDrag:endDrag,moveDrag:moveDrag,drop:drop)
                                            .frame(width:model.columnWidth * CGFloat(cell.span) + CGFloat(cell.span-1)*4,height:34).id(item.id)
                                    }
                                }
                            }
                        }
                    }.padding(10)
                }.scrollIndicators(.hidden)
                    .onChange(of:model.focusedID) { _,id in if let id { proxy.scrollTo(id) } }
            }.frame(width:model.size.width,height:model.size.height)
                .accessibilityLabel("Pocket icons")
        }
    }
}
private struct PocketCell:View {
    @ObservedObject var model:PocketModel
    let item:PocketItem
    let activate:(PocketItem,CGMouseButton)->Void
    let place:(PocketItem)->Void
    let beginDrag:(PocketItem,String)->Bool
    let endDrag:(PocketItem,NSPoint,Bool)->Void
    let moveDrag:(NSPoint,Bool)->Void
    let drop:(PocketItem,String,Bool,Bool)->Bool
    var body:some View {
        ZStack {
            if let image = model.images[item.id] {
                Image(nsImage:image).renderingMode(image.isTemplate ? .template : .original).accessibilityHidden(true)
            } else if model.loading { ProgressView().controlSize(.mini).accessibilityHidden(true) }
            else { Image(systemName:"exclamationmark.circle").font(.system(size:16)).foregroundStyle(.secondary).accessibilityHidden(true) }
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
            .background(model.hovered == item.id || model.focusedID == item.id ? Color.primary.opacity(0.09) : .clear,in:RoundedRectangle(cornerRadius:6))
            .overlay(PocketClickTarget(label:item.name,itemID:item.id,enabled:!model.loading || model.images[item.id] != nil,pinned:Preferences.shared.pinnedPocketBundles.contains(item.bundle),image:model.images[item.id],place:{place(item)},beginDrag:{ beginDrag(item,$0) },endDrag:{ endDrag(item,$0,$1) },moveDrag:moveDrag,
                drop:{ drop(item,$0,$1,$2) },dropHover:{ after in
                    if let after { model.dropTargetID = item.id;model.dropAfter = after }
                    else if model.dropTargetID == item.id { model.dropTargetID = nil }
                },
                focus:{ focused in if focused { model.focusedID = item.id } else if model.focusedID == item.id { model.focusedID = nil } },
                move:{ key in PocketLayout.neighbor(of:item.id,keyCode:key,items:model.displayedItems.map { ($0.id,((model.images[$0.id]?.size.width ?? 22)+12)*66/model.columnWidth) }) },
                activate:{ activate(item,$0) }))
            .overlay(alignment:model.dropAfter ? .trailing : .leading) {
                if model.dropTargetID == item.id { Capsule().fill(Color.accentColor).frame(width:2).padding(.vertical,4).allowsHitTesting(false) }
            }
            .onHover { model.hovered = $0 ? item.id : nil }
            .help((model.images[item.id] == nil && !model.loading ? "\(item.name) · Icon unavailable; right-click the pocket button to refresh" : item.name)
                  + " · ⌘-drag to rearrange or return to the menu bar")
    }
}
