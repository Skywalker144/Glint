import AppKit
import ScreenCaptureKit
import Vision
import GlintCore

@MainActor
final class CaptureService {
    private var window: NSPanel?
    private var continuation: CheckedContinuation<CGImage?, Error>?
    var active: Bool { window != nil }
    func capture() async throws -> CGImage? {
        guard !active else { return nil }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else { throw GlintError.message("截图翻译需要屏幕录制权限，请在设置 → 权限中授权后重启应用。") }
        let screen = ScreenCoordinates.screen(at: NSEvent.mouseLocation)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let identifier = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        guard let display = content.displays.first(where: { $0.displayID == identifier }) else { throw GlintError.message("无法获取当前显示器") }
        let ownApps = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(screen.frame.width * screen.backingScaleFactor)
        config.height = Int(screen.frame.height * screen.backingScaleFactor)
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let panel = GlintPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.level = .screenSaver; panel.isOpaque = true; panel.backgroundColor = .black; panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.isReleasedWhenClosed = false
            let overlay = CaptureOverlay(frame: CGRect(origin: .zero, size: screen.frame.size), image: image)
            overlay.complete = { [weak self] rect in
                var cropped: CGImage?
                if let rect, rect.width >= 3, rect.height >= 3 {
                    let sx = CGFloat(image.width) / screen.frame.width, sy = CGFloat(image.height) / screen.frame.height
                    let pixels = CGRect(x: rect.minX * sx, y: rect.minY * sy, width: rect.width * sx, height: rect.height * sy).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
                    cropped = image.cropping(to: pixels)
                }
                self?.finish(cropped)
            }
            panel.contentView = overlay; self.window = panel
            NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(overlay)
        }
    }
    func finish(_ image: CGImage? = nil) {
        window?.orderOut(nil); window = nil
        let continuation = continuation; self.continuation = nil; continuation?.resume(returning: image)
    }
    static func recognize(_ image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
            let supported = try request.supportedRecognitionLanguages()
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja", "ko"].filter { supported.contains($0) }
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).sorted {
                abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.012 ? $0.boundingBox.midY > $1.boundingBox.midY : $0.boundingBox.minX < $1.boundingBox.minX
            }.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }
}

final class CaptureOverlay: NSView {
    let image: NSImage
    var complete: (CGRect?) -> Void = { _ in }
    private var start: CGPoint?
    private var selection: CGRect?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(frame: CGRect, image: CGImage) { self.image = NSImage(cgImage: image, size: frame.size); super.init(frame: frame) }
    required init?(coder: NSCoder) { nil }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        NSColor.black.withAlphaComponent(0.4).setFill(); bounds.fill()
        if let selection {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: selection).addClip()
            image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
            NSColor.white.setStroke(); let border = NSBezierPath(rect: selection); border.lineWidth = 1; border.stroke()
            let label = "\(Int(selection.width)) × \(Int(selection.height))"
            label.draw(at: CGPoint(x: selection.minX, y: max(8, selection.minY - 24)), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white])
        } else {
            "拖动选择区域 · Esc 取消".draw(at: CGPoint(x: 24, y: 24), withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.white])
        }
    }
    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil); selection = nil }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { complete(selection) }
    override func rightMouseDown(with event: NSEvent) { complete(nil) }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { complete(nil) } }
}
