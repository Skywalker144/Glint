import SwiftUI
import GlintCore

struct VocabularyView: View {
    @Bindable var model: AppModel
    @ViewState<String> private var search = ""
    @ViewState<String> private var sort = "recent"
    @ViewState<String?> private var selected: String?
    @ViewState<VocabularyEntry?> private var pendingRemoval: VocabularyEntry?
    var filtered: [VocabularyEntry] {
        let query = search.precomposedStringWithCanonicalMapping.trimmed.lowercased()
        return model.vocabulary.filter { query.isEmpty || ($0.headword + "\n" + $0.translated).precomposedStringWithCanonicalMapping.lowercased().contains(query) }
            .sorted { sort == "queries" && $0.queryCount != $1.queryCount ? $0.queryCount > $1.queryCount : $0.createdAt > $1.createdAt }
    }
    var selectedEntry: VocabularyEntry? { filtered.first { $0.id == selected } ?? filtered.first }
    var body: some View {
        WindowCard {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("生词本").font(.system(size: 15, weight: .bold))
                    Text(search.isEmpty ? "\(model.vocabulary.count) 个词" : "\(filtered.count) / \(model.vocabulary.count) 个词").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    WindowDragArea().frame(height: 22).frame(maxWidth: .infinity)
                    IconButton(symbol: "xmark", label: "关闭生词本", action: model.closeVocabulary)
                }.padding(.horizontal, 14).padding(.vertical, 8)
                HStack(spacing: 10) {
                    NavigationSearchField(text: $search, placeholder: "搜索单词或释义", moveSelection: moveSelection)
                        .modifier(FieldSurface())
                    ChoiceMenu(title: "排序方式", value: sort == "recent" ? "最近收藏" : "查询次数从高到低", selection: $sort) {
                        Text("最近收藏").tag("recent"); Text("查询次数从高到低").tag("queries")
                    }.frame(width: 174)
                }.padding(.horizontal, 18).padding(.vertical, 12)
                Divider()
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ScrollViewReader { reader in
                            ScrollView {
                                LazyVStack(spacing: 3) {
                                    ForEach(filtered) { entry in
                                        Button { selected = entry.id } label: {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(entry.headword).font(.system(size: 15, weight: .semibold))
                                                Text("\(Language.label(entry.language)) · 查询 \(entry.queryCount) 次").font(.system(size: 11)).foregroundStyle(Theme.muted)
                                            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                                .background(selectedEntry?.id == entry.id ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 10))
                                        }.buttonStyle(.plain).id(entry.id)
                                    }
                                }.padding(8)
                            }.onChange(of: selectedEntry?.id) { _, id in if let id { reader.scrollTo(id) } }
                        }.frame(width: max(180, geometry.size.width * 0.36))
                        Divider()
                        ScrollView {
                            if let entry = selectedEntry {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(entry.headword).font(.system(size: 23, weight: .bold)).textSelection(.enabled)
                                    if !entry.pronunciation.isEmpty { Text(entry.pronunciation).foregroundStyle(Theme.muted).textSelection(.enabled) }
                                    Text("收藏于 \(StoredDate.display(entry.createdAt)) · 收藏后查询 \(entry.queryCount) 次").font(.system(size: 12)).foregroundStyle(Theme.muted)
                                    HStack(spacing: 8) {
                                        SpeechButton(speech: model.speech, channel: "vocabulary:" + entry.id, label: "朗读单词") {
                                            model.speech.speak(entry.headword, language: entry.language, proxy: model.settings.proxy, channel: "vocabulary:" + entry.id)
                                        }
                                        CopyButton(title: "复制释义", text: NativeMarkdown.plainText(entry.translated))
                                        Button("在翻译窗打开") { model.openTranslation(entry.headword) }.buttonStyle(GlintButtonStyle())
                                    }
                                    RichText(text: entry.definition).fixedSize(horizontal: false, vertical: true)
                                    Button("取消收藏", role: .destructive) { pendingRemoval = entry }.buttonStyle(GlintButtonStyle()).padding(.top, 8)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                            } else {
                                Text(model.vocabulary.isEmpty ? "查词后点击 ☆，把单词收入生词本" : "没有匹配的词条").foregroundStyle(Theme.muted).padding(20)
                            }
                        }.frame(maxWidth: .infinity)
                    }
                }
                Divider()
                HStack { Text("查询次数从收藏后开始统计").font(.system(size: 12)).foregroundStyle(Theme.muted); Spacer() }.padding(.horizontal, 18).padding(.vertical, 9)
            }
        }.onExitCommand(perform: model.closeVocabulary)
            .onChange(of: selectedEntry?.id) { _, _ in
                if model.speech.channel.hasPrefix("vocabulary:") { model.speech.stop() }
            }
            .alert("取消收藏此词条？", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
                Button("取消", role: .cancel) { pendingRemoval = nil }
                Button("取消收藏", role: .destructive) {
                    if let entry = pendingRemoval { model.removeFavorite(entry.id) }
                    pendingRemoval = nil
                }
            } message: { Text("取消收藏「\(pendingRemoval?.headword ?? "")」会同时删除它的查询次数。") }
    }
    func moveSelection(_ offset: Int) {
        guard !filtered.isEmpty else { return }
        let index = selectedEntry.flatMap { entry in filtered.firstIndex { $0.id == entry.id } } ?? 0
        selected = filtered[min(filtered.count - 1, max(0, index + offset))].id
    }
}
