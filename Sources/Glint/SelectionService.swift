import AppKit
import ApplicationServices
import GlintCore

@MainActor
enum ScreenCoordinates {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }
    static func cocoa(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: primaryHeight - point.y) }
    static func quartz(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: primaryHeight - point.y) }
    static func screen(at point: CGPoint) -> NSScreen { NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens[0] }
    static func popup(at point: CGPoint, area: CGRect, options: PopupOptions) -> CGRect {
        let size: CGFloat = 40, distance = CGFloat(options.distance)
        let right = point.x + distance, left = point.x - size - distance
        let above = point.y + distance, below = point.y - size - distance
        let toRight = options.position.hasSuffix("right"), toBottom = options.position.hasPrefix("bottom")
        var x = toRight ? right : left, y = toBottom ? below : above
        if x < area.minX || x + size > area.maxX { x = toRight ? left : right }
        if y < area.minY || y + size > area.maxY { y = toBottom ? above : below }
        return CGRect(x: max(area.minX, min(x, area.maxX - size)).rounded(), y: max(area.minY, min(y, area.maxY - size)).rounded(), width: size, height: size)
    }
}

@MainActor
final class SelectionService {
    private let monitor = SelectionMonitor(parentPID: getpid(), delayMilliseconds: 120)
    private var popup: NSPanel?
    private var selected = ""
    private var enabled = false
    private var options = PopupOptions()
    var isBlocked: (Bool) -> Bool = { _ in false }
    var onTranslate: (String) -> Void = { _ in }
    init() {
        monitor.onEvent = { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
    }
    func configure(enabled: Bool, options: PopupOptions) {
        self.options = options; monitor.selectionDelay = Double(options.delayMs) / 1000
        dismiss()
        if self.enabled != enabled {
            self.enabled = enabled
            if enabled { monitor.start() } else { monitor.stop() }
        }
    }
    func dismiss() { selected = ""; popup?.orderOut(nil) }
    private func handle(_ event: MonitorEvent) {
        guard enabled else { return }
        switch event.type {
        case "pointer":
            if let x = event.x, let y = event.y, popup?.isVisible == true, popup?.frame.contains(ScreenCoordinates.cocoa(CGPoint(x: x, y: y))) == true { return }
            dismiss()
        case "dismiss": dismiss()
        case "selection":
            dismiss()
            guard !isBlocked(false), let text = event.text?.trimmed, !text.isEmpty, let x = event.x, let y = event.y else { return }
            selected = text
            if popup == nil {
                let panel = PassivePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isFloatingPanel = true; panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
                panel.hasShadow = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
                let button = SelectionButton(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
                button.target = self; button.action = #selector(activate)
                panel.contentView = button; popup = panel
            }
            let point = ScreenCoordinates.cocoa(CGPoint(x: x, y: y))
            popup?.setFrame(ScreenCoordinates.popup(at: point, area: ScreenCoordinates.screen(at: point).visibleFrame, options: options), display: true)
            popup?.orderFrontRegardless()
        default: break
        }
    }
    @objc private func activate() {
        let text = selected; dismiss()
        if enabled && !text.isEmpty && !isBlocked(true) { onTranslate(text) }
    }
    func selectedText() async throws -> String {
        guard AXIsProcessTrusted() else { throw GlintError.message("划词翻译需要辅助功能权限，请在设置 → 权限中授权后重试。") }
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return "" }
        let point = ScreenCoordinates.quartz(NSEvent.mouseLocation)
        let pid = app.processIdentifier
        return try await SelectionTextReader(
            pasteboard: .general,
            isSourceActive: { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid },
            menuCopy: {
                let item = await Task.detached { SelectionCopyMenu.find(pid: pid) }.value
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, let item else { return nil }
                return { AXUIElementPerformAction(item, kAXPressAction as CFString) == .success }
            },
            shortcutCopy: {
                let source = CGEventSource(stateID: .hidSystemState)
                guard let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else { return false }
                for event in [down, up] {
                    event.flags = .maskCommand
                    event.post(tap: .cghidEventTap)
                }
                return true
            },
            accessibilityText: {
                await Task.detached { SelectionMonitor(parentPID: getpid(), delayMilliseconds: 0).selectedText(pid: pid, point: point) }.value
            }
        ).read()
    }
    func stop() { monitor.stop(); dismiss() }
}

final class PassivePanel: NSPanel { override var canBecomeKey: Bool { false }; override var canBecomeMain: Bool { false } }
final class SelectionButton: NSButton {
    private var hovering = false
    override init(frame: NSRect) { super.init(frame: frame); title = "译"; isBordered = false; font = .systemFont(ofSize: 16, weight: .semibold); setAccessibilityLabel("翻译选中文字") }
    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4.5, dy: 4.5), xRadius: 9, yRadius: 9)
        NSColor(isHighlighted ? Theme.pressed : hovering ? Theme.hover : Theme.card).setFill(); path.fill()
        NSColor.adaptive(0xbcbcc2, 0x66666e).setStroke(); path.lineWidth = 1; path.stroke()
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? .systemFont(ofSize: 16, weight: .semibold), .foregroundColor: NSColor.labelColor]
        let size = title.size(withAttributes: attributes)
        title.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}
