import Foundation

public final class LocalStore {
    public let directory: URL
    public private(set) var settings: AppSettings
    public private(set) var history: [HistoryItem]
    public private(set) var vocabulary: [VocabularyEntry]

    public init(directory: URL, legacyDirectories: [URL] = []) throws {
        self.directory = directory
        let fm = FileManager.default
        let names = ["settings.json", "history.json", "vocabulary.json"]
        let existing = names.contains { fm.fileExists(atPath: directory.appendingPathComponent($0).path) }
        let source = existing ? directory : legacyDirectories.first { candidate in names.contains { fm.fileExists(atPath: candidate.appendingPathComponent($0).path) } } ?? directory
        func read<T: Decodable>(_ name: String, default fallback: T) throws -> T {
            let file = source.appendingPathComponent(name)
            guard fm.fileExists(atPath: file.path) else { return fallback }
            do { return try JSONDecoder().decode(T.self, from: Data(contentsOf: file)) }
            catch { throw GlintError.message("读取 \(name) 失败，原文件已保留：\(error.localizedDescription)") }
        }
        settings = try read("settings.json", default: AppSettings())
        history = try read("history.json", default: [HistoryItem]())
        let vocabularyURL = source.appendingPathComponent("vocabulary.json")
        if fm.fileExists(atPath: vocabularyURL.path) {
            let data = try Data(contentsOf: vocabularyURL)
            if let entries = try? JSONDecoder().decode([VocabularyEntry].self, from: data) {
                guard Set(entries.map(\.id)).count == entries.count, entries.allSatisfy({ $0.queryCount >= 0 }) else { throw GlintError.message("生词本查询计数无效，原文件已保留") }
                vocabulary = entries
            } else {
                struct Legacy: Decodable {
                    struct Entry: Decodable { let word: String; let translated: String; let source: String; let target: String; let createdAt: String }
                    let version: Int
                    let entries: [Entry]
                }
                let old = try JSONDecoder().decode(Legacy.self, from: data)
                guard old.version == 1 else { throw GlintError.message("生词本版本无效，原文件已保留") }
                var entries: [String: VocabularyEntry] = [:]
                for value in old.entries {
                    guard var entry = VocabularyEntry.parse(value.translated, language: value.source, definitionLanguage: value.target), !value.word.trimmed.isEmpty, StoredDate.parse(value.createdAt) != nil else { throw GlintError.message("旧版生词本包含无法迁移的词条，原文件已保留") }
                    entry.createdAt = min(entries[entry.id]?.createdAt ?? value.createdAt, value.createdAt)
                    entries[entry.id] = entry
                }
                vocabulary = entries.values.sorted { $0.createdAt > $1.createdAt }
                if source == directory {
                    let backup = directory.appendingPathComponent("vocabulary.json.v1.bak")
                    if !fm.fileExists(atPath: backup.path) { try data.write(to: backup, options: .withoutOverwriting) }
                    else if try Data(contentsOf: backup) != data { throw GlintError.message("生词本备份冲突，原文件已保留") }
                }
            }
        } else { vocabulary = [] }
        if Catalog.prompts["LEGACY_SYSTEM_PROMPTS"]?.strings.contains(settings.systemPrompt) == true { settings.systemPrompt = Catalog.defaultSystemPrompt }
        if Catalog.prompts["LEGACY_DICTIONARY_PROMPTS"]?.strings.contains(settings.dictionaryPrompt) == true { settings.dictionaryPrompt = Catalog.defaultDictionaryPrompt }
        if settings.providers["deepseek"]?.model == "deepseek-chat" { settings.providers["deepseek"]?.model = "deepseek-v4-flash" }
        if source != directory {
            let staging = directory.deletingLastPathComponent().appendingPathComponent(".glint-import-" + UUID().uuidString)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: staging) }
            for name in names where fm.fileExists(atPath: source.appendingPathComponent(name).path) {
                try fm.copyItem(at: source.appendingPathComponent(name), to: staging.appendingPathComponent(name + ".electron-backup"))
            }
            try Self.write(settings, to: staging.appendingPathComponent("settings.json"))
            try Self.write(history, to: staging.appendingPathComponent("history.json"))
            try Self.write(vocabulary, to: staging.appendingPathComponent("vocabulary.json"))
            if fm.fileExists(atPath: directory.path) {
                for name in try fm.contentsOfDirectory(atPath: staging.path) {
                    try fm.moveItem(at: staging.appendingPathComponent(name), to: directory.appendingPathComponent(name))
                }
            } else { try fm.moveItem(at: staging, to: directory) }
        } else {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
    public func saveSettings(_ value: AppSettings) throws {
        try Self.write(value, to: directory.appendingPathComponent("settings.json"))
        settings = value
    }
    public func addHistory(_ item: HistoryItem) throws {
        guard !item.original.isEmpty && !item.translated.isEmpty else { return }
        let next = Array(([item] + history.filter { $0.original != item.original || $0.translated != item.translated }).prefix(100))
        try Self.write(next, to: directory.appendingPathComponent("history.json")); history = next
    }
    public func clearHistory() throws {
        try Self.write([HistoryItem](), to: directory.appendingPathComponent("history.json")); history = []
    }
    public func addVocabulary(_ entry: VocabularyEntry) throws {
        guard let valid = VocabularyEntry.parse(entry.translated, language: entry.language, definitionLanguage: entry.definitionLanguage), valid.id == entry.id else { throw GlintError.message("没有可收藏的完整词条") }
        if vocabulary.contains(where: { $0.id == entry.id }) { return }
        try persistVocabulary([valid] + vocabulary)
    }
    public func removeVocabulary(_ id: String) throws { try persistVocabulary(vocabulary.filter { $0.id != id }) }
    public func recordLookup(_ entry: VocabularyEntry?) throws {
        guard let entry, let index = vocabulary.firstIndex(where: { $0.id == entry.id }) else { return }
        var next = vocabulary
        next[index].queryCount += 1
        next[index].lastQueriedAt = ISO8601DateFormatter().string(from: Date())
        try persistVocabulary(next)
    }
    private func persistVocabulary(_ next: [VocabularyEntry]) throws {
        try Self.write(next, to: directory.appendingPathComponent("vocabulary.json")); vocabulary = next
    }
    public static func write<T: Encodable>(_ value: T, to file: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: file, options: .atomic)
    }
}
