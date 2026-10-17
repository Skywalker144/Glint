import Foundation
import GlintCore

struct OCRLine {
    let text: String
    let bounds: CGRect
}

enum OCRText {
    static func paragraphs(_ lines: [OCRLine]) -> String {
        let sorted = lines.filter { !$0.text.trimmed.isEmpty }.sorted {
            abs($0.bounds.midY - $1.bounds.midY) > min($0.bounds.height, $1.bounds.height) * 0.5
                ? $0.bounds.midY > $1.bounds.midY : $0.bounds.minX < $1.bounds.minX
        }
        var result = ""
        for (index, line) in sorted.enumerated() {
            let text = line.text.trimmed
            guard index > 0 else { result = text; continue }
            let previous = sorted[index - 1]
            let height = max(previous.bounds.height, line.bounds.height)
            let gap = previous.bounds.minY - line.bounds.maxY
            let aligned = abs(previous.bounds.minX - line.bounds.minX) < height * 0.8
            let sameColumn = line.bounds.maxX > previous.bounds.minX && line.bounds.minX < previous.bounds.maxX
            let list = text.match(#"^(?:[•●▪–—-]|\d+[.)、])\s+"#) != nil
            let shortEnding = previous.bounds.width < line.bounds.width * 0.7 && previous.text.match(#"[。！？.!?:：]$"#) != nil
            if !sameColumn || !aligned || gap > height * 0.8 || gap < -height * 0.5 || list || shortEnding || abs(previous.bounds.height - line.bounds.height) > height * 0.3 {
                result += "\n\n" + text
            } else if result.hasSuffix("-"), text.match("^[a-z]") != nil {
                result.removeLast(); result += text
            } else {
                let cjk = #"[\p{script=Han}\p{script=Hiragana}\p{script=Katakana}，。！？、：；「」『』]"#
                let separator = String(result.suffix(1)).match(cjk) != nil || String(text.prefix(1)).match(cjk) != nil ? "" : " "
                result += separator + text
            }
        }
        return result
    }
}
