#if DEBUG
import AppKit
import SwiftUI
import GlintCore

@MainActor
enum AppDiagnostics {
    static func run(delegate: AppDelegate, output: URL) async {
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let model = delegate.model!
            model.changeSettings { $0.engine = "openai"; $0.pinned = true }
            model.input = "abstract"
            model.output = "**abstract** /ˈæbstrækt/\nadj. 抽象的；难以理解的\nn. 摘要；梗概\n\n---\n\n例句 An abstract idea. — 一个抽象的想法。"
            model.displayMode = .dict
            model.source = "en"; model.target = "zh-CN"
            model.currentEntry = VocabularyEntry.parse(model.output, language: "en", definitionLanguage: "zh-CN")
            if !model.isFavorite { model.toggleFavorite() }
            try model.store.addHistory(.init(original: model.input, translated: model.output, source: "en", target: "zh-CN", engine: "openai"))
            try model.store.addHistory(.init(original: "A longer original text.\n" + String(repeating: "Read the complete paragraph. ", count: 6), translated: String(repeating: "展开后可以阅读完整的原文与译文。", count: 12), source: "en", target: "zh-CN", engine: "google"))
            model.history = model.store.history
            for dark in [false, true] {
                NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                for width in [360.0, 420.0, 820.0] {
                    let window = delegate.translator!.window
                    window.setContentSize(CGSize(width: width, height: window.frame.height))
                    delegate.translator.show()
                    try await Task.sleep(for: .milliseconds(350))
                    try snapshot(window, at: output.appendingPathComponent("translator-\(Int(width))-\(dark ? "dark" : "light").png"))
                    guard window.frame.height >= 100, window.frame.height <= 600 else { throw GlintError.message("翻译窗口高度异常") }
                }
            }
            let resizeWindow = delegate.translator!.window
            model.input = String(repeating: "横向拖动保持原文区域高度。", count: 4)
            model.output = String(repeating: "译文根据窗口宽度重新排版，顶部控件保持原位。", count: 12)
            try await Task.sleep(for: .milliseconds(150))
            guard let resizeRoot = resizeWindow.contentView,
                  let handle = descendants(of: resizeRoot, type: WindowWidthHandle.Handle.self).first,
                  let input = descendants(of: resizeRoot, type: InputScrollView.self).first,
                  let result = descendants(of: resizeRoot, type: TranslationScrollView.self).first,
                  let down = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: resizeWindow.frame.width - 3, y: 60), modifierFlags: [], timestamp: 0, windowNumber: resizeWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { throw GlintError.message("无法建立窗口拖动检查") }
            let resizeTop = resizeWindow.frame.maxY
            let inputTop = resizeWindow.frame.height - input.convert(input.bounds, to: nil).maxY
            let inputHeight = input.frame.height
            let resultTop = resizeWindow.frame.height - result.convert(result.bounds, to: nil).maxY
            handle.mouseDown(with: down)
            for width in [760.0, 680.0, 600.0, 520.0, 440.0, 360.0, 440.0, 560.0, 680.0, 820.0] {
                guard let drag = NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: width - 3, y: 60), modifierFlags: [], timestamp: 0, windowNumber: resizeWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { throw GlintError.message("无法建立拖动事件") }
                handle.mouseDragged(with: drag)
                try await Task.sleep(for: .milliseconds(80))
                guard abs(resizeWindow.frame.maxY - resizeTop) < 0.5,
                      abs(resizeWindow.frame.height - input.convert(input.bounds, to: nil).maxY - inputTop) < 0.5,
                      abs(input.frame.height - inputHeight) < 0.5,
                      abs(resizeWindow.frame.height - result.convert(result.bounds, to: nil).maxY - resultTop) < 0.5 else { throw GlintError.message("横向拖动布局异常 width=\(width), top=\(resizeWindow.frame.maxY)/\(resizeTop), inputTop=\(resizeWindow.frame.height - input.convert(input.bounds, to: nil).maxY)/\(inputTop), inputHeight=\(input.frame.height)/\(inputHeight), resultTop=\(resizeWindow.frame.height - result.convert(result.bounds, to: nil).maxY)/\(resultTop)") }
                if [360.0, 600.0, 820.0].contains(width) {
                    try snapshot(resizeWindow, at: output.appendingPathComponent("translator-resize-\(Int(width)).png"))
                }
            }
            handle.mouseUp(with: down)
            NSApp.appearance = NSAppearance(named: .darkAqua)
            let translator = delegate.translator!
            translator.window.setContentSize(CGSize(width: 420, height: translator.window.frame.height))
            model.input = ""; model.translate()
            model.input = "Hello world."; model.streaming = true
            try await Task.sleep(for: .milliseconds(200))
            try snapshot(translator.window, at: output.appendingPathComponent("translator-waiting.png"))
            model.output = "你好，世界。"
            try await Task.sleep(for: .milliseconds(200))
            let streamingHeight = translator.window.frame.height
            try snapshot(translator.window, at: output.appendingPathComponent("translator-streaming.png"))
            model.streaming = false
            try await Task.sleep(for: .milliseconds(200))
            guard abs(translator.window.frame.height - streamingHeight) <= 1 else { throw GlintError.message("翻译完成时操作栏导致窗口跳动") }
            try snapshot(translator.window, at: output.appendingPathComponent("translator-complete.png"))
            model.editInput("Hello again.")
            try await Task.sleep(for: .milliseconds(200))
            guard model.resultIsStale, !model.canSwap else { throw GlintError.message("编辑原文后未使旧结果失效") }
            try snapshot(translator.window, at: output.appendingPathComponent("translator-edited.png"))
            model.restoreHistory(model.history[0])
            model.clearInput()
            guard model.input.isEmpty, model.output.isEmpty else { throw GlintError.message("清空输入未清空结果") }
            model.input = "Hello world."
            model.streaming = true
            model.output = String(repeating: "这是一段用于验证流式阅读位置的译文。\n", count: 35)
            try await Task.sleep(for: .milliseconds(200))
            guard let scroll = descendants(of: translator.window.contentView!, type: TranslationScrollView.self).first else { throw GlintError.message("缺少译文滚动视图") }
            guard scroll.distanceFromEnd <= 1 else { throw GlintError.message("流式译文没有跟随底部") }
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 60))
            scroll.reflectScrolledClipView(scroll.contentView)
            let readingOffset = scroll.contentView.bounds.minY
            model.output += String(repeating: "继续追加译文。\n", count: 12)
            try await Task.sleep(for: .milliseconds(200))
            guard abs(scroll.contentView.bounds.minY - readingOffset) <= 1, scroll.showsLatest else { throw GlintError.message("追加译文抢夺阅读位置") }
            try snapshot(translator.window, at: output.appendingPathComponent("translator-reading.png"))
            scroll.jumpToLatest()
            guard scroll.distanceFromEnd <= 1 else { throw GlintError.message("回到最新译文失败") }
            model.streaming = false
            NSApp.appearance = NSAppearance(named: .aqua)
            model.input = ""; model.translate(); model.input = "Markdown"
            model.output = "# 富文本\n\n**粗体**、*斜体*、[链接](https://example.com)、`code`\n\n- 第一项\n- 第二项\n\n| 原文 | 译文 |\n| --- | --- |\n| apple | 苹果 |\n\n$$x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}$$"
            delegate.translator.window.setContentSize(CGSize(width: 420, height: 400))
            try await Task.sleep(for: .milliseconds(350))
            try snapshot(delegate.translator.window, at: output.appendingPathComponent("rich-text.png"))
            for dark in [false, true] {
                NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                for tab in SettingsPage.allCases {
                    let controller = GlintWindowController(title: "设置", size: SettingsView.size, root: SettingsView(model: model, tab: tab))
                    controller.show()
                    try await Task.sleep(for: .milliseconds(300))
                    try snapshot(controller.window, at: output.appendingPathComponent("settings-\(tab.rawValue)-\(dark ? "dark" : "light").png"))
                    controller.hide()
                }
            }
            NSApp.appearance = NSAppearance(named: .aqua)
            let second = VocabularyEntry.parse("**serene** /səˈriːn/\nadj. 平静的；安详的", language: "en", definitionLanguage: "zh-CN")!
            try model.store.addVocabulary(second); model.vocabulary = model.store.vocabulary
            delegate.openVocabulary()
            try await Task.sleep(for: .milliseconds(300))
            try snapshot(delegate.vocabularyWindow!.window, at: output.appendingPathComponent("vocabulary.png"))
            guard let vocabularyRoot = delegate.vocabularyWindow?.window.contentView,
                  let search = descendants(of: vocabularyRoot, type: NavigationSearchField.SearchField.self).first,
                  let editor = search.currentEditor(),
                  let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: delegate.vocabularyWindow!.window.windowNumber, context: nil, characters: String(UnicodeScalar(NSDownArrowFunctionKey)!), charactersIgnoringModifiers: String(UnicodeScalar(NSDownArrowFunctionKey)!), isARepeat: false, keyCode: 125) else { throw GlintError.message("生词本搜索框未获得焦点") }
            editor.keyDown(with: down)
            try await Task.sleep(for: .milliseconds(150))
            try snapshot(delegate.vocabularyWindow!.window, at: output.appendingPathComponent("vocabulary-keyboard.png"))
            guard descendants(of: vocabularyRoot, type: RichTextView.self).contains(where: { $0.string.hasPrefix("adj. 抽象的") }) else { throw GlintError.message("生词本方向键导航或词头去重失败") }
            delegate.openSettings()
            let settingsWindow = delegate.settingsWindow!.window
            settingsWindow.setContentSize(CGSize(width: 800, height: 800))
            try await Task.sleep(for: .milliseconds(150))
            guard abs(settingsWindow.contentView!.frame.height - 800) < 1 else { throw GlintError.message("设置窗口高度无法调整") }
            try snapshot(settingsWindow, at: output.appendingPathComponent("settings-resized.png"))
            settingsWindow.performClose(nil)
            guard !settingsWindow.isVisible else { throw GlintError.message("标准关闭窗口动作失败") }
            delegate.translator.hide(); model.openTranslation("")
            guard delegate.translator.window.isVisible, delegate.translator.window.isMainWindow, delegate.translator.window.isKeyWindow else { throw GlintError.message("重译入口未将翻译窗置前") }
            let plain = NativeMarkdown.plainText("**普通译文**\n\n- [链接](https://example.com)\n\n`code`")
            guard plain.contains("普通译文"), plain.contains("链接"), !plain.contains("**"), !plain.contains("](https") else { throw GlintError.message("纯文本复制检查失败") }
            try Data("原生窗口、三个宽度、深浅主题、横向拖动、词典、流式高度与阅读位置、编辑失效与清空、富文本与公式、设置垂直缩放、标准关闭、重译显示、生词本方向键与词头去重、纯文本复制检查通过\n".utf8).write(to: output.appendingPathComponent("result.txt"))
            NSApp.terminate(nil)
        } catch {
            try? Data(error.localizedDescription.utf8).write(to: output.appendingPathComponent("failure.txt"))
            fputs("UI verification failed: \(error)\n", stderr)
            exit(1)
        }
    }
    static func descendants<View: NSView>(of root: NSView, type: View.Type) -> [View] {
        (root as? View).map { [$0] } ?? root.subviews.flatMap { descendants(of: $0, type: type) }
    }
    static func snapshot(_ window: NSWindow, at url: URL) throws {
        guard let view = window.contentView else { throw GlintError.message("窗口缺少视图") }
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw GlintError.message("无法创建窗口快照") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw GlintError.message("无法编码窗口快照") }
        try png.write(to: url)
    }
}
#endif
