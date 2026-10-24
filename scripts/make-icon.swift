// Draws the app icon. Writes Resources/AppIcon.icns for the app bundle and
// Resources/AppIcon.png (1024 px) for the README.
// Usage: swift scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

let output = URL(filePath: CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns")

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = size / 1024

    // macOS icon grid: an 824 pt rounded square centred on a 1024 pt canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824).applying(.init(scaleX: scale, y: scale))
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * scale, yRadius: 185 * scale)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 24 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [
        NSColor(srgbRed: 0.20, green: 0.78, blue: 0.86, alpha: 1),
        NSColor(srgbRed: 0.16, green: 0.42, blue: 0.95, alpha: 1),
        NSColor(srgbRed: 0.33, green: 0.22, blue: 0.80, alpha: 1),
    ])!.draw(in: body, angle: -70)
    // Soft top highlight, the way glass catches light.
    NSGradient(colors: [.white.withAlphaComponent(0.28), .white.withAlphaComponent(0)])!
        .draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    func symbol(_ name: String, pointSize: CGFloat, center: CGPoint, alpha: CGFloat) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize * scale, weight: .medium)
            .applying(.init(paletteColors: [.white.withAlphaComponent(alpha)]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let rect = CGRect(
            x: center.x * scale - image.size.width / 2, y: center.y * scale - image.size.height / 2,
            width: image.size.width, height: image.size.height
        )
        image.draw(in: rect)
    }

    symbol("memorychip", pointSize: 400, center: CGPoint(x: 500, y: 492), alpha: 1)
    symbol("sparkle", pointSize: 150, center: CGPoint(x: 735, y: 742), alpha: 0.95)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = drawIcon(size: CGFloat(base * factor)).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appending(path: name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(filePath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
try drawIcon(size: 1024).representation(using: .png, properties: [:])!
    .write(to: output.deletingPathExtension().appendingPathExtension("png"))
print("Wrote \(output.path)")
