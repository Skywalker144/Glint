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

final class InputScrollView: NSScrollView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false; hasVerticalScroller = true; autohidesScrollers = true
        scrollerStyle = .overlay
        let view = InputTextView()
        view.isRichText = false; view.drawsBackground = false; view.font = .systemFont(ofSize: 14)
        view.textColor = .adaptive(0x1a1a1a, 0xf2f2f5); view.insertionPointColor = .labelColor
        view.textContainerInset = NSSize(width: 12, height: 8); view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
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
    @discardableResult func layoutText() -> CGFloat {
        guard let view = documentView as? InputTextView, let container = view.textContainer, let manager = view.layoutManager else { return 40 }
        container.containerSize = NSSize(width: max(1, contentSize.width - view.textContainerInset.width * 2), height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let textHeight = max(manager.defaultLineHeight(for: view.font ?? .systemFont(ofSize: 14)), ceil(manager.usedRect(for: container).height))
        let inset = max(8, (contentSize.height - textHeight) / 2)
        if abs(view.textContainerInset.height - inset) > 0.25 { view.textContainerInset.height = inset }
        let size = NSSize(width: contentSize.width, height: max(contentSize.height, textHeight + 16))
        if view.frame.size != size { view.setFrameSize(size) }
        view.needsDisplay = true
        return min(62, max(40, textHeight + 16))
    }
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
        (scroll.documentView as? InputTextView)?.delegate = context.coordinator
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
        context.coordinator.measure(view)
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeInput
        var focusRevision = 0
        var resultFocusRevision = 0
        init(_ parent: NativeInput) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? InputTextView else { return }
            parent.text = view.string; measure(view)
        }
        func measure(_ view: NSTextView) {
            guard let scroll = view.enclosingScrollView as? InputScrollView else { return }
            let size = scroll.layoutText()
            if abs(parent.height - size) > 0.5 { DispatchQueue.main.async { self.parent.height = size } }
        }
    }
}
