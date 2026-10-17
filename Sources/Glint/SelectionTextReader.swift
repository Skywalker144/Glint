import AppKit
import GlintCore

@MainActor
struct SelectionTextReader {
    let pasteboard: NSPasteboard
    let isSourceActive: () -> Bool
    let modifiers: () -> NSEvent.ModifierFlags
    let copy: () -> Void
    let accessibilityText: () async -> String?

    func read() async throws -> String {
        try Task.checkCancellation()
        guard isSourceActive() else { return "" }
        for _ in 0..<80 {
            if modifiers().intersection([.option, .command, .control, .shift]).isEmpty { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        guard isSourceActive() else { return "" }
        guard modifiers().intersection([.option, .command, .control, .shift]).isEmpty else { throw GlintError.message("请松开快捷键的修饰键，再试一次划词翻译。") }
        try Task.checkCancellation()
        let saved = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
        let initialCount = pasteboard.changeCount
        copy()
        for _ in 0..<30 {
            await Task.detached { try? await Task.sleep(for: .milliseconds(25)) }.value
            if pasteboard.changeCount != initialCount {
                let text = pasteboard.string(forType: .string) ?? ""
                pasteboard.clearContents()
                let items = saved.map { data in
                    let item = NSPasteboardItem()
                    data.forEach { item.setData($0.value, forType: $0.key) }
                    return item
                }
                pasteboard.writeObjects(items)
                try Task.checkCancellation()
                guard isSourceActive() else { return "" }
                if !text.trimmed.isEmpty { return text.trimmed }
                break
            }
        }
        try Task.checkCancellation()
        guard isSourceActive() else { return "" }
        let direct = await accessibilityText()
        try Task.checkCancellation()
        guard isSourceActive() else { return "" }
        return direct?.trimmed ?? ""
    }
}
