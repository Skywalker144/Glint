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
    static let text = Color(nsColor: .adaptive(0x1a1a1a, 0xf2f2f5))
    static let muted = Color(nsColor: .adaptive(0x8a8a8e, 0x98989f))
    static let border = Color(nsColor: .adaptive(0xe4e4e7, 0x38383c))
    static let card = Color(nsColor: .adaptive(0xffffff, 0x232326))
    static let sidebar = Color(nsColor: .adaptive(0xf2f2f4, 0x18181a))
    static let settingsBackground = Color(nsColor: .adaptive(0xf9f9fa, 0x1c1c1e))
}

struct GlintButtonStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Theme.text : Theme.muted)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(selected || configuration.isPressed ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
    }
}

struct IconButton: View {
    let symbol: String
    let label: String
    var selected = false
    var action: () -> Void
    @ViewState<Bool> private var hovering = false
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 13, weight: .regular)).frame(width: 24, height: 24).foregroundStyle(selected || hovering ? Theme.text : Theme.muted).background(selected || hovering ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 6)) }
            .buttonStyle(.plain).onHover { hovering = $0 }.help(label).accessibilityLabel(label)
    }
}

struct HeightPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
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
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border.opacity(0.8), lineWidth: 1))
    }
}

struct GlintToggle: View {
    let title: String
    var detail = ""
    var symbol: String? = nil
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    .frame(width: 28, height: 28).background(Theme.surface, in: RoundedRectangle(cornerRadius: 7)).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13))
                if !detail.isEmpty { Text(detail).font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(Theme.text).controlSize(.small)
        }.frame(minHeight: 30)
    }
}

struct WindowWidthHandle: NSViewRepresentable {
    final class Handle: NSView {
        private var hovering = false
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
            let initial = window.frame, x = NSEvent.mouseLocation.x
            while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
                if next.type == .leftMouseUp { break }
                var frame = initial
                frame.size.width = min(820, max(360, initial.width + NSEvent.mouseLocation.x - x))
                window.setFrame(frame, display: true)
            }
        }
    }
    func makeNSView(context: Context) -> Handle { Handle() }
    func updateNSView(_ view: Handle, context: Context) {}
}
