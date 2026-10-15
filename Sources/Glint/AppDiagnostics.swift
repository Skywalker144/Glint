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
            NSApp.appearance = NSAppearance(named: .aqua)
            model.output = "# 富文本\n\n**粗体**、*斜体*、[链接](https://example.com)、`code`\n\n- 第一项\n- 第二项\n\n| 原文 | 译文 |\n| --- | --- |\n| apple | 苹果 |\n\n$$x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}$$"
            delegate.translator.window.setContentSize(CGSize(width: 420, height: 400))
            try await Task.sleep(for: .milliseconds(350))
            try snapshot(delegate.translator.window, at: output.appendingPathComponent("rich-text.png"))
            for tab in ["general", "translate", "ai", "hotkeys", "permissions", "history", "about"] {
                let controller = GlintWindowController(title: "设置", size: CGSize(width: 640, height: 562), root: SettingsView(model: model, tab: tab))
                model.resizeSettings = { controller.fitHeight($0) }
                controller.show()
                try await Task.sleep(for: .milliseconds(300))
                try snapshot(controller.window, at: output.appendingPathComponent("settings-\(tab).png"))
                controller.hide()
            }
            delegate.openVocabulary()
            try await Task.sleep(for: .milliseconds(300))
            try snapshot(delegate.vocabularyWindow!.window, at: output.appendingPathComponent("vocabulary.png"))
            let plain = NativeMarkdown.plainText("**普通译文**\n\n- [链接](https://example.com)\n\n`code`")
            guard plain.contains("普通译文"), plain.contains("链接"), !plain.contains("**"), !plain.contains("](https") else { throw GlintError.message("纯文本复制检查失败") }
            try Data("原生窗口、三个宽度、深浅主题、词典、富文本、公式、设置、生词本与纯文本复制检查通过\n".utf8).write(to: output.appendingPathComponent("result.txt"))
            NSApp.terminate(nil)
        } catch {
            try? Data(error.localizedDescription.utf8).write(to: output.appendingPathComponent("failure.txt"))
            fputs("UI verification failed: \(error)\n", stderr)
            exit(1)
        }
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
