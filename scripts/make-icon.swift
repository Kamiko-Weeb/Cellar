// Draws Cellar's app icon into an .iconset folder: `swift scripts/make-icon.swift build/AppIcon.iconset`
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Standard macOS icon grid: the tile fills about 80% of the canvas.
    let inset = size * 0.1
    let tile = CGRect(x: inset, y: inset * 1.15, width: size - inset * 2, height: size - inset * 2)
    let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = size * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    shadow.set()
    NSColor(red: 0.22, green: 0.04, blue: 0.11, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [
        NSColor(red: 0.70, green: 0.20, blue: 0.32, alpha: 1),
        NSColor(red: 0.42, green: 0.08, blue: 0.18, alpha: 1),
        NSColor(red: 0.20, green: 0.03, blue: 0.10, alpha: 1),
    ])!.draw(in: shape, angle: -70)

    NSColor.white.withAlphaComponent(0.14).setStroke()
    shape.lineWidth = max(1, size * 0.004)
    shape.stroke()

    let config = NSImage.SymbolConfiguration(pointSize: tile.width * 0.46, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let glass = NSImage(systemSymbolName: "wineglass.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let glyph = glass.size
        glass.draw(in: CGRect(x: tile.midX - glyph.width / 2, y: tile.midY - glyph.height / 2, width: glyph.width, height: glyph.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    try render(pixels: points * scale).write(to: output.appending(path: name))
}
