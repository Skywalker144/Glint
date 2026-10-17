import AppKit
import GlintCore

@MainActor
struct SelectionTextReader {
    typealias CopyAction = @MainActor () -> Bool

    let pasteboard: NSPasteboard
    let isSourceActive: () -> Bool
    let menuCopy: () async -> CopyAction?
    let shortcutCopy: CopyAction
    let accessibilityText: () async -> String?

    func read() async throws -> String {
        try Task.checkCancellation()
        guard isSourceActive() else { return "" }
        let menuAction = await menuCopy()
        for action in [menuAction, shortcutCopy].compactMap({ $0 }) {
            try Task.checkCancellation()
            guard isSourceActive() else { return "" }
            let saved = (pasteboard.pasteboardItems ?? []).map { item in
                Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
            }
            let initialCount = pasteboard.changeCount
            let started = action()
            var copiedText: String?
            if started {
                for _ in 0..<30 {
                    if pasteboard.changeCount != initialCount, let text = pasteboard.string(forType: .string), !text.trimmed.isEmpty {
                        copiedText = text.trimmed
                        break
                    }
                    await Task.detached { try? await Task.sleep(for: .milliseconds(25)) }.value
                }
            }
            if pasteboard.changeCount != initialCount {
                pasteboard.clearContents()
                let items = saved.map { data in
                    let item = NSPasteboardItem()
                    data.forEach { item.setData($0.value, forType: $0.key) }
                    return item
                }
                pasteboard.writeObjects(items)
            }
            try Task.checkCancellation()
            guard isSourceActive() else { return "" }
            if let copiedText { return copiedText }
        }
        try Task.checkCancellation()
        guard isSourceActive() else { return "" }
        let direct = await accessibilityText()
        try Task.checkCancellation()
        guard isSourceActive() else { return "" }
        return direct?.trimmed ?? ""
    }
}
