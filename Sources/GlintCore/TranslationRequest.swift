import Foundation

public enum TranslationMode: String, Codable, Sendable { case auto, translate, dict }

public struct TranslationOverrides: Codable, Equatable, Sendable {
    public var source = ""
    public var target = ""
    public var mode: TranslationMode = .auto
    public init(source: String = "", target: String = "", mode: TranslationMode = .auto) {
        self.source = source; self.target = target; self.mode = mode
    }
    enum CodingKeys: String, CodingKey { case source, target, mode }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        target = try c.decodeIfPresent(String.self, forKey: .target) ?? ""
        mode = try c.decodeIfPresent(TranslationMode.self, forKey: .mode) ?? .auto
    }
}

public struct TranslationOptions: Codable, Equatable, Sendable {
    public let systemPrompt: String
    public let forceTarget: Bool
    public let forceSource: Bool
    public let dict: Bool
    public let dictionaryExtras: DictionaryExtras
    public let semanticDirection: Bool
    public let primaryLanguage: String
    public let secondaryLanguage: String
    public let source: String
}

public struct TranslationRequest: Codable, Equatable, Sendable {
    public let engine: String
    public let config: ProviderConfig
    public let target: String
    public let options: TranslationOptions
    public var resultTarget: String { options.semanticDirection ? "" : target }
    public func resolvedLanguages(original: String, translated: String, detectedSource: String) -> (source: String, target: String) {
        let normalized = detectedSource.hasPrefix("zh") ? "zh-CN" : detectedSource
        let source = Language.valid(normalized) ? normalized : (Language.detect(original) ?? Language.guess(original))
        let target = options.semanticDirection
            ? (Language.detect(translated) ?? (source == options.primaryLanguage ? options.secondaryLanguage : options.primaryLanguage))
            : (options.dict ? options.primaryLanguage : self.target)
        return (source, target)
    }
    public static func resolve(_ text: String, settings s: AppSettings, overrides o: TranslationOverrides = .init()) throws -> Self {
        guard let provider = Provider.find(s.engine) else { throw GlintError.message("未知翻译引擎：" + s.engine) }
        let primary = Language.valid(s.primaryLanguage) ? s.primaryLanguage : "zh-CN"
        let secondary = Language.valid(s.secondaryLanguage) ? s.secondaryLanguage : "en"
        let source = Language.valid(o.source) ? o.source : ""
        let forced = Language.valid(o.target) ? o.target : ""
        let detected = source.isEmpty ? (Language.probably(text, primary) ? primary : "auto") : source
        let target = forced.isEmpty ? (detected == primary ? secondary : primary) : forced
        if o.mode == .dict && !provider.isAI { throw GlintError.message("当前引擎不支持词典，请在设置中选择 AI 引擎") }
        let dict = provider.isAI && (o.mode == .dict || (o.mode != .translate && forced.isEmpty && s.dictionaryMode && Language.isWord(text)))
        let semantic = source.isEmpty && forced.isEmpty && !dict && provider.isAI && Language.semantic(text, primary)
        return Self(engine: s.engine, config: s.providers[s.engine] ?? .init(), target: target, options: .init(
            systemPrompt: dict ? (s.dictionaryPrompt.isEmpty ? Catalog.defaultDictionaryPrompt : s.dictionaryPrompt) : (forced.isEmpty ? s.systemPrompt : ""),
            forceTarget: !forced.isEmpty && !dict, forceSource: !source.isEmpty, dict: dict,
            dictionaryExtras: s.dictionaryExtras, semanticDirection: semantic,
            primaryLanguage: dict && (!source.isEmpty || !forced.isEmpty) ? target : primary,
            secondaryLanguage: dict ? (!source.isEmpty ? source : (!forced.isEmpty && target == secondary ? primary : secondary)) : secondary,
            source: semantic ? "auto" : detected
        ))
    }
    public func userContent(_ text: String) -> String {
        if options.dict { return text }
        let direction = options.semanticDirection
            ? "翻译方向：若待翻译文本的主要语言是" + Language.name(options.primaryLanguage) + "，译成" + Language.name(options.secondaryLanguage) + "；否则译成" + Language.name(options.primaryLanguage) + "。"
            : "目标语言：" + Language.name(target) + "。"
        let source = options.source != "auto" && !options.source.isEmpty ? "原文语言：" + Language.name(options.source) + "。\n" : ""
        return source + direction + "\n待翻译文本：\n\n" + text
    }
    public var systemPrompt: String {
        var raw = options.systemPrompt.trimmed
        if raw.isEmpty { raw = options.dict ? Catalog.defaultDictionaryPrompt : Catalog.defaultSystemPrompt }
        if options.dict {
            let extras = options.dictionaryExtras
            raw += "\n\n词条识别格式：词条首行必须以 **规范词头** 开头，后面可附读音；下一行开始写释义。词头使用词典原形和规范大小写，保留有意义的大小写差异。若输出普通句子译文，不使用此词头格式。"
            raw += "\n\n词典补充内容规则（与前文冲突时以此为准）：\n" + [
                extras.examples ? "例句：只给一条自然、简短的 {{secondary}} 例句，附 {{primary}} 译文，格式为「例句 原句 — 译文」。" : "禁止输出例句。",
                extras.synonyms ? "近义词和反义词：各最多三个，只列可靠且对应具体义项的词，标明词性；格式为「近义 adj. word；n. word」「反义 adj. word」。没有明确对应项时省略，不把相关词当成同义词。" : "禁止输出近义词和反义词。",
                extras.related ? "关联词：最多三个，优先常用派生词，每个附简短 {{primary}} 释义；格式为「关联 word 释义；word 释义」。不重复词头或近反义词。" : "禁止输出关联词。",
                extras.examples || extras.synonyms || extras.related ? "只在实际有补充内容时，在基础释义后空一行，插入单独一行的 ---，再空一行输出补充内容；仅用这一条分隔线。补充内容按例句、近义、反义、关联的顺序各占一行，不用标题、列表、链接或空栏目。" : "只输出词头、读音与紧凑释义，不输出分隔线或其他补充内容。",
                "不确定的信息直接省略，不编造。若输入按正常翻译处理，不添加任何词典补充内容。"
            ].joined(separator: "\n")
        }
        for (key, value) in [("target", target), ("primary", options.primaryLanguage), ("secondary", options.secondaryLanguage)] {
            raw = raw.replacingOccurrences(of: #"\{\{\s*"# + key + #"\s*\}\}|\$?\{\s*"# + key + #"\s*\}"#, with: Language.name(value), options: .regularExpression)
        }
        return raw
    }
}
