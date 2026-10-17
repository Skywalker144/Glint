import Testing
import Foundation
@testable import GlintCore

final class TranslationRulesTests {
    @Test func completedSemanticDirectionUsesActualLanguages() throws {
        var settings = AppSettings(); settings.engine = "openai"; settings.primaryLanguage = "en"; settings.secondaryLanguage = "zh-CN"
        let request = try TranslationRequest.resolve("This is a complete English sentence.", settings: settings)
        #expect(request.options.semanticDirection)
        let resolved = request.resolvedLanguages(original: "This is a complete English sentence.", translated: "这是一个完整的中文句子。", detectedSource: "auto")
        #expect(resolved.source == "en")
        #expect(resolved.target == "zh-CN")
        settings.primaryLanguage = "fr"; settings.secondaryLanguage = "en"
        let french = try TranslationRequest.resolve("Bonjour, je voudrais réserver une table pour ce soir.", settings: settings)
        let languages = french.resolvedLanguages(original: "Bonjour, je voudrais réserver une table pour ce soir.", translated: "Hello, I would like to reserve a table for tonight.", detectedSource: "auto")
        #expect(languages.source == "fr")
        #expect(languages.target == "en")
        let forced = try TranslationRequest.resolve("你好", settings: settings, overrides: .init(source: "zh-CN", target: "ja", mode: .translate))
        #expect(forced.resolvedLanguages(original: "你好", translated: "こんにちは", detectedSource: "zh").target == "ja")
    }

    @Test func dictionaryDetailSeparatesHeadingFromDefinition() throws {
        let entry = try #require(VocabularyEntry.parse("**café** /ka.fe/\r\nn. 咖啡\n\n例句 Un café. — 一杯咖啡。", language: "fr", definitionLanguage: "zh-CN"))
        #expect(entry.pronunciation == "/ka.fe/")
        #expect(entry.definition == "n. 咖啡\n\n例句 Un café. — 一杯咖啡。")
    }
    struct Fixture: Decodable {
        let text: String
        let settings: AppSettings
        let overrides: TranslationOverrides
        let expected: TranslationRequest?
        let error: String?
        let system: String?
        let user: String?
    }

    @Test func testExistingTranslationContracts() throws {
        let url = try #require(Bundle.module.url(forResource: "translation", withExtension: "json"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
        for fixture in fixtures {
            if fixture.error != nil {
                #expect(throws: (any Error).self) { try TranslationRequest.resolve(fixture.text, settings: fixture.settings, overrides: fixture.overrides) }
            } else {
                let request = try TranslationRequest.resolve(fixture.text, settings: fixture.settings, overrides: fixture.overrides)
                #expect(request == fixture.expected)
                #expect(request.systemPrompt == fixture.system)
                #expect(request.userContent(fixture.text) == fixture.user)
            }
        }
    }

    @Test func testWordClassification() {
        for text in ["apple", "迭代", "naïve", "don't", "人工智能", "C语言", "食べる"] {
            #expect(Language.isWord(text))
        }
        for text in ["hello world", "这是一个句子。", "用AI写代码", "机器学习算法导论", "", String(repeating: "a", count: 50)] {
            #expect(!(Language.isWord(text)))
        }
    }

    @Test func testFilenameAndDictionaryIdentity() throws {
        let input = PreparedInput("quarterly-sales-report.tar.gz")
        #expect(input.text == "quarterly sales report")
        #expect(input.restore("季度销售报告") == "季度销售报告.tar.gz")
        #expect(PreparedInput("openai.com").suffix == "")
        let entry = try #require(VocabularyEntry.parse("**café** /ka.fe/\nn. 咖啡", language: "fr", definitionLanguage: "zh-CN"))
        #expect(entry.id == "[\"fr\",\"café\"]")
        #expect(VocabularyEntry.parse("普通译文", language: "en", definitionLanguage: "zh-CN") == nil)
    }
}
