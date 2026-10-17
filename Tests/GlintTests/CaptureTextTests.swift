import Testing
import AppKit
@testable import Glint

@MainActor
struct CaptureTextTests {
    @Test func wrappedTextPreservesParagraphsAndScriptSpacing() {
        let lines = [
            OCRLine(text: "A paragraph wraps across", bounds: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.04)),
            OCRLine(text: "multiple lines in a document.", bounds: CGRect(x: 0.1, y: 0.75, width: 0.8, height: 0.04)),
            OCRLine(text: "Another paragraph.", bounds: CGRect(x: 0.1, y: 0.6, width: 0.6, height: 0.04))
        ]
        #expect(OCRText.paragraphs(lines) == "A paragraph wraps across multiple lines in a document.\n\nAnother paragraph.")
        #expect(OCRText.paragraphs([
            .init(text: "这是自然段的第一行", bounds: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.04)),
            .init(text: "下一行继续正文。", bounds: CGRect(x: 0.1, y: 0.75, width: 0.6, height: 0.04))
        ]) == "这是自然段的第一行下一行继续正文。")
    }

    @Test func listsColumnsAndHyphenatedWordsStayReadable() {
        #expect(OCRText.paragraphs([
            .init(text: "A hyphenated trans-", bounds: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.04)),
            .init(text: "lation continues here.", bounds: CGRect(x: 0.1, y: 0.75, width: 0.8, height: 0.04)),
            .init(text: "• First item", bounds: CGRect(x: 0.1, y: 0.7, width: 0.5, height: 0.04)),
            .init(text: "• Second item", bounds: CGRect(x: 0.1, y: 0.65, width: 0.5, height: 0.04))
        ]) == "A hyphenated translation continues here.\n\n• First item\n\n• Second item")
        #expect(OCRText.paragraphs([]).isEmpty)
        #expect(OCRText.paragraphs([
            .init(text: "Left column.", bounds: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.04)),
            .init(text: "Right column.", bounds: CGRect(x: 0.6, y: 0.8, width: 0.3, height: 0.04))
        ]) == "Left column.\n\nRight column.")
    }

    @Test func captureCropUsesTopOriginPixelsAndCocoaScreenCoordinates() throws {
        let context = try #require(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.red.cgColor); context.fill(CGRect(x: 0, y: 50, width: 100, height: 50))
        context.setFillColor(NSColor.blue.cgColor); context.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
        let image = try #require(context.makeImage())
        let display = CapturedDisplay(frame: CGRect(x: -100, y: -100, width: 100, height: 100), image: image)
        let top = try #require(CaptureService.composite([display], selection: CGRect(x: -100, y: -25, width: 100, height: 25)))
        let bottom = try #require(CaptureService.composite([display], selection: CGRect(x: -100, y: -100, width: 100, height: 25)))
        #expect((NSBitmapImageRep(cgImage: top).colorAt(x: 10, y: 10)?.redComponent ?? 0) > 0.9)
        #expect((NSBitmapImageRep(cgImage: bottom).colorAt(x: 10, y: 10)?.blueComponent ?? 0) > 0.9)
    }

    @Test func captureCompositeHandlesDifferentDisplayScalesAndNegativeOrigins() throws {
        func image(_ color: NSColor, width: Int, height: Int) throws -> CGImage {
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            color.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
            NSGraphicsContext.restoreGraphicsState()
            return try #require(bitmap.cgImage)
        }
        let frames = [
            CapturedDisplay(frame: CGRect(x: -100, y: 0, width: 100, height: 100), image: try image(.red, width: 100, height: 100)),
            CapturedDisplay(frame: CGRect(x: 0, y: 0, width: 100, height: 100), image: try image(.blue, width: 200, height: 200))
        ]
        let result = try #require(CaptureService.composite(frames, selection: CGRect(x: -25, y: 20, width: 50, height: 40)))
        #expect(result.width == 100 && result.height == 80)
        let bitmap = NSBitmapImageRep(cgImage: result)
        #expect((bitmap.colorAt(x: 10, y: 20)?.redComponent ?? 0) > 0.9)
        #expect((bitmap.colorAt(x: 90, y: 20)?.blueComponent ?? 0) > 0.9)
    }
}
