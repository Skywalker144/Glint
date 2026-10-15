import SwiftUI
import GlintCore

struct VocabularyView: View {
    @Bindable var model: AppModel
    @ViewState<String> private var search = ""
    @ViewState<String> private var sort = "recent"
    @ViewState<String?> private var selected: String?
    @FocusState private var searchFocused: Bool
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
                    TextField("搜索单词或释义", text: $search).textFieldStyle(.plain).padding(.horizontal, 11).frame(height: 38).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border, lineWidth: 1)).focused($searchFocused)
                    Picker("排序方式", selection: $sort) { Text("最近收藏").tag("recent"); Text("查询次数从高到低").tag("queries") }.labelsHidden().frame(width: 174)
                }.padding(.horizontal, 18).padding(.vertical, 12)
                Divider()
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ScrollView {
                            LazyVStack(spacing: 3) {
                                ForEach(filtered) { entry in
                                    Button { selected = entry.id } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(entry.headword).font(.system(size: 15, weight: .semibold))
                                            Text("\(Language.label(entry.language)) · 查询 \(entry.queryCount) 次").font(.system(size: 11)).foregroundStyle(Theme.muted)
                                        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                            .background(selectedEntry?.id == entry.id ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 10))
                                    }.buttonStyle(.plain)
                                }
                            }.padding(8)
                        }.frame(width: max(180, geometry.size.width * 0.36))
                        Divider()
                        ScrollView {
                            if let entry = selectedEntry {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(entry.headword).font(.system(size: 23, weight: .bold)).textSelection(.enabled)
                                    Text("收藏于 \(StoredDate.display(entry.createdAt)) · 收藏后查询 \(entry.queryCount) 次").font(.system(size: 12)).foregroundStyle(Theme.muted)
                                    RichText(text: entry.translated).fixedSize(horizontal: false, vertical: true)
                                    Button("取消收藏") { model.removeFavorite(entry.id) }.buttonStyle(GlintButtonStyle()).padding(.top, 8)
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
        }.onAppear { searchFocused = true }.onExitCommand(perform: model.closeVocabulary)
    }
}
