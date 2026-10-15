import Testing
import Foundation
@testable import GlintCore

final class NetworkTests {
    @Test func testRequestUsesProviderProtocolAndDirection() throws {
        var settings = AppSettings()
        settings.engine = "deepseek"
        settings.providers["deepseek"] = .init(apiKey: "fixture", model: "test")
        let translation = try TranslationRequest.resolve("hello world", settings: settings, overrides: .init(source: "en", target: "ja", mode: .translate))
        let request = try TranslationEngine.makeRequest(translation, text: "hello world")
        let payload = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        #expect(request.url?.absoluteString == "https://api.deepseek.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture")
        #expect((body["thinking"] as? [String: String])?["type"] == "disabled")
        #expect(body["stream"] as? Bool == true)
        #expect(((body["messages"] as? [[String: String]])?.last?["content"] ?? "").contains("目标语言：日语"))
        settings.engine = "anthropic"
        settings.providers["anthropic"] = .init(apiKey: "fixture", model: "test")
        let anthropic = try TranslationEngine.makeRequest(TranslationRequest.resolve("hello", settings: settings), text: "hello")
        let anthropicPayload = try #require(anthropic.httpBody)
        let abody = try #require(JSONSerialization.jsonObject(with: anthropicPayload) as? [String: Any])
        #expect(anthropic.value(forHTTPHeaderField: "x-api-key") == "fixture")
        #expect(abody["max_tokens"] as? Int == 4096)
        #expect(abody["system"] != nil)
    }
    @Test func testSSEEventsAndErrors() throws {
        var parser = SSEParser()
        #expect(parser.consume(": keepalive") == nil)
        #expect(parser.consume("event: message") == nil)
        #expect(parser.consume("data: {\"x\":1}") == nil)
        #expect(parser.consume("") == "{\"x\":1}")
        #expect(try TranslationEngine.delta(#"{"choices":[{"delta":{"content":"你好"}}]}"#) == "你好")
        #expect(try TranslationEngine.delta(#"{"type":"content_block_delta","delta":{"text":"世界"}}"#) == "世界")
        #expect(try TranslationEngine.delta("[DONE]") == "")
        #expect(throws: (any Error).self) { try TranslationEngine.delta(#"{"type":"error","error":{"message":"quota"}}"#) }
    }
    @Test func testProxyConfigurationAndVersionComparison() throws {
        let direct = try HTTPClient.configuration(proxy: .init())
        #expect(direct.connectionProxyDictionary?["HTTPEnable"] as? Int == 0)
        let proxy = try HTTPClient.configuration(proxy: .init(enabled: true, url: "127.0.0.1:7890"))
        #expect(proxy.connectionProxyDictionary?["HTTPSPort"] as? Int == 7890)
        #expect(throws: (any Error).self) { try HTTPClient.configuration(proxy: .init(enabled: true, url: "garbage")) }
        #expect(AppVersion.isNewer("v0.3.0", than: "0.2.22"))
        #expect(!(AppVersion.isNewer("0.2.9", than: "0.2.22")))
    }
}
