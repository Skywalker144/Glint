import Foundation

public enum GlintError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

public enum Catalog {
    public static func load<T: Decodable>(_ name: String, as: T.Type = T.self) -> T {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(T.self, from: data) else {
            fatalError("缺少应用资源：\(name)")
        }
        return value
    }
    public static let providers: [Provider] = load("providers")
    public static let languages: [Language] = load("languages")
    public static let prompts: [String: JSONValue] = load("prompts")
    public static let changelog: [ChangelogEntry] = load("changelog")
    public static var defaultSystemPrompt: String { prompts["DEFAULT_SYSTEM_PROMPT"]?.string ?? "" }
    public static var defaultDictionaryPrompt: String { prompts["DEFAULT_DICTIONARY_PROMPT"]?.string ?? "" }
}

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var strings: [String] { if case .array(let v) = self { return v.compactMap(\.string) }; return [] }
}

public struct Provider: Decodable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let kind: String
    public let baseURL: String?
    public let defaultModel: String?
    public let models: [String]?
    public let keyHint: String?
    public let keyURL: String?
    public let desc: String?
    public let extraBody: [String: JSONValue]?
    public let extraHeaders: [String: String]?
    public var isAI: Bool { kind != "free" }
    public static func find(_ id: String) -> Provider? { Catalog.providers.first { $0.id == id } }
}

public struct ProviderConfig: Codable, Equatable, Sendable {
    public var apiKey = ""
    public var model = ""
    public var baseURL = ""
    public init(apiKey: String = "", model: String = "", baseURL: String = "") {
        self.apiKey = apiKey; self.model = model; self.baseURL = baseURL
    }
    enum CodingKeys: String, CodingKey { case apiKey, model, baseURL }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
    }
}

public struct ProxySettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var url = ""
    public init(enabled: Bool = false, url: String = "") { self.enabled = enabled; self.url = url }
    enum CodingKeys: String, CodingKey { case enabled, url }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
    }
}

public struct DictionaryExtras: Codable, Equatable, Sendable {
    public var examples = false
    public var synonyms = false
    public var related = false
    public init() {}
    enum CodingKeys: String, CodingKey { case examples, synonyms, related }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        examples = try c.decodeIfPresent(Bool.self, forKey: .examples) ?? false
        synonyms = try c.decodeIfPresent(Bool.self, forKey: .synonyms) ?? false
        related = try c.decodeIfPresent(Bool.self, forKey: .related) ?? false
    }
}

public struct PopupOptions: Codable, Equatable, Sendable {
    public var position = "bottom-right"
    public var distance = 12
    public var delayMs = 120
    public init() {}
    enum CodingKeys: String, CodingKey { case position, distance, delayMs }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        position = try c.decodeIfPresent(String.self, forKey: .position) ?? "bottom-right"
        distance = try c.decodeIfPresent(Int.self, forKey: .distance) ?? 12
        delayMs = try c.decodeIfPresent(Int.self, forKey: .delayMs) ?? 120
        normalize()
    }
    public static let positions = ["bottom-right", "bottom-left", "top-right", "top-left"]
    public mutating func normalize() {
        if !Self.positions.contains(position) { position = "bottom-right" }
        distance = min(100, max(0, distance)); delayMs = min(2000, max(0, delayMs))
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var engine = "google"
    public var launchAtLogin = false
    public var selectionPopup = true
    public var selectionPopupOptions = PopupOptions()
    public var pinned = false
    public var hideTrayIcon = false
    public var windowWidth: Double = 420
    public var windowX: Double?
    public var windowY: Double?
    public var proxy = ProxySettings()
    public var primaryLanguage = "zh-CN"
    public var secondaryLanguage = "en"
    public var systemPrompt = Catalog.defaultSystemPrompt
    public var dictionaryMode = true
    public var dictionaryPrompt = Catalog.defaultDictionaryPrompt
    public var dictionaryExtras = DictionaryExtras()
    public var hotkeys = ["input": "Alt+Q", "screenshot": "Alt+W", "selection": "Alt+E", "clipboard": "Alt+R"]
    public var providers = Dictionary(uniqueKeysWithValues: Catalog.providers.filter(\.isAI).map { ($0.id, ProviderConfig(model: $0.defaultModel ?? "")) })
    public init() {}
    enum CodingKeys: String, CodingKey, CaseIterable {
        case engine, launchAtLogin, selectionPopup, selectionPopupOptions, pinned, hideTrayIcon, windowWidth, windowX, windowY, proxy, primaryLanguage, secondaryLanguage, systemPrompt, dictionaryMode, dictionaryPrompt, dictionaryExtras, hotkeys, providers
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        engine = try c.decodeIfPresent(String.self, forKey: .engine) ?? engine
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? launchAtLogin
        selectionPopup = try c.decodeIfPresent(Bool.self, forKey: .selectionPopup) ?? selectionPopup
        selectionPopupOptions = try c.decodeIfPresent(PopupOptions.self, forKey: .selectionPopupOptions) ?? selectionPopupOptions
        selectionPopupOptions.normalize()
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? pinned
        hideTrayIcon = try c.decodeIfPresent(Bool.self, forKey: .hideTrayIcon) ?? hideTrayIcon
        windowWidth = min(820, max(360, try c.decodeIfPresent(Double.self, forKey: .windowWidth) ?? windowWidth))
        windowX = try c.decodeIfPresent(Double.self, forKey: .windowX)
        windowY = try c.decodeIfPresent(Double.self, forKey: .windowY)
        proxy = try c.decodeIfPresent(ProxySettings.self, forKey: .proxy) ?? proxy
        primaryLanguage = try c.decodeIfPresent(String.self, forKey: .primaryLanguage) ?? primaryLanguage
        secondaryLanguage = try c.decodeIfPresent(String.self, forKey: .secondaryLanguage) ?? secondaryLanguage
        systemPrompt = try c.decodeIfPresent(String.self, forKey: .systemPrompt) ?? systemPrompt
        dictionaryMode = try c.decodeIfPresent(Bool.self, forKey: .dictionaryMode) ?? dictionaryMode
        dictionaryPrompt = try c.decodeIfPresent(String.self, forKey: .dictionaryPrompt) ?? dictionaryPrompt
        dictionaryExtras = try c.decodeIfPresent(DictionaryExtras.self, forKey: .dictionaryExtras) ?? dictionaryExtras
        hotkeys.merge(try c.decodeIfPresent([String: String].self, forKey: .hotkeys) ?? [:]) { _, new in new }
        var configured = try c.decodeIfPresent([String: ProviderConfig].self, forKey: .providers) ?? [:]
        let raw = try c.decodeIfPresent([String: [String: JSONValue]].self, forKey: .providers) ?? [:]
        for key in configured.keys where raw[key]?["model"] == nil { configured[key]?.model = providers[key]?.model ?? "" }
        enum LegacyKeys: String, CodingKey { case openrouter }
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        if configured["openrouter"] == nil, var old = try legacy.decodeIfPresent(ProviderConfig.self, forKey: .openrouter) {
            let rawOld = try legacy.decode([String: JSONValue].self, forKey: .openrouter)
            if rawOld["model"] == nil { old.model = providers["openrouter"]?.model ?? "" }
            configured["openrouter"] = old
        }
        providers.merge(configured) { _, new in new }
    }
}

public struct ChangelogEntry: Decodable, Identifiable {
    public let version: String
    public let date: String?
    public let items: [String]
    public var id: String { version }
}

public struct HistoryItem: Codable, Identifiable, Equatable {
    public var id = UUID().uuidString
    public var createdAt = ISO8601DateFormatter().string(from: Date())
    public let original: String
    public let translated: String
    public let source: String
    public let target: String
    public let engine: String
    public init(original: String, translated: String, source: String, target: String, engine: String) {
        self.original = original; self.translated = translated; self.source = source; self.target = target; self.engine = engine
    }
}

public struct VocabularyEntry: Codable, Identifiable, Equatable {
    public let id: String
    public let headword: String
    public let language: String
    public let definitionLanguage: String
    public let translated: String
    public var createdAt = ISO8601DateFormatter().string(from: Date())
    public var queryCount = 0
    public var lastQueriedAt: String?
    public var pronunciation: String { translated.trimmed.match(#"^\*\*[^*\n]+\*\*([^\n]*)"#)?[1].trimmed ?? "" }
    public var definition: String { translated.trimmed.match(#"^\*\*[^*\n]+\*\*[^\n]*\r?\n\s*([\s\S]*)$"#)?[1] ?? translated }
    public static func parse(_ text: String, language: String, definitionLanguage: String) -> Self? {
        guard Language.valid(language), let match = text.trimmed.match(#"^\*\*([^*\n]+)\*\*[^\n]*\r?\n\s*(\S[\s\S]*)$"#) else { return nil }
        let word = match[1].precomposedStringWithCanonicalMapping.trimmed.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let encoder = JSONEncoder(); encoder.outputFormatting = .withoutEscapingSlashes
        guard !word.isEmpty, word.match(#"[<>\[\]`]"#) == nil,
              let data = try? encoder.encode([language, word]), let id = String(data: data, encoding: .utf8) else { return nil }
        return Self(id: id, headword: word, language: language, definitionLanguage: definitionLanguage, translated: text)
    }
}

public extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    func match(_ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern), let result = re.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return nil }
        return (0..<result.numberOfRanges).map { Range(result.range(at: $0), in: self).map { String(self[$0]) } ?? "" }
    }
    func matchesCount(_ pattern: String) -> Int {
        (try? NSRegularExpression(pattern: pattern).numberOfMatches(in: self, range: NSRange(startIndex..., in: self))) ?? 0
    }
}

public enum StoredDate {
    public static func parse(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
    public static func display(_ text: String, time: Bool = false) -> String {
        guard let date = parse(text) else { return text }
        return date.formatted(date: .numeric, time: time ? .shortened : .omitted)
    }
}
