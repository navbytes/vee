import AppKit

// Renders Vee's app icon (a rounded-square gradient badge with a menu-bar motif
// and a bold "V") to a 1024×1024 PNG. Run: swift scripts/make-icon.swift out.png
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let px = 1024

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let size = CGFloat(px)
// macOS icon: artwork inset from the canvas edges with a rounded-rect shape.
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let radius = rect.width * 0.235
let badge = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

// Gradient fill (indigo → blue), clipped to the badge.
NSGraphicsContext.saveGraphicsState()
badge.addClip()
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.36, green: 0.30, blue: 0.90, alpha: 1),
    NSColor(srgbRed: 0.15, green: 0.52, blue: 0.98, alpha: 1),
])!
gradient.draw(in: rect, angle: -90)
// A subtle menu-bar strip across the top of the badge.
NSColor(white: 1, alpha: 0.16).setFill()
CGRect(x: rect.minX, y: rect.maxY - rect.height * 0.19, width: rect.width, height: rect.height * 0.19).fill()
// Three small "status item" dots on the strip.
NSColor(white: 1, alpha: 0.9).setFill()
let dotY = rect.maxY - rect.height * 0.095
let dotR = rect.width * 0.028
for i in 0..<3 {
    let cx = rect.maxX - rect.width * (0.12 + CGFloat(i) * 0.09)
    NSBezierPath(ovalIn: CGRect(x: cx - dotR, y: dotY - dotR, width: dotR * 2, height: dotR * 2)).fill()
}
NSGraphicsContext.restoreGraphicsState()

// Bold "V".
let font = NSFont.systemFont(ofSize: rect.height * 0.62, weight: .bold)
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.25)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -14)
let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white, .shadow: shadow]
let glyph = NSAttributedString(string: "V", attributes: attrs)
let gs = glyph.size()
glyph.draw(at: NSPoint(x: rect.midX - gs.width / 2, y: rect.midY - gs.height / 2 - rect.height * 0.06))

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(px)x\(px))")
