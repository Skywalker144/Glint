import Testing
import AppKit
import SwiftUI
import GlintCore
@testable import Glint

@MainActor
struct TranslatorLayoutTests {
    @Test func inputCentersShortTextAndKeepsLongTextScrollable() throws {
        _ = NSApplication.shared
        let font = NSFont.systemFont(ofSize: 14)
        let height = ceil(NSLayoutManager().defaultLineHeight(for: font) * 2.5) + 16
        let scroll = InputScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: height))
        let text = try #require(scroll.documentView as? InputTextView)
        text.string = "你好 Hello"
        scroll.layoutSubtreeIfNeeded()
        scroll.layoutText()
        let manager = try #require(text.layoutManager)
        let container = try #require(text.textContainer)
        let used = manager.usedRect(for: container)
        #expect(abs(text.textContainerOrigin.y + used.midY - scroll.contentSize.height / 2) <= 1)
        text.string = String(repeating: "原文输入需要保留多行和滚动。\n", count: 20)
        scroll.layoutText()
        #expect(scroll.frame.height == height)
        #expect(text.frame.height > scroll.contentSize.height)
        #expect(text.textContainerInset.height == 8)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: text.frame.height - scroll.contentSize.height))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(scroll.contentView.bounds.minY > 0)
        #expect(abs(scroll.contentView.bounds.maxY - text.frame.height) < 1)
        text.string = "短原文"
        scroll.layoutText()
        #expect(text.frame.height == scroll.contentSize.height)
        #expect(abs(scroll.contentView.bounds.minY) < 1)
    }

    @Test func inputScrollbarOverlaysAtTheRightEdgeOutsideTheClearButtonSpace() throws {
        _ = NSApplication.shared
        let scroll = InputScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 60))
        let text = try #require(scroll.documentView as? InputTextView)
        text.string = String(repeating: "检查原文滚动条与清空按钮。\n", count: 20)
        scroll.layoutSubtreeIfNeeded()
        scroll.layoutText()
        let scroller = try #require(scroll.verticalScroller)
        let container = try #require(text.textContainer)
        #expect(scroll.scrollerStyle == .overlay)
        #expect(scroll.autohidesScrollers)
        #expect(scroller.controlSize == .small)
        #expect(abs(scroll.contentSize.width - scroll.bounds.width) < 1)
        #expect(container.containerSize.width <= scroll.contentSize.width - 48)
    }

    @Test func inputStartsAtOneLineAndGrowsOnlyToAutomaticLimit() async throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".cache/input-height-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: try LocalStore(directory: directory))
        let controller = GlintWindowController(title: "Test", size: CGSize(width: 420, height: 150), translator: true, root: TranslatorView(model: model))
        defer { controller.window.close() }
        controller.pinned = { true }
        model.resizeTranslator = { [weak controller] in controller?.fitHeight($0) }
        controller.show()
        let root = try #require(controller.window.contentView)
        let maximum = ceil(NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: 14)) * 2.5) + 16
        for (source, expected) in [("", 40.0), ("短原文", 40.0), (String(repeating: "多行原文\n", count: 20), maximum), ("清空后重新输入", 40.0)] {
            model.input = source
            try await Task.sleep(for: .milliseconds(100))
            root.layoutSubtreeIfNeeded()
            let scroll = try #require(descendants(of: root, type: InputScrollView.self).first)
            #expect(abs(scroll.frame.height - expected) < 0.5)
        }
    }

    @Test(arguments: [false, true]) func inputBordersResizeEditorAndKeepOppositeEdgeAnchored(topEdge: Bool) async throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".cache/input-resize-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: try LocalStore(directory: directory))
        model.input = "原文"
        model.output = "译文保持完整可见。"
        var requestedHeight: CGFloat = 0
        let controller = GlintWindowController(title: "Test", size: CGSize(width: 420, height: 200), translator: true, root: TranslatorView(model: model))
        defer { controller.window.close() }
        controller.pinned = { true }
        model.resizeTranslator = { [weak controller] in requestedHeight = $0; controller?.fitHeight($0) }
        controller.show()
        try await Task.sleep(for: .milliseconds(120))
        let root = try #require(controller.window.contentView)
        root.layoutSubtreeIfNeeded()
        let input = try #require(descendants(of: root, type: InputScrollView.self).first)
        let result = try #require(descendants(of: root, type: TranslationScrollView.self).first)
        let handle = try #require(descendants(of: root, type: InputHeightHandle.Handle.self).first { $0.edge == (topEdge ? .top : .bottom) })
        for _ in 0..<100 {
            root.layoutSubtreeIfNeeded()
            if input.frame.height == 40, handle.height == 40, result.preferredHeight < 100,
               requestedHeight > 0, abs(controller.window.frame.height - ceil(requestedHeight)) < 0.5 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(input.frame.height == 40)
        let inputFrame = input.convert(input.bounds, to: nil)
        let handleFrame = handle.convert(handle.bounds, to: nil)
        #expect(!inputFrame.intersects(handleFrame))
        #expect(abs(topEdge ? handleFrame.minY - inputFrame.maxY : inputFrame.minY - handleFrame.maxY) < 1)
        let handleCenter = NSPoint(x: handleFrame.midX, y: handleFrame.midY)
        let handleParent = try #require(handle.superview)
        let inputParent = try #require(input.superview)
        #expect(handle.hitTest(handleParent.convert(handleCenter, from: nil)) === handle)
        #expect(input.hitTest(inputParent.convert(handleCenter, from: nil)) == nil)
        NSCursor.iBeam.set()
        let cursorEvent = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: handle.convert(NSPoint(x: handle.bounds.midX, y: handle.bounds.midY), to: nil), modifierFlags: [], timestamp: 0, windowNumber: controller.window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        handle.mouseEntered(with: cursorEvent)
        #expect(NSCursor.current == NSCursor.resizeUpDown)
        NSCursor.iBeam.set()
        handle.cursorUpdate(with: cursorEvent)
        #expect(NSCursor.current == NSCursor.resizeUpDown)
        NSCursor.arrow.set()
        let frame = controller.window.frame
        let resultTop = controller.window.convertToScreen(result.convert(result.bounds, to: nil)).maxY
        let point = handle.convert(NSPoint(x: handle.bounds.midX, y: handle.bounds.midY), to: nil)
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: controller.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let drag = try #require(NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: point.x, y: point.y + (topEdge ? 80 : -80)), modifierFlags: [], timestamp: 0, windowNumber: controller.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        handle.mouseDown(with: down)
        handle.mouseDragged(with: drag)
        handle.mouseUp(with: drag)
        try await Task.sleep(for: .milliseconds(120))
        root.layoutSubtreeIfNeeded()
        #expect(abs(input.frame.height - 120) < 0.5)
        #expect(abs(controller.window.frame.height - frame.height - 80) < 0.5)
        #expect(abs(controller.window.frame.maxY - frame.maxY - (topEdge ? 80 : 0)) < 0.5)
        #expect(abs(controller.window.convertToScreen(result.convert(result.bounds, to: nil)).maxY - resultTop + (topEdge ? 0 : 80)) < 0.5)
        #expect(result.convert(result.bounds, to: nil).minY >= TranslatorLayout.bottomInset + TranslatorLayout.footerHeight + TranslatorLayout.resultFooterSpacing)
        model.input = String(repeating: "手动高度不被内容覆盖。\n", count: 20)
        try await Task.sleep(for: .milliseconds(100))
        #expect(abs(input.frame.height - 120) < 0.5)
        let reset = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: controller.window.windowNumber, context: nil, eventNumber: 0, clickCount: 2, pressure: 1))
        handle.mouseDown(with: reset)
        try await Task.sleep(for: .milliseconds(100))
        #expect(abs(input.frame.height - InputScrollView.maximumAutomaticHeight) < 0.5)
        model.clearInput()
        try await Task.sleep(for: .milliseconds(100))
        #expect(input.frame.height == 40)
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

    @Test func resultFadesOnlyTheEdgesWithHiddenContentAndKeepsScrollbarUnmasked() throws {
        _ = NSApplication.shared
        let scroll = TranslationScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        scroll.update(text: String(repeating: "滚动时让译文边缘逐渐隐去。\n", count: 30), revision: UUID(), appearance: .aqua)
        let mask = try #require(scroll.contentView.layer?.mask as? CAGradientLayer)
        try #require(mask.colors?.count == 4)
        let topIndex = scroll.contentView.isFlipped ? 0 : 3
        let bottomIndex = 3 - topIndex
        #expect(mask.frame == scroll.contentView.bounds)
        #expect((mask.colors as? [CGColor])?[topIndex].alpha == 1)
        #expect((mask.colors as? [CGColor])?[bottomIndex].alpha == 0)
        #expect(scroll.layer?.mask == nil)
        #expect(scroll.verticalScroller?.layer?.mask == nil)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 60))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(mask.frame == scroll.contentView.bounds)
        #expect((mask.colors as? [CGColor])?[topIndex].alpha == 0)
        #expect((mask.colors as? [CGColor])?[bottomIndex].alpha == 0)
        scroll.jumpToLatest()
        #expect((mask.colors as? [CGColor])?[topIndex].alpha == 0)
        #expect((mask.colors as? [CGColor])?[bottomIndex].alpha == 1)
        scroll.setFrameSize(NSSize(width: 420, height: 80))
        scroll.tile()
        #expect(mask.frame == scroll.contentView.bounds)
        scroll.update(text: "完整的短译文", revision: UUID(), appearance: .darkAqua)
        #expect((mask.colors as? [CGColor])?[topIndex].alpha == 1)
        #expect((mask.colors as? [CGColor])?[bottomIndex].alpha == 1)
    }

    @Test func resultScrollbarSitsNearWindowEdgeAndPreservesTextInsets() async throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".cache/result-scrollbar-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: try LocalStore(directory: directory))
        model.output = String(repeating: "译文保持原有文字边距。\n", count: 30)
        let controller = GlintWindowController(title: "Test", size: CGSize(width: 420, height: 500), translator: true, root: TranslatorView(model: model))
        defer { controller.window.close() }
        controller.pinned = { true }
        model.resizeTranslator = { [weak controller] in controller?.fitHeight($0) }
        controller.show()
        try await Task.sleep(for: .milliseconds(160))
        let root = try #require(controller.window.contentView)
        root.layoutSubtreeIfNeeded()
        let result = try #require(descendants(of: root, type: TranslationScrollView.self).first)
        let scroller = try #require(result.verticalScroller as? ThinScroller)
        let inputScroller = try #require(descendants(of: root, type: InputScrollView.self).first?.verticalScroller)
        let widthHandle = try #require(descendants(of: root, type: WindowWidthHandle.Handle.self).first)
        let text = try #require(result.documentView as? RichTextView)
        #expect(type(of: scroller) == type(of: inputScroller))
        #expect(scroller.controlSize == .small)
        #expect(result.scrollerStyle == .overlay)
        #expect(result.autohidesScrollers)
        #expect(abs(result.convert(result.bounds, to: nil).maxX - controller.window.frame.width) < 0.5)
        #expect(abs(result.convert(result.contentView.frame, to: nil).minX - TranslatorLayout.resultInset) < 0.5)
        #expect(text.textContainer?.containerSize.width == controller.window.frame.width - TranslatorLayout.resultInset * 2)
        let knob = scroller.convert(scroller.knobFrame, to: nil)
        #expect(knob.width == 3)
        #expect(!knob.intersects(widthHandle.convert(widthHandle.bounds, to: nil)))
        #expect(!scroller.convert(scroller.bounds, to: nil).intersects(widthHandle.convert(widthHandle.bounds, to: nil)))
        #expect(scroller.testPart(NSPoint(x: knob.midX, y: knob.midY)) == .knob)
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

    @Test func translatorDisablesNativeEdgeResizingAndAllowsOffscreenFrames() throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main)
        let controller = GlintWindowController(title: "Test", size: CGSize(width: 420, height: 300), translator: true, resizable: true, root: Color.clear)
        defer { controller.window.close() }
        #expect(!controller.window.styleMask.contains(.resizable))
        for origin in [
            NSPoint(x: screen.visibleFrame.minX + 100, y: screen.visibleFrame.minY - 160),
            NSPoint(x: screen.visibleFrame.minX - 200, y: screen.visibleFrame.minY + 100),
            NSPoint(x: screen.visibleFrame.maxX - 200, y: screen.visibleFrame.minY + 100),
            NSPoint(x: screen.visibleFrame.minX + 100, y: screen.visibleFrame.maxY - 100)
        ] {
            let frame = NSRect(origin: origin, size: controller.window.frame.size)
            #expect(controller.window.constrainFrameRect(frame, to: screen) == frame)
        }
        let settings = GlintWindowController(title: "Settings", size: CGSize(width: 800, height: 650), resizable: true, root: Color.clear)
        defer { settings.window.close() }
        #expect(settings.window.styleMask.contains(.resizable))
    }

    @Test func windowDragCanCrossScreenBottomWhileContentHeightChanges() async throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main)
        let controller = GlintWindowController(title: "Test", size: CGSize(width: 420, height: 150), translator: true, root: WindowDragArea().frame(height: 24))
        defer { controller.window.close() }
        controller.window.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 100, y: screen.visibleFrame.minY + 50))
        let root = try #require(controller.window.contentView)
        root.layoutSubtreeIfNeeded()
        let handle = try #require(descendants(of: root, type: WindowDragArea.DragView.self).first)
        let frame = controller.window.frame
        let point = NSPoint(x: 100, y: 120)
        let pointer = controller.window.convertPoint(toScreen: point)
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: controller.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        handle.mouseDown(with: down)
        controller.fitHeight(300)
        try await Task.sleep(for: .milliseconds(40))
        let target = controller.window.convertPoint(fromScreen: NSPoint(x: pointer.x + 40, y: pointer.y - 160))
        let drag = try #require(NSEvent.mouseEvent(with: .leftMouseDragged, location: target, modifierFlags: [], timestamp: 0, windowNumber: controller.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        handle.mouseDragged(with: drag)
        handle.mouseUp(with: drag)
        #expect(controller.window.frame.minY < screen.visibleFrame.minY)
        #expect(controller.window.frame.height == 300)
        #expect(abs(controller.window.frame.maxY - frame.maxY + 160) < 0.5)
        #expect(abs(controller.window.frame.minX - frame.minX - 40) < 0.5)
    }

    @Test func heightGrowthCanExtendBelowScreenAndPreservesTopEdge() async throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main)
        let controller = GlintWindowController(title: "Test", size: CGSize(width: 420, height: 150), translator: true, root: Color.clear)
        defer { controller.window.close() }
        let top = screen.visibleFrame.minY + 240
        controller.window.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 100, y: top - 150))
        for height in [180.0, 220.0, 260.0, 500.0, 720.0, 180.0] {
            controller.fitHeight(height)
            try await Task.sleep(for: .milliseconds(40))
            #expect(abs(controller.window.frame.maxY - top) < 0.5)
            #expect(abs(controller.window.frame.height - min(height, 600)) < 0.5)
        }
    }

    @Test func movingAndShowingPinnedWindowPreservesOffscreenPositionAndHeight() async throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main)
        let controller = GlintWindowController(title: "Test", size: CGSize(width: 420, height: 500), translator: true, root: Color.clear)
        defer { controller.window.close() }
        controller.pinned = { true }
        for space in [240.0, 520.0, 300.0] {
            let top = screen.visibleFrame.minY + space
            controller.window.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 100, y: top - controller.window.frame.height))
            controller.fitHeight(500)
            controller.show()
            try await Task.sleep(for: .milliseconds(40))
            #expect(abs(controller.window.frame.maxY - top) < 0.5)
            #expect(controller.window.frame.height == 500)
        }
    }

    @Test func oversizedTranslatorContentKeepsHeaderAtWindowTop() throws {
        _ = NSApplication.shared
        let controller = GlintWindowController(title: "Test", size: CGSize(width: 420, height: 150), translator: true, root:
            VStack(spacing: 0) {
                WindowDragArea().frame(height: 24)
                Color.clear.frame(height: 276)
            }.fixedSize(horizontal: false, vertical: true)
        )
        defer { controller.window.close() }
        controller.pinned = { true }
        controller.show()
        let root = try #require(controller.window.contentView)
        root.layoutSubtreeIfNeeded()
        var views = [root]
        var index = 0
        while index < views.count {
            views.append(contentsOf: views[index].subviews)
            index += 1
        }
        let drag = try #require(views.compactMap { $0 as? WindowDragArea.DragView }.first)
        #expect(controller.window.frame.height == 150)
        #expect(abs(drag.convert(drag.bounds, to: nil).maxY - controller.window.frame.height) < 0.5)
    }

    @Test(arguments: [false, true]) func streamingKeepsControlsAndReadingPositionStable(nearScreenBottom: Bool) async throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main)
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".cache/layout-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: try LocalStore(directory: directory))
        model.input = String(repeating: "用于验证原文自动高度的长文本。\n", count: 20)
        model.streaming = true
        let controller = GlintWindowController(title: "Test", size: CGSize(width: 420, height: 150), translator: true, root: TranslatorView(model: model))
        defer { controller.window.close() }
        controller.pinned = { true }
        var requestedHeight: CGFloat?
        model.resizeTranslator = { [weak controller] height in
            requestedHeight = height
            controller?.fitHeight(height)
        }
        if nearScreenBottom {
            controller.window.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 100, y: screen.visibleFrame.minY + 90))
        }
        controller.show()
        let top = controller.window.frame.maxY
        let maximumHeight: CGFloat = 600
        let root = try #require(controller.window.contentView)
        for _ in 0..<100 {
            root.layoutSubtreeIfNeeded()
            let input = descendants(of: root, type: InputScrollView.self).first
            if let requestedHeight, abs(controller.window.frame.height - min(requestedHeight, maximumHeight)) < 0.5,
               input?.frame.height == InputScrollView.maximumAutomaticHeight { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let initialHeight = try #require(requestedHeight)
        try #require(abs(controller.window.frame.height - min(initialHeight, maximumHeight)) < 0.5)
        var views = [root]
        var index = 0
        while index < views.count {
            views.append(contentsOf: views[index].subviews)
            index += 1
        }
        let input = try #require(views.compactMap { $0 as? InputScrollView }.first)
        let result = try #require(views.compactMap { $0 as? TranslationScrollView }.first)
        let rendered = try #require(result.documentView as? RichTextView)
        let drag = try #require(views.compactMap { $0 as? WindowDragArea.DragView }.first)
        let expectedInputHeight = ceil(NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: 14)) * 2.5) + 16
        #expect(abs(input.frame.height - expectedInputHeight) < 0.5)
        let inputTop = input.convert(input.bounds, to: nil).maxY - controller.window.frame.height
        let resultTop = result.convert(result.bounds, to: nil).maxY - controller.window.frame.height
        let footerHeight = TranslatorLayout.bottomInset + TranslatorLayout.footerHeight + TranslatorLayout.resultFooterSpacing
        let maximumResultHeight = maximumHeight + resultTop - footerHeight
        for _ in 0..<16 {
            model.output += "这是一段持续追加、超过窗口剩余高度的译文。\n"
            for _ in 0..<100 {
                root.layoutSubtreeIfNeeded()
                if rendered.string == model.output.trimmed,
                   abs(result.frame.height - min(result.preferredHeight, maximumResultHeight)) < 0.5,
                   result.convert(result.bounds, to: nil).minY >= footerHeight { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            try #require(rendered.string == model.output.trimmed)
            #expect(abs(result.frame.height - min(result.preferredHeight, maximumResultHeight)) < 0.5)
            #expect(abs(controller.window.frame.maxY - top) < 0.5)
            #expect(controller.window.frame.height <= maximumHeight)
            #expect(root.bounds.contains(drag.convert(drag.bounds, to: nil)))
            #expect(root.bounds.contains(input.convert(input.bounds, to: nil)))
            #expect(result.convert(result.bounds, to: nil).minY >= footerHeight)
            #expect(abs(input.convert(input.bounds, to: nil).maxY - controller.window.frame.height - inputTop) < 0.5)
            #expect(abs(result.convert(result.bounds, to: nil).maxY - controller.window.frame.height - resultTop) < 0.5)
            #expect(abs(result.contentView.bounds.minY) < 0.5)
        }
        #expect(result.distanceFromEnd > 2)
        #expect(result.showsLatest)
        result.contentView.scroll(to: NSPoint(x: 0, y: 40))
        result.reflectScrolledClipView(result.contentView)
        let readingOffset = result.contentView.bounds.minY
        model.output += "继续追加译文。\n"
        for _ in 0..<100 {
            root.layoutSubtreeIfNeeded()
            if rendered.string == model.output.trimmed { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(rendered.string == model.output.trimmed)
        #expect(abs(result.contentView.bounds.minY - readingOffset) < 0.5)
        let finalFrame = controller.window.frame
        model.streaming = false
        try await Task.sleep(for: .milliseconds(80))
        #expect(controller.window.frame == finalFrame)
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

    private func descendants<View: NSView>(of root: NSView, type: View.Type) -> [View] {
        (root as? View).map { [$0] } ?? root.subviews.flatMap { descendants(of: $0, type: type) }
    }
}
