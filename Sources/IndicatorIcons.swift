import AppKit
import UniformTypeIdentifiers

enum BarSide { case left, right }
enum RevealTrigger: String, CaseIterable {
    case hover, click
    var title: String { self == .hover ? "Hover" : "Click" }
}
enum IndicatorStyle: String, CaseIterable {
    case chevron, arrow, triangle, hiddenBar, dots, custom
    var title: String {
        switch self {
        case .chevron: return "Chevron"
        case .arrow: return "Arrow"
        case .triangle: return "Triangle"
        case .hiddenBar: return "Hidden Bar"
        case .dots: return "Dots"
        case .custom: return "Custom"
        }
    }
}

enum IndicatorIcons {
    static let size = NSSize(width: 14, height: 14)
    private static var cache: [String: NSImage] = [:]
    static func image(for side: BarSide, expanded: Bool, prefs: Preferences = .shared) -> NSImage {
        image(style: prefs.icon(for: side), data: prefs.customIcon(for: side), side: side, expanded: expanded)
    }
    static func image(style: IndicatorStyle, data: Data? = nil, side: BarSide = .left, expanded: Bool = false) -> NSImage {
        let pointsRight = side == .left ? !expanded : expanded
        let key = "\(style.rawValue)-\(pointsRight)-\(data?.hashValue ?? 0)"
        if let cached = cache[key] { return cached }
        let direction = pointsRight ? "right" : "left"
        var source: NSImage?
        switch style {
        case .chevron: source = NSImage(systemSymbolName: "chevron.\(direction)", accessibilityDescription: nil)
        case .arrow: source = NSImage(systemSymbolName: "arrow.\(direction)", accessibilityDescription: nil)
        case .triangle: source = NSImage(systemSymbolName: "arrowtriangle.\(direction).fill", accessibilityDescription: nil)
        case .dots: source = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
        case .hiddenBar:
            let name = pointsRight ? "ic_collapse" : "ic_expand"
            if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "HiddenBar") { source = NSImage(contentsOf: url) }
        case .custom: if let data { source = NSImage(data: data) }
        }
        source = source?.withSymbolConfiguration(.init(pointSize: 12, weight: .medium)) ?? source
        guard let source else { return image(style: .chevron, side: side, expanded: expanded) }
        source.isTemplate = false
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 56, pixelsHigh: 56, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        let bounds = NSRect(x: 0, y: 0, width: 56, height: 56)
        NSColor.clear.setFill(); bounds.fill(using: .copy)
            let scale = min(bounds.width / max(1, source.size.width), bounds.height / max(1, source.size.height))
            let extent = NSSize(width: source.size.width * scale, height: source.size.height * scale)
            let frame = NSRect(x: bounds.midX - extent.width / 2, y: bounds.midY - extent.height / 2, width: extent.width, height: extent.height)
            source.draw(in: frame)
            NSColor.white.setFill()
            bounds.fill(using: .sourceIn)
        context.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
        rep.size = size
        let result = NSImage(size: size)
        result.addRepresentation(rep)
        result.isTemplate = true
        if cache.count > 64 { cache.removeAll() }
        cache[key] = result
        return result
    }
    static func importIcon(prefs: Preferences, side: BarSide?) {
        let panel = NSOpenPanel()
        panel.title = "Choose a menu-bar icon"
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { prefs.setCustomIcon(try normalizedIcon(at: url), side: side); prefs.error = "" }
        catch { prefs.error = error.localizedDescription }
    }
    static func normalizedIcon(at url: URL) throws -> Data {
        let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard bytes <= 8 * 1024 * 1024, let source = NSImage(contentsOf: url), source.isValid,
              source.size.width > 0, source.size.height > 0 else {
            throw NSError(domain: "Draplet", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose a valid PNG, JPEG, TIFF, or PDF smaller than 8 MB."])
        }
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8,
                                        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { throw CocoaError(.fileReadCorruptFile) }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: 64, height: 64).fill(using: .copy)
        let factor = min(56 / source.size.width, 56 / source.size.height)
        let extent = NSSize(width: source.size.width * factor, height: source.size.height * factor)
        source.draw(in: NSRect(x: (64 - extent.width) / 2, y: (64 - extent.height) / 2, width: extent.width, height: extent.height))
        context.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }
}
