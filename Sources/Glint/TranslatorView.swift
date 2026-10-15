import SwiftUI
import AppKit
import GlintCore

struct TranslatorView: View {
    @Bindable var model: AppModel
    @ViewState<CGFloat> private var inputHeight: CGFloat = 40
    @ViewState<CGFloat> private var resultHeight: CGFloat = 20
    var body: some View {
        WindowCard {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text("译").font(.system(size: 15, weight: .bold))
                    WindowDragArea().frame(height: 24).frame(maxWidth: .infinity)
                    IconButton(symbol: "book.closed", label: "生词本", action: model.showVocabulary)
                    IconButton(symbol: "gearshape", label: "设置", action: model.showSettings)
                    IconButton(symbol: "pin", label: "钉住窗口", selected: model.settings.pinned) { model.changeSettings { $0.pinned.toggle() } }
                    IconButton(symbol: "xmark", label: "关闭 (Esc)", action: model.hideTranslator)
                }.padding(.horizontal, 10).padding(.vertical, 3)
                VStack(spacing: 8) {
                    ZStack(alignment: .topLeading) {
                        if model.input.isEmpty { Text("输入或粘贴文字…").font(.system(size: 14)).foregroundStyle(Theme.muted).padding(.horizontal, 12).padding(.top, 9).allowsHitTesting(false) }
                        NativeInput(text: Binding(get: { model.input }, set: model.editInput), selectAllOnFocus: model.selectAllOnFocus, focusRevision: model.inputFocusRevision, resultFocusRevision: model.resultFocusRevision, submit: { model.translate() }, dismiss: model.hideTranslator, height: $inputHeight)
                    }.frame(height: inputHeight).background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border, lineWidth: 1))
                    HStack(spacing: 6) {
                        IconButton(symbol: "speaker.wave.2", label: "朗读原文", selected: model.speech.channel == "input", action: model.speakInput)
                        languageMenu(source: true)
                        IconButton(symbol: "arrow.left.arrow.right", label: "交换语言", action: model.swapLanguages).disabled(!model.canSwap)
                        languageMenu(source: false)
                        Spacer(minLength: 0)
                        if model.streaming { Button("停止", action: model.stop).buttonStyle(GlintButtonStyle()).font(.system(size: 12)) }
                        HStack(spacing: 0) {
                            Button("词典") { model.translate(mode: .dict) }.frame(width: 40, height: 22).background(model.displayMode == .dict ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
                            Button("翻译") { model.translate(mode: .translate) }.frame(width: 40, height: 22).background(model.displayMode == .translate ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain).font(.system(size: 12)).padding(2).background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border, lineWidth: 1))
                    }.frame(height: 28)
                    if !model.status.isEmpty {
                        HStack(alignment: .top) {
                            Text(model.status).font(.system(size: 12)).foregroundStyle(Theme.muted).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            if model.failed { Button("重试") { model.translate() }.buttonStyle(GlintButtonStyle()) }
                        }
                    }
                    if !model.output.isEmpty {
                        VStack(spacing: 4) {
                            ScrollView {
                                RichText(text: model.output, fontSize: 15).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(GeometryReader { proxy in Color.clear.preference(key: HeightPreference.self, value: proxy.size.height) }).padding(.horizontal, 12).padding(.vertical, 10)
                            }.frame(height: min(340, resultHeight + 20)).background(Theme.surface, in: RoundedRectangle(cornerRadius: 9)).onPreferenceChange(HeightPreference.self) { height in if height > 0 { resultHeight = height } }
                            if !model.streaming {
                                HStack(spacing: 6) {
                                    IconButton(symbol: "speaker.wave.2", label: "朗读译文", selected: model.speech.channel == "result", action: model.speakOutput)
                                    Spacer()
                                    if model.currentEntry != nil { IconButton(symbol: model.isFavorite ? "star.fill" : "star", label: model.isFavorite ? "取消收藏" : "收藏到生词本", action: model.toggleFavorite) }
                                    Button(model.copied ? "已复制" : "复制", action: model.copyResult).buttonStyle(GlintButtonStyle()).font(.system(size: 12))
                                }
                            }
                        }
                    }
                }.padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 6)
            }
        }.overlay(alignment: .trailing) { WindowWidthHandle().frame(width: 6).padding(.vertical, 16) }.fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in Color.clear.onChange(of: proxy.size.height, initial: true) { _, height in model.resizeTranslator(height) } })
    }
    @ViewBuilder func languageMenu(source isSource: Bool) -> some View {
        let selected = isSource ? model.overrides.source : model.overrides.target
        let detected = isSource ? model.source : model.target
        CompactLanguagePicker(selection: selected) { value in
            if isSource { model.overrides.source = value } else { model.overrides.target = value }
            model.translate()
        }.frame(width: 54, height: 26).help((isSource ? "原文语言：" : "译文语言：") + Language.label(selected.isEmpty ? detected : selected))
    }
}

struct CompactLanguagePicker: NSViewRepresentable {
    let selection: String
    let changed: (String) -> Void
    final class Control: NSPopUpButton {
        var changed: (String) -> Void = { _ in }
        override var intrinsicContentSize: NSSize { NSSize(width: 54, height: 26) }
        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            NSColor.adaptive(0xf4f4f5, 0x2a2a2d).setFill(); path.fill()
            NSColor.adaptive(0xe4e4e7, 0x38383c).setStroke(); path.lineWidth = 1; path.stroke()
            let code = selectedItem?.representedObject as? String ?? ""
            let text = Catalog.languages.first { $0.code == code }.map { $0.shortLabel ?? $0.label } ?? "自动"
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.adaptive(0x1a1a1a, 0xf2f2f5)]
            let size = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attrs)
        }
        @objc func selectLanguage() { changed(selectedItem?.representedObject as? String ?? ""); needsDisplay = true }
    }
    func makeNSView(context: Context) -> Control {
        let control = Control(frame: .zero, pullsDown: false)
        control.addItem(withTitle: "自动"); control.lastItem?.representedObject = ""
        control.menu?.addItem(.separator())
        for language in Catalog.languages { control.addItem(withTitle: language.label); control.lastItem?.representedObject = language.code }
        control.target = control; control.action = #selector(Control.selectLanguage)
        control.setAccessibilityLabel("选择语言")
        return control
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Control, context: Context) -> CGSize? { CGSize(width: 54, height: 26) }
    func updateNSView(_ view: Control, context: Context) {
        view.changed = changed
        view.select(view.itemArray.first { ($0.representedObject as? String) == selection })
        view.needsDisplay = true
    }
}
