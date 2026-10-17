import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(size)/1024, y: CGFloat(size)/1024)
    let bounds = NSRect(x: 20, y: 20, width: 984, height: 984)
    let shape = NSBezierPath(roundedRect: bounds, xRadius: 220, yRadius: 220)
    NSGradient(starting: NSColor(srgbRed: 0.30, green: 0.19, blue: 0.39, alpha: 1), ending: NSColor(srgbRed: 0.12, green: 0.08, blue: 0.19, alpha: 1))!.draw(in: shape, angle: -65)
    let cream = NSColor(srgbRed: 0.95, green: 0.87, blue: 0.81, alpha: 1)
    cream.setStroke()
    let rail = NSBezierPath(); rail.move(to: NSPoint(x: 225, y: 754)); rail.line(to: NSPoint(x: 799, y: 754)); rail.lineWidth = 36; rail.lineCapStyle = .round; rail.stroke()
    for mirror in [false, true] {
        context.saveGState()
        if mirror { context.translateBy(x: 1024, y: 0); context.scaleBy(x: -1, y: 1) }
        let drape = NSBezierPath()
        drape.move(to: NSPoint(x: 248, y: 710)); drape.line(to: NSPoint(x: 480, y: 710))
        drape.curve(to: NSPoint(x: 328, y: 385), controlPoint1: NSPoint(x: 468, y: 546), controlPoint2: NSPoint(x: 390, y: 431))
        drape.line(to: NSPoint(x: 395, y: 253))
        drape.curve(to: NSPoint(x: 248, y: 273), controlPoint1: NSPoint(x: 342, y: 280), controlPoint2: NSPoint(x: 293, y: 226))
        drape.close(); cream.setFill(); drape.fill()
        NSColor(srgbRed: 0.52, green: 0.34, blue: 0.52, alpha: 0.55).setStroke()
        let fold = NSBezierPath(); fold.move(to: NSPoint(x: 322, y: 684)); fold.curve(to: NSPoint(x: 296, y: 431), controlPoint1: NSPoint(x: 339, y: 587), controlPoint2: NSPoint(x: 326, y: 497)); fold.lineWidth = 15; fold.lineCapStyle = .round; fold.stroke()
        context.restoreGState()
    }
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size).png"))
}
