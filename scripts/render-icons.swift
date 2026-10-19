import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconURL = root.appendingPathComponent("build/icon.svg")
let document = try XMLDocument(contentsOf: iconURL)
guard let glyph = document.rootElement()?.children?.compactMap({ $0 as? XMLElement }).first(where: {
    $0.attribute(forName: "id")?.stringValue == "glyph"
})?.copy() as? XMLElement,
      let image = NSImage(contentsOf: iconURL) else {
    fatalError("Unable to load build/icon.svg or its glyph")
}

func writePNG(_ image: NSImage, size: Int, to url: URL) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Unable to create icon bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode icon PNG")
    }
    try data.write(to: url)
}

try writePNG(image, size: 1024, to: root.appendingPathComponent("build/icon.png"))
let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
for size in [16, 32, 128, 256, 512] {
    try writePNG(image, size: size, to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try writePNG(image, size: size * 2, to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

glyph.removeAttribute(forName: "transform")
glyph.attribute(forName: "color")?.stringValue = "#000000"
let symbol = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"18\" height=\"18\" viewBox=\"32 32 192 192\">\(glyph.xmlString)</svg>"
guard let symbolImage = NSImage(data: Data(symbol.utf8)),
      let data = CFDataCreateMutable(nil, 0),
      let consumer = CGDataConsumer(data: data) else {
    fatalError("Unable to create menu bar icon")
}
var bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
guard let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else {
    fatalError("Unable to create menu bar PDF context")
}
context.beginPDFPage(nil)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
symbolImage.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
context.endPDFPage()
context.closePDF()
try (data as Data).write(to: root.appendingPathComponent("Sources/Glint/Resources/MenuBarIcon.pdf"))
