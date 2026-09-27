import AppKit
import ApplicationServices
import Vision
import NaturalLanguage

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}

let args = CommandLine.arguments
switch args[1] {
case "front":
    print(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)
case "restore":
    if let pid = Int32(args[2]), let app = NSRunningApplication(processIdentifier: pid) {
        app.activate(options: [.activateIgnoringOtherApps])
    }
case "selection":
    guard AXIsProcessTrusted() else {
        fail("请在系统设置 → 隐私与安全性 → 辅助功能中允许 Glint，然后重新启动应用。")
    }
    let system = AXUIElementCreateSystemWide()
    var focused: CFTypeRef?
    AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
    if let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
        var selected: CFTypeRef?
        AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected)
        if let text = selected as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print(text)
            exit(0)
        }
    }
    let pasteboard = NSPasteboard.general
    let saved = pasteboard.pasteboardItems?.map { item in
        item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
    } ?? []
    let count = pasteboard.changeCount
    let down = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true)
    let up = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: false)
    down?.flags = .maskCommand
    up?.flags = .maskCommand
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
    for _ in 0..<30 {
        Thread.sleep(forTimeInterval: 0.02)
        if pasteboard.changeCount != count { break }
    }
    guard pasteboard.changeCount != count else { fail("未取到选中文字。请先选择文本，再按划词快捷键。") }
    let copiedCount = pasteboard.changeCount
    let text = pasteboard.string(forType: .string) ?? ""
    if pasteboard.changeCount == copiedCount {
        pasteboard.clearContents()
        let items = saved.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { fail("所选内容不是文本，请使用截图翻译。") }
    print(text)
case "ocr":
    guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
        fail("请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许 Glint，然后重新启动应用。")
    }
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("glint-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: path) }
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-i", "-s", "-x", path.path]
    try capture.run()
    capture.waitUntilExit()
    guard FileManager.default.fileExists(atPath: path.path) else { exit(2) }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.automaticallyDetectsLanguage = true
    try VNImageRequestHandler(url: path).perform([request])
    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    guard !text.isEmpty else { fail("截图中未识别到文字，请重新框选。") }
    print(text)
case "language":
    let text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    if let language = recognizer.dominantLanguage, (recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0) >= 0.6 {
        print(language.rawValue)
    } else {
        fail("无法确定源语言，请手动选择。")
    }
case "copy":
    let data = FileHandle.standardInput.readDataToEndOfFile()
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string)
default:
    fail("Unknown native command")
}
