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
        #expect(scroll.layoutText() == 62)
        #expect(text.frame.height > scroll.contentSize.height)
        #expect(text.textContainerInset.height == 8)
    }

    @Test func resultFollowsStreamUntilReaderScrollsAway() {
        _ = NSApplication.shared
        let scroll = TranslationScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        let revision = UUID()
        let first = String(repeating: "这是一段足够长的流式译文。\n", count: 30)
        scroll.update(text: first, revision: revision, streaming: true, appearance: .aqua)
        #expect(scroll.followsEnd)
        #expect(scroll.distanceFromEnd <= 1)
        #expect(scroll.preferredHeight == 340)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 80))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(!scroll.followsEnd)
        let readingOffset = scroll.contentView.bounds.minY
        scroll.update(text: first + String(repeating: "追加的译文。\n", count: 15), revision: revision, streaming: true, appearance: .aqua)
        #expect(abs(scroll.contentView.bounds.minY - readingOffset) <= 1)
        #expect(scroll.showsLatest)
        scroll.jumpToLatest()
        #expect(scroll.followsEnd)
        #expect(!scroll.showsLatest)
        #expect(scroll.distanceFromEnd <= 1)
    }

    @Test func resultResetsForNewRequestAndPreservesSelectionOnAppend() throws {
        _ = NSApplication.shared
        let scroll = TranslationScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 100))
        let revision = UUID()
        let first = String(repeating: "Hello world.\n", count: 30)
        scroll.update(text: first, revision: revision, streaming: true, appearance: .aqua)
        let text = try #require(scroll.documentView as? RichTextView)
        text.setSelectedRange(NSRange(location: 0, length: 5))
        scroll.update(text: first + "More text.", revision: revision, streaming: false, appearance: .aqua)
        #expect(text.selectedRange() == NSRange(location: 0, length: 5))
        scroll.update(text: "短译文", revision: UUID(), streaming: false, appearance: .darkAqua)
        #expect(scroll.contentView.bounds.minY == 0)
        #expect(scroll.preferredHeight < 100)
        #expect(!scroll.showsLatest)
        #expect(text.string == "短译文")
    }

    @Test func streamingHeightDoesNotShrinkWhenMarkdownReflows() {
        _ = NSApplication.shared
        let scroll = TranslationScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        let revision = UUID()
        scroll.update(text: String(repeating: "待重排的内容。\n", count: 10), revision: revision, streaming: true, appearance: .aqua)
        let reservedHeight = scroll.preferredHeight
        scroll.update(text: "短译文", revision: revision, streaming: true, appearance: .aqua)
        #expect(scroll.preferredHeight == reservedHeight)
        scroll.update(text: "短译文", revision: revision, streaming: false, appearance: .aqua)
        #expect(scroll.preferredHeight == reservedHeight)
        scroll.update(text: "短译文", revision: revision, streaming: false, appearance: .aqua)
        #expect(scroll.preferredHeight == reservedHeight)
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
