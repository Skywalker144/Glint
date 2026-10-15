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
            model.currentEntry = VocabularyEntry.parse(model.output, language: "en", definitionLanguage: "zh-CN")
            if !model.isFavorite { model.toggleFavorite() }
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
                    model.resizeSettings = { controller.fitHeight($0) }
                    controller.show()
                    try await Task.sleep(for: .milliseconds(300))
                    try snapshot(controller.window, at: output.appendingPathComponent("settings-\(tab.rawValue)-\(dark ? "dark" : "light").png"))
                    controller.hide()
                }
            }
            NSApp.appearance = NSAppearance(named: .aqua)
            delegate.openVocabulary()
            try await Task.sleep(for: .milliseconds(300))
            try snapshot(delegate.vocabularyWindow!.window, at: output.appendingPathComponent("vocabulary.png"))
            let plain = NativeMarkdown.plainText("**普通译文**\n\n- [链接](https://example.com)\n\n`code`")
            guard plain.contains("普通译文"), plain.contains("链接"), !plain.contains("**"), !plain.contains("](https") else { throw GlintError.message("纯文本复制检查失败") }
            try Data("原生窗口、三个宽度、深浅主题、横向拖动顶边与内容稳定、词典、流式完成高度、阅读位置保持、回到最新、富文本、公式、设置、生词本与纯文本复制检查通过\n".utf8).write(to: output.appendingPathComponent("result.txt"))
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
