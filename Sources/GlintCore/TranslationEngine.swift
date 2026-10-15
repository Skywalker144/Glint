import Foundation

public struct TranslationOutput: Sendable {
    public let translated: String
    public let source: String
}

public struct TranslationEngine {
    public let client: HTTPClient
    public init(client: HTTPClient) { self.client = client }
    public static func makeRequest(_ translation: TranslationRequest, text: String) throws -> URLRequest {
        guard let provider = Provider.find(translation.engine) else { throw GlintError.message("未知翻译服务商") }
        let config = translation.config
        let base = (provider.id == "custom" ? config.baseURL : provider.baseURL ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !base.isEmpty, let url = URL(string: base + (provider.kind == "anthropic" ? "/messages" : "/chat/completions")), ["http", "https"].contains(url.scheme ?? "") else { throw GlintError.message("缺少或无效的 Base URL") }
        guard !config.apiKey.trimmed.isEmpty else { throw GlintError.message("未配置 API Key") }
        guard !config.model.trimmed.isEmpty else { throw GlintError.message("未选择模型") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: JSONValue] = provider.extraBody ?? [:]
        body["model"] = .string(config.model)
        body["temperature"] = .number(0)
        body["stream"] = .bool(true)
        if provider.kind == "anthropic" {
            request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body["max_tokens"] = .number(4096)
            body["system"] = .string(translation.systemPrompt)
            body["messages"] = .array([.object(["role": .string("user"), "content": .string(translation.userContent(text))])])
        } else {
            request.setValue("Bearer " + config.apiKey, forHTTPHeaderField: "Authorization")
            for (key, value) in provider.extraHeaders ?? [:] { request.setValue(value, forHTTPHeaderField: key) }
            body["messages"] = .array([
                .object(["role": .string("system"), "content": .string(translation.systemPrompt)]),
                .object(["role": .string("user"), "content": .string(translation.userContent(text))])
            ])
        }
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
    public static func delta(_ payload: String) throws -> String {
        guard payload != "[DONE]", let data = payload.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        if let error = value["error"] as? [String: Any] { throw GlintError.message(error["message"] as? String ?? "流式响应错误") }
        if let choices = value["choices"] as? [[String: Any]], let delta = choices.first?["delta"] as? [String: Any] { return delta["content"] as? String ?? "" }
        if value["type"] as? String == "content_block_delta", let delta = value["delta"] as? [String: Any] { return delta["text"] as? String ?? "" }
        return ""
    }
    public func translate(_ text: String, request: TranslationRequest, onDelta: @escaping (String) async -> Void) async throws -> TranslationOutput {
        let prepared = PreparedInput(text)
        if request.engine == "google" {
            var url = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
            url.queryItems = ["client": "gtx", "sl": request.options.forceSource ? request.options.source : "auto", "tl": request.target, "dt": "t", "q": prepared.text].map { URLQueryItem(name: $0.key, value: $0.value) }
            var http = URLRequest(url: url.url!)
            http.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            let data = try await client.data(for: http)
            guard let array = try JSONSerialization.jsonObject(with: data) as? [Any], let segments = array.first as? [[Any]] else { throw GlintError.message("Google 返回了无法识别的译文") }
            let full = prepared.restore(segments.compactMap { $0.first as? String }.joined())
            await onDelta(full)
            return .init(translated: full, source: array.count > 2 ? array[2] as? String ?? "auto" : "auto")
        }
        let http = try Self.makeRequest(request, text: prepared.text)
        let (bytes, response) = try await client.session.bytes(for: http)
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            var errorData = Data()
            for try await byte in bytes { errorData.append(byte); if errorData.count >= 16384 { break } }
            try HTTPClient.validate(response, data: errorData)
        }
        var parser = SSEParser(), full = ""
        var line = Data(), previousCR = false, completed = false
        func emit(_ payload: String?) async throws {
            guard let payload else { return }
            if payload == "[DONE]" { completed = true; return }
            let delta = try Self.delta(payload)
            if !delta.isEmpty { full += delta; await onDelta(delta) }
        }
        for try await byte in bytes {
            try Task.checkCancellation()
            if byte == 10 && previousCR { previousCR = false; continue }
            if byte == 10 || byte == 13 {
                try await emit(parser.consume(String(decoding: line, as: UTF8.self)))
                line.removeAll(keepingCapacity: true)
                previousCR = byte == 13
                if completed { break }
            } else {
                previousCR = false; line.append(byte)
                if line.count > 1_048_576 { throw GlintError.message("流式响应行过长") }
            }
        }
        if !line.isEmpty { try await emit(parser.consume(String(decoding: line, as: UTF8.self))) }
        try await emit(parser.finish())
        try Task.checkCancellation()
        guard !full.trimmed.isEmpty else { throw GlintError.message("模型没有返回译文") }
        if !prepared.suffix.isEmpty { await onDelta(prepared.suffix) }
        return .init(translated: prepared.restore(full), source: request.options.source)
    }
    public func models(provider: Provider, config: ProviderConfig) async throws -> [String] {
        let base = (provider.id == "custom" ? config.baseURL : provider.baseURL ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/models"), url.host != nil else { throw GlintError.message("缺少 Base URL") }
        var request = URLRequest(url: url)
        if provider.kind == "anthropic" {
            request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else if !config.apiKey.isEmpty { request.setValue("Bearer " + config.apiKey, forHTTPHeaderField: "Authorization") }
        struct Models: Decodable { struct Item: Decodable { let id: String }; let data: [Item] }
        return try JSONDecoder().decode(Models.self, from: await client.data(for: request)).data.map(\.id).sorted()
    }
}
