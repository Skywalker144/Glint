import SwiftUI
import GlintCore

struct HistoryCard: View {
    let item: HistoryItem
    let retranslate: () -> Void
    @ViewState<Bool> private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.original).font(.system(size: 12)).foregroundStyle(SettingsPalette.secondary)
                .lineLimit(expanded ? nil : 1).textSelection(.enabled)
            Text(NativeMarkdown.plainText(item.translated)).lineLimit(expanded ? nil : 2).textSelection(.enabled)
            HStack {
                Text(Language.label(item.source) + " → " + Language.label(item.target))
                Spacer()
                Text(StoredDate.display(item.createdAt, time: true))
            }.font(.system(size: 11)).foregroundStyle(SettingsPalette.secondary)
            HStack {
                Button(expanded ? "收起" : "展开全文") { expanded.toggle() }
                Spacer(minLength: 0)
                CopyButton(title: "复制原文", text: item.original)
                CopyButton(title: "复制译文", text: NativeMarkdown.plainText(item.translated))
                Button("重新翻译", action: retranslate)
            }.font(.system(size: 11)).buttonStyle(GlintButtonStyle())
        }.padding(16).background(SettingsPalette.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(SettingsPalette.border, lineWidth: 0.5))
    }
}
