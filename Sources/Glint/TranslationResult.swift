import AppKit
import SwiftUI

final class TranslationScrollView: OverlayScrollView {
    static let minimumHeight = ceil(NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: 15)))
    private let edgeMask = CAGradientLayer()
    private var revision: UUID?
    private var source = ""
    private var updatingLayout = false
    private var layoutWidth: CGFloat = 0
    private(set) var followsEnd = false
    private(set) var preferredHeight = minimumHeight
    var onMetrics: (CGFloat, Bool) -> Void = { _, _ in }
    var distanceFromEnd: CGFloat { max(0, (documentView?.frame.height ?? 0) - contentView.bounds.maxY) }
    var showsLatest: Bool { !followsEnd && distanceFromEnd > 2 }

    override init(frame: NSRect) {
        super.init(frame: frame)
        scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: TranslatorLayout.widthHandleWidth)
        contentView.wantsLayer = true
        contentView.layer?.mask = edgeMask
        edgeMask.startPoint = CGPoint(x: 0.5, y: 0)
        edgeMask.endPoint = CGPoint(x: 0.5, y: 1)
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
        contentView.frame = contentView.frame.insetBy(dx: TranslatorLayout.resultInset, dy: 0)
        updatingLayout = wasUpdating
        layoutTranslation()
    }
    func update(text: String, revision: UUID, appearance: NSAppearance.Name) {
        if self.revision != revision {
            self.revision = revision
            preferredHeight = Self.minimumHeight; followsEnd = false
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
        updateFades()
        onMetrics(preferredHeight, showsLatest)
    }
    private func updateFades() {
        let height = contentView.bounds.height
        guard height > 0 else { return }
        let fade = min(12, height / 2)
        let top = NSColor.black.withAlphaComponent(1 - min(1, max(0, contentView.bounds.minY) / fade)).cgColor
        let bottom = NSColor.black.withAlphaComponent(1 - min(1, distanceFromEnd / fade)).cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeMask.frame = contentView.bounds
        edgeMask.colors = contentView.isFlipped ? [top, NSColor.black.cgColor, NSColor.black.cgColor, bottom] : [bottom, NSColor.black.cgColor, NSColor.black.cgColor, top]
        edgeMask.locations = [0, NSNumber(value: fade / height), NSNumber(value: 1 - fade / height), 1]
        CATransaction.commit()
    }
    @objc private func didScroll() {
        guard !updatingLayout else { return }
        followsEnd = distanceFromEnd <= 2
        updateFades()
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
        scroll.update(text: text, revision: revision, appearance: colorScheme == .dark ? .darkAqua : .aqua)
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
        VStack(spacing: TranslatorLayout.resultFooterSpacing) {
            NativeTranslationResult(text: model.output, revision: model.resultRevision, jumpRevision: jumpRevision, height: $height, showsLatest: $showsLatest)
                .frame(height: min(height, max(TranslationScrollView.minimumHeight, maximumHeight - TranslatorLayout.resultFooterSpacing - TranslatorLayout.footerHeight)))
                .overlay(alignment: .topLeading) {
                    if model.streaming && model.output.isEmpty {
                        Text("正在翻译…").font(.system(size: 12)).foregroundStyle(Theme.muted)
                            .frame(height: TranslationScrollView.minimumHeight, alignment: .leading).padding(.leading, TranslatorLayout.resultInset).allowsHitTesting(false)
                    }
                }
                .opacity(model.resultIsStale ? 0.4 : 1)
            HStack(spacing: 6) {
                SpeechButton(speech: model.speech, channel: "result", label: "朗读译文", action: model.speakOutput)
                    .disabled(model.streaming || model.output.isEmpty || model.resultIsStale)
                Spacer(minLength: 0)
                if showsLatest {
                    IconButton(symbol: "arrow.down", label: "回到最新译文") { jumpRevision += 1 }
                }
                if model.streaming {
                    IconButton(symbol: "stop", label: "停止翻译", action: model.stop)
                }
                IconButton(symbol: model.isFavorite ? "star.fill" : "star", label: model.isFavorite ? "取消收藏" : "收藏到生词本", action: model.toggleFavorite)
                    .disabled(model.streaming || model.currentEntry == nil || model.resultIsStale)
                CopyButton(title: "复制", text: NativeMarkdown.plainText(model.output))
                    .disabled(model.streaming || model.output.isEmpty || model.resultIsStale)
            }.frame(height: TranslatorLayout.footerHeight).padding(.horizontal, TranslatorLayout.inset).accessibilityIdentifier("translation-actions")
        }
    }
}
