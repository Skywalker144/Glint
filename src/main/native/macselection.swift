import AppKit
import ApplicationServices

struct MonitorEvent: Encodable {
    let type: String
    var text: String? = nil
    var x: Double? = nil
    var y: Double? = nil
    var accessibility: Bool? = nil
}

final class SelectionMonitor {
    private let parentPID: pid_t
    private let system = AXUIElementCreateSystemWide()
    private let reader = DispatchQueue(label: "com.glint.selection-reader")
    private var revision = 0
    private var startPoint: CGPoint?
    private var dragged = false
    private var monitors: [Any] = []
    private var keyMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var permissionTimer: Timer?
    private var trusted: Bool?

    init(parentPID: pid_t) {
        self.parentPID = parentPID
        AXUIElementSetMessagingTimeout(system, 0.15)
    }

    func emit(_ event: MonitorEvent) {
        guard let data = try? JSONEncoder().encode(event) else { return }
        FileHandle.standardOutput.write(data + Data([10]))
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func selectedText(pid: pid_t, point: CGPoint) -> String? {
        let application = AXUIElementCreateApplication(pid)
        var hit: AXUIElement?
        AXUIElementCopyElementAtPosition(application, Float(point.x), Float(point.y), &hit)
        let focused = elementAttribute(application, kAXFocusedUIElementAttribute)
        var candidates: [AXUIElement] = []
        if let hit { candidates.append(hit) }
        if let focused, let hit,
           let hitWindow = elementAttribute(hit, kAXWindowAttribute),
           let focusedWindow = elementAttribute(focused, kAXWindowAttribute),
           CFEqual(hitWindow, focusedWindow) {
            candidates.append(focused)
        }
        for candidate in candidates {
            var current: AXUIElement? = candidate
            for _ in 0..<6 {
                guard let element = current else { break }
                if attribute(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole { break }
                if let text = attribute(element, kAXSelectedTextAttribute) as? String,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
                current = elementAttribute(element, kAXParentAttribute)
            }
        }
        return nil
    }

    private func dismiss(resetGesture: Bool = true) {
        revision += 1
        if resetGesture {
            startPoint = nil
            dragged = false
        }
        emit(MonitorEvent(type: "dismiss"))
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            revision += 1
            startPoint = event.cgEvent?.location
            dragged = false
            if let point = startPoint {
                emit(MonitorEvent(type: "pointer", x: point.x, y: point.y))
            }
        case .leftMouseDragged:
            if let startPoint, let point = event.cgEvent?.location {
                dragged = dragged || hypot(point.x - startPoint.x, point.y - startPoint.y) >= 3
            }
        case .leftMouseUp:
            guard let startPoint, let point = event.cgEvent?.location,
                  dragged || event.clickCount >= 2 || event.modifierFlags.contains(.shift),
                  AXIsProcessTrusted(),
                  let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
                  pid != parentPID, pid != getpid() else { return }
            let requestRevision = revision
            self.startPoint = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self, self.revision == requestRevision else { return }
                self.reader.async { [weak self] in
                    guard let self else { return }
                    let text = self.selectedText(pid: pid, point: startPoint)
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.revision == requestRevision,
                              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                        self.emit(MonitorEvent(type: "selection", text: text ?? "", x: point.x, y: point.y))
                    }
                }
            }
        default:
            dismiss()
        }
    }

    private func refreshPermission() {
        let currentTrust = AXIsProcessTrusted()
        if currentTrust {
            if keyMonitor == nil {
                keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
                    self?.dismiss()
                }
            }
        } else {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            dismiss()
        }
        if trusted != currentTrust {
            trusted = currentTrust
            emit(MonitorEvent(type: "ready", accessibility: currentTrust))
        }
    }

    func start() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp,
                                           .rightMouseDown, .otherMouseDown, .scrollWheel]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
        }) { monitors.append(monitor) }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.dismiss(resetGesture: false) }
        refreshPermission()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshPermission()
            if kill(self?.parentPID ?? 0, 0) != 0 { NSApplication.shared.terminate(nil) }
        }
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
guard let argument = CommandLine.arguments.dropFirst().first, let parentPID = Int32(argument), parentPID > 0 else {
    exit(1)
}
let monitor = SelectionMonitor(parentPID: parentPID)
monitor.start()
application.run()
