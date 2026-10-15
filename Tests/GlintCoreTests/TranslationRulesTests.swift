import Testing
import Foundation
@testable import GlintCore

final class TranslationRulesTests {
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

    @Test func testWordClassificationAndMixedScripts() {
        for text in ["apple", "迭代", "naïve", "don't", "人工智能", "C语言", "食べる"] {
            #expect(Language.isWord(text))
        }
        for text in ["hello world", "这是一个句子。", "用AI写代码", "机器学习算法导论", "", String(repeating: "a", count: 50)] {
            #expect(!(Language.isWord(text)))
        }
        for text in ["你好 hello", "日本語 English", "한국어 English", "Привет hello"] {
            #expect(Language.isMixed(text))
        }
        for text in ["食べる東京カタカナ", "한국 漢字", "Bonjour hello", "123!?"] {
            #expect(!(Language.isMixed(text)))
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
