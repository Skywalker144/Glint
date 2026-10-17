import Testing
import AppKit
import GlintCore
@testable import Glint

@MainActor
struct SelectionTextTests {
    @Test func copiedSelectionPreservesLineBreaksAndRestoresPasteboard() async throws {
        _ = NSApplication.shared
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let original = NSPasteboardItem()
        original.setString("Existing clipboard", forType: .string)
        original.setString("<b>Existing clipboard</b>", forType: .html)
        let binaryType = NSPasteboard.PasteboardType("com.glint.test-data")
        let binary = Data([0, 1, 127, 255])
        original.setData(binary, forType: binaryType)
        #expect(pasteboard.writeObjects([original]))
        let source = "First line\nSecond line\n\nThird paragraph\n\tIndented line"
        let editor = NSTextView()
        editor.isRichText = false
        editor.string = source
        editor.isSelectable = true
        editor.setSelectedRange(NSRange(location: 0, length: (source as NSString).length))
        var copies = 0, accessibilityReads = 0
        let reader = SelectionTextReader(
            pasteboard: pasteboard, isSourceActive: { true }, modifiers: { [] },
            copy: {
                copies += 1
                pasteboard.clearContents()
                #expect(editor.writeSelection(to: pasteboard, types: editor.writablePasteboardTypes))
            },
            accessibilityText: { accessibilityReads += 1; return "First lineSecond lineThird paragraphIndented line" }
        )
        let text = try await reader.read()
        #expect(text == source)
        #expect(copies == 1 && accessibilityReads == 0)
        #expect(pasteboard.pasteboardItems?.count == 1)
        #expect(pasteboard.string(forType: .string) == "Existing clipboard")
        #expect(pasteboard.string(forType: .html) == "<b>Existing clipboard</b>")
        #expect(pasteboard.data(forType: binaryType) == binary)
        let input = InputScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 40))
        let view = try #require(input.documentView as? InputTextView)
        view.string = text
        #expect(view.string == source)
        #expect(input.layoutText() > 40)
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func copiedTextKeepsInternalLineEndings(separator: String) async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let source = "One" + separator + separator + "Two\tThree"
        let reader = SelectionTextReader(
            pasteboard: pasteboard, isSourceActive: { true }, modifiers: { [] },
            copy: { pasteboard.clearContents(); pasteboard.setString("  " + source + "  ", forType: .string) },
            accessibilityText: { "OneTwoThree" }
        )
        #expect(try await reader.read() == source)
        #expect(pasteboard.pasteboardItems?.isEmpty != false)
    }

    @Test func unavailableCopyFallsBackWithoutReadingOldClipboard() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Unrelated clipboard", forType: .string)
        var copies = 0, accessibilityReads = 0
        let reader = SelectionTextReader(
            pasteboard: pasteboard, isSourceActive: { true }, modifiers: { [] },
            copy: { copies += 1 },
            accessibilityText: { accessibilityReads += 1; return "Fallback\nselection" }
        )
        #expect(try await reader.read() == "Fallback\nselection")
        #expect(copies == 1 && accessibilityReads == 1)
        #expect(pasteboard.string(forType: .string) == "Unrelated clipboard")
    }

    @Test func nonTextCopyRestoresAllItemsBeforeFallback() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let originals = ["First", "Second"].map { value in
            let item = NSPasteboardItem()
            item.setString(value, forType: .string)
            return item
        }
        #expect(pasteboard.writeObjects(originals))
        let reader = SelectionTextReader(
            pasteboard: pasteboard, isSourceActive: { true }, modifiers: { [] },
            copy: { pasteboard.clearContents(); pasteboard.setData(Data([1, 2]), forType: .png) },
            accessibilityText: {
                #expect(pasteboard.pasteboardItems?.map { $0.string(forType: .string) } == ["First", "Second"])
                return "Fallback\nselection"
            }
        )
        #expect(try await reader.read() == "Fallback\nselection")
        #expect(pasteboard.pasteboardItems?.map { $0.string(forType: .string) } == ["First", "Second"])
    }

    @Test func sourceChangeAbortsAfterRestoringClipboard() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Existing clipboard", forType: .string)
        var active = true, accessibilityReads = 0
        let reader = SelectionTextReader(
            pasteboard: pasteboard, isSourceActive: { active }, modifiers: { [] },
            copy: { pasteboard.clearContents(); pasteboard.setString("Selection", forType: .string); active = false },
            accessibilityText: { accessibilityReads += 1; return "Selection" }
        )
        #expect(try await reader.read().isEmpty)
        #expect(accessibilityReads == 0)
        #expect(pasteboard.string(forType: .string) == "Existing clipboard")
    }

    @Test func cancellationRestoresPendingCopyAndSkipsFallback() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Existing clipboard", forType: .string)
        var started = false, accessibilityReads = 0
        let reader = SelectionTextReader(
            pasteboard: pasteboard, isSourceActive: { true }, modifiers: { [] },
            copy: {
                started = true
                _ = Task { @MainActor in
                    try await Task.sleep(for: .milliseconds(50))
                    pasteboard.clearContents()
                    pasteboard.setString("Selected\ntext", forType: .string)
                }
            },
            accessibilityText: { accessibilityReads += 1; return "Selection" }
        )
        var completed = false
        let task = Task {
            defer { completed = true }
            return try await reader.read()
        }
        while !started && !completed { await Task.yield() }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled selection returned text")
        } catch is CancellationError {
        }
        #expect(accessibilityReads == 0)
        #expect(pasteboard.string(forType: .string) == "Existing clipboard")
    }
}
