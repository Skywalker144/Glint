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
    private(set) var resultIsStale = false
    private(set) var historySelection: String?
    var currentEntry: VocabularyEntry?
    var overrides = TranslationOverrides()
    var displayMode: TranslationMode = .translate
    var source = "auto"
    var target = ""
    var selectAllOnFocus = false
    var inputFocusRevision = 0
    var resultFocusRevision = 0
    var translatorMaximumHeight: CGFloat = 600
    var speech = SpeechService()
    var onApplySettings: ((AppSettings, AppSettings) throws -> Void)?
    var showSettings: () -> Void = {}
    var showVocabulary: () -> Void = {}
    var hideTranslator: () -> Void = {}
    var showTranslator: () -> Void = {}
    var onRecordingHotkey: (Bool) -> Void = { _ in }
    var resizeTranslator: (CGFloat) -> Void = { _ in }
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
        guard input != value else { return }
        input = value; stop(); speech.stop(); currentEntry = nil; historySelection = nil
        resultIsStale = !output.isEmpty; status = ""; failed = false
        if value.trimmed.isEmpty { output = ""; resultIsStale = false }
        source = "auto"; target = ""
    }
    func clearInput() { editInput(""); selectAllOnFocus = false; inputFocusRevision += 1 }
    func openTranslation(_ text: String) { showTranslator(); overrides = .init(); receive(text) }
    var supportsDictionary: Bool { Provider.find(settings.engine)?.isAI == true }
    var historyIndex: Int? { history.firstIndex { $0.id == historySelection } }
    var canBrowseOlder: Bool { !history.isEmpty && (historyIndex.map { $0 + 1 < history.count } ?? true) }
    var canBrowseNewer: Bool { historyIndex.map { $0 > 0 } ?? false }
    func browseHistory(older: Bool) {
        let index = (historyIndex ?? -1) + (older ? 1 : -1)
        guard history.indices.contains(index) else { return }
        restoreHistory(history[index])
    }
    func restoreHistory(_ item: HistoryItem) {
        stop(); speech.stop(); input = item.original; output = item.translated; source = item.source; target = item.target
        status = ""; failed = false; resultIsStale = false; overrides = .init(); historySelection = item.id
        currentEntry = VocabularyEntry.parse(item.translated, language: item.source, definitionLanguage: item.target)
        displayMode = currentEntry == nil ? .translate : .dict
        resultRevision = UUID(); resultFocusRevision += 1
    }
    func receive(_ text: String) {
        stop(); input = text; overrides.mode = .auto; source = "auto"; target = ""
        resultFocusRevision += 1; translate()
    }
    func beginInput() {
        stop(); speech.stop(); input = ""; output = ""; status = ""; currentEntry = nil; failed = false; resultIsStale = false; historySelection = nil
        overrides.mode = .auto; displayMode = .translate; source = "auto"; target = ""
        selectAllOnFocus = false; inputFocusRevision += 1
    }
    func showMessage(_ text: String) {
        stop(); speech.stop(); status = text; output = ""; currentEntry = nil; failed = false; resultIsStale = false; historySelection = nil
        overrides.mode = .auto; displayMode = .translate; source = "auto"; target = ""
        selectAllOnFocus = true; inputFocusRevision += 1
    }
    func translate(mode: TranslationMode? = nil) {
        stop(); speech.stop()
        if let mode { overrides.mode = mode }
        let text = input.trimmed
        status = ""; output = ""; failed = false; currentEntry = nil; resultIsStale = false; historySelection = nil; resultRevision = UUID()
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
                    let languages = request.resolvedLanguages(original: text, translated: result.translated, detectedSource: result.source)
                    self.source = languages.source; self.target = languages.target
                    self.streaming = false
                    if request.options.dict { self.currentEntry = VocabularyEntry.parse(result.translated, language: request.options.secondaryLanguage, definitionLanguage: request.options.primaryLanguage) }
                    do { try self.store.recordLookup(self.currentEntry); self.vocabulary = self.store.vocabulary }
                    catch { self.status = "生词本计数保存失败：" + error.localizedDescription }
                    do {
                        try self.store.addHistory(.init(original: text, translated: result.translated, source: self.source, target: self.target, engine: request.engine))
                        self.history = self.store.history
                        self.historySelection = self.history.first?.id
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
        return !streaming && !failed && !resultIsStale && !input.trimmed.isEmpty && Language.valid(a) && Language.valid(b) && a != b
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
    static func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    func speakInput() {
        let language = !overrides.source.isEmpty ? overrides.source : (source == "auto" ? (Language.detect(input) ?? Language.guess(input)) : source)
        speech.speak(input, language: language, proxy: settings.proxy, channel: "input")
    }
    func speakOutput() { speech.speak(NativeMarkdown.plainText(output), language: target, proxy: settings.proxy, channel: "result") }
}
