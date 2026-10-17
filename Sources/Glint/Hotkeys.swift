import AppKit
import Carbon
import SwiftUI
import GlintCore

struct Hotkey: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    static let keys: [String: UInt32] = ["A":0,"S":1,"D":2,"F":3,"H":4,"G":5,"Z":6,"X":7,"C":8,"V":9,"B":11,"Q":12,"W":13,"E":14,"R":15,"Y":16,"T":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"=":24,"9":25,"7":26,"-":27,"8":28,"0":29,"]":30,"O":31,"U":32,"[":33,"I":34,"P":35,"Return":36,"L":37,"J":38,"'":39,"K":40,";":41,"\\":42,",":43,"/":44,"N":45,"M":46,".":47,"Tab":48,"Space":49,"`":50,"Backspace":51,"Escape":53,"F1":122,"F2":120,"F3":99,"F4":118,"F5":96,"F6":97,"F7":98,"F8":100,"F9":101,"F10":109,"F11":103,"F12":111,"F13":105,"F14":107,"F15":113,"F16":106,"F17":64,"F18":79,"F19":80,"F20":90,"Home":115,"End":119,"PageUp":116,"PageDown":121,"Left":123,"Right":124,"Down":125,"Up":126,"Delete":117]
    static func parse(_ string: String) -> Hotkey? {
        let parts = string.split(separator: "+").map(String.init)
        guard let key = parts.last, let code = keys[key] ?? keys[key.uppercased()] else { return nil }
        var modifiers: UInt32 = 0
        for part in parts.dropLast() {
            switch part {
            case "Alt", "Option": modifiers |= UInt32(optionKey)
            case "Command", "CommandOrControl", "Cmd": modifiers |= UInt32(cmdKey)
            case "Control", "Ctrl": modifiers |= UInt32(controlKey)
            case "Shift": modifiers |= UInt32(shiftKey)
            default: return nil
            }
        }
        return .init(keyCode: code, modifiers: modifiers)
    }
    static func accelerator(_ event: NSEvent) -> String? {
        guard let key = keys.first(where: { $0.value == UInt32(event.keyCode) })?.key else { return nil }
        var parts: [String] = []
        if event.modifierFlags.contains(.command) { parts.append("Command") }
        if event.modifierFlags.contains(.control) { parts.append("Control") }
        if event.modifierFlags.contains(.option) { parts.append("Alt") }
        if event.modifierFlags.contains(.shift) { parts.append("Shift") }
        guard !parts.isEmpty || key.match("^F[0-9]+$") != nil else { return nil }
        return (parts + [key]).joined(separator: "+")
    }
    static func display(_ value: String) -> String {
        value.split(separator: "+").map { ["Command":"⌘", "CommandOrControl":"⌘", "Control":"⌃", "Alt":"⌥", "Shift":"⇧", "Space":"␣", "Return":"↩"] [String($0)] ?? String($0) }.joined()
    }
    var menuKeyEquivalent: String {
        let special: [UInt32: Int] = [123: NSLeftArrowFunctionKey, 124: NSRightArrowFunctionKey, 125: NSDownArrowFunctionKey, 126: NSUpArrowFunctionKey, 115: NSHomeFunctionKey, 119: NSEndFunctionKey, 116: NSPageUpFunctionKey, 121: NSPageDownFunctionKey, 117: NSDeleteFunctionKey]
        if let code = special[keyCode], let scalar = UnicodeScalar(code) { return String(scalar) }
        guard let key = Self.keys.first(where: { $0.value == keyCode })?.key else { return "" }
        if key.hasPrefix("F"), let number = Int(key.dropFirst()), let scalar = UnicodeScalar(NSF1FunctionKey + number - 1) { return String(scalar) }
        return ["Space": " ", "Return": "\r", "Tab": "\t", "Backspace": "\u{8}", "Escape": "\u{1b}"][key] ?? key.lowercased()
    }
    var menuModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        for (carbon, cocoa) in [(cmdKey, NSEvent.ModifierFlags.command), (optionKey, .option), (controlKey, .control), (shiftKey, .shift)] {
            if modifiers & UInt32(carbon) != 0 { flags.insert(cocoa) }
        }
        return flags
    }
}

@MainActor
final class HotkeyManager {
    private var registrations: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var actions: [UInt32: String] = [:]
    var onTrigger: (String) -> Void = { _ in }
    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer -> OSStatus in
            guard let event, let pointer else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr else { return result }
            MainActor.assumeIsolated {
                let manager = Unmanaged<HotkeyManager>.fromOpaque(pointer).takeUnretainedValue()
                if let action = manager.actions[id.id] { manager.onTrigger(action) }
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func unregister() {
        registrations.forEach { UnregisterEventHotKey($0) }; registrations.removeAll(); actions.removeAll()
    }
    func register(_ values: [String: String]) throws {
        unregister()
        do {
            for (index, key) in ["input", "screenshot", "selection", "clipboard"].enumerated() {
                let value = values[key] ?? ""
                if value.isEmpty { continue }
                guard let hotkey = Hotkey.parse(value) else { throw GlintError.message("无效的快捷键：" + value) }
                let id = UInt32(index + 1)
                var ref: EventHotKeyRef?
                let result = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, EventHotKeyID(signature: 0x474c4e54, id: id), GetApplicationEventTarget(), 0, &ref)
                guard result == noErr, let ref else { throw GlintError.message("快捷键已被占用或重复：" + Hotkey.display(value)) }
                registrations.append(ref); actions[id] = key
            }
        } catch { unregister(); throw error }
    }
    func stop() { unregister(); if let handler { RemoveEventHandler(handler) }; handler = nil }
}

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var value: String
    var onRecordingChanged: (Bool) -> Void = { _ in }
    final class Recorder: NSButton {
        var onRecord: (String) -> Void = { _ in }
        var onRecordingChanged: (Bool) -> Void = { _ in }
        private(set) var recording = false
        var value = ""
        override var acceptsFirstResponder: Bool { true }
        @objc func beginRecording() { window?.makeFirstResponder(self) }
        override func becomeFirstResponder() -> Bool {
            guard super.becomeFirstResponder() else { return false }
            recording = true; onRecordingChanged(true)
            title = "请按下新的组合键…"; needsDisplay = true
            return true
        }
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
            if recording { recording = false; onRecordingChanged(false) }
            super.viewWillMove(toWindow: newWindow)
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { NotificationCenter.default.addObserver(self, selector: #selector(windowResigned), name: NSWindow.didResignKeyNotification, object: window) }
        }
        @objc private func windowResigned() { window?.makeFirstResponder(nil) }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event); return true
        }
        override func draw(_ dirtyRect: NSRect) {
            let focused = window?.firstResponder === self
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
            NSColor(Theme.surface).setFill(); path.fill()
            (focused ? NSColor(Theme.text).withAlphaComponent(0.55) : NSColor(Theme.border)).setStroke()
            path.lineWidth = 1; path.stroke()
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: value.isEmpty || focused ? NSColor(Theme.muted) : NSColor(Theme.text)]
            let size = title.size(withAttributes: attributes)
            title.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
        }
        override func keyDown(with event: NSEvent) {
            if [UInt16(53), 51, 117].contains(event.keyCode) { onRecord(""); window?.makeFirstResponder(nil); return }
            guard let accelerator = Hotkey.accelerator(event) else { NSSound.beep(); return }
            onRecord(accelerator); window?.makeFirstResponder(nil)
        }
        override func resignFirstResponder() -> Bool {
            guard super.resignFirstResponder() else { return false }
            if recording { recording = false; onRecordingChanged(false) }
            title = value.isEmpty ? "点击录制快捷键" : Hotkey.display(value); needsDisplay = true
            return true
        }
    }
    func makeNSView(context: Context) -> Recorder {
        let button = Recorder(); button.isBordered = false; button.focusRingType = .none; button.alignment = .center
        button.target = button; button.action = #selector(Recorder.beginRecording)
        button.font = .systemFont(ofSize: 13); button.setAccessibilityLabel("录制快捷键")
        return button
    }
    func updateNSView(_ view: Recorder, context: Context) {
        view.value = value
        if view.window?.firstResponder !== view { view.title = value.isEmpty ? "点击录制快捷键" : Hotkey.display(value) }
        view.needsDisplay = true
        view.onRecord = { value = $0 }
        view.onRecordingChanged = onRecordingChanged
    }
    static func dismantleNSView(_ view: Recorder, coordinator: ()) {
        if view.recording { view.window?.makeFirstResponder(nil) }
        NotificationCenter.default.removeObserver(view)
    }
}
