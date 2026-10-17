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
                let values = stride(from: 0, to: width, by: 4).map { pixels[(y * width + $0) * 4 + channel] }.sorted()
                rows[y * 4 + channel] = values[values.count / 2]
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
        for y in max(0, Int(5 * scale))..<min(height, Int(28 * scale)) {
            for x in max(0, Int(16 * scale))..<min(width, Int(35 * scale)) {
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
        isClear = alphas.allSatisfy { $0 <= 1 }
        isOpaque = alphas.allSatisfy { $0 == 255 }
        signature = Data(rows) + Data([luma > 0.5 ? 255 : 0])
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

// Mutable presentation state is confined to main. The capture queue only uses
// its own CIContext and hands immutable CGImages back to main.
final class MenuBarBackdrop: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    static let shared = MenuBarBackdrop()
    static let didChange = Notification.Name("Draplet.MenuBarBackdropChanged")
    private(set) var ready = false
    private(set) var failure: String?
    private(set) var mode = BackgroundMode.cached
    private(set) var foreground = NSColor.white
    private(set) var screenFrame = NSRect.zero
    private(set) var snapshotCount = 0
    private(set) var frameCount = 0
    var streaming: Bool { stream != nil }
    private var cleanImage: CGImage?
    private var composedImage: CGImage?
    private var treatment: NativeBarTreatment?
    private var stream: SCStream?
    private var nativeWindow: SCWindow?
    private var desktopFilter: SCContentFilter?
    private var desktopConfig: SCStreamConfiguration?
    private var monitor: Timer?
    private var nativeRefresh: Timer?
    private var pendingRefresh: DispatchWorkItem?
    private var wallpaper: WallpaperFingerprint?
    private var nativeInFlight = false
    private var desktopInFlight = false
    private var refreshAgain = false
    private var active = false
    private var generation = 0
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let captureQueue = DispatchQueue(label: "Draplet.MenuBarBackground", qos: .userInitiated)
    private var captureNeedsDesktop = true
    private var lastFingerprint: UInt64?
    var permission: Bool { CGPreflightScreenCaptureAccess() }
    var snapshot: CGImage? { composedImage }

    func start(mode: BackgroundMode = .cached) {
        if active && self.mode == mode { return }
        guard failure == nil, permission else { return }
        if active { stop() }
        self.mode = mode; active = true; generation += 1; let token = generation
        wallpaper = .current()
        captureQueue.async { [self] in self.captureNeedsDesktop = true; self.lastFingerprint = nil }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard token == self.generation, self.active else { return }
                guard let screen = NSScreen.screens.first,
                      let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
                    self.fail("The primary display is unavailable."); return
                }
                let height = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top) + 1
                self.screenFrame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
                // Exclude our future covers by app, but other overlays by window:
                // excluding their entire app could remove a live-wallpaper provider.
                let excludedApps = content.applications.filter { $0.processID == getpid() }
                let overlays = content.windows.filter { $0.windowLayer >= 24 && $0.owningApplication?.processID != getpid() }
                let filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: overlays)
                filter.includeMenuBar = false
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
                if mode == .live {
                    let capture = SCStream(filter: filter, configuration: config, delegate: self)
                    try capture.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.captureQueue)
                    self.stream = capture
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
    func refreshAppearance() {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }
    private func captureDesktop() {
        guard active, let filter = desktopFilter, let config = desktopConfig else { return }
        if desktopInFlight { refreshAgain = true; return }
        desktopInFlight = true; let token = generation
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { [weak self] image, error in
            DispatchQueue.main.async {
                guard let self, token == self.generation, self.active else { return }
                self.desktopInFlight = false
                if let image {
                    self.snapshotCount += 1; self.cleanImage = image; self.publish()
                } else if let error { self.fail(error.localizedDescription); return }
                if self.refreshAgain { self.refreshAgain = false; self.refreshAppearance() }
            }
        }
    }
    private func refreshNativeTreatment() {
        guard active, !nativeInFlight, let nativeWindow else { return }
        nativeInFlight = true; let token = generation
        let filter = SCContentFilter(desktopIndependentWindow: nativeWindow)
        let config = SCStreamConfiguration()
        config.width = Int(nativeWindow.frame.width * (NSScreen.screens.first?.backingScaleFactor ?? 2))
        config.height = Int(nativeWindow.frame.height * (NSScreen.screens.first?.backingScaleFactor ?? 2))
        config.showsCursor = false; config.ignoreShadowsSingleWindow = true
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { [weak self] image, _ in
            let newTreatment = image.flatMap { NativeBarTreatment(native: $0, logicalWidth: nativeWindow.frame.width) }
            DispatchQueue.main.async {
                guard let self, token == self.generation, self.active else { return }
                self.nativeInFlight = false
                if let newTreatment {
                    guard self.treatment?.signature != newTreatment.signature else { return }
                    self.treatment = newTreatment; self.foreground = newTreatment.foreground
                    self.captureQueue.async { [self] in self.captureNeedsDesktop = !newTreatment.isOpaque; self.lastFingerprint = nil }
                    self.publish()
                }
            }
        }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard captureNeedsDesktop, type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: status) == .complete,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
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
        guard let cgImage = imageContext.createCGImage(image, from: image.extent) else { return }
        DispatchQueue.main.async { [weak self, weak stream] in
            guard let self, self.stream === stream, self.active else { return }
            self.frameCount += 1; self.cleanImage = cgImage; self.publish()
        }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.fail(error.localizedDescription)
        }
    }
    private func fail(_ message: String) {
        failure = message; stop()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
        NSLog("Draplet background capture: %@", message)
    }
    private func publish() {
        guard let treatment else { return }
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
        guard composedImage != nil else { return }
        setReady(true)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
    private func setReady(_ value: Bool) {
        guard ready != value else { return }; ready = value
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
    func draw(in bounds: NSRect, screenRect: NSRect, operation: NSCompositingOperation = .sourceOver) {
        guard let composedImage, ready else { NSColor.windowBackgroundColor.setFill(); bounds.fill(using: operation); return }
        NSGraphicsContext.saveGraphicsState(); bounds.clip()
        NSGraphicsContext.current?.imageInterpolation = .none
        let combined = NSImage(cgImage: composedImage, size: screenFrame.size)
        let source = NSRect(x: screenRect.minX - screenFrame.minX, y: screenRect.minY - screenFrame.minY,
                            width: screenRect.width, height: screenRect.height)
        combined.draw(in: bounds, from: source, operation: operation, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }
    func stop() {
        generation += 1; active = false; nativeInFlight = false; desktopInFlight = false; refreshAgain = false
        pendingRefresh?.cancel(); pendingRefresh = nil
        monitor?.invalidate(); monitor = nil; nativeRefresh?.invalidate(); nativeRefresh = nil
        let capture = stream; stream = nil
        if let capture { Task { try? await capture.stopCapture() } }
        cleanImage = nil; composedImage = nil; treatment = nil; nativeWindow = nil
        desktopFilter = nil; desktopConfig = nil; setReady(false)
    }
    func restart() { let selectedMode = mode; failure = nil; stop(); start(mode: selectedMode) }
    func requestPermission() {
        _ = CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }
}
