import Foundation
import NaturalLanguage

public struct Language: Decodable, Identifiable, Sendable {
    public let code: String
    public let label: String
    public let promptName: String
    public let shortLabel: String?
    public var id: String { code }
    public static func valid(_ code: String) -> Bool { Catalog.languages.contains { $0.code == code } }
    public static func label(_ code: String) -> String { Catalog.languages.first { $0.code == code }?.label ?? "自动" }
    public static func name(_ code: String) -> String { Catalog.languages.first { $0.code == code }?.promptName ?? code }
    public static func detect(_ text: String) -> String? {
        guard let language = NLLanguageRecognizer.dominantLanguage(for: text) else { return nil }
        let code = language.rawValue.hasPrefix("zh") ? "zh-CN" : language.rawValue
        return valid(code) ? code : nil
    }
    static func weights(_ text: String) -> (han: Int, kana: Int, hangul: Int, cyrillic: Int, latin: Int) {
        (text.matchesCount(#"\p{script=Han}"#), text.matchesCount(#"[\p{script=Hiragana}\p{script=Katakana}]"#), text.matchesCount(#"\p{script=Hangul}"#), text.matchesCount(#"\p{script=Cyrillic}"#), text.matchesCount("[A-Za-zÀ-ÖØ-öø-ÿ]+"))
    }
    public static func probably(_ text: String, _ code: String) -> Bool {
        let w = weights(text)
        switch code {
        case "zh-CN": return w.han > 0 && w.kana == 0 && w.hangul == 0 && w.han >= w.latin
        case "ja": return w.kana > 0
        case "ko": return w.hangul > 0
        case "ru": return w.cyrillic > 0
        case "en", "fr", "de", "es", "it", "pt": return w.latin > 0 && w.kana == 0 && w.hangul == 0 && w.cyrillic == 0 && w.latin >= w.han
        default: return false
        }
    }
    public static func semantic(_ text: String, _ code: String) -> Bool {
        let w = weights(text)
        switch code {
        case "zh-CN", "ja": return w.han > 0 && w.kana == 0 && w.hangul == 0 && w.han >= w.latin
        case "ru": return w.cyrillic > 0
        case "en", "fr", "de", "es", "it", "pt": return w.latin > 0 && w.latin >= w.han && w.kana == 0 && w.hangul == 0 && w.cyrillic == 0
        default: return false
        }
    }
    public static func isWord(_ text: String) -> Bool {
        let t = text.trimmed
        guard !t.isEmpty, t.utf16.count <= 40, t.match(#"^[\p{L}\p{M}][\p{L}\p{M}'’\-·]*$"#) != nil else { return false }
        let w = weights(t)
        return w.han + w.kana == 0 || (w.han + w.kana <= 4 && t.match("[A-Za-z]{2,}") == nil)
    }
    public static func guess(_ text: String) -> String {
        let w = weights(text)
        if w.kana > 0 { return "ja" }
        if w.hangul > 0 { return "ko" }
        if w.han > 0 { return "zh-CN" }
        if w.cyrillic > 0 { return "ru" }
        return "en"
    }
}

public struct PreparedInput {
    public let text: String
    public let suffix: String
    public init(_ input: String) {
        if let m = input.match(#"^([A-Za-z0-9]+(?:[_-][A-Za-z0-9]+)+)((?:\.[A-Za-z0-9]{1,10})+)$"#), m[1].match("[A-Za-z]") != nil {
            text = m[1].replacingOccurrences(of: "[_-]+", with: " ", options: .regularExpression)
            suffix = m[2]
        } else { text = input; suffix = "" }
    }
    public func restore(_ output: String) -> String { output.trimmed.isEmpty ? "" : output.trimmed + suffix }
}
