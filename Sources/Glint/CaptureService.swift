import AppKit
import ScreenCaptureKit
import Vision
import GlintCore

struct CapturedDisplay {
    let frame: CGRect
    let image: CGImage
}

@MainActor
final class CaptureService {
    private var windows: [NSPanel] = []
    private var continuation: CheckedContinuation<CGImage?, Error>?
    private(set) var active = false
    func capture() async throws -> CGImage? {
        guard !active else { return nil }
        active = true
        defer { active = false }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else { throw GlintError.message("截图翻译需要屏幕录制权限，请在设置 → 权限中授权后重启应用。") }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownApps = content.applications.filter { $0.processID == getpid() }
        var displays: [CapturedDisplay] = []
        for screen in NSScreen.screens {
            let identifier = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            guard let display = content.displays.first(where: { $0.displayID == identifier }) else { continue }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            displays.append(CapturedDisplay(frame: screen.frame, image: image))
            try Task.checkCancellation()
        }
        guard !displays.isEmpty else { throw GlintError.message("无法获取显示器画面") }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            var start: CGPoint?
            var selection: CGRect?
            for display in displays {
                let panel = GlintPanel(contentRect: display.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                panel.level = .screenSaver; panel.isOpaque = true; panel.backgroundColor = .black; panel.hasShadow = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.isReleasedWhenClosed = false
                panel.onEscape = { [weak self] in self?.finish() }
                let overlay = CaptureOverlay(frame: CGRect(origin: .zero, size: display.frame.size), image: display.image)
                overlay.begin = { start = $0; selection = nil }
                overlay.drag = { [weak self] point in
                    guard let start else { return }
                    let rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
                    selection = rect
                    for window in self?.windows ?? [] {
                        let local = CGRect(x: rect.minX - window.frame.minX, y: window.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
                        (window.contentView as? CaptureOverlay)?.selection = local.intersection(CGRect(origin: .zero, size: window.frame.size))
                    }
                }
                overlay.complete = { [weak self] accepted in
                    self?.finish(accepted ? selection.flatMap { Self.composite(displays, selection: $0) } : nil)
                }
                panel.contentView = overlay; windows.append(panel)
                panel.orderFrontRegardless(); panel.makeFirstResponder(overlay)
            }
            NSApp.activate(ignoringOtherApps: true)
            windows.first { $0.frame.contains(NSEvent.mouseLocation) }?.makeKeyAndOrderFront(nil)
        }
    }
    func finish(_ image: CGImage? = nil) {
        windows.forEach { $0.orderOut(nil) }; windows.removeAll()
        let continuation = continuation; self.continuation = nil; continuation?.resume(returning: image)
    }
    static func composite(_ displays: [CapturedDisplay], selection: CGRect) -> CGImage? {
        let intersecting = displays.filter { $0.frame.intersects(selection) }
        guard selection.width >= 3, selection.height >= 3,
              let scale = intersecting.map({ CGFloat($0.image.width) / $0.frame.width }).max(),
              let context = CGContext(data: nil, width: Int(ceil(selection.width * scale)), height: Int(ceil(selection.height * scale)), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        for display in intersecting {
            let rect = display.frame.intersection(selection)
            let sx = CGFloat(display.image.width) / display.frame.width, sy = CGFloat(display.image.height) / display.frame.height
            let pixels = CGRect(x: (rect.minX - display.frame.minX) * sx, y: (display.frame.maxY - rect.maxY) * sy, width: rect.width * sx, height: rect.height * sy).integral
            guard let crop = display.image.cropping(to: pixels) else { continue }
            context.draw(crop, in: CGRect(x: (rect.minX - selection.minX) * scale, y: (rect.minY - selection.minY) * scale, width: rect.width * scale, height: rect.height * scale))
        }
        return context.makeImage()
    }
    static func recognize(_ image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
            let supported = try request.supportedRecognitionLanguages()
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja", "ko"].filter { supported.contains($0) }
            try VNImageRequestHandler(cgImage: image).perform([request])
            return OCRText.paragraphs((request.results ?? []).compactMap { observation in
                observation.topCandidates(1).first.map { OCRLine(text: $0.string, bounds: observation.boundingBox) }
            })
        }.value
    }
}

final class CaptureOverlay: NSView {
    let image: NSImage
    var begin: (CGPoint) -> Void = { _ in }
    var drag: (CGPoint) -> Void = { _ in }
    var complete: (Bool) -> Void = { _ in }
    var selection: CGRect? { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(frame: CGRect, image: CGImage) { self.image = NSImage(cgImage: image, size: frame.size); super.init(frame: frame) }
    required init?(coder: NSCoder) { nil }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        NSColor.black.withAlphaComponent(0.4).setFill(); bounds.fill()
        if let selection, !selection.isNull {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: selection).addClip()
            image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
            NSColor.white.setStroke(); let border = NSBezierPath(rect: selection); border.lineWidth = 1; border.stroke()
            let label = "\(Int(selection.width)) × \(Int(selection.height))"
            label.draw(at: CGPoint(x: selection.minX, y: max(8, selection.minY - 24)), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white])
        } else {
            "拖动选择区域 · 可跨显示器 · Esc 取消".draw(at: CGPoint(x: 24, y: 24), withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.white])
        }
    }
    override func mouseDown(with event: NSEvent) { if let window { begin(window.convertPoint(toScreen: event.locationInWindow)) } }
    override func mouseDragged(with event: NSEvent) { if let window { drag(window.convertPoint(toScreen: event.locationInWindow)) } }
    override func mouseUp(with event: NSEvent) { mouseDragged(with: event); complete(true) }
    override func rightMouseDown(with event: NSEvent) { complete(false) }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { complete(false) } }
}
