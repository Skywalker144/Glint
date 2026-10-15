import Testing
import Foundation
import AppKit
import AVFoundation
@testable import Glint
import GlintCore

@MainActor
struct NativeTests {
    @Test func testHotkeyAliasesAndKeys() {
        #expect(Hotkey.parse("Alt+Q") == Hotkey.parse("Option+Q"))
        #expect(Hotkey.parse("CommandOrControl+Return") == Hotkey.parse("Command+Return"))
        #expect(Hotkey.parse("unknown+Q") == nil)
        #expect(Hotkey.display("Command+Alt+Q") == "⌘⌥Q")
    }
    @Test func testPopupBoundsAcrossDisplays() {
        let area = CGRect(x: -1440, y: -900, width: 1440, height: 900)
        for position in PopupOptions.positions {
            var options = PopupOptions(); options.position = position
            for point in [CGPoint(x: -1440, y: -900), CGPoint(x: -1, y: -1), CGPoint(x: -720, y: -450)] {
                let frame = ScreenCoordinates.popup(at: point, area: area, options: options)
                #expect(area.contains(frame))
                #expect(frame.width == 40)
            }
        }
    }
    @Test func testNativeMarkdownAndMath() throws {
        _ = NSApplication.shared
        let source = "**bold** and *italic*\n\n- [link](https://example.com)\n\n`code`\n\n$$x^2+1$$"
        let rendered = NativeMarkdown.render(source)
        #expect(rendered.string.contains("bold"))
        #expect(!rendered.string.contains("**"))
        var equations = 0
        rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if value is MathAttachment { equations += 1 }
        }
        #expect(equations == 1)
        let plain = NativeMarkdown.plainText(source)
        #expect(plain.contains("link"))
        #expect(plain.contains("x^2+1"))
        #expect(!plain.contains("[link]"))
    }
    @Test func testNativeTableAndCodeRemainSelectableText() {
        _ = NSApplication.shared
        let result = NativeMarkdown.render("| A | B |\n|---|---|\n| one | two |\n\n```swift\nlet x = 1\n```")
        #expect(result.string.contains("one"))
        #expect(result.string.contains("two"))
        #expect(result.string.contains("let x = 1"))
        var table = false
        result.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: result.length)) { value, _, _ in
            if let style = value as? NSParagraphStyle, !style.textBlocks.isEmpty { table = true }
        }
        #expect(table)
    }
    @Test func testCodeDoesNotTypesetMath() {
        let source = "`$HOME$`\n\n```sh\necho $$PID$$\n```"
        let result = NativeMarkdown.render(source)
        #expect(result.string.contains("$HOME$"))
        #expect(result.string.contains("$$PID$$"))
        #expect(!result.string.contains("GLINTMATHTOKEN"))
    }
    @Test func testVisionWithRealImage() async throws {
        _ = NSApplication.shared
        let image = NSImage(size: NSSize(width: 700, height: 140), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            "Glint native OCR".draw(at: NSPoint(x: 30, y: 50), withAttributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black])
            return true
        }
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let result = try await CaptureService.recognize(cgImage)
        #expect(result.contains("Glint"))
        #expect(result.contains("OCR"))
    }
    @Test func testInputAndErrorFocusState() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".cache/model-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(store: try LocalStore(directory: root))
        model.input = "old"; model.output = "old result"; model.overrides.source = "en"
        model.beginInput()
        #expect(model.input.isEmpty && model.output.isEmpty)
        #expect(model.overrides.source == "en")
        #expect(model.inputFocusRevision == 1)
        model.showMessage("No selection")
        #expect(model.selectAllOnFocus)
        #expect(model.inputFocusRevision == 2)
        #expect(model.displayMode == .translate)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GLINT_LIVE_NETWORK"] == "1"))
    func testLiveGoogleTranslationAndAudio() async throws {
        let client = try HTTPClient(proxy: .init())
        let request = try TranslationRequest.resolve("Hello world", settings: AppSettings())
        let output = try await TranslationEngine(client: client).translate("Hello world", request: request) { _ in }
        #expect(output.translated.contains("世界"))
        var audioRequest = URLRequest(url: URL(string: "https://translate.googleapis.com/translate_tts?ie=UTF-8&client=tw-ob&tl=en&q=Hello")!)
        audioRequest.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let data = try await client.data(for: audioRequest)
        let player = try AVAudioPlayer(data: data)
        #expect(player.duration > 0)
    }
    @Test func testSpeechSplittingAndLongInput() {
        let parts = SpeechService.split(String(repeating: "Hello world. ", count: 100))
        #expect(parts.count == 5)
        #expect(parts.allSatisfy { $0.count <= 190 && !$0.isEmpty })
    }
}
