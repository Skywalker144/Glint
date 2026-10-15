import Testing
import Foundation
@testable import GlintCore

final class StorageTests {
    var root: URL!
    init() throws {
        root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".cache/tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    @Test func testPartialLegacySettingsKeepDefaults() throws {
        let data = Data(#"{"proxy":{"enabled":true},"dictionaryExtras":{"examples":true},"selectionPopupOptions":{"distance":24},"providers":{"openai":{"apiKey":"fixture"}},"openrouter":{"apiKey":"legacy","model":"old"}}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(settings.proxy.enabled)
        #expect(settings.proxy.url.isEmpty)
        #expect(settings.dictionaryExtras.examples)
        #expect(!settings.dictionaryExtras.synonyms)
        #expect(settings.selectionPopupOptions.delayMs == 120)
        #expect(settings.providers["openai"]?.model == "gpt-4o-mini")
        #expect(settings.providers["openrouter"]?.apiKey == "legacy")
        #expect(VocabularyEntry.parse("**and/or**\nn. 和／或", language: "en", definitionLanguage: "zh-CN")?.id == #"["en","and/or"]"#)
    }
    @Test func testImportPreservesOriginalAndAllData() throws {
        let old = root.appendingPathComponent("Glint")
        let target = root.appendingPathComponent("native")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        let original = Data(#"{"engine":"custom","providers":{"custom":{"apiKey":"fixture","model":"test","baseURL":"http://localhost:9000"}},"pinned":true}"#.utf8)
        try original.write(to: old.appendingPathComponent("settings.json"))
        let entry = try #require(VocabularyEntry.parse("**apple** /a/\nn. 苹果", language: "en", definitionLanguage: "zh-CN"))
        try JSONEncoder().encode([entry]).write(to: old.appendingPathComponent("vocabulary.json"))
        let store = try LocalStore(directory: target, legacyDirectories: [old])
        #expect(store.settings.engine == "custom")
        #expect(store.settings.providers["custom"]?.apiKey == "fixture")
        #expect(store.vocabulary.count == 1)
        try store.recordLookup(entry)
        try store.addVocabulary(entry)
        #expect(store.vocabulary.count == 1)
        #expect(store.vocabulary[0].queryCount == 1)
        #expect(try Data(contentsOf: old.appendingPathComponent("settings.json")) == original)
        let reloaded = try LocalStore(directory: target, legacyDirectories: [old])
        #expect(reloaded.vocabulary[0].queryCount == 1)
        #expect(reloaded.settings == store.settings)
    }
    @Test func testMalformedLegacyDataDoesNotCreateOrOverwriteStore() throws {
        let old = root.appendingPathComponent("old")
        let target = root.appendingPathComponent("native")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: old.appendingPathComponent("vocabulary.json"))
        #expect(throws: (any Error).self) { try LocalStore(directory: target, legacyDirectories: [old]) }
        #expect(!(FileManager.default.fileExists(atPath: target.appendingPathComponent("settings.json").path)))
    }
    @Test func testVersionOneVocabularyImportAndBackup() throws {
        let old = root.appendingPathComponent("old"), target = root.appendingPathComponent("native")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        let data = Data(#"{"version":1,"entries":[{"word":"apple","translated":"**apple** /a/\nn. 苹果","source":"en","target":"zh-CN","createdAt":"2025-01-02T03:04:05.000Z"},{"word":"apples","translated":"**apple** /a/\nn. 苹果","source":"en","target":"zh-CN","createdAt":"2025-02-03T03:04:05.000Z"}]}"#.utf8)
        try data.write(to: old.appendingPathComponent("vocabulary.json"))
        let store = try LocalStore(directory: target, legacyDirectories: [old])
        #expect(store.vocabulary.count == 1)
        #expect(store.vocabulary.first?.createdAt == "2025-01-02T03:04:05.000Z")
        #expect(store.vocabulary.first?.queryCount == 0)
        #expect(try Data(contentsOf: target.appendingPathComponent("vocabulary.json.electron-backup")) == data)
        #expect(try Data(contentsOf: old.appendingPathComponent("vocabulary.json")) == data)
    }
    @Test func testHistoryDeduplicatesAndKeepsMostRecent100() throws {
        let store = try LocalStore(directory: root)
        for index in 0..<102 {
            try store.addHistory(.init(original: "\(index)", translated: "译文", source: "en", target: "zh-CN", engine: "google"))
        }
        #expect(store.history.count == 100)
        try store.addHistory(store.history[0])
        #expect(store.history.count == 100)
        try store.clearHistory()
        #expect(try LocalStore(directory: root).history.isEmpty)
    }
}
