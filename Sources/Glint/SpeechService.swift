import AVFoundation
import Observation
import SwiftUI
import GlintCore

@MainActor @Observable
final class SpeechService: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    var channel = ""
    private(set) var loading = false
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var utterance: AVSpeechUtterance?
    override init() { super.init(); synthesizer.delegate = self }
    func stop() {
        revision = UUID(); task?.cancel(); task = nil; player?.stop(); player = nil
        utterance = nil; synthesizer.stopSpeaking(at: .immediate); channel = ""; loading = false
    }
    func speak(_ text: String, language: String, proxy: ProxySettings, channel: String) {
        if self.channel == channel { stop(); return }
        stop()
        guard !text.trimmed.isEmpty else { return }
        let token = UUID(); revision = token; self.channel = channel; loading = true
        let code = Language.valid(language) ? language : (Language.detect(text) ?? Language.guess(text))
        task = Task {
            do {
                let client = try HTTPClient(proxy: proxy)
                let parts = Self.split(text)
                var audio = Data()
                for (index, part) in parts.enumerated() {
                    var url = URLComponents(string: "https://translate.googleapis.com/translate_tts")!
                    url.queryItems = ["ie": "UTF-8", "client": "tw-ob", "tl": code, "total": String(parts.count), "idx": String(index), "textlen": String(part.utf16.count), "q": part].map { URLQueryItem(name: $0.key, value: $0.value) }
                    var request = URLRequest(url: url.url!); request.timeoutInterval = 10
                    request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                    request.setValue("https://translate.google.com/", forHTTPHeaderField: "Referer")
                    audio.append(try await client.data(for: request))
                }
                try Task.checkCancellation()
                guard revision == token else { return }
                player = try AVAudioPlayer(data: audio); player?.delegate = self
                guard player?.play() == true else { throw GlintError.message("无法播放朗读音频") }
                loading = false
            } catch {
                guard revision == token, !Task.isCancelled else { return }
                let utterance = AVSpeechUtterance(string: text)
                self.utterance = utterance; loading = false
                utterance.voice = AVSpeechSynthesisVoice(language: code); synthesizer.speak(utterance)
            }
        }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in if self.player === player { self.channel = "" } }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in if self.utterance === utterance { self.channel = ""; self.utterance = nil } }
    }
    static func split(_ text: String) -> [String] {
        var remaining = Array(text.trimmed), result: [String] = []
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "。．.!?！？,，、;；:："))
        while remaining.count > 190 && result.count < 4 {
            let index = stride(from: 189, through: 96, by: -1).first { remaining[$0].unicodeScalars.allSatisfy { separators.contains($0) } } ?? 189
            result.append(String(remaining.prefix(index + 1)).trimmed); remaining.removeFirst(index + 1)
        }
        if !remaining.isEmpty { result.append(String(remaining.prefix(190)).trimmed) }
        return result.filter { !$0.isEmpty }
    }
}

struct SpeechButton: View {
    let speech: SpeechService
    let channel: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Group {
                if speech.channel == channel && speech.loading { ProgressView().controlSize(.mini) }
                else { Image(systemName: speech.channel == channel ? "stop.fill" : "speaker.wave.2").font(.system(size: 13)) }
            }.frame(width: 24, height: 24)
        }.buttonStyle(GlintButtonStyle(selected: speech.channel == channel, horizontalPadding: 0, verticalPadding: 0))
            .help(speech.channel == channel ? "停止朗读" : label).accessibilityLabel(speech.channel == channel ? "停止朗读" : label)
    }
}
