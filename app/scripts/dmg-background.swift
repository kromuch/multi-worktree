import AppKit

let canvas = NSSize(width: 640, height: 400)
let appCenter = NSPoint(x: 160, y: 190)
let applicationsCenter = NSPoint(x: 480, y: 190)

func flipped(_ point: NSPoint) -> NSPoint {
    NSPoint(x: point.x, y: canvas.height - point.y)
}

func drawCentered(_ text: String, font: NSFont, alpha: CGFloat, top: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white.withAlphaComponent(alpha),
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    let size = string.size()
    string.draw(at: NSPoint(x: (canvas.width - size.width) / 2, y: canvas.height - top - size.height))
}

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(canvas.width * scale), pixelsHigh: Int(canvas.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let top = NSColor(srgbRed: 0.478, green: 0.525, blue: 0.627, alpha: 1)
    let bottom = NSColor(srgbRed: 0.369, green: 0.408, blue: 0.502, alpha: 1)
    NSGradient(starting: top, ending: bottom)!.draw(in: NSRect(origin: .zero, size: canvas), angle: -90)

    let arrowStart = flipped(NSPoint(x: appCenter.x + 96, y: appCenter.y))
    let arrowEnd = flipped(NSPoint(x: applicationsCenter.x - 96, y: applicationsCenter.y))
    let arrow = NSBezierPath()
    arrow.move(to: arrowStart)
    arrow.line(to: arrowEnd)
    arrow.move(to: NSPoint(x: arrowEnd.x - 18, y: arrowEnd.y + 16))
    arrow.line(to: arrowEnd)
    arrow.line(to: NSPoint(x: arrowEnd.x - 18, y: arrowEnd.y - 16))
    arrow.lineWidth = 6
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    NSColor.white.withAlphaComponent(0.85).setStroke()
    arrow.stroke()

    drawCentered("Drag MultiWorktree to Applications", font: .systemFont(ofSize: 20, weight: .semibold), alpha: 1, top: 40)
    drawCentered("First launch: System Settings → Privacy & Security → Open Anyway",
                 font: .systemFont(ofSize: 12, weight: .regular), alpha: 0.85, top: 328)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try render(scale: 1).write(to: output.appending(path: "background.png"))
try render(scale: 2).write(to: output.appending(path: "background@2x.png"))
