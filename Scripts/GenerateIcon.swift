import AppKit
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let destination = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSColor(srgbRed: 0.13, green: 0.15, blue: 0.19, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
NSColor(srgbRed: 0.25, green: 0.27, blue: 0.31, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 210, y: 200, width: 500, height: 650), xRadius: 70, yRadius: 70).fill()
NSColor(srgbRed: 0.86, green: 0.20, blue: 0.25, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 300, y: 140, width: 500, height: 650), xRadius: 70, yRadius: 70).fill()
if let symbol = NSImage(systemSymbolName: "lock.open.fill", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 230, weight: .semibold)) {
    let white = NSImage(size: symbol.size)
    white.lockFocus()
    NSColor.white.set()
    NSRect(origin: .zero, size: symbol.size).fill()
    symbol.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1)
    white.unlockFocus()
    white.draw(in: NSRect(x: 420, y: 370, width: 260, height: 270))
}
let label = "3DS" as NSString
label.draw(at: NSPoint(x: 395, y: 220), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 92, weight: .bold), .foregroundColor: NSColor.white])
image.unlockFocus()
guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Icon rendering failed") }
context.draw(source, in: CGRect(origin: .zero, size: size))
guard let resized = context.makeImage(),
      let png = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("PNG encoding failed") }
CGImageDestinationAddImage(png, resized, nil)
guard CGImageDestinationFinalize(png) else { fatalError("PNG writing failed") }
print("Generated AppIcon.png")
