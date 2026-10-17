import Testing
import AppKit
import ApplicationServices
@testable import Glint

@MainActor
@Suite(.serialized)
struct SelectionMenuTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GLINT_LIVE_SELECTION"] == "1"), arguments: ["shortcut", "identifier"])
    func globalHotkeyCopiesThroughSourceMenu(matching: String) async throws {
        _ = NSApplication.shared
        try #require(AXIsProcessTrusted(), "Real menu selection requires Accessibility access")
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".cache/menu-selection-" + UUID().uuidString)
        let bundle = root.appendingPathComponent("SelectionHost.app/Contents")
        let executable = bundle.appendingPathComponent("MacOS/SelectionHost")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let info: [String: Any] = ["CFBundleIdentifier": "com.glint.tests.selection-host", "CFBundleExecutable": "SelectionHost", "CFBundleName": "SelectionHost", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Info.plist"))
        let compiler = Process()
        let errors = Pipe()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
        compiler.arguments = ["-parse-as-library", "-module-cache-path", URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".cache/clang").path, URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("selection_menu_host.swift").path, "-o", executable.path]
        compiler.standardError = errors
        try compiler.run()
        compiler.waitUntilExit()
        let diagnostics = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        try #require(compiler.terminationStatus == 0, "Selection host compilation failed: \(diagnostics)")

        let previousApp = NSWorkspace.shared.frontmostApplication
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
        defer {
            pasteboard.clearContents()
            pasteboard.writeObjects(saved.map { data in
                let item = NSPasteboardItem()
                data.forEach { item.setData($0.value, forType: $0.key) }
                return item
            })
            previousApp?.activate(options: [])
        }
        let host = Process()
        let ready = Pipe()
        host.executableURL = executable
        host.arguments = [matching, root.appendingPathComponent("copy-key.txt").path]
        host.standardOutput = ready
        host.standardError = FileHandle.nullDevice
        try host.run()
        defer { host.terminate(); host.waitUntilExit() }
        try #require(String(decoding: ready.fileHandleForReading.availableData, as: UTF8.self).contains("ready"))
        for _ in 0..<200 {
            while let event = NSApp.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == host.processIdentifier { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(NSWorkspace.shared.frontmostApplication?.processIdentifier == host.processIdentifier)
        let menuItem = await Task.detached { SelectionCopyMenu.find(pid: host.processIdentifier) }.value
        try #require(menuItem != nil, "Source Copy menu item was not found")
        let original = NSPasteboardItem()
        original.setString("Clipboard before selection", forType: .string)
        original.setString("<b>Clipboard before selection</b>", forType: .html)
        pasteboard.clearContents()
        try #require(pasteboard.writeObjects([original]))

        let driverExecutable = root.appendingPathComponent("SelectionDriver.app/Contents/MacOS/SelectionDriver")
        try FileManager.default.createDirectory(at: driverExecutable.deletingLastPathComponent(), withIntermediateDirectories: true)
        let driverInfo: [String: Any] = ["CFBundleIdentifier": "com.glint.tests.selection-driver", "CFBundleExecutable": "SelectionDriver", "CFBundleName": "SelectionDriver", "CFBundlePackageType": "APPL", "LSUIElement": true]
        try PropertyListSerialization.data(fromPropertyList: driverInfo, format: .xml, options: 0).write(to: driverExecutable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist"))
        let build = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/debug").resolvingSymlinksInPath()
        let driverCompiler = Process()
        let driverErrors = Pipe()
        driverCompiler.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
        let coreObjects = try FileManager.default.contentsOfDirectory(at: build.appendingPathComponent("GlintCore.build"), includingPropertiesForKeys: nil).filter { $0.pathExtension == "o" }
        let sources = ["Hotkeys", "Theme", "WindowController", "SelectionService", "SelectionMonitor", "SelectionCopyMenu", "SelectionTextReader"].map { URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/Glint/" + $0 + ".swift").path }
        driverCompiler.arguments = ["-parse-as-library", "-I", build.appendingPathComponent("Modules").path, "-module-cache-path", URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".cache/clang").path, URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("selection_menu_driver.swift").path] + sources + coreObjects.map(\.path) + ["-o", driverExecutable.path]
        driverCompiler.standardError = driverErrors
        try driverCompiler.run()
        driverCompiler.waitUntilExit()
        let driverDiagnostics = String(decoding: driverErrors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        try #require(driverCompiler.terminationStatus == 0, "Selection driver compilation failed: \(driverDiagnostics)")
        let output = root.appendingPathComponent("selection.txt")
        let driver = Process()
        let driverReady = Pipe()
        driver.executableURL = driverExecutable
        driver.arguments = [output.path, String(host.processIdentifier)]
        driver.standardOutput = driverReady
        driver.standardError = FileHandle.nullDevice
        try driver.run()
        defer { if driver.isRunning { driver.terminate() }; driver.waitUntilExit() }
        try #require(String(decoding: driverReady.fileHandleForReading.availableData, as: UTF8.self).contains("ready"))
        let sourceApp = try #require(NSRunningApplication(processIdentifier: host.processIdentifier))
        sourceApp.activate(options: [])
        for _ in 0..<200 {
            while let event = NSApp.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == host.processIdentifier { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(NSWorkspace.shared.frontmostApplication?.processIdentifier == host.processIdentifier)
        try await Task.sleep(for: .milliseconds(50))
        let source = CGEventSource(stateID: .hidSystemState)
        let flags = CGEventSource.flagsState(.combinedSessionState)
        defer {
            for code: UInt16 in [16, 56, 59] {
                let release = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
                release?.flags = flags
                release?.post(tap: .cghidEventTap)
            }
        }
        let events = [(UInt16(59), true, CGEventFlags.maskControl), (UInt16(56), true, [.maskControl, .maskShift]), (UInt16(16), true, [.maskControl, .maskShift]), (UInt16(16), false, [.maskControl, .maskShift])].compactMap { code, down, flags -> CGEvent? in
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            event?.flags = flags
            return event
        }
        try #require(events.count == 4)
        events.forEach { $0.post(tap: .cghidEventTap) }
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: output.path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(FileManager.default.fileExists(atPath: output.path), "Global hotkey did not trigger")
        let result = try String(contentsOf: output, encoding: .utf8)
        #expect(result == "First line\nSecond line\n\nThird paragraph\n\tIndented line")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("copy-key.txt").path))
        #expect(pasteboard.string(forType: .string) == "Clipboard before selection")
        #expect(pasteboard.string(forType: .html) == "<b>Clipboard before selection</b>")
    }
}
