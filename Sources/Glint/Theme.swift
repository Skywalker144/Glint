import SwiftUI
import AppKit

typealias ViewState<Value> = SwiftUI.State<Value>

extension NSColor {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
        }
    }
}

enum Theme {
    static let background = Color(nsColor: .adaptive(0xffffff, 0x1c1c1e))
    static let surface = Color(nsColor: .adaptive(0xf4f4f5, 0x2a2a2d))
    static let hover = Color(nsColor: .adaptive(0xeaeaec, 0x34343a))
    static let pressed = Color(nsColor: .adaptive(0xdcdce0, 0x45454c))
    static let text = Color(nsColor: .adaptive(0x1a1a1a, 0xf2f2f5))
    static let muted = Color(nsColor: .adaptive(0x8a8a8e, 0x98989f))
    static let border = Color(nsColor: .adaptive(0xe4e4e7, 0x38383c))
    static let card = Color(nsColor: .adaptive(0xffffff, 0x232326))
}

enum TranslatorLayout {
    static let maximumHeight: CGFloat = 600
    static let inset: CGFloat = 10
    static let widthHandleWidth: CGFloat = 6
    static let resultInset: CGFloat = 15
    static let resultFooterSpacing: CGFloat = 6
    static let bottomInset: CGFloat = 6
    static let footerHeight: CGFloat = 28
}

class OverlayScrollView: NSScrollView {
    override var scrollerStyle: NSScroller.Style {
        get { super.scrollerStyle }
        set { super.scrollerStyle = .overlay }
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false; verticalScroller = ThinScroller(); hasVerticalScroller = true; autohidesScrollers = true
        verticalScroller?.controlSize = .small
        scrollerStyle = .overlay
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class ThinScroller: NSScroller {
    var knobFrame: NSRect {
        let knob = rect(for: .knob).insetBy(dx: 0, dy: 2)
        return NSRect(x: bounds.maxX - 5, y: knob.minY, width: 3, height: knob.height)
    }
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
    override func drawKnob() {
        let knob = knobFrame
        guard knob.height > 0 else { return }
        NSColor.secondaryLabelColor.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: knob, xRadius: 1.5, yRadius: 1.5).fill()
    }
}

struct GlintButtonStyle: ButtonStyle {
    var selected = false
    var horizontalPadding: CGFloat = 7
    var verticalPadding: CGFloat = 4
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState<Bool> private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected || hovering || configuration.isPressed ? Theme.text : Theme.muted)
            .padding(.horizontal, horizontalPadding).padding(.vertical, verticalPadding)
            .background(enabled && configuration.isPressed ? Theme.pressed : selected || (enabled && hovering) ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .scaleEffect(enabled && configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(enabled ? 1 : 0.35)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
    }
}

struct IconButton: View {
    let symbol: String
    let label: String
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .regular)).frame(width: 24, height: 24)
        }
        .buttonStyle(GlintButtonStyle(selected: selected, horizontalPadding: 0, verticalPadding: 0))
        .help(label).accessibilityLabel(label)
    }
}

struct WindowCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.font(.system(size: 13)).foregroundStyle(Theme.text).tint(Theme.text)
            .background(Theme.background)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
    }
}

struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        private var drag: (x: CGFloat, top: CGFloat, pointer: NSPoint)?
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            guard (window as? GlintPanel)?.allowsOffscreen == true else { window.performDrag(with: event); return }
            drag = (window.frame.minX, window.frame.maxY, window.convertPoint(toScreen: event.locationInWindow))
        }
        override func mouseDragged(with event: NSEvent) {
            guard let window, let drag else { return }
            let pointer = window.convertPoint(toScreen: event.locationInWindow)
            window.setFrameOrigin(NSPoint(x: drag.x + pointer.x - drag.pointer.x, y: drag.top + pointer.y - drag.pointer.y - window.frame.height))
        }
        override func mouseUp(with event: NSEvent) { drag = nil }
    }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}

struct WindowWidthHandle: NSViewRepresentable {
    final class Handle: NSView {
        private var hovering = false
        private var drag: (width: CGFloat, pointerX: CGFloat, top: CGFloat)?
        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
        override func updateTrackingAreas() {
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self))
            super.updateTrackingAreas()
        }
        override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
        override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
        override func draw(_ dirtyRect: NSRect) {
            if hovering { NSColor.secondaryLabelColor.setFill(); NSBezierPath(roundedRect: CGRect(x: 2, y: bounds.midY - 12, width: 2, height: 24), xRadius: 1, yRadius: 1).fill() }
        }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            drag = (window.frame.width, window.convertPoint(toScreen: event.locationInWindow).x, window.frame.maxY)
        }
        override func mouseDragged(with event: NSEvent) {
            guard let window, let drag else { return }
            var frame = window.frame
            frame.size.width = min(window.maxSize.width, max(window.minSize.width, drag.width + window.convertPoint(toScreen: event.locationInWindow).x - drag.pointerX))
            frame.origin.y = drag.top - frame.height
            window.setFrame(frame, display: true)
        }
        override func mouseUp(with event: NSEvent) { drag = nil }
    }
    func makeNSView(context: Context) -> Handle { Handle() }
    func updateNSView(_ view: Handle, context: Context) {}
}
