import AppKit
import ScreenCaptureKit
import CoreImage

// Reconstruct only the native background layer. Median scanlines discard menu
// glyphs while preserving the bar's opacity and vertical shading. Compositing
// this treatment over the clean desktop strip also handles Reduce Transparency.
struct NativeBarTreatment {
    let image: CGImage
    let foreground: NSColor
    let isClear: Bool
    let isOpaque: Bool
    let signature: Data
    let opacitySignature: Data
    init?(native: CGImage, logicalWidth: CGFloat) {
        let width = native.width, height = native.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(native, in: CGRect(x: 0, y: 0, width: width, height: height))
        var rows = [UInt8](repeating: 0, count: height * 4)
        for y in 0..<height {
            for channel in 0..<4 {
                var histogram = [Int](repeating: 0, count: 256)
                for x in stride(from: 0, to: width, by: 4) {
                    histogram[Int(pixels[(y * width + x) * 4 + channel])] += 1
                }
                let middle = ((width + 3) / 4) / 2
                var count = 0
                for value in 0..<256 {
                    count += histogram[value]
                    if count > middle { rows[y * 4 + channel] = UInt8(value); break }
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(rows) as CFData),
              let treatment = CGImage(width: 1, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                                      space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        image = treatment
        // The Apple glyph stays native and outside Draplet's cover. Its pixels
        // reveal the OS-selected light/dark foreground independently of theme.
        let scale = Double(width) / max(1, Double(logicalWidth))
        var candidates: [(Int, Double)] = []
        for y in min(height, max(0, Int(5 * scale)))..<min(height, Int(28 * scale)) {
            for x in min(width, max(0, Int(16 * scale)))..<min(width, Int(35 * scale)) {
                let i = (y * width + x) * 4, alpha = Int(pixels[i + 3])
                guard alpha > 160 else { continue }
                let difference = (0..<4).map { abs(Int(pixels[i + $0]) - Int(rows[y * 4 + $0])) }.max() ?? 0
                guard difference > 80 else { continue }
                let luma = Double(Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])) / (3 * Double(alpha))
                candidates.append((difference, luma))
            }
        }
        let strongest = candidates.sorted { $0.0 > $1.0 }.prefix(100)
        let luma = strongest.isEmpty ? 1 : strongest.map(\.1).reduce(0, +) / Double(strongest.count)
        foreground = luma > 0.5 ? .white : .black
        let alphas = stride(from: 3, to: rows.count, by: 4).map { rows[$0] }
        opacitySignature = Data(alphas)
        isClear = alphas.allSatisfy { $0 <= 1 }
        isOpaque = alphas.allSatisfy { $0 == 255 }
        signature = Data(rows) + Data([luma > 0.5 ? 255 : 0])
    }
}

// A complete WindowServer frame can still be part of the native menu bar's
// fullscreen fade. Confirm its opacity has stopped changing before caching it.
// Color is deliberately excluded: Live wallpaper colors may keep changing.
struct NativeBarRecovery {
    static let confirmationInterval: TimeInterval = 0.1
    private var opacity: Data?
    private var stableSince: TimeInterval = 0
    mutating func accepts(opacity next: Data, at time: TimeInterval) -> Bool {
        guard opacity == next else {
            opacity = next; stableSince = time
            return false
        }
        return time - stableSince >= Self.confirmationInterval
    }
}

enum BackgroundMode: String, CaseIterable {
    case cached, live
    var title: String { self == .cached ? "Cached" : "Live" }
}

// No public wallpaper-changed notification exists. Compare the public image URL
// and options plus file metadata. The optional store stamp catches changes from
// providers that keep returning the same URL; it is not our sole change signal.
struct WallpaperFingerprint: Equatable {
    let url: URL?
    let options: String
    let imageModified: Date?
    let imageSize: UInt64?
    let storeModified: Date?
    init(url: URL?, options: String, storeURL: URL?) {
        self.url = url; self.options = options
        let image = url.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path) }
        imageModified = image?[.modificationDate] as? Date
        imageSize = (image?[.size] as? NSNumber)?.uint64Value
        storeModified = storeURL.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date }
    }
    static func current() -> Self {
        let screen = NSScreen.screens.first
        let workspace = NSWorkspace.shared
        let options = screen.flatMap { workspace.desktopImageOptions(for: $0) } ?? [:]
        let description = options.keys.sorted { $0.rawValue < $1.rawValue }.map { "\($0.rawValue)=\(options[$0]!)" }.joined(separator: ";")
        return Self(url: screen.flatMap { workspace.desktopImageURL(for: $0) }, options: description,
                    storeURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist"))
    }
}

// A still wallpaper can have a changing rendered backdrop: windows near the
// bar contribute shadows, and activation changes their appearance. Ignore our
// own cover/status windows so animating the curtains cannot invalidate the cache.
struct BackdropScene: Equatable {
    struct Window: Equatable {
        let number: Int
        let layer: Int
        let frame: CGRect
    }
    let frontPID: pid_t
    let windows: [Window]
    init(frontPID: pid_t, windows: [Window], band: CGRect) {
        self.frontPID = frontPID
        self.windows = windows.filter {
            $0.layer >= 0 && $0.layer < 24 && $0.frame.maxX > band.minX && $0.frame.minX < band.maxX
                && $0.frame.maxY > band.minY && $0.frame.minY < band.maxY + 80
        }
    }
    static func current() -> Self {
        let display = CGDisplayBounds(CGMainDisplayID())
        let height = max(NSStatusBar.system.thickness, NSScreen.screens.first?.safeAreaInsets.top ?? 0)
        let band = CGRect(x: display.minX, y: display.minY, width: display.width, height: height)
        let windows = WindowServerSnapshot.shared.current(freshGeometry: true).map {
            Window(number: $0.number, layer: $0.layer, frame: $0.frame)
        }
        return Self(frontPID: ForegroundApplication.shared.current()?.pid ?? 0, windows: windows, band: band)
    }
}

// Mutable presentation state is confined to main. The capture queue only uses
// its own CIContext and hands immutable CGImages back to main.
final class MenuBarBackdrop: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    static let shared = MenuBarBackdrop()
    static let didChange = Notification.Name("Draplet.MenuBarBackdropChanged")
    static let presentationDidChange = Notification.Name("Draplet.MenuBarPresentationChanged")
    private(set) var ready = false
    private(set) var failure: String?
    private(set) var mode = BackgroundMode.cached
    private(set) var foreground = NSColor.white
    private(set) var screenFrame = NSRect.zero
    private(set) var snapshotCount = 0
    private(set) var frameCount = 0
    private(set) var systemPresentationSuspended = false
    private(set) var presentationSuppressed = false
    private var awaitingNativeAfterPresentation = false
    private var awaitingDesktopAfterPresentation = false
    private var nativeRecovery = NativeBarRecovery()
    private var presentationMonitor: Timer?
    var onPresentationTick: (() -> Void)?
    var streaming: Bool { stream != nil }
    private var cleanImage: CGImage?
    private var composedImage: CGImage?
    private var composedDrawing: NSImage?
    private var treatment: NativeBarTreatment?
    private var stream: SCStream?
    private var nativeWindow: SCWindow?
    private var desktopFilter: SCContentFilter?
    private var desktopConfig: SCStreamConfiguration?
    private var includedOwnWindows = Set<Int>()
    private var filterUpdateInFlight = false
    private var monitor: Timer?
    private var nativeRefresh: Timer?
    private var pendingRefresh: DispatchWorkItem?
    private var wallpaper: WallpaperFingerprint?
    private var scene: BackdropScene?
    private var nativeInFlight = false
    private var desktopInFlight = false
    private var refreshAgain = false
    private var recovery = CaptureRetryPolicy()
    private var active = false
    private var generation = 0
    // Capture-queue confined and released when capture stops.
    private var imageContext: CIContext?
    private var frameDelivery = FrameDeliveryGate()
    private let captureQueue = DispatchQueue(label: "Draplet.MenuBarBackground", qos: .userInitiated, autoreleaseFrequency: .workItem)
    private var queuedStreamID: ObjectIdentifier?
    private var singleFrameCapture = false
    private var captureNeedsDesktop = true
    private var lastFingerprint: UInt64?
    var permission: Bool { CGPreflightScreenCaptureAccess() }
    var snapshot: CGImage? { composedImage }

    func start(mode: BackgroundMode = .cached) {
        if systemPresentationSuspended { self.mode = mode; return }
        if active && self.mode == mode { return }
        guard failure == nil, permission else { self.mode = mode; return }
        if SystemPresentation.current() {
            suspendForSystemPresentation(); watchSystemPresentation(); self.mode = mode; return
        }
        if active { stop() }
        if systemPresentationSuspended { self.mode = mode; return }
        watchSystemPresentation()
        self.mode = mode; active = true; generation += 1; let token = generation
        // A desktop frame without a usable native bar must not leave Setup
        // spinning forever. Fullscreen return has its own recovery deadline.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, token == self.generation, self.active, !self.ready else { return }
            self.fail("macOS did not provide a complete menu-bar background. Please retry.")
        }
        wallpaper = .current(); scene = .current()
        captureQueue.async { [self] in self.singleFrameCapture = false; self.captureNeedsDesktop = true; self.lastFingerprint = nil }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard token == self.generation, self.active, self.acceptsCapture() else { return }
                guard let screen = NSScreen.screens.first,
                      let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
                    self.fail("The primary display is unavailable."); return
                }
                let height = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top) + 1
                self.screenFrame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
                let filter = self.makeDesktopFilter(content: content, display: display)
                self.desktopFilter = filter
                // macOS also advertises inactive black menu-bar windows. Prefer
                // the visible native bar, with the oldest WindowServer bar as the
                // fallback while auto-hide/full-screen temporarily hides it.
                self.nativeWindow = content.windows.filter { $0.title == "Menubar" && $0.windowLayer == 24 && $0.frame.intersects(display.frame) }
                    .sorted { $0.isOnScreen == $1.isOnScreen ? $0.windowID < $1.windowID : $0.isOnScreen }.first
                let config = SCStreamConfiguration()
                config.sourceRect = CGRect(x: 0, y: 0, width: screen.frame.width, height: height)
                config.width = Int(screen.frame.width * screen.backingScaleFactor)
                config.height = Int(height * screen.backingScaleFactor)
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                config.queueDepth = 3; config.showsCursor = false; config.capturesAudio = false
                config.pixelFormat = kCVPixelFormatType_32BGRA
                self.desktopConfig = config
                self.refreshNativeTreatment()
                guard token == self.generation, self.active else { return }
                if mode == .live {
                    let capture = SCStream(filter: filter, configuration: config, delegate: self)
                    try capture.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.captureQueue)
                    self.stream = capture
                    let captureID = ObjectIdentifier(capture)
                    self.captureQueue.async { [self] in
                        self.queuedStreamID = captureID; self.frameDelivery.reset(); self.lastFingerprint = nil; self.singleFrameCapture = false
                    }
                    try await capture.startCapture()
                    guard token == self.generation else { try? await capture.stopCapture(); return }
                    let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refreshNativeTreatment() }
                    self.nativeRefresh = timer; RunLoop.main.add(timer, forMode: .common)
                } else { self.captureDesktop() }
                let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                    guard let self, self.active else { return }
                    let current = WallpaperFingerprint.current()
                    guard current != self.wallpaper else { return }
                    self.wallpaper = current; self.refreshAppearance()
                }
                self.monitor = timer; RunLoop.main.add(timer, forMode: .common)
            } catch {
                guard token == self.generation else { return }
                self.fail(error.localizedDescription)
            }
        }
    }
    // Coalesce provider, Space and appearance events. Keep the last good image
    // visible until its replacement is ready, avoiding an exposed-menu flash.
    private func makeDesktopFilter(content: SCShareableContent, display: SCDisplay) -> SCContentFilter {
        // Exclude future covers by app, then whitelist our ordinary windows so
        // Settings contributes its real shadow without feeding the covers back.
        let excludedApps = content.applications.filter { $0.processID == getpid() }
        let overlays = content.windows.filter { $0.isOnScreen && $0.windowLayer >= 24 && $0.owningApplication?.processID != getpid() }
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == getpid() && $0.windowLayer == 0 }
        includedOwnWindows = Set(ownWindows.map { Int($0.windowID) })
        let filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: overlays + ownWindows)
        filter.includeMenuBar = false
        return filter
    }
    private func watchSystemPresentation() {
        guard presentationMonitor == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.checkSystemPresentation()
            self.onPresentationTick?()
        }
        presentationMonitor = timer; RunLoop.main.add(timer, forMode: .common)
    }
    @discardableResult private func checkSystemPresentation() -> Bool {
        guard active || systemPresentationSuspended else { return false }
        if SystemPresentation.current() { suspendForSystemPresentation(); return true }
        if systemPresentationSuspended {
            systemPresentationSuspended = false
            awaitingNativeAfterPresentation = true; awaitingDesktopAfterPresentation = true
            nativeRecovery = NativeBarRecovery()
            start(mode: mode)
            let token = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self, token == self.generation, !self.systemPresentationSuspended,
                      self.presentationSuppressed else { return }
                self.fail("The menu-bar background did not recover after fullscreen or Mission Control. Please retry.")
            }
        }
        return false
    }
    func checkScene() {
        guard active || systemPresentationSuspended else { return }
        if checkSystemPresentation() || presentationSuppressed { return }
        if mode == .live {
            let ownWindows = Set(NSApp.windows.filter { $0.isVisible && $0.level.rawValue < 24 }.map(\.windowNumber))
            guard !ownWindows.isSubset(of: includedOwnWindows), !filterUpdateInFlight, let capture = stream else { return }
            filterUpdateInFlight = true; let token = generation
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { if token == self.generation { self.filterUpdateInFlight = false } }
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                    guard token == self.generation, self.stream === capture,
                          let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else { return }
                    let filter = self.makeDesktopFilter(content: content, display: display)
                    self.desktopFilter = filter
                    try await capture.updateContentFilter(filter)
                } catch { if token == self.generation { self.fail(error.localizedDescription) } }
            }
        } else {
            let current = BackdropScene.current()
            guard current != scene else { return }
            scene = current
            refreshAppearance(after: 0.05)
        }
    }
    func refreshAppearance(after delay: TimeInterval = 0.4) {
        guard active else { return }
        pendingRefresh?.cancel()
        let token = generation
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.active, token == self.generation else { return }
            self.pendingRefresh = nil; self.wallpaper = .current()
            self.refreshNativeTreatment()
            if self.mode == .cached { self.captureDesktop() }
        }
        pendingRefresh = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
    private func captureDesktop() {
        guard active, acceptsCapture(), let config = desktopConfig else { return }
        if desktopInFlight { refreshAgain = true; return }
        desktopInFlight = true; let token = generation
        // SCScreenshotManager flattens this strip without the native lower-edge
        // shading/border. Freeze a real stream frame, exactly as Live renders it.
        captureQueue.async { [self] in self.singleFrameCapture = true; self.lastFingerprint = nil }
        Task { @MainActor [weak self] in
            guard let self, token == self.generation, self.active else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard token == self.generation, self.active, self.acceptsCapture(),
                      let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else { return }
                let filter = self.makeDesktopFilter(content: content, display: display)
                self.desktopFilter = filter
                let capture = SCStream(filter: filter, configuration: config, delegate: self)
                try capture.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.captureQueue)
                self.stream = capture
                let captureID = ObjectIdentifier(capture)
                self.captureQueue.async { [self] in
                    self.queuedStreamID = captureID; self.frameDelivery.reset(); self.lastFingerprint = nil; self.singleFrameCapture = true
                }
                try await capture.startCapture()
                guard token == self.generation else { try? await capture.stopCapture(); return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak capture] in
                    guard let self, let capture, token == self.generation, self.stream === capture, self.desktopInFlight else { return }
                    self.fail("The menu-bar background did not deliver a complete frame. Please retry.")
                }
            } catch {
                guard token == self.generation else { return }
                self.fail(error.localizedDescription)
            }
        }
    }
    private func refreshNativeTreatment() {
        // After a fullscreen/overview transition, first wait for WindowServer
        // to deliver a complete desktop frame. Capturing the native backing
        // earlier can return the game's still-transparent bar and freeze it.
        guard active, !nativeInFlight, !awaitingDesktopAfterPresentation,
              acceptsCapture(), let nativeWindow else { return }
        nativeInFlight = true; let token = generation
        let filter = SCContentFilter(desktopIndependentWindow: nativeWindow)
        let config = SCStreamConfiguration()
        config.width = Int(nativeWindow.frame.width * (NSScreen.screens.first?.backingScaleFactor ?? 2))
        config.height = Int(nativeWindow.frame.height * (NSScreen.screens.first?.backingScaleFactor ?? 2))
        config.showsCursor = false; config.ignoreShadowsSingleWindow = true
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { [weak self] image, _ in
            let newTreatment = image.flatMap { NativeBarTreatment(native: $0, logicalWidth: nativeWindow.frame.width) }
            DispatchQueue.main.async {
                guard let self, token == self.generation, self.active, self.acceptsCapture() else { return }
                self.nativeInFlight = false
                if let newTreatment {
                    let wasAwaiting = self.awaitingNativeAfterPresentation
                    if wasAwaiting && !self.nativeRecovery.accepts(opacity: newTreatment.opacitySignature,
                                                                  at: ProcessInfo.processInfo.systemUptime) {
                        self.retryNativeTreatment(generation: token)
                        return
                    }
                    self.awaitingNativeAfterPresentation = false
                    guard self.treatment?.signature != newTreatment.signature else {
                        if wasAwaiting { self.publish() }
                        return
                    }
                    self.treatment = newTreatment; self.foreground = newTreatment.foreground
                    let needsDesktop = !newTreatment.isOpaque || self.awaitingDesktopAfterPresentation
                    self.captureQueue.async { [self] in self.captureNeedsDesktop = needsDesktop; self.lastFingerprint = nil }
                    self.publish()
                } else if self.awaitingNativeAfterPresentation {
                    self.retryNativeTreatment(generation: token)
                }
            }
        }
    }
    private func retryNativeTreatment(generation token: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + NativeBarRecovery.confirmationInterval) { [weak self] in
            guard let self, token == self.generation, self.active, self.awaitingNativeAfterPresentation else { return }
            self.refreshNativeTreatment()
        }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard queuedStreamID == ObjectIdentifier(stream), (captureNeedsDesktop || singleFrameCapture), type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: status) == .complete,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard let delivery = frameDelivery.begin() else { return }
        var delivered = false
        defer { if !delivered { frameDelivery.finish(delivery) } }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        var fingerprint: UInt64 = 1469598103934665603
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer), stride = CVPixelBufferGetBytesPerRow(buffer)
            for y in Swift.stride(from: 0, to: height, by: max(1, height / 6)) {
                for x in Swift.stride(from: 0, to: width * 4, by: max(4, (width / 64) * 4)) {
                    for c in 0..<3 { fingerprint = (fingerprint ^ UInt64(bytes[y * stride + x + c])) &* 1099511628211 }
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        guard fingerprint != lastFingerprint else { return }
        lastFingerprint = fingerprint
        let image = CIImage(cvPixelBuffer: buffer)
        if imageContext == nil { imageContext = CIContext(options: [.cacheIntermediates: false]) }
        guard let cgImage = imageContext?.createCGImage(image, from: image.extent) else { return }
        delivered = true
        DispatchQueue.main.async { [weak self, weak stream] in
            guard let self else { return }
            defer { self.captureQueue.async { self.frameDelivery.finish(delivery) } }
            guard let stream, self.stream === stream, self.active, self.acceptsCapture() else { return }
            if self.mode == .cached {
                guard self.desktopInFlight else { return }
                self.desktopInFlight = false; self.snapshotCount += 1
                self.stream = nil
                self.captureQueue.async { [self] in self.singleFrameCapture = false; self.queuedStreamID = nil; self.imageContext?.clearCaches(); self.imageContext = nil }
                Task { try? await stream.stopCapture() }
            } else { self.frameCount += 1 }
            self.cleanImage = cgImage
            if self.awaitingDesktopAfterPresentation {
                self.awaitingDesktopAfterPresentation = false
                let needsDesktop = !(self.treatment?.isOpaque ?? false)
                self.captureQueue.async { [self] in self.captureNeedsDesktop = needsDesktop }
                self.refreshNativeTreatment()
            }
            self.publish()
            if self.refreshAgain { self.refreshAgain = false; self.refreshAppearance() }
        }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.fail(error.localizedDescription)
        }
    }
    func fail(_ message: String) {
        let retryDelay = recovery.failed(permissionGranted: permission)
        failure = message; stop(preservingRecovery: true)
        let token = generation
        NotificationCenter.default.post(name: Self.didChange, object: nil)
        NSLog("Draplet background capture: %@", message)
        guard let retryDelay else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
            guard let self, token == self.generation, self.failure != nil,
                  Preferences.shared.needsBackground, self.permission else { return }
            self.failure = nil
            self.start(mode: self.mode)
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }
    private func publish() {
        guard !awaitingNativeAfterPresentation, !awaitingDesktopAfterPresentation, let treatment else { return }
        if treatment.isOpaque { composedImage = treatment.image }
        else if treatment.isClear { composedImage = cleanImage }
        else if let cleanImage,
              let context = CGContext(data: nil, width: cleanImage.width, height: cleanImage.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: cleanImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            let rect = CGRect(x: 0, y: 0, width: cleanImage.width, height: cleanImage.height)
            context.interpolationQuality = .none
            context.draw(cleanImage, in: rect); context.draw(treatment.image, in: rect)
            composedImage = context.makeImage()
        }
        guard let composedImage else { return }
        composedDrawing = NSImage(cgImage: composedImage, size: screenFrame.size)
        recovery.reset()
        setReady(true)
        if presentationSuppressed && !systemPresentationSuspended {
            presentationSuppressed = false
            NotificationCenter.default.post(name: Self.presentationDidChange, object: nil)
        }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
    private func setReady(_ value: Bool) {
        guard ready != value else { return }; ready = value
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
    func draw(in bounds: NSRect, screenRect: NSRect, operation: NSCompositingOperation = .sourceOver) {
        guard let combined = composedDrawing, ready else { NSColor.windowBackgroundColor.setFill(); bounds.fill(using: operation); return }
        NSGraphicsContext.saveGraphicsState(); bounds.clip()
        NSGraphicsContext.current?.imageInterpolation = .none
        let source = NSRect(x: screenRect.minX - screenFrame.minX, y: screenRect.minY - screenFrame.minY,
                            width: screenRect.width, height: screenRect.height)
        combined.draw(in: bounds, from: source, operation: operation, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }
    // Mission Control and fullscreen games replace or cover the native bar.
    // Retain the last complete pair while our covers are removed, invalidating
    // in-flight callbacks so neither scene can contaminate the normal cache.
    private func suspendForSystemPresentation() {
        guard !systemPresentationSuspended else { return }
        stop(keepingSnapshot: true)
        systemPresentationSuspended = true
        presentationSuppressed = true
        NotificationCenter.default.post(name: Self.presentationDidChange, object: nil)
    }
    private func acceptsCapture() -> Bool {
        guard !systemPresentationSuspended else { return false }
        if SystemPresentation.current() { suspendForSystemPresentation(); return false }
        return true
    }
    func stop(keepingSnapshot: Bool = false, preservingRecovery: Bool = false) {
        if !preservingRecovery { recovery.reset() }
        generation += 1; active = false; nativeInFlight = false; desktopInFlight = false; refreshAgain = false; filterUpdateInFlight = false
        pendingRefresh?.cancel(); pendingRefresh = nil
        monitor?.invalidate(); monitor = nil; nativeRefresh?.invalidate(); nativeRefresh = nil
        captureQueue.async { [self] in
            queuedStreamID = nil; frameDelivery.reset()
            imageContext?.clearCaches(); imageContext = nil
        }
        let capture = stream; stream = nil
        if let capture { Task { try? await capture.stopCapture() } }
        nativeWindow = nil; desktopFilter = nil; desktopConfig = nil
        if !keepingSnapshot {
            systemPresentationSuspended = false
            presentationSuppressed = false
            awaitingNativeAfterPresentation = false; awaitingDesktopAfterPresentation = false
            nativeRecovery = NativeBarRecovery()
            presentationMonitor?.invalidate(); presentationMonitor = nil
            cleanImage = nil; composedImage = nil; composedDrawing = nil; treatment = nil; setReady(false)
        }
    }
    func restart() { let selectedMode = mode; failure = nil; stop(); start(mode: selectedMode) }
    func requestPermission() {
        _ = CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }
}
