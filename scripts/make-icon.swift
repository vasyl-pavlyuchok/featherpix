// Generates Resources/AppIcon.icns. Run: swift scripts/make-icon.swift  (needs iconutil)
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let set = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

// Artwork: Resources/icon-source.jpg (generated with Google Gemini, square, full-bleed).
let artwork = NSImage(contentsOf: root.appendingPathComponent("Resources/icon-source.jpg"))

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // macOS icon grid: 824/1024 body with rounded corners.
    let inset = s * 100 / 1024, body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    // Soft drop shadow like system icons.
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.28)
    sh.shadowBlurRadius = s * 0.018; sh.shadowOffset = NSSize(width: 0, height: -s * 0.008); sh.set()
    NSColor.black.setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    if let art = artwork {
        art.draw(in: body, from: .zero, operation: .copy, fraction: 1)
    } else {
        NSGradient(colors: [NSColor(srgbRed: 0.11, green: 0.73, blue: 0.69, alpha: 1),
                            NSColor(srgbRed: 0.25, green: 0.33, blue: 0.86, alpha: 1)])!.draw(in: path, angle: -60)
    }
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! p.run(); p.waitUntilExit()
try! render(512).write(to: root.appendingPathComponent("docs/icon.png"))
print(p.terminationStatus == 0 ? "OK" : "iconutil failed")
