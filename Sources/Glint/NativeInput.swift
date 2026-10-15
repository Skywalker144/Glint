import AppKit
import SwiftUI

final class InputTextView: NSTextView {
    var submit: () -> Void = {}
    var dismiss: () -> Void = {}
    override func keyDown(with event: NSEvent) {
        if !hasMarkedText(), event.keyCode == 36, !event.modifierFlags.contains(.shift) { submit(); return }
        if !hasMarkedText(), event.keyCode == 53 { dismiss(); return }
        super.keyDown(with: event)
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
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let view = InputTextView()
        view.isRichText = false; view.drawsBackground = false; view.font = .systemFont(ofSize: 14)
        view.textColor = .adaptive(0x1a1a1a, 0xf2f2f5); view.insertionPointColor = .labelColor
        view.textContainerInset = NSSize(width: 10, height: 8); view.textContainer?.lineFragmentPadding = 2
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false; view.delegate = context.coordinator
        view.setAccessibilityLabel("输入或粘贴文字"); view.setAccessibilityIdentifier("translation-input")
        scroll.documentView = view; return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
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
            guard let container = view.textContainer, let manager = view.layoutManager else { return }
            manager.ensureLayout(for: container)
            let size = min(62, max(40, ceil(manager.usedRect(for: container).height) + 16))
            if abs(parent.height - size) > 0.5 { DispatchQueue.main.async { self.parent.height = size } }
        }
    }
}
