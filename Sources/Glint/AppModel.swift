import AppKit
import SwiftUI
import Observation
import GlintCore

@MainActor @Observable
final class AppModel {
    let store: LocalStore
    var settings: AppSettings
    var history: [HistoryItem]
    var vocabulary: [VocabularyEntry]
    var input = ""
    var output = ""
    private(set) var resultRevision = UUID()
    var status = ""
    var saveMessage = ""
    var streaming = false
    var failed = false
    var currentEntry: VocabularyEntry?
    var overrides = TranslationOverrides()
    var displayMode: TranslationMode = .translate
    var source = "auto"
    var target = ""
    var selectAllOnFocus = false
    var inputFocusRevision = 0
    var resultFocusRevision = 0
    var translatorMaximumHeight: CGFloat = 600
    var copied = false
    var speech = SpeechService()
    var onApplySettings: ((AppSettings, AppSettings) throws -> Void)?
    var showSettings: () -> Void = {}
    var showVocabulary: () -> Void = {}
    var hideTranslator: () -> Void = {}
    var resizeTranslator: (CGFloat) -> Void = { _ in }
    var resizeSettings: (CGFloat) -> Void = { _ in }
    var closeSettings: () -> Void = {}
    var closeVocabulary: () -> Void = {}
    var update: UpdateService?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var revision = UUID()
    init(store: LocalStore) {
        self.store = store; settings = store.settings; history = store.history; vocabulary = store.vocabulary
    }
    func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { self.settings[keyPath: keyPath] }, set: { value in self.changeSettings { $0[keyPath: keyPath] = value } })
    }
    func changeSettings(_ change: (inout AppSettings) -> Void) {
        var next = settings; change(&next); next.selectionPopupOptions.normalize()
        do {
            try onApplySettings?(settings, next)
            do { try store.saveSettings(next) }
            catch {
                try? onApplySettings?(next, settings)
                throw error
            }
            settings = next; saveMessage = "已自动保存"
        } catch { saveMessage = error.localizedDescription }
    }
    func editInput(_ value: String) {
        input = value; stop(); currentEntry = nil; overrides.mode = .auto
        displayMode = .translate; source = "auto"; target = ""
    }
    func receive(_ text: String) {
        stop(); input = text; overrides.mode = .auto; source = "auto"; target = ""
        resultFocusRevision += 1; translate()
    }
    func beginInput() {
        stop(); input = ""; output = ""; status = ""; currentEntry = nil; failed = false
        overrides.mode = .auto; displayMode = .translate; source = "auto"; target = ""
        selectAllOnFocus = false; inputFocusRevision += 1
    }
    func showMessage(_ text: String) {
        stop(); status = text; output = ""; currentEntry = nil; failed = false
        overrides.mode = .auto; displayMode = .translate; source = "auto"; target = ""
        selectAllOnFocus = true; inputFocusRevision += 1
    }
    func translate(mode: TranslationMode? = nil) {
        stop()
        if let mode { overrides.mode = mode }
        let text = input.trimmed
        status = ""; output = ""; failed = false; currentEntry = nil; resultRevision = UUID()
        guard !text.isEmpty else { return }
        let token = UUID(); revision = token
        do {
            let request = try TranslationRequest.resolve(text, settings: settings, overrides: overrides)
            source = request.options.source; target = request.resultTarget
            displayMode = request.options.dict ? .dict : .translate
            let client = try HTTPClient(proxy: settings.proxy)
            streaming = true
            task = Task {
                do {
                    let result = try await TranslationEngine(client: client).translate(text, request: request) { delta in
                        await MainActor.run {
                            guard self.revision == token else { return }
                            self.output += delta
                        }
                    }
                    try Task.checkCancellation()
                    guard self.revision == token else { return }
                    self.output = result.translated
                    self.source = result.source == "zh" ? "zh-CN" : result.source
                    self.streaming = false
                    if request.options.dict { self.currentEntry = VocabularyEntry.parse(result.translated, language: request.options.secondaryLanguage, definitionLanguage: request.options.primaryLanguage) }
                    do { try self.store.recordLookup(self.currentEntry); self.vocabulary = self.store.vocabulary }
                    catch { self.status = "生词本计数保存失败：" + error.localizedDescription }
                    do {
                        try self.store.addHistory(.init(original: text, translated: result.translated, source: self.source, target: self.target, engine: request.engine))
                        self.history = self.store.history
                    } catch { self.status = "历史记录保存失败：" + error.localizedDescription }
                } catch {
                    guard self.revision == token, !Task.isCancelled else { return }
                    self.streaming = false; self.failed = true
                    self.status = "翻译失败：" + HTTPClient.friendly(error, engine: request.engine)
                }
            }
        } catch { failed = true; status = error.localizedDescription }
    }
    func stop() { revision = UUID(); task?.cancel(); task = nil; streaming = false }
    var canSwap: Bool {
        let a = overrides.source.isEmpty ? source : overrides.source
        let b = overrides.target.isEmpty ? target : overrides.target
        return Language.isMixed(input) && Language.valid(a) && Language.valid(b) && a != b
    }
    func swapLanguages() {
        guard canSwap else { return }
        let old = overrides.source.isEmpty ? source : overrides.source
        overrides.source = overrides.target.isEmpty ? target : overrides.target
        overrides.target = old; translate()
    }
    var isFavorite: Bool { currentEntry.map { entry in vocabulary.contains { $0.id == entry.id } } ?? false }
    func toggleFavorite() {
        guard let entry = currentEntry else { return }
        do {
            if isFavorite { try store.removeVocabulary(entry.id) } else { try store.addVocabulary(entry) }
            vocabulary = store.vocabulary
        } catch { status = error.localizedDescription }
    }
    func removeFavorite(_ id: String) {
        do { try store.removeVocabulary(id); vocabulary = store.vocabulary }
        catch { saveMessage = error.localizedDescription }
    }
    func clearHistory() {
        do { try store.clearHistory(); history = store.history }
        catch { saveMessage = error.localizedDescription }
    }
    func copyResult() {
        Self.copy(NativeMarkdown.plainText(output)); copied = true
        Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
    }
    static func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    func speakInput() {
        let language = !overrides.source.isEmpty ? overrides.source : (source == "auto" ? Language.guess(input) : source)
        speech.speak(input, language: language, proxy: settings.proxy, channel: "input")
    }
    func speakOutput() { speech.speak(NativeMarkdown.plainText(output), language: target, proxy: settings.proxy, channel: "result") }
}
