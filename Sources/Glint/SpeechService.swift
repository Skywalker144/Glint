import AVFoundation
import Observation
import GlintCore

@MainActor @Observable
final class SpeechService: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    var channel = ""
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var revision = UUID()
    override init() { super.init(); synthesizer.delegate = self }
    func stop() {
        revision = UUID(); task?.cancel(); task = nil; player?.stop(); player = nil
        synthesizer.stopSpeaking(at: .immediate); channel = ""
    }
    func speak(_ text: String, language: String, proxy: ProxySettings, channel: String) {
        stop()
        guard !text.trimmed.isEmpty else { return }
        let token = UUID(); revision = token; self.channel = channel
        let code = Language.valid(language) ? language : "en"
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
            } catch {
                guard revision == token, !Task.isCancelled else { return }
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = AVSpeechSynthesisVoice(language: code); synthesizer.speak(utterance)
            }
        }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in if self.player === player { self.channel = "" } }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.channel = "" }
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
