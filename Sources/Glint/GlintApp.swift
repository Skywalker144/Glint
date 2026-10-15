import AppKit
import SwiftUI
import ServiceManagement
import GlintCore

@main
@MainActor
enum GlintApp {
    static func main() {
        if CommandLine.arguments.contains("--install-update") { exit(UpdateService.install(arguments: CommandLine.arguments)) }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel!
    var translator: GlintWindowController!
    var settingsWindow: GlintWindowController?
    var vocabularyWindow: GlintWindowController?
    var statusItem: NSStatusItem?
    let hotkeys = HotkeyManager()
    let selection = SelectionService()
    let capture = CaptureService()
    private var lock: Int32 = -1
    private var timers: [Timer] = []
    private var frameSave: DispatchWorkItem?
    private var recording = false
    private var isolated = false
    private var captureTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let args = CommandLine.arguments
            let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let directory: URL
            if let index = args.firstIndex(of: "--data-directory"), args.indices.contains(index + 1) {
                directory = URL(fileURLWithPath: args[index + 1]); isolated = true
            } else { directory = applicationSupport.appendingPathComponent("com.skywalker144.glint") }
            let legacy = isolated ? [] : ["Glint", "glint", "translator"].map { applicationSupport.appendingPathComponent($0) }
            let store = try LocalStore(directory: directory, legacyDirectories: legacy)
            lock = Darwin.open(directory.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, 0o600)
            guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else {
                DistributedNotificationCenter.default().post(name: .init("com.skywalker144.glint.show"), object: directory.path)
                NSApp.terminate(nil); return
            }
            model = AppModel(store: store)
            translator = GlintWindowController(title: "Glint", size: CGSize(width: model.settings.windowWidth, height: 120), translator: true, resizable: true, root: TranslatorView(model: model))
            translator.pinned = { [weak self] in self?.model.settings.pinned ?? false }
            translator.onFrameChanged = { [weak self] frame in self?.saveFrame(frame) }
            if model.settings.pinned, let x = model.settings.windowX, let y = model.settings.windowY {
                let cocoa = ScreenCoordinates.cocoa(CGPoint(x: x, y: y))
                let frame = CGRect(x: cocoa.x, y: cocoa.y - translator.window.frame.height, width: model.settings.windowWidth, height: translator.window.frame.height)
                if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) { translator.window.setFrame(frame, display: false) }
            }
            connectActions()
            buildMainMenu()
            rebuildStatusItem()
            selection.isBlocked = { [weak self] activating in
                guard let self else { return true }
                return self.capture.active || (NSApp.keyWindow != nil && !(activating && NSApp.keyWindow === self.translator.window))
            }
            selection.onTranslate = { [weak self] text in self?.showTranslation(text) }
            if !isolated {
                if model.settings.launchAtLogin && SMAppService.mainApp.status == .notRegistered {
                    do { try SMAppService.mainApp.register() } catch { model.saveMessage = error.localizedDescription }
                }
                selection.configure(enabled: model.settings.selectionPopup, options: model.settings.selectionPopupOptions)
                do { try hotkeys.register(model.settings.hotkeys) } catch { model.saveMessage = error.localizedDescription }
            }
            hotkeys.onTrigger = { [weak self] in self?.perform($0) }
            let updater = UpdateService(directory: directory.appendingPathComponent("updates"), settings: { [weak self] in self?.model.settings ?? AppSettings() })
            updater.onChange = { [weak self] in self?.rebuildStatusItem() }
            model.update = updater
            if !isolated {
                timers.append(Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in Task { @MainActor in await updater.check() } })
                timers.append(Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { _ in Task { @MainActor in await updater.check() } })
            }
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(reopenFromNotification), name: .init("com.skywalker144.glint.show"), object: directory.path)
            if args.contains("--show") { perform("input") }
            #if DEBUG
            if let index = args.firstIndex(of: "--verify-ui"), args.indices.contains(index + 1) {
                Task { await AppDiagnostics.run(delegate: self, output: URL(fileURLWithPath: args[index + 1])) }
            }
            #endif
        } catch {
            let alert = NSAlert(); alert.messageText = "Glint 无法启动"; alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "退出"); alert.runModal(); NSApp.terminate(nil)
        }
    }
    private func connectActions() {
        model.showSettings = { [weak self] in self?.openSettings() }
        model.showVocabulary = { [weak self] in self?.openVocabulary() }
        model.hideTranslator = { [weak self] in self?.translator.hide() }
        model.closeSettings = { [weak self] in self?.settingsWindow?.hide() }
        model.closeVocabulary = { [weak self] in self?.vocabularyWindow?.hide() }
        model.resizeTranslator = { [weak self] in self?.translator?.fitHeight($0) }
        model.resizeSettings = { [weak self] in self?.settingsWindow?.fitHeight($0) }
        model.onApplySettings = { [weak self] old, next in
            guard let self else { return }
            if old.hotkeys != next.hotkeys && !self.isolated {
                do { try self.hotkeys.register(next.hotkeys); if self.recording { self.hotkeys.unregister() } }
                catch { if !self.recording { try? self.hotkeys.register(old.hotkeys) }; throw error }
            }
            if old.launchAtLogin != next.launchAtLogin && !self.isolated {
                if next.launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            }
            if !self.isolated && (old.selectionPopup != next.selectionPopup || old.selectionPopupOptions != next.selectionPopupOptions) {
                self.selection.configure(enabled: next.selectionPopup, options: next.selectionPopupOptions)
            }
            DispatchQueue.main.async { [weak self] in self?.rebuildStatusItem() }
        }
    }
    private func saveFrame(_ frame: CGRect) {
        frameSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.model.changeSettings {
                $0.windowWidth = frame.width
                if $0.pinned { $0.windowX = frame.minX; $0.windowY = ScreenCoordinates.primaryHeight - frame.maxY }
            }
        }
        frameSave = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    func showTranslation(_ text: String) {
        translator.show(nearCursor: !model.settings.pinned); model.receive(text)
    }
    func perform(_ action: String) {
        selection.dismiss()
        switch action {
        case "input": translator.show(nearCursor: !model.settings.pinned); model.beginInput()
        case "clipboard":
            let text = NSPasteboard.general.string(forType: .string)?.trimmed ?? ""
            if text.isEmpty { translator.show(nearCursor: !model.settings.pinned); model.showMessage("剪贴板里没有文本。先复制一段文字，再按快捷键。") }
            else { showTranslation(text) }
        case "selection":
            selectionTask?.cancel()
            selectionTask = Task {
                do {
                    let text = try await selection.selectedText(); try Task.checkCancellation()
                    if text.isEmpty { translator.show(nearCursor: !model.settings.pinned); model.showMessage("没有检测到选中的文字。先选中文字，再按划词快捷键。") }
                    else { showTranslation(text) }
                } catch {
                    if !Task.isCancelled { translator.show(nearCursor: true); model.showMessage(error.localizedDescription) }
                }
            }
        case "screenshot":
            guard captureTask == nil else { return }
            translator.hide()
            captureTask = Task {
                defer { captureTask = nil }
                do {
                    guard let image = try await capture.capture() else { return }
                    translator.show(nearCursor: !model.settings.pinned); model.showMessage("正在识别文字…")
                    let text = try await CaptureService.recognize(image)
                    if text.isEmpty { model.showMessage("没有识别到文字，换个区域再试试。") } else { model.receive(text) }
                } catch { translator.show(nearCursor: true); model.showMessage(error.localizedDescription) }
            }
        default: break
        }
    }
    func openSettings() {
        selection.dismiss()
        if settingsWindow == nil {
            settingsWindow = GlintWindowController(title: "设置 · Glint", size: SettingsView.size, root: SettingsView(model: model))
            settingsWindow?.onFocusChanged = { [weak self] focused in
                guard let self else { return }
                self.recording = focused
                guard !self.isolated else { return }
                if focused { self.hotkeys.unregister() }
                else { do { try self.hotkeys.register(self.model.settings.hotkeys) } catch { self.model.saveMessage = error.localizedDescription } }
            }
        }
        settingsWindow?.show()
    }
    func openVocabulary() {
        selection.dismiss()
        if vocabularyWindow == nil { vocabularyWindow = GlintWindowController(title: "生词本 · Glint", size: CGSize(width: 760, height: 560), resizable: true, root: VocabularyView(model: model)) }
        vocabularyWindow?.show()
    }
    func rebuildStatusItem() {
        guard model != nil else { return }
        if model.settings.hideTrayIcon {
            if let item = statusItem { NSStatusBar.system.removeStatusItem(item); statusItem = nil }; return
        }
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem?.button?.image = MenuBarIcon.image
            statusItem?.button?.toolTip = "闪译 · Glint"
        }
        let menu = NSMenu()
        if let update = model.update, !update.latest.isEmpty {
            let item = NSMenuItem(title: update.ready ? "↻ 重启以更新到 v\(update.latest)" : "↓ 有新版 v\(update.latest)", action: #selector(updateAction), keyEquivalent: "")
            item.target = self; menu.addItem(item); menu.addItem(.separator())
        }
        for (action, title) in [("input","输入翻译"),("screenshot","截图翻译"),("selection","划词翻译"),("clipboard","剪贴板翻译")] {
            let item = NSMenuItem(title: title + "   " + Hotkey.display(model.settings.hotkeys[action] ?? ""), action: #selector(menuAction(_:)), keyEquivalent: "")
            item.representedObject = action; item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator())
        for (title, selector) in [("生词本…", #selector(vocabularyAction)), ("设置…", #selector(settingsAction))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator()); menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem?.menu = menu
    }
    private func buildMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu(); appMenu.addItem(withTitle: "退出 Glint", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); appItem.submenu = appMenu; menu.addItem(appItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", Selector(("undo:")), "z"), ("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] { edit.addItem(withTitle: title, action: selector, keyEquivalent: key) }
        editItem.submenu = edit; menu.addItem(editItem); NSApp.mainMenu = menu
    }
    @objc private func menuAction(_ sender: NSMenuItem) { if let action = sender.representedObject as? String { perform(action) } }
    @objc private func settingsAction() { openSettings() }
    @objc private func vocabularyAction() { openVocabulary() }
    @objc private func updateAction() { if model.update?.ready == true { model.update?.apply() } else if let url = URL(string: model.update?.releaseURL ?? AppVersion.repository) { NSWorkspace.shared.open(url) } }
    @objc private func reopenFromNotification() { perform("input") }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { perform("input"); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        timers.forEach { $0.invalidate() }; frameSave?.perform(); frameSave?.cancel()
        model?.stop(); model?.speech.stop(); hotkeys.stop(); selection.stop(); capture.finish()
        DistributedNotificationCenter.default().removeObserver(self)
        if lock >= 0 { flock(lock, LOCK_UN); Darwin.close(lock) }
    }
}
