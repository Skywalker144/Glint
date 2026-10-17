import Testing
import AppKit
import SwiftUI
import GlintCore
@testable import Glint

@MainActor
struct InteractionTests {
    @Test func recordingSuspendsOnlyWhileFocusedAndCapturesCommandKeys() throws {
        _ = NSApplication.shared
        let controller = GlintWindowController(title: "Recorder", size: CGSize(width: 400, height: 360), root: Color.clear)
        defer { controller.window.close() }
        let recorder = HotkeyRecorder.Recorder(frame: CGRect(x: 0, y: 0, width: 230, height: 30))
        var states: [Bool] = [], recorded = ""
        recorder.onRecordingChanged = { states.append($0) }
        recorder.onRecord = { recorded = $0 }
        controller.window.contentView?.addSubview(recorder)
        #expect(states.isEmpty)
        #expect(controller.window.makeFirstResponder(recorder))
        #expect(states == [true])
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: controller.window.windowNumber, context: nil, characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12))
        #expect(recorder.performKeyEquivalent(with: event))
        #expect(recorded == "Command+Q")
        #expect(states == [true, false])
        #expect(controller.window.makeFirstResponder(recorder))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: controller.window)
        #expect(!recorder.recording && states == [true, false, true, false])
        var closed = false; controller.window.onEscape = { closed = true }
        controller.window.performClose(nil)
        #expect(closed)
        let hotkey = try #require(Hotkey.parse("Command+Alt+Q"))
        #expect(hotkey.menuKeyEquivalent == "q" && hotkey.menuModifiers == [.command, .option])
        #expect(Hotkey.parse("Shift+F12")?.menuKeyEquivalent == String(UnicodeScalar(NSF12FunctionKey)!))
    }
    @Test func historyNavigationRestoresResultsAndRetranslationOpensWindow() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".cache/interaction-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalStore(directory: root)
        let older = HistoryItem(original: "hello", translated: "你好", source: "en", target: "zh-CN", engine: "google")
        let newer = HistoryItem(original: "world", translated: "世界", source: "en", target: "zh-CN", engine: "google")
        try store.addHistory(older); try store.addHistory(newer)
        let model = AppModel(store: store)
        model.browseHistory(older: true)
        #expect(model.input == "world" && model.output == "世界")
        #expect(model.canBrowseOlder && !model.canBrowseNewer)
        model.browseHistory(older: true)
        #expect(model.input == "hello" && !model.canBrowseOlder)
        model.browseHistory(older: false)
        #expect(model.output == "世界" && !model.streaming)
        var opened = 0; model.showTranslator = { opened += 1 }
        model.settings.engine = "custom"
        model.overrides = .init(source: "fr", target: "de", mode: .dict)
        model.openTranslation("New text.")
        #expect(opened == 1 && model.input == "New text.")
        #expect(model.overrides == .init())
        model.stop()
    }

    @Test func completedStreamPersistsDetectedLanguagesAndIgnoresDisabledProxy() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".cache/interaction-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = Process(); let pipe = Pipe()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("GlintCoreTests/stream_server.py").path]
        server.standardOutput = pipe; server.standardError = FileHandle.nullDevice
        try server.run()
        defer { server.terminate(); server.waitUntilExit() }
        let port = String(data: pipe.fileHandleForReading.availableData, encoding: .utf8)!.trimmed
        let model = AppModel(store: try LocalStore(directory: root))
        model.settings.engine = "custom"; model.settings.primaryLanguage = "en"; model.settings.secondaryLanguage = "zh-CN"
        model.settings.providers["custom"] = .init(apiKey: "fixture", model: "normal", baseURL: "http://127.0.0.1:\(port)/v1")
        model.settings.proxy = .init(enabled: false, url: "invalid proxy")
        model.receive("Hello world.")
        for _ in 0..<150 { if !model.streaming { break }; try await Task.sleep(for: .milliseconds(20)) }
        #expect(!model.streaming && !model.failed)
        #expect(model.output == "你好 🌍")
        #expect(model.source == "en" && model.target == "zh-CN")
        #expect(model.history.first?.target == "zh-CN")
        #expect(model.canSwap)
        model.settings.providers["custom"]?.model = "slow"
        model.receive("Hello again.")
        try await Task.sleep(for: .milliseconds(100))
        model.editInput("Keep my edit.")
        let output = model.output
        try await Task.sleep(for: .milliseconds(550))
        #expect(model.input == "Keep my edit." && model.output == output)
        #expect(!model.streaming && model.history.count == 1)
    }
    @Test func editingKeepsExplicitModeAndInvalidatesResultActions() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".cache/interaction-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(store: try LocalStore(directory: root))
        model.input = "hello"; model.output = "你好"; model.source = "en"; model.target = "zh-CN"
        model.overrides.mode = .dict; model.displayMode = .dict
        model.editInput("hello again")
        #expect(model.overrides.mode == .dict)
        #expect(model.displayMode == .dict)
        #expect(!model.canSwap)
        #expect(model.currentEntry == nil)
    }

    @Test func singleLanguageResultsCanSwapButIdenticalLanguagesCannot() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".cache/interaction-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(store: try LocalStore(directory: root))
        model.input = "Hello world."; model.output = "你好，世界。"; model.source = "en"; model.target = "zh-CN"
        #expect(model.canSwap)
        model.target = "en"
        #expect(!model.canSwap)
        model.target = "zh-CN"; model.streaming = true
        #expect(!model.canSwap)
    }

    @Test func repeatingSpeechActionStopsPendingAudio() {
        let speech = SpeechService()
        speech.speak("Hello world", language: "en", proxy: .init(), channel: "input")
        #expect(speech.channel == "input")
        speech.speak("Hello world", language: "en", proxy: .init(), channel: "input")
        #expect(speech.channel.isEmpty)
        speech.stop()
    }
}
