import AppKit
import SwiftUI
import Markdown
import SwiftMath
import GlintCore

final class MathAttachment: NSTextAttachment {
    let source: String
    init(source: String, image: NSImage) {
        self.source = source
        super.init(data: nil, ofType: nil)
        self.image = image
        bounds = NSRect(x: 0, y: -3, width: image.size.width, height: image.size.height)
    }
    required init?(coder: NSCoder) { nil }
}

@MainActor
enum NativeMarkdown {
    static func render(_ source: String, fontSize: CGFloat = 14, width: CGFloat = 400) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 6
        let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.adaptive(0x1a1a1a, 0xf2f2f5), .paragraphStyle: paragraph]
        var equations: [String: (String, Bool)] = [:]
        var input = source
        if let regex = try? NSRegularExpression(pattern: #"(?<!\\)(\$\$)([\s\S]+?)\$\$|(?<![\\$])\$([^\n$]+?)\$(?!\$)"#) {
            let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
            for (index, match) in matches.enumerated().reversed() {
                guard let range = Range(match.range, in: input) else { continue }
                let display = match.range(at: 2).location != NSNotFound
                guard let contentRange = Range(match.range(at: display ? 2 : 3), in: source) else { continue }
                let token = "GLINTMATHTOKEN\(index)END"
                equations[token] = (String(source[contentRange]), display)
                input.replaceSubrange(range, with: token)
            }
        }
        func restoreCode(_ value: String) -> String {
            equations.reduce(value) { result, pair in
                let delimiter = pair.value.1 ? "$$" : "$"
                return result.replacingOccurrences(of: pair.key, with: delimiter + pair.value.0 + delimiter)
            }
        }
        func text(_ value: String, _ attrs: [NSAttributedString.Key: Any]) -> NSMutableAttributedString {
            let result = NSMutableAttributedString(string: value, attributes: attrs)
            for (token, equation) in equations {
                let range = (result.string as NSString).range(of: token)
                guard range.location != NSNotFound else { continue }
                let color = NSColor.adaptive(0x1a1a1a, 0xf2f2f5)
                let math = MTMathImage(latex: equation.0, fontSize: fontSize + (equation.1 ? 2 : 0), textColor: color, labelMode: equation.1 ? .display : .text)
                let (_, image) = math.asImage()
                if let image {
                    let attachment = MathAttachment(source: equation.0, image: image)
                    if image.size.width > width { let scale = width / image.size.width; attachment.bounds.size = NSSize(width: width, height: image.size.height * scale) }
                    result.replaceCharacters(in: range, with: NSAttributedString(attachment: attachment))
                } else { result.replaceCharacters(in: range, with: equation.0) }
            }
            return result
        }
        func renderNode(_ node: any Markup, _ attrs: [NSAttributedString.Key: Any]) -> NSMutableAttributedString {
            var attributes = attrs
            let result = NSMutableAttributedString()
            switch node {
            case let node as Markdown.Text: return text(node.string, attributes)
            case is SoftBreak, is LineBreak: return text("\n", attributes)
            case let node as InlineCode:
                attributes[.font] = NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular)
                attributes[.backgroundColor] = NSColor.adaptive(0xeaeaec, 0x34343a)
                return NSMutableAttributedString(string: restoreCode(node.code), attributes: attributes)
            case let node as CodeBlock:
                attributes[.font] = NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular)
                attributes[.backgroundColor] = NSColor.adaptive(0xeaeaec, 0x34343a)
                return NSMutableAttributedString(string: restoreCode(node.code) + "\n", attributes: attributes)
            case let node as Heading:
                attributes[.font] = NSFont.boldSystemFont(ofSize: fontSize + CGFloat(max(1, 5 - node.level)))
            case is Strong: attributes[.font] = NSFontManager.shared.convert(attrs[.font] as? NSFont ?? .systemFont(ofSize: fontSize), toHaveTrait: .boldFontMask)
            case is Emphasis: attributes[.font] = NSFontManager.shared.convert(attrs[.font] as? NSFont ?? .systemFont(ofSize: fontSize), toHaveTrait: .italicFontMask)
            case is Strikethrough: attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            case let node as Markdown.Link:
                if let destination = node.destination, let url = URL(string: destination), ["http", "https", "mailto"].contains(url.scheme ?? "") { attributes[.link] = url }
            case is BlockQuote:
                let p = paragraph.mutableCopy() as! NSMutableParagraphStyle
                p.headIndent = 12; p.firstLineHeadIndent = 12
                attributes[.paragraphStyle] = p
                attributes[.foregroundColor] = NSColor.secondaryLabelColor
            case is ThematicBreak:
                let image = NSImage(size: NSSize(width: max(20, width), height: 13), flipped: false) { rect in
                    NSColor.separatorColor.setFill(); NSRect(x: 0, y: 6, width: rect.width, height: 0.5).fill(); return true
                }
                let attachment = NSTextAttachment(); attachment.image = image
                result.append(NSAttributedString(attachment: attachment)); result.append(text("\n", attrs)); return result
            case let node as Markdown.Table:
                let table = NSTextTable(); table.numberOfColumns = node.maxColumnCount
                table.collapsesBorders = true; table.layoutAlgorithm = .automaticLayoutAlgorithm
                let rows: [any Markup] = [node.head] + Array(node.body.children)
                for (rowIndex, row) in rows.enumerated() {
                    for (column, cell) in row.children.enumerated() {
                        let block = NSTextTableBlock(table: table, startingRow: rowIndex, rowSpan: 1, startingColumn: column, columnSpan: 1)
                        block.setWidth(0.5, type: .absoluteValueType, for: .border)
                        block.setBorderColor(.separatorColor)
                        block.setWidth(5, type: .absoluteValueType, for: .padding)
                        let p = paragraph.mutableCopy() as! NSMutableParagraphStyle
                        p.textBlocks = [block]; p.paragraphSpacing = 0
                        var a = attrs; a[.paragraphStyle] = p
                        if rowIndex == 0 { a[.font] = NSFont.boldSystemFont(ofSize: fontSize) }
                        for child in cell.children { result.append(renderNode(child, a)) }
                        result.append(text("\n", a))
                    }
                }
                return result
            case let node as HTMLBlock: return text(node.rawHTML + "\n", attrs)
            case let node as InlineHTML: return text(node.rawHTML, attrs)
            case is ListItem:
                let index = node.indexInParent
                let start = (node.parent as? OrderedList)?.startIndex ?? 1
                let marker = node.parent is OrderedList ? "\(start + UInt(index)). " : "• "
                result.append(text(marker, attrs))
            default: break
            }
            for child in node.children { result.append(renderNode(child, attributes)) }
            if node is Paragraph || node is Heading || node is BlockQuote { result.append(text("\n", attrs)) }
            return result
        }
        let result = renderNode(Document(parsing: input), base)
        while result.length > 0, result.string.last?.isWhitespace == true { result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1)) }
        return result
    }
    static func plainText(_ source: String) -> String {
        let attributed = render(source)
        let copy = NSMutableAttributedString(attributedString: attributed)
        attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length), options: .reverse) { value, range, _ in
            if let equation = value as? MathAttachment { copy.replaceCharacters(in: range, with: equation.source) }
            else if value != nil { copy.replaceCharacters(in: range, with: "") }
        }
        return copy.string.trimmed
    }
}

final class RichTextView: NSTextView {
    private var renderedText = ""
    private var renderedFontSize: CGFloat = 0
    private var renderedAppearance: NSAppearance.Name?
    private var renderedWidth: CGFloat = 0
    func render(_ text: String, fontSize: CGFloat, width: CGFloat) {
        let appearance = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        guard text != renderedText || fontSize != renderedFontSize || abs(width - renderedWidth) > 0.5 || appearance != renderedAppearance else { return }
        let selection = selectedRanges
        effectiveAppearance.performAsCurrentDrawingAppearance {
            textStorage?.setAttributedString(NativeMarkdown.render(text, fontSize: fontSize, width: width))
        }
        renderedText = text; renderedFontSize = fontSize; renderedWidth = width; renderedAppearance = appearance
        let length = (string as NSString).length
        let validSelection = selection.filter { $0.rangeValue.location != NSNotFound && NSMaxRange($0.rangeValue) <= length }
        selectedRanges = validSelection.isEmpty ? [NSValue(range: NSRange(location: 0, length: 0))] : validSelection
    }
}

struct RichText: NSViewRepresentable {
    let text: String
    var fontSize: CGFloat = 14
    @Environment(\.colorScheme) var colorScheme
    func makeNSView(context: Context) -> RichTextView {
        let view = RichTextView()
        view.isEditable = false; view.isSelectable = true; view.drawsBackground = false
        view.textContainerInset = .zero; view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.linkTextAttributes = [.foregroundColor: NSColor.labelColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        view.setAccessibilityIdentifier("translation-result")
        return view
    }
    func updateNSView(_ view: RichTextView, context: Context) {
        view.render(text, fontSize: fontSize, width: max(100, view.bounds.width))
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RichTextView, context: Context) -> CGSize? {
        let width = max(100, proposal.width ?? 400)
        nsView.render(text, fontSize: fontSize, width: width)
        nsView.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        guard let manager = nsView.layoutManager, let container = nsView.textContainer else { return nil }
        manager.ensureLayout(for: container)
        return NSSize(width: width, height: max(20, ceil(manager.usedRect(for: container).height)))
    }
}
