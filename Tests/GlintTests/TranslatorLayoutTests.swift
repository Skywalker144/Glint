import Testing
import AppKit
import SwiftUI
@testable import Glint

@MainActor
struct TranslatorLayoutTests {
    @Test func inputCentersSingleLineAndKeepsLongInputScrollable() throws {
        _ = NSApplication.shared
        let scroll = InputScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 40))
        let text = try #require(scroll.documentView as? InputTextView)
        text.string = "你好 Hello"
        scroll.layoutSubtreeIfNeeded()
        let height = scroll.layoutText()
        let manager = try #require(text.layoutManager)
        let container = try #require(text.textContainer)
        let used = manager.usedRect(for: container)
        #expect(height == 40)
        #expect(abs(text.textContainerOrigin.y + used.midY - scroll.contentSize.height / 2) <= 1)
        text.string = "原文\n"
        #expect(scroll.layoutText() > 40)
        text.string = String(repeating: "原文输入需要保留多行和滚动。\n", count: 20)
        #expect(scroll.layoutText() == 140)
        #expect(text.frame.height > scroll.contentSize.height)
        #expect(text.textContainerInset.height == 8)
    }

    @Test func resultStaysAtTopWhileStreamingAndJumpsOnlyOnDemand() {
        _ = NSApplication.shared
        let scroll = TranslationScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        let revision = UUID()
        let first = String(repeating: "这是一段足够长的流式译文。\n", count: 30)
        scroll.update(text: first, revision: revision, appearance: .aqua)
        #expect(!scroll.followsEnd)
        #expect(scroll.contentView.bounds.minY == 0)
        #expect(scroll.showsLatest)
        #expect(scroll.distanceFromEnd > 2)
        #expect(scroll.preferredHeight == 340)
        scroll.update(text: first + String(repeating: "追加的译文。\n", count: 15), revision: revision, appearance: .aqua)
        #expect(scroll.contentView.bounds.minY == 0)
        #expect(!scroll.followsEnd)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 80))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(!scroll.followsEnd)
        let readingOffset = scroll.contentView.bounds.minY
        scroll.update(text: first + String(repeating: "追加的译文。\n", count: 30), revision: revision, appearance: .aqua)
        #expect(abs(scroll.contentView.bounds.minY - readingOffset) <= 1)
        #expect(scroll.showsLatest)
        scroll.jumpToLatest()
        #expect(scroll.followsEnd)
        #expect(!scroll.showsLatest)
        #expect(scroll.distanceFromEnd <= 1)
        scroll.update(text: first + String(repeating: "追加的译文。\n", count: 45), revision: revision, appearance: .aqua)
        #expect(scroll.distanceFromEnd <= 1)
    }

    @Test func resultResetsForNewRequestAndPreservesSelectionOnAppend() throws {
        _ = NSApplication.shared
        let scroll = TranslationScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 100))
        let revision = UUID()
        let first = String(repeating: "Hello world.\n", count: 30)
        scroll.update(text: first, revision: revision, appearance: .aqua)
        let text = try #require(scroll.documentView as? RichTextView)
        text.setSelectedRange(NSRange(location: 0, length: 5))
        scroll.update(text: first + "More text.", revision: revision, appearance: .aqua)
        #expect(text.selectedRange() == NSRange(location: 0, length: 5))
        scroll.update(text: "短译文", revision: UUID(), appearance: .darkAqua)
        #expect(!scroll.followsEnd)
        #expect(scroll.contentView.bounds.minY == 0)
        #expect(scroll.preferredHeight < 100)
        #expect(!scroll.showsLatest)
        #expect(text.string == "短译文")
    }

    @Test func resultHeightDoesNotShrinkWhenMarkdownReflows() {
        _ = NSApplication.shared
        let scroll = TranslationScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        let revision = UUID()
        scroll.update(text: String(repeating: "待重排的内容。\n", count: 10), revision: revision, appearance: .aqua)
        let reservedHeight = scroll.preferredHeight
        scroll.update(text: "短译文", revision: revision, appearance: .aqua)
        #expect(scroll.preferredHeight == reservedHeight)
        scroll.update(text: "短译文", revision: revision, appearance: .aqua)
        #expect(scroll.preferredHeight == reservedHeight)
    }

    @Test func resultHasNoExtraInsetAndReflowsOnResize() throws {
        _ = NSApplication.shared
        let scroll = TranslationScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        let revision = UUID()
        let source = String(repeating: "译文随着窗口宽度自然换行。", count: 6)
        scroll.update(text: source, revision: revision, appearance: .aqua)
        let narrowHeight = scroll.preferredHeight
        let text = try #require(scroll.documentView as? RichTextView)
        #expect(text.textContainerInset == .zero)
        scroll.setFrameSize(NSSize(width: 820, height: 120))
        scroll.tile()
        scroll.update(text: source, revision: revision, appearance: .aqua)
        #expect(scroll.preferredHeight < narrowHeight)
        scroll.update(text: "短译文", revision: UUID(), appearance: .aqua)
        let manager = try #require(text.layoutManager)
        #expect(scroll.preferredHeight <= ceil(manager.defaultLineHeight(for: .systemFont(ofSize: 15))) + 1)
    }

    @Test func widthReflowPreservesTheParagraphBeingRead() throws {
        _ = NSApplication.shared
        let scroll = TranslationScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        let source = (1...40).map { "第\($0)段：" + String(repeating: "保持正在阅读的段落，调整宽度时只重排当前内容。", count: 3) }.joined(separator: "\n")
        scroll.update(text: source, revision: UUID(), appearance: .aqua)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 180))
        scroll.reflectScrolledClipView(scroll.contentView)
        let text = try #require(scroll.documentView as? RichTextView)
        let manager = try #require(text.layoutManager)
        let container = try #require(text.textContainer)
        let glyph = manager.glyphIndex(for: NSPoint(x: 0, y: scroll.contentView.bounds.minY), in: container)
        let paragraph = (text.string as NSString).paragraphRange(for: NSRange(location: manager.characterIndexForGlyph(at: glyph), length: 0))
        scroll.setFrameSize(NSSize(width: 820, height: 120))
        scroll.tile()
        let newGlyph = manager.glyphIndex(for: NSPoint(x: 0, y: scroll.contentView.bounds.minY), in: container)
        #expect(NSLocationInRange(manager.characterIndexForGlyph(at: newGlyph), paragraph))
        #expect(!scroll.followsEnd)
    }

    @Test func widthDragPreservesTopAndCurrentHeight() async throws {
        _ = NSApplication.shared
        let controller = GlintWindowController(title: "Test", size: CGSize(width: 420, height: 150), translator: true, resizable: true, root: Color.clear)
        controller.window.setFrameOrigin(NSPoint(x: 100, y: 300))
        let handle = WindowWidthHandle.Handle(frame: NSRect(x: 414, y: 16, width: 6, height: 118))
        controller.window.contentView!.addSubview(handle)
        let top = controller.window.frame.maxY
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 417, y: 70), modifierFlags: [], timestamp: 0, windowNumber: controller.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        handle.mouseDown(with: event)
        for (width, height) in [(600.0, 220.0), (380.0, 300.0), (720.0, 180.0)] {
            controller.fitHeight(height)
            try await Task.sleep(for: .milliseconds(40))
            let drag = try #require(NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: width - 3, y: 70), modifierFlags: [], timestamp: 0, windowNumber: controller.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            handle.mouseDragged(with: drag)
            #expect(abs(controller.window.frame.width - width) < 0.5)
            #expect(abs(controller.window.frame.height - height) < 0.5)
            #expect(controller.window.frame.maxY == top)
        }
        handle.mouseUp(with: event)
        controller.window.close()
    }

    @Test func inputHeightChangesForEditsInsteadOfWidthChanges() async throws {
        _ = NSApplication.shared
        let scroll = InputScrollView(frame: NSRect(x: 0, y: 0, width: 820, height: 40))
        let text = try #require(scroll.documentView as? InputTextView)
        text.string = String(repeating: "原文只在编辑时调整高度", count: 5)
        var height: CGFloat = 40
        let input = NativeInput(text: .constant(text.string), selectAllOnFocus: false, focusRevision: 0, resultFocusRevision: 0, submit: {}, dismiss: {}, height: Binding(get: { height }, set: { height = $0 }))
        let coordinator = NativeInput.Coordinator(input)
        coordinator.measure(text)
        try await Task.sleep(for: .milliseconds(20))
        let originalHeight = height
        scroll.setFrameSize(NSSize(width: 360, height: originalHeight))
        coordinator.measure(text)
        try await Task.sleep(for: .milliseconds(20))
        #expect(height == originalHeight)
        text.string += "\n新增一行"
        coordinator.measure(text)
        try await Task.sleep(for: .milliseconds(20))
        #expect(height > originalHeight)
    }

    @Test func heightGrowthNearScreenBottomPreservesTopEdge() async throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main)
        let controller = GlintWindowController(title: "Test", size: CGSize(width: 420, height: 150), translator: true, root: Color.clear)
        let top = screen.visibleFrame.minY + 240
        controller.window.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 100, y: top - 150))
        let handle = WindowWidthHandle.Handle(frame: NSRect(x: 414, y: 16, width: 6, height: 118))
        controller.window.contentView!.addSubview(handle)
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 417, y: 70), modifierFlags: [], timestamp: 0, windowNumber: controller.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        var availableHeight: CGFloat = 0
        controller.onAvailableHeightChanged = { availableHeight = $0 }
        handle.mouseDown(with: event)
        controller.fitHeight(500)
        try await Task.sleep(for: .milliseconds(50))
        #expect(abs(controller.window.frame.maxY - top) < 0.5)
        #expect(abs(controller.window.frame.height - 240) < 0.5)
        #expect(abs(availableHeight - 240) < 0.5)
        controller.window.close()
    }

    @Test func heightRequestsUseLatestValueAndKeepTopEdge() async throws {
        _ = NSApplication.shared
        let controller = GlintWindowController(title: "Test", size: CGSize(width: 420, height: 150), translator: true, root: Color.clear)
        controller.window.setFrameOrigin(NSPoint(x: 100, y: 300))
        let top = controller.window.frame.maxY
        controller.fitHeight(240)
        controller.fitHeight(300)
        controller.fitHeight(180)
        try await Task.sleep(for: .milliseconds(100))
        #expect(controller.window.frame.height == 180)
        #expect(controller.window.frame.maxY == top)
        controller.window.close()
    }
}
