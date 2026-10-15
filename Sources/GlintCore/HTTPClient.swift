import Foundation

public final class HTTPClient {
    public let session: URLSession
    public init(proxy: ProxySettings, session: URLSession? = nil) throws {
        self.session = try session ?? URLSession(configuration: Self.configuration(proxy: proxy))
    }
    deinit { session.invalidateAndCancel() }
    public static func configuration(proxy: ProxySettings) throws -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        configuration.urlCache = nil
        var values: [AnyHashable: Any] = ["HTTPEnable": 0, "HTTPSEnable": 0, "SOCKSEnable": 0, "ProxyAutoConfigEnable": 0, "ProxyAutoDiscoveryEnable": 0]
        if proxy.enabled && !proxy.url.trimmed.isEmpty {
            let raw = proxy.url.trimmed.contains("://") ? proxy.url.trimmed : "http://" + proxy.url.trimmed
            guard let url = URLComponents(string: raw), let host = url.host, !host.isEmpty,
                  let port = url.port, (1...65535).contains(port), let scheme = url.scheme,
                  ["http", "https", "socks", "socks5"].contains(scheme) else { throw GlintError.message("代理地址无效，请使用 http://127.0.0.1:7890 或 socks5://127.0.0.1:7890") }
            if scheme.hasPrefix("socks") {
                values.merge(["SOCKSEnable": 1, "SOCKSProxy": host, "SOCKSPort": port]) { _, new in new }
            } else {
                values.merge(["HTTPEnable": 1, "HTTPProxy": host, "HTTPPort": port, "HTTPSEnable": 1, "HTTPSProxy": host, "HTTPSPort": port]) { _, new in new }
            }
            values["ExcludeSimpleHostnames"] = 1
            values["ExceptionsList"] = ["localhost", "127.0.0.1", "::1", "*.local"]
        }
        configuration.connectionProxyDictionary = values
        return configuration
    }
    public func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        try Self.validate(response, data: data)
        return data
    }
    public static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw GlintError.message("服务器返回无效响应") }
        guard (200..<300).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = object?["error"] as? [String: Any]
            let message = error?["message"] as? String ?? object?["error"] as? String ?? "HTTP \(http.statusCode)"
            throw GlintError.message("HTTP \(http.statusCode)：\(message)")
        }
    }
    public static func friendly(_ error: Error, engine: String) -> String {
        let text = error.localizedDescription
        if let url = error as? URLError {
            switch url.code {
            case .timedOut: return "请求超时，网络或代理较慢，请稍后重试"
            case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost:
                return engine == "google" ? "网络不通，Google 在受限网络可能需要代理（设置 → 通用）" : "网络不通，可在设置 → 通用检查代理"
            default: break
            }
        }
        if text.match(#"401|403|unauthorized|invalid.*key"#) != nil { return "API Key 无效或没有权限，请在设置 → 翻译检查" }
        if text.match(#"429|quota|rate.limit|billing"#) != nil { return "请求太频繁或额度已用尽，请稍后重试" }
        if text.contains("404") { return "模型或接口地址不对，请在设置 → 翻译检查模型和 Base URL" }
        return text
    }
}

public struct SSEParser {
    private var lines: [String] = []
    public init() {}
    public mutating func consume(_ line: String) -> String? {
        if line.isEmpty {
            guard !lines.isEmpty else { return nil }
            defer { lines.removeAll(keepingCapacity: true) }
            return lines.joined(separator: "\n")
        }
        if line.hasPrefix("data:") {
            var value = String(line.dropFirst(5))
            if value.first == " " { value.removeFirst() }
            lines.append(value)
        }
        return nil
    }
    public mutating func finish() -> String? { consume("") }
}

public enum AppVersion {
    public static let repository = "https://github.com/Skywalker144/Glint"
    public static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.22" }
    public static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.replacingOccurrences(of: "^v", with: "", options: [.regularExpression, .caseInsensitive]).split(separator: "-").first?.split(separator: ".").map { Int($0) ?? 0 } ?? [] }
        let left = parts(a), right = parts(b)
        for i in 0..<max(left.count, right.count) {
            let x = i < left.count ? left[i] : 0, y = i < right.count ? right[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
