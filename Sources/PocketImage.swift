import AppKit

// Remove a nearly uniform native menu-bar background from the captured icon.
// Keep antialiasing as alpha, including white-on-black and black-on-light icons.
// Blank snapshots are rejected; they must never masquerade as a captured icon.
enum PocketImage {
    // Keep only a small raster in the tray cache, rather than retaining every
    // application's full multi-resolution artwork for the lifetime of Draplet.
    static func appArtwork(_ source: NSImage) -> NSImage {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 48, pixelsHigh: 48,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return source }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: 48, height: 48), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: 24, height: 24)); image.addRepresentation(bitmap)
        return image
    }

    static func isMonochrome(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data, let p = CFDataGetBytePtr(data), image.bitsPerPixel == 32, CFDataGetLength(data) >= image.bytesPerRow * image.height else { return false }
        for row in 0..<image.height {
            for x in 0..<image.width {
                let i = row * image.bytesPerRow + x * 4
                if p[i+3] > 32 && max(p[i], p[i+1], p[i+2]) - min(p[i], p[i+1], p[i+2]) > 12 { return false }
            }
        }
        return true
    }
    static func isolate(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 1, height > 1, width <= 4096, height <= 256 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let corners = [0, (width - 1) * 4, (height - 1) * width * 4, (width * height - 1) * 4]
        if corners.allSatisfy({ bytes[$0 + 3] < 16 }) {
            return stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] > 32 } ? image : nil
        }
        let background = (0..<3).map { channel -> Double in
            let samples = corners.map { Int(bytes[$0 + channel]) }.sorted()
            return Double(samples[1] + samples[2]) / 2
        }
        var ink = 0
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let sourceAlpha = Double(bytes[index + 3]) / 255
            if sourceAlpha < 0.99 { if sourceAlpha > 0.08 { ink += 1 }; continue }
            let rgb = (0..<3).map { Double(bytes[index + $0]) }
            var alpha = 0.0
            for c in 0..<3 {
                let distance = rgb[c] - background[c]
                let range = distance >= 0 ? 255 - background[c] : background[c]
                if range > 0 { alpha = max(alpha, abs(distance) / range) }
            }
            if alpha < 0.06 { for c in 0..<4 { bytes[index + c] = 0 }; continue }
            alpha = min(1, alpha); ink += 1
            for c in 0..<3 { bytes[index + c] = UInt8(max(0, min(255 * alpha, (rgb[c] - background[c] * (1 - alpha))).rounded())) }
            bytes[index + 3] = UInt8((255 * alpha).rounded())
        }
        guard ink > max(1, width * height / 500) else { return nil }
        // Own the resulting bytes independently of the temporary drawing context.
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
