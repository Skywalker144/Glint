import AppKit
import SwiftUI
import GlintCore

final class GlintPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var onEscape: () -> Void = {}
    override func cancelOperation(_ sender: Any?) { onEscape() }
    override func performClose(_ sender: Any?) { onEscape() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape() } else { super.keyDown(with: event) }
    }
}

@MainActor
final class GlintWindowController: NSObject, NSWindowDelegate {
    let window: GlintPanel
    var pinned: () -> Bool = { false }
    var onFrameChanged: (CGRect) -> Void = { _ in }
    var onAvailableHeightChanged: (CGFloat) -> Void = { _ in }
    let translator: Bool
    private var changingFrame = false
    private var pendingHeight: CGFloat?
    private var heightUpdateScheduled = false
    private var availableHeight: CGFloat {
        let area = window.screen?.visibleFrame ?? ScreenCoordinates.screen(at: NSEvent.mouseLocation).visibleFrame
        if translator { return min(600, max(100, window.frame.maxY - area.minY)) }
        return min(720, area.height - 20)
    }
    init<Content: View>(title: String, size: CGSize, translator: Bool = false, resizable: Bool = false, root: Content) {
        self.translator = translator
        var mask: NSWindow.StyleMask = [.borderless]
        if resizable { mask.insert(.resizable) }
        window = GlintPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: mask, backing: .buffered, defer: false)
        super.init()
        window.title = title; window.isOpaque = false; window.backgroundColor = .clear
        window.hasShadow = true; window.hidesOnDeactivate = false; window.isReleasedWhenClosed = false
        window.isFloatingPanel = translator; window.level = translator ? .floating : .normal
        window.collectionBehavior = translator ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.fullScreenAuxiliary]
        window.animationBehavior = .none; window.delegate = self
        window.onEscape = { [weak self] in self?.hide() }
        let hosting = NSHostingView(rootView: root.frame(maxWidth: .infinity, minHeight: translator ? 0 : nil, maxHeight: .infinity, alignment: translator ? .top : .center))
        hosting.sizingOptions = []; hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        window.minSize = translator ? CGSize(width: 360, height: 100) : CGSize(width: resizable ? 480 : size.width, height: 360)
        window.maxSize = translator ? CGSize(width: 820, height: 600) : CGSize(width: resizable ? 1600 : size.width, height: 1000)
        if translator { window.center() }
    }
    func show(nearCursor: Bool = false) {
        let area = ScreenCoordinates.screen(at: NSEvent.mouseLocation).visibleFrame
        if nearCursor {
            let mouse = NSEvent.mouseLocation
            let origin = CGPoint(x: min(max(mouse.x + 16, area.minX), area.maxX - window.frame.width), y: min(max(mouse.y - window.frame.height - 12, area.minY), area.maxY - window.frame.height))
            window.setFrameOrigin(origin)
        } else if !window.isVisible && !pinned() {
            window.setFrameOrigin(CGPoint(x: area.midX - window.frame.width / 2, y: area.midY - window.frame.height / 2))
        }
        if translator { onAvailableHeightChanged(availableHeight) }
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); window.makeMain()
    }
    func hide() { window.orderOut(nil) }
    func fitHeight(_ value: CGFloat) {
        pendingHeight = value
        guard !heightUpdateScheduled else { return }
        heightUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self, let value = self.pendingHeight else { return }
            self.heightUpdateScheduled = false; self.pendingHeight = nil
            let area = self.window.screen?.visibleFrame ?? ScreenCoordinates.screen(at: NSEvent.mouseLocation).visibleFrame
            let maximumHeight = self.availableHeight
            if self.translator { self.onAvailableHeightChanged(maximumHeight) }
            let height = min(maximumHeight, max(self.translator ? 100 : 360, ceil(value)))
            guard abs(self.window.frame.height - height) > 0.5 else { return }
            self.changingFrame = true
            var frame = self.window.frame
            frame.origin.y = self.translator ? frame.maxY - height : max(area.minY, frame.maxY - height)
            frame.size.height = height
            if self.translator {
                self.window.minSize = CGSize(width: 360, height: height)
                self.window.maxSize = CGSize(width: 820, height: height)
            }
            self.window.setFrame(frame, display: true); self.changingFrame = false
        }
    }
    func windowDidResignKey(_ notification: Notification) {
        if translator && !pinned() && !window.inLiveResize { hide() }
    }
    func windowDidResize(_ notification: Notification) { if !changingFrame { onFrameChanged(window.frame) } }
    func windowDidMove(_ notification: Notification) {
        if !changingFrame {
            if translator { onAvailableHeightChanged(availableHeight) }
            onFrameChanged(window.frame)
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hide(); return false }
}
