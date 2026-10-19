import AppKit
import SwiftUI

final class InputTextView: NSTextView {
    var submit: () -> Void = {}
    var dismiss: () -> Void = {}
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            ("输入或粘贴文字…" as NSString).draw(at: textContainerOrigin, withAttributes: [.font: font ?? .systemFont(ofSize: 14), .foregroundColor: NSColor.adaptive(0x8a8a8e, 0x98989f)])
        }
    }
    override func keyDown(with event: NSEvent) {
        if !hasMarkedText(), event.keyCode == 36, !event.modifierFlags.contains(.shift) { submit(); return }
        if !hasMarkedText(), event.keyCode == 53 { dismiss(); return }
        super.keyDown(with: event)
    }
}

final class InputScrollView: OverlayScrollView {
    static let font = NSFont.systemFont(ofSize: 14)
    static let minimumHeight: CGFloat = 40
    static let maximumAutomaticHeight = ceil(NSLayoutManager().defaultLineHeight(for: font) * 2.5) + 16
    var onHeightChange: (CGFloat) -> Void = { _ in }
    override init(frame: NSRect) {
        super.init(frame: frame)
        scrollerInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        let view = InputTextView()
        view.isRichText = false; view.drawsBackground = false; view.font = Self.font
        view.textColor = .adaptive(0x1a1a1a, 0xf2f2f5); view.insertionPointColor = .labelColor
        view.textContainerInset = NSSize(width: 12, height: 8); view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = false
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.setAccessibilityLabel("输入或粘贴文字"); view.setAccessibilityIdentifier("translation-input")
        documentView = view
    }
    required init?(coder: NSCoder) { fatalError() }
    override func tile() {
        super.tile()
        layoutText()
    }
    func layoutText() {
        guard let view = documentView as? InputTextView, let container = view.textContainer, let manager = view.layoutManager else { return }
        container.containerSize = NSSize(width: max(1, contentSize.width - view.textContainerInset.width * 2 - 28), height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let lineHeight = manager.defaultLineHeight(for: Self.font)
        let textHeight = max(lineHeight, ceil(manager.usedRect(for: container).height))
        let inset = textHeight <= ceil(lineHeight) ? max(8, (contentSize.height - textHeight) / 2) : 8
        if abs(view.textContainerInset.height - inset) > 0.25 { view.textContainerInset.height = inset }
        let size = NSSize(width: contentSize.width, height: max(contentSize.height, textHeight + 16))
        if view.frame.size != size { view.setFrameSize(size) }
        view.needsDisplay = true
        onHeightChange(min(Self.maximumAutomaticHeight, max(Self.minimumHeight, textHeight + 16)))
    }
}

struct TranslationInput: View {
    @Bindable var model: AppModel
    @ViewState<CGFloat> private var automaticHeight = InputScrollView.minimumHeight
    @ViewState<CGFloat?> private var manualHeight = nil
    private var height: CGFloat { manualHeight ?? automaticHeight }
    var body: some View {
        NativeInput(text: Binding(get: { model.input }, set: model.editInput), selectAllOnFocus: model.selectAllOnFocus, focusRevision: model.inputFocusRevision, resultFocusRevision: model.resultFocusRevision, submit: { model.translate() }, dismiss: model.hideTranslator, height: $automaticHeight)
            .frame(height: height)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if !model.input.isEmpty { IconButton(symbol: "xmark.circle.fill", label: "清空输入", action: model.clearInput).padding(8) }
            }
            .padding(.vertical, InputHeightHandle.thickness)
            .overlay(alignment: .top) { InputHeightHandle(edge: .top, height: height, resize: { manualHeight = $0 }).frame(height: InputHeightHandle.thickness).padding(.horizontal, 10) }
            .overlay(alignment: .bottom) { InputHeightHandle(edge: .bottom, height: height, resize: { manualHeight = $0 }).frame(height: InputHeightHandle.thickness).padding(.horizontal, 10) }
            .onChange(of: model.input.isEmpty) { _, empty in if empty { manualHeight = nil } }
    }
}

struct InputHeightHandle: NSViewRepresentable {
    static let thickness: CGFloat = 6
    enum Edge { case top, bottom }
    let edge: Edge
    let height: CGFloat
    let resize: (CGFloat?) -> Void
    final class Handle: NSView {
        var edge = Edge.bottom
        var height = InputScrollView.minimumHeight
        var resize: (CGFloat?) -> Void = { _ in }
        private var hovering = false
        private var drag: (height: CGFloat, pointerY: CGFloat, top: CGFloat)?
        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeUpDown) }
        override func cursorUpdate(with event: NSEvent) { NSCursor.resizeUpDown.set() }
        override func updateTrackingAreas() {
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .cursorUpdate, .inVisibleRect], owner: self))
            super.updateTrackingAreas()
        }
        override func mouseEntered(with event: NSEvent) { hovering = true; NSCursor.resizeUpDown.set(); needsDisplay = true }
        override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
        override func draw(_ dirtyRect: NSRect) {
            if hovering {
                NSColor.secondaryLabelColor.withAlphaComponent(0.4).setFill()
                NSBezierPath(roundedRect: NSRect(x: bounds.midX - 12, y: bounds.midY - 1, width: 24, height: 2), xRadius: 1, yRadius: 1).fill()
            }
        }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { resize(nil); return }
            guard let window else { return }
            drag = (height, window.convertPoint(toScreen: event.locationInWindow).y, window.frame.maxY)
        }
        override func mouseDragged(with event: NSEvent) {
            guard let window, let drag else { return }
            let offset = window.convertPoint(toScreen: event.locationInWindow).y - drag.pointerY
            let next = min(TranslatorLayout.maximumHeight / 2, max(InputScrollView.minimumHeight, drag.height + (edge == .top ? offset : -offset)))
            if edge == .top { window.setFrameOrigin(NSPoint(x: window.frame.minX, y: drag.top + next - drag.height - window.frame.height)) }
            resize(next)
        }
        override func mouseUp(with event: NSEvent) { drag = nil }
    }
    func makeNSView(context: Context) -> Handle {
        let view = Handle()
        view.toolTip = "拖动调整原文高度，双击恢复自动高度"
        return view
    }
    func updateNSView(_ view: Handle, context: Context) { view.edge = edge; view.height = height; view.resize = resize }
}

struct NativeInput: NSViewRepresentable {
    @Binding var text: String
    let selectAllOnFocus: Bool
    let focusRevision: Int
    let resultFocusRevision: Int
    let submit: () -> Void
    let dismiss: () -> Void
    @Binding var height: CGFloat
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> InputScrollView {
        let scroll = InputScrollView()
        let coordinator = context.coordinator
        (scroll.documentView as? InputTextView)?.delegate = coordinator
        scroll.onHeightChange = { [weak coordinator] in coordinator?.publish($0) }
        return scroll
    }
    func updateNSView(_ scroll: InputScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? InputTextView else { return }
        view.submit = submit; view.dismiss = dismiss
        if view.string != text && !view.hasMarkedText() { view.string = text }
        if context.coordinator.focusRevision != focusRevision {
            context.coordinator.focusRevision = focusRevision
            DispatchQueue.main.async { view.window?.makeFirstResponder(view); if selectAllOnFocus { view.selectAll(nil) } }
        }
        if context.coordinator.resultFocusRevision != resultFocusRevision {
            context.coordinator.resultFocusRevision = resultFocusRevision
            DispatchQueue.main.async { view.window?.makeFirstResponder(nil) }
        }
        scroll.layoutText()
    }
    static func dismantleNSView(_ scroll: InputScrollView, coordinator: Coordinator) {
        scroll.onHeightChange = { _ in }
        coordinator.pending?.cancel()
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeInput
        var focusRevision = 0
        var resultFocusRevision = 0
        var pending: DispatchWorkItem?
        init(_ parent: NativeInput) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? InputTextView else { return }
            parent.text = view.string
            (view.enclosingScrollView as? InputScrollView)?.layoutText()
        }
        func publish(_ height: CGFloat) {
            pending?.cancel()
            guard abs(parent.height - height) > 0.5 else { return }
            let update = DispatchWorkItem { [weak self] in self?.parent.height = height }
            pending = update
            DispatchQueue.main.async(execute: update)
        }
    }
}
