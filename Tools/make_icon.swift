// Draws the Telekin app icon (a magic wand on a violet-to-cyan night-sky square) and writes Assets/AppIcon.icns.
// Usage: swift Tools/make_icon.swift   (run from the telekin folder)
import AppKit

let assets = URL(fileURLWithPath: "Assets", isDirectory: true)
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Telekin.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

func render(pixels: Int) -> Data? {
    let size = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // macOS icon grid: the tile fills about 80% of the canvas.
    let inset = size * 0.1
    let tile = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(colors: [NSColor(calibratedRed: 0.10, green: 0.06, blue: 0.28, alpha: 1),
                        NSColor(calibratedRed: 0.42, green: 0.24, blue: 0.86, alpha: 1),
                        NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.98, alpha: 1)])?.draw(in: path, angle: -55)
    let config = NSImage.SymbolConfiguration(pointSize: tile.width * 0.5, weight: .regular)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let s = symbol.size
        symbol.draw(in: NSRect(x: tile.midX - s.width / 2, y: tile.midY - s.height / 2, width: s.width, height: s.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        guard let data = render(pixels: base * scale) else { fatalError("could not render \(name)") }
        try data.write(to: iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", assets.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote Assets/AppIcon.icns")
