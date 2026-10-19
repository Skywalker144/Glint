import Testing
import AppKit
import GlintCore
@testable import Glint

@MainActor
struct SelectionTextTests {
    @Test func menuCopyPrecedesOtherStrategies() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        var shortcuts = 0, accessibilityReads = 0
        let reader = SelectionTextReader(
            pasteboard: pasteboard, isSourceActive: { true },
            menuCopy: { {
                pasteboard.clearContents()
                pasteboard.setString("First\nSecond", forType: .string)
                return true
            } },
            shortcutCopy: { shortcuts += 1; return false },
            accessibilityText: { accessibilityReads += 1; return "FirstSecond" }
        )
        #expect(try await reader.read() == "First\nSecond")
        #expect(shortcuts == 0 && accessibilityReads == 0)
    }

    @Test func menuWithoutTextFallsBackToShortcut() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Original", forType: .string)
        var steps: [String] = []
        let reader = SelectionTextReader(
            pasteboard: pasteboard, isSourceActive: { true },
            menuCopy: { { steps.append("menu"); return true } },
            shortcutCopy: {
                steps.append("shortcut")
                #expect(pasteboard.string(forType: .string) == "Original")
                pasteboard.clearContents()
                pasteboard.setString("First\nSecond", forType: .string)
                return true
            },
            accessibilityText: { steps.append("accessibility"); return "FirstSecond" }
        )
        #expect(try await reader.read() == "First\nSecond")
        #expect(steps == ["menu", "shortcut"])
        #expect(pasteboard.string(forType: .string) == "Original")
    }

    @Test func failedCopyActionsFallBackToAccessibility() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        var steps: [String] = []
        let reader = SelectionTextReader(
            pasteboard: pasteboard, isSourceActive: { true },
            menuCopy: { { steps.append("menu"); return false } },
            shortcutCopy: { steps.append("shortcut"); return false },
            accessibilityText: { steps.append("accessibility"); return "First\nSecond" }
        )
        #expect(try await reader.read() == "First\nSecond")
        #expect(steps == ["menu", "shortcut", "accessibility"])
    }

    @Test func failedMenuActionRestoresClipboardBeforeNextStrategy() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Original", forType: .string)
        let reader = SelectionTextReader(
            pasteboard: pasteboard, isSourceActive: { true },
            menuCopy: { {
                pasteboard.clearContents()
                pasteboard.setString("Partial copy", forType: .string)
                return false
            } },
            shortcutCopy: {
                #expect(pasteboard.string(forType: .string) == "Original")
                pasteboard.clearContents()
                pasteboard.setString("First\nSecond", forType: .string)
                return true
            },
            accessibilityText: { nil }
        )
        #expect(try await reader.read() == "First\nSecond")
        #expect(pasteboard.string(forType: .string) == "Original")
    }

    @Test func copyWaitsForTextAfterPasteboardClears() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Original", forType: .string)
        let reader = SelectionTextReader(
            pasteboard: pasteboard, isSourceActive: { true },
            menuCopy: { {
                pasteboard.clearContents()
                _ = Task { @MainActor in
                    try await Task.sleep(for: .milliseconds(50))
                    pasteboard.setString("First\nSecond", forType: .string)
                }
                return true
            } },
            shortcutCopy: { Issue.record("Shortcut should not run"); return false },
            accessibilityText: { Issue.record("Accessibility should not run"); return nil }
        )
        #expect(try await reader.read() == "First\nSecond")
        #expect(pasteboard.string(forType: .string) == "Original")
    }

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
            pasteboard: pasteboard, isSourceActive: { true }, menuCopy: { nil },
            shortcutCopy: {
                copies += 1
                pasteboard.clearContents()
                return editor.writeSelection(to: pasteboard, types: editor.writablePasteboardTypes)
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
        let input = InputScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: InputScrollView.maximumAutomaticHeight))
        let view = try #require(input.documentView as? InputTextView)
        view.string = text
        #expect(view.string == source)
        input.layoutText()
        #expect(view.frame.height > input.contentSize.height)
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func copiedTextKeepsInternalLineEndings(separator: String) async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let source = "One" + separator + separator + "Two\tThree"
        let reader = SelectionTextReader(
            pasteboard: pasteboard, isSourceActive: { true }, menuCopy: { nil },
            shortcutCopy: { pasteboard.clearContents(); pasteboard.setString("  " + source + "  ", forType: .string); return true },
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
            pasteboard: pasteboard, isSourceActive: { true }, menuCopy: { nil },
            shortcutCopy: { copies += 1; return true },
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
            pasteboard: pasteboard, isSourceActive: { true }, menuCopy: { nil },
            shortcutCopy: { pasteboard.clearContents(); pasteboard.setData(Data([1, 2]), forType: .png); return true },
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
            pasteboard: pasteboard, isSourceActive: { active }, menuCopy: { nil },
            shortcutCopy: { pasteboard.clearContents(); pasteboard.setString("Selection", forType: .string); active = false; return true },
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
            pasteboard: pasteboard, isSourceActive: { true }, menuCopy: { nil },
            shortcutCopy: {
                started = true
                _ = Task { @MainActor in
                    try await Task.sleep(for: .milliseconds(50))
                    pasteboard.clearContents()
                    pasteboard.setString("Selected\ntext", forType: .string)
                }
                return true
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
