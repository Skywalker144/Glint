import AppKit
import SwiftUI

final class TranslationScrollView: NSScrollView {
    static let minimumHeight = ceil(NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: 15)))
    private var revision: UUID?
    private var source = ""
    private var updatingLayout = false
    private var layoutWidth: CGFloat = 0
    private(set) var followsEnd = true
    private(set) var preferredHeight = minimumHeight
    var onMetrics: (CGFloat, Bool) -> Void = { _, _ in }
    var distanceFromEnd: CGFloat { max(0, (documentView?.frame.height ?? 0) - contentView.bounds.maxY) }
    var showsLatest: Bool { !followsEnd && distanceFromEnd > 2 }

    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false; hasVerticalScroller = true; autohidesScrollers = true
        scrollerStyle = .overlay
        let view = RichTextView()
        view.isEditable = false; view.isSelectable = true; view.drawsBackground = false
        view.textContainerInset = .zero; view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = false; view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = false
        view.linkTextAttributes = [.foregroundColor: NSColor.labelColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        view.setAccessibilityIdentifier("translation-result")
        view.setAccessibilityLabel("译文")
        documentView = view
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(didScroll), name: NSView.boundsDidChangeNotification, object: contentView)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func tile() {
        let wasUpdating = updatingLayout
        updatingLayout = true
        super.tile()
        updatingLayout = wasUpdating
        layoutTranslation()
    }
    func update(text: String, revision: UUID, streaming: Bool, appearance: NSAppearance.Name) {
        if self.revision != revision {
            self.revision = revision
            preferredHeight = Self.minimumHeight; followsEnd = streaming
            (documentView as? NSTextView)?.setSelectedRange(NSRange(location: 0, length: 0))
            updatingLayout = true
            contentView.scroll(to: .zero)
            updatingLayout = false
        }
        source = text
        self.appearance = NSAppearance(named: appearance)
        layoutTranslation()
    }
    private func layoutTranslation() {
        guard !updatingLayout, revision != nil, let view = documentView as? RichTextView,
              let container = view.textContainer, let manager = view.layoutManager else { return }
        updatingLayout = true
        defer { updatingLayout = false }
        let offset = contentView.bounds.origin
        let width = max(1, contentSize.width)
        let widthChanged = abs(layoutWidth - width) > 0.5
        var readingAnchor: (character: Int, offset: CGFloat)?
        if widthChanged {
            preferredHeight = Self.minimumHeight
            if !followsEnd && offset.y > 0 && manager.numberOfGlyphs > 0 {
                let glyph = manager.glyphIndex(for: NSPoint(x: 0, y: offset.y), in: container)
                let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                readingAnchor = (manager.characterIndexForGlyph(at: glyph), offset.y - line.minY)
            }
        }
        layoutWidth = width
        let textWidth = max(1, width - view.textContainerInset.width * 2)
        view.render(source, fontSize: 15, width: textWidth)
        container.containerSize = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let height = max(Self.minimumHeight, ceil(manager.usedRect(for: container).height))
        view.setFrameSize(NSSize(width: width, height: max(contentSize.height, height)))
        preferredHeight = min(340, max(preferredHeight, height))
        var readingY = offset.y
        if let readingAnchor, readingAnchor.character < (view.textStorage?.length ?? 0) {
            let glyph = manager.glyphIndexForCharacter(at: readingAnchor.character)
            readingY = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + readingAnchor.offset
        }
        contentView.scroll(to: NSPoint(x: 0, y: followsEnd ? max(0, view.frame.height - contentSize.height) : min(readingY, max(0, view.frame.height - contentSize.height))))
        reflectScrolledClipView(contentView)
        onMetrics(preferredHeight, showsLatest)
    }
    @objc private func didScroll() {
        guard !updatingLayout else { return }
        followsEnd = distanceFromEnd <= 2
        onMetrics(preferredHeight, showsLatest)
    }
    func jumpToLatest() {
        followsEnd = true
        layoutTranslation()
    }
}

struct NativeTranslationResult: NSViewRepresentable {
    let text: String
    let revision: UUID
    let streaming: Bool
    let jumpRevision: Int
    @Binding var height: CGFloat
    @Binding var showsLatest: Bool
    @Environment(\.colorScheme) private var colorScheme
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> TranslationScrollView { TranslationScrollView() }
    func updateNSView(_ scroll: TranslationScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        scroll.onMetrics = { [weak coordinator] height, latest in coordinator?.publish(height: height, latest: latest) }
        scroll.update(text: text, revision: revision, streaming: streaming, appearance: colorScheme == .dark ? .darkAqua : .aqua)
        if coordinator.jumpRevision != jumpRevision {
            coordinator.jumpRevision = jumpRevision
            scroll.jumpToLatest()
        }
    }
    static func dismantleNSView(_ scroll: TranslationScrollView, coordinator: Coordinator) {
        scroll.onMetrics = { _, _ in }
        coordinator.pending?.cancel()
    }
    final class Coordinator {
        var parent: NativeTranslationResult
        var jumpRevision = 0
        var pending: DispatchWorkItem?
        init(_ parent: NativeTranslationResult) { self.parent = parent }
        func publish(height: CGFloat, latest: Bool) {
            pending?.cancel()
            guard abs(parent.height - height) > 0.5 || parent.showsLatest != latest else { return }
            let update = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.parent.height = height
                self.parent.showsLatest = latest
            }
            pending = update
            DispatchQueue.main.async(execute: update)
        }
    }
}

struct TranslationResult: View {
    @Bindable var model: AppModel
    let maximumHeight: CGFloat
    @ViewState<CGFloat> private var height = TranslationScrollView.minimumHeight
    @ViewState<Bool> private var showsLatest = false
    @ViewState<Int> private var jumpRevision = 0
    var body: some View {
        VStack(spacing: TranslatorLayout.inset) {
            NativeTranslationResult(text: model.output, revision: model.resultRevision, streaming: model.streaming, jumpRevision: jumpRevision, height: $height, showsLatest: $showsLatest)
                .frame(height: min(height, max(TranslationScrollView.minimumHeight, maximumHeight - TranslatorLayout.inset - TranslatorLayout.footerHeight)))
                .overlay(alignment: .topLeading) {
                    if model.streaming && model.output.isEmpty {
                        Text("正在翻译…").font(.system(size: 12)).foregroundStyle(Theme.muted)
                            .frame(height: TranslationScrollView.minimumHeight, alignment: .leading).allowsHitTesting(false)
                    }
                }
            HStack(spacing: 6) {
                IconButton(symbol: "speaker.wave.2", label: "朗读译文", selected: model.speech.channel == "result", action: model.speakOutput)
                    .disabled(model.streaming || model.output.isEmpty)
                Spacer(minLength: 0)
                if showsLatest {
                    IconButton(symbol: "arrow.down", label: "回到最新译文") { jumpRevision += 1 }
                }
                if model.streaming {
                    IconButton(symbol: "stop", label: "停止翻译", action: model.stop)
                }
                IconButton(symbol: model.isFavorite ? "star.fill" : "star", label: model.isFavorite ? "取消收藏" : "收藏到生词本", action: model.toggleFavorite)
                    .disabled(model.streaming || model.currentEntry == nil)
                Button(model.copied ? "已复制" : "复制", action: model.copyResult)
                    .buttonStyle(GlintButtonStyle()).font(.system(size: 12))
                    .disabled(model.streaming || model.output.isEmpty)
            }.frame(height: TranslatorLayout.footerHeight).accessibilityIdentifier("translation-actions")
        }
    }
}
