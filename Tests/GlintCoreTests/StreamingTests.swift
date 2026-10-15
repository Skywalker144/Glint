import Foundation
import Testing
@testable import GlintCore

final class StreamingTests {
    let server: Process
    let port: String
    init() throws {
        server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("stream_server.py").path]
        let pipe = Pipe(); server.standardOutput = pipe; server.standardError = FileHandle.nullDevice
        try server.run()
        port = String(data: pipe.fileHandleForReading.availableData, encoding: .utf8)!.trimmed
    }
    deinit { server.terminate(); server.waitUntilExit() }
    func request(_ mode: String = "normal") throws -> TranslationRequest {
        var settings = AppSettings(); settings.engine = "custom"
        settings.providers["custom"] = .init(apiKey: "fixture", model: mode, baseURL: "http://127.0.0.1:\(port)/v1")
        return try TranslationRequest.resolve("Hello world", settings: settings)
    }
    @Test func testRealChunkedStreamPreservesUnicodeAndEvents() async throws {
        let engine = TranslationEngine(client: try HTTPClient(proxy: .init()))
        var deltas: [String] = []
        let output = try await engine.translate("Hello world", request: request()) { deltas.append($0) }
        #expect(deltas == ["你", "好", " 🌍"])
        #expect(output.translated == "你好 🌍")
    }
    @Test func testCancellationDoesNotFinishStream() async throws {
        let engine = TranslationEngine(client: try HTTPClient(proxy: .init()))
        let request = try request("slow")
        let task = Task { try await engine.translate("Hello world", request: request) { _ in } }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled request completed") }
        catch { #expect(error is CancellationError || (error as? URLError)?.code == .cancelled) }
    }
    @Test func testServerAndEmptyResponseErrors() async throws {
        let engine = TranslationEngine(client: try HTTPClient(proxy: .init()))
        for mode in ["unauthorized", "empty"] {
            do { _ = try await engine.translate("Hello", request: request(mode)) { _ in }; Issue.record("Invalid response accepted") }
            catch { #expect(error.localizedDescription.contains(mode == "empty" ? "没有返回" : "401")) }
        }
    }
}
