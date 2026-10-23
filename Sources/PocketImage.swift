import AppKit

// Remove a nearly uniform native menu-bar background from the captured icon.
// Keep antialiasing as alpha, including white-on-black and black-on-light icons.
// Blank snapshots are rejected; they must never masquerade as a captured icon.
enum PocketImage {
    static func isMonochrome(_ image: CGImage) -> Bool {
        // A CGImage crop may retain its original row stride but omit padding
        // after the last pixel. Only bytes actually visited must be present.
        guard image.width > 0, image.height > 0, image.bitsPerPixel == 32,
              let data = image.dataProvider?.data, let p = CFDataGetBytePtr(data),
              CFDataGetLength(data) >= (image.height-1)*image.bytesPerRow+image.width*4 else { return false }
        var minimum = [255,255,255], maximum = [0,0,0]
        for row in 0..<image.height {
            for x in 0..<image.width {
                let i = row * image.bytesPerRow + x * 4
                if p[i+3] > 96 {
                    let rgb = (0..<3).map { min(255, Int(p[i+$0]) * 255 / Int(p[i+3])) }
                    if rgb.max()! - rgb.min()! > 12 { return false }
                    for c in 0..<3 { minimum[c] = min(minimum[c], rgb[c]); maximum[c] = max(maximum[c], rgb[c]) }
                }
            }
        }
        return (0..<3).allSatisfy { maximum[$0] - minimum[$0] < 24 }
    }
    static func trim(_ image: CGImage) -> CGImage? {
        guard let data = image.dataProvider?.data, let p = CFDataGetBytePtr(data), image.bitsPerPixel == 32 else { return nil }
        var left = image.width, right = -1
        for y in 0..<image.height { for x in 0..<image.width where p[y * image.bytesPerRow + x * 4 + 3] > 8 { left = min(left,x); right = max(right,x) } }
        guard right >= left else { return nil }
        left = max(0,left - 2); right = min(image.width - 1,right + 2)
        return image.cropping(to: CGRect(x: left, y: 0, width: right - left + 1, height: image.height))
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
            var difference = 0.0
            for c in 0..<3 {
                let distance = rgb[c] - background[c]
                difference = max(difference,abs(distance))
                let range = distance >= 0 ? 255 - background[c] : background[c]
                if range > 0 { alpha = max(alpha, abs(distance) / range) }
            }
            // Near black/white, a one-level native background fluctuation can
            // divide by a range of one and become fully opaque "ink". Reject
            // this quantization noise before it changes the extracted bounds.
            if difference <= 2 || alpha < 1.0 / 255 { for c in 0..<4 { bytes[index + c] = 0 }; continue }
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
