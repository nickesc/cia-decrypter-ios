import AppKit
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let destinations = ["App/Assets.xcassets/AppIcon.appiconset/AppIcon.png", "docs/icon.png"]
let size = NSSize(width: 1024, height: 1024)
// AppKit's SVG renderer omits filter effects such as the artwork's shadows.
let rendered = FileManager.default.temporaryDirectory.appendingPathComponent("cia-icon-\(UUID().uuidString).png")
defer { try? FileManager.default.removeItem(at: rendered) }
let renderer = Process()
renderer.executableURL = URL(fileURLWithPath: "/usr/bin/env")
renderer.arguments = ["rsvg-convert", "--width=1024", "--height=1024", root.appendingPathComponent("docs/icon.svg").path, "--output", rendered.path]
try renderer.run()
renderer.waitUntilExit()
guard renderer.terminationStatus == 0 else { fatalError("SVG rendering failed. Install librsvg to provide rsvg-convert.") }
guard let image = NSImage(contentsOf: rendered) else { fatalError("Rendered icon loading failed") }
guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Icon rendering failed") }
context.draw(source, in: CGRect(origin: .zero, size: size))
guard let resized = context.makeImage() else { fatalError("Icon rendering failed") }
for path in destinations {
    let destination = root.appendingPathComponent(path)
    guard let png = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("PNG encoding failed") }
    CGImageDestinationAddImage(png, resized, nil)
    guard CGImageDestinationFinalize(png) else { fatalError("PNG writing failed") }
    print("Generated \(path)")
}
