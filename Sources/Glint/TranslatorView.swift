import SwiftUI
import AppKit
import GlintCore

struct TranslatorHeaderHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct TranslatorView: View {
    @Bindable var model: AppModel
    @ViewState<CGFloat> private var inputHeight: CGFloat = 40
    @ViewState<CGFloat> private var headerHeight: CGFloat = 0
    var body: some View {
        WindowCard {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Text("译").font(.system(size: 15, weight: .bold)).frame(width: 24, height: 24)
                        WindowDragArea().frame(height: 24).frame(maxWidth: .infinity)
                        IconButton(symbol: "chevron.left", label: "上一条历史 (⌘[)") { model.browseHistory(older: true) }
                            .disabled(!model.canBrowseOlder).keyboardShortcut("[", modifiers: .command)
                        IconButton(symbol: "chevron.right", label: "下一条历史 (⌘])") { model.browseHistory(older: false) }
                            .disabled(!model.canBrowseNewer).keyboardShortcut("]", modifiers: .command)
                        IconButton(symbol: "book.closed", label: "生词本", action: model.showVocabulary)
                        IconButton(symbol: "gearshape", label: "设置", action: model.showSettings)
                        IconButton(symbol: "pin", label: "钉住窗口", selected: model.settings.pinned) { model.changeSettings { $0.pinned.toggle() } }
                        IconButton(symbol: "xmark", label: "关闭 (Esc)", action: model.hideTranslator)
                    }.padding(.horizontal, TranslatorLayout.inset).padding(.vertical, 6)
                    VStack(spacing: TranslatorLayout.inset) {
                        NativeInput(text: Binding(get: { model.input }, set: model.editInput), selectAllOnFocus: model.selectAllOnFocus, focusRevision: model.inputFocusRevision, resultFocusRevision: model.resultFocusRevision, submit: { model.translate() }, dismiss: model.hideTranslator, height: $inputHeight)
                            .frame(height: inputHeight).padding(.trailing, model.input.isEmpty ? 0 : 28)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border, lineWidth: 1))
                            .overlay(alignment: .topTrailing) {
                                if !model.input.isEmpty { IconButton(symbol: "xmark.circle.fill", label: "清空输入", action: model.clearInput).padding(8) }
                            }
                        HStack(spacing: 6) {
                            SpeechButton(speech: model.speech, channel: "input", label: "朗读原文", action: model.speakInput).disabled(model.input.trimmed.isEmpty)
                            languageMenu(source: true)
                            IconButton(symbol: "arrow.left.arrow.right", label: "交换语言", action: model.swapLanguages).disabled(!model.canSwap)
                            languageMenu(source: false)
                            Spacer(minLength: 0)
                            HStack(spacing: 0) {
                                Button { model.translate(mode: .dict) } label: { Text("词典").frame(width: 40, height: 22) }.buttonStyle(GlintButtonStyle(selected: model.displayMode == .dict, horizontalPadding: 0, verticalPadding: 0))
                                    .disabled(!model.supportsDictionary).help(model.supportsDictionary ? "查询词典" : "词典需要 AI 翻译引擎")
                                Button { model.translate(mode: .translate) } label: { Text("翻译").frame(width: 40, height: 22) }.buttonStyle(GlintButtonStyle(selected: model.displayMode == .translate, horizontalPadding: 0, verticalPadding: 0))
                            }.font(.system(size: 12)).padding(2).background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border, lineWidth: 1))
                        }.frame(height: 28)
                        if model.resultIsStale {
                            HStack {
                                Text("原文已修改，按回车重新翻译").font(.system(size: 11)).foregroundStyle(Theme.muted)
                                Spacer(minLength: 0)
                                Button("重新翻译") { model.translate() }.font(.system(size: 12)).buttonStyle(GlintButtonStyle())
                            }
                        }
                        if !model.status.isEmpty {
                            HStack(alignment: .top) {
                                Text(model.status).font(.system(size: 12)).foregroundStyle(Theme.muted).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                if model.failed { Button("重试") { model.translate() }.buttonStyle(GlintButtonStyle()) }
                            }
                        }
                    }.padding(.horizontal, TranslatorLayout.inset)
                }.background(GeometryReader { proxy in Color.clear.preference(key: TranslatorHeaderHeight.self, value: proxy.size.height) })
                if model.streaming || !model.output.isEmpty {
                    TranslationResult(model: model, maximumHeight: model.translatorMaximumHeight - headerHeight - TranslatorLayout.inset - TranslatorLayout.bottomInset)
                        .id(model.resultRevision)
                        .padding(.horizontal, TranslatorLayout.inset).padding(.top, TranslatorLayout.inset)
                }
            }.padding(.bottom, TranslatorLayout.bottomInset)
            .onPreferenceChange(TranslatorHeaderHeight.self) { headerHeight = $0 }
        }.overlay(alignment: .trailing) { WindowWidthHandle().frame(width: 6).padding(.vertical, 16) }.fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in Color.clear.onChange(of: proxy.size.height, initial: true) { _, height in model.resizeTranslator(height) } })
    }
    @ViewBuilder func languageMenu(source isSource: Bool) -> some View {
        let selected = isSource ? model.overrides.source : model.overrides.target
        let detected = isSource ? model.source : model.target
        let label = Catalog.languages.first { $0.code == selected }.map { $0.shortLabel ?? $0.label }
            ?? (Language.valid(detected) ? "自动 · " + Language.label(detected).prefix(1) : "自动")
        ChoiceMenu(title: isSource ? "原文语言" : "译文语言", value: label, selection: Binding(get: { selected }, set: { value in
            if isSource { model.overrides.source = value } else { model.overrides.target = value }
            model.translate()
        }), compact: true) {
            Text("自动").tag("")
            Divider()
            ForEach(Catalog.languages) { Text($0.label).tag($0.code) }
        }.help((isSource ? "原文语言：" : "译文语言：") + Language.label(selected.isEmpty ? detected : selected))
    }
}
