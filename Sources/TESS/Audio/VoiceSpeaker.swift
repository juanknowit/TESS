import AVFoundation

/// Speaks replies with a macOS voice or OpenAI's text-to-speech, and reports a level for the orb.
@MainActor
final class VoiceSpeaker: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    struct Config {
        var engine: VoiceEngine
        var systemVoiceID: String
        var rate: Float
        var openAIKey: String
        var openAIVoice: String
        var openAIModel: String
    }

    var onLevel: ((Float) -> Void)?

    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Never>?
    private var currentUtterance: ObjectIdentifier?
    private var meterTimer: Timer?
    private var speechID = 0

    override init() {
        super.init()
        synth.delegate = self
    }

    /// Speaks and returns when finished or interrupted by `stop()`.
    func speak(_ text: String, config: Config) async {
        stop()
        speechID += 1
        let id = speechID

        if config.engine == .openai, !config.openAIKey.isEmpty {
            if let audio = try? await fetchOpenAISpeech(text, config) {
                guard id == speechID else { return }
                UsageStore.shared.recordSpeech(characters: text.count, cloud: true)
                await play(audio)
                return
            }
            guard id == speechID else { return }
        }
        UsageStore.shared.recordSpeech(characters: text.count, cloud: false)
        await speakWithSystemVoice(text, config)
    }

    func stop() {
        speechID += 1
        currentUtterance = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        player?.stop()
        player = nil
        meterTimer?.invalidate()
        meterTimer = nil
        finish()
    }

    private func finish() {
        let c = continuation
        continuation = nil
        c?.resume()
    }

    // MARK: macOS voice

    private func speakWithSystemVoice(_ text: String, _ config: Config) async {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(identifier: config.systemVoiceID) ?? Self.defaultVoice()
        utterance.rate = config.rate
        utterance.postUtteranceDelay = 0
        currentUtterance = ObjectIdentifier(utterance)
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            self.continuation = c
            self.synth.speak(utterance)
        }
    }

    /// Best installed English voice, preferring British English and higher quality.
    nonisolated static func defaultVoice() -> AVSpeechSynthesisVoice? {
        let english = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix("en") && !$0.voiceTraits.contains(.isNoveltyVoice)
        }
        return english.max { a, b in
            let sa = a.quality.rawValue * 10 + (a.language == "en-GB" ? 1 : 0)
            let sb = b.quality.rawValue * 10 + (b.language == "en-GB" ? 1 : 0)
            return sa < sb
        } ?? AVSpeechSynthesisVoice(language: "en-GB")
    }

    nonisolated static func availableVoices(languagePrefix: String) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(languagePrefix) && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { ($0.quality.rawValue, $1.name) > ($1.quality.rawValue, $0.name) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onLevel?(Float.random(in: 0.55...0.9)) }
    }

    private func utteranceEnded(_ id: ObjectIdentifier) {
        guard id == currentUtterance else { return }
        currentUtterance = nil
        onLevel?(0)
        finish()
    }

    // MARK: OpenAI voice

    private func fetchOpenAISpeech(_ text: String, _ config: Config) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(config.openAIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: JSONObject = [
            "model": config.openAIModel,
            "voice": config.openAIVoice,
            "input": text,
            "response_format": "mp3",
        ]
        if config.openAIModel.hasPrefix("gpt") {
            body["instructions"] = "Speak in a calm, warm, quietly confident tone, like a polished personal AI assistant. Brisk, natural pace."
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await HTTP.session.data(for: request)
        try HTTP.check(response, data)
        return data
    }

    private func play(_ data: Data) async {
        guard let newPlayer = try? AVAudioPlayer(data: data) else { return }
        newPlayer.delegate = self
        newPlayer.isMeteringEnabled = true
        player = newPlayer
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateMeter() }
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            self.continuation = c
            newPlayer.play()
        }
        meterTimer?.invalidate()
        meterTimer = nil
        onLevel?(0)
    }

    private func updateMeter() {
        guard let player else { return }
        player.updateMeters()
        let db = player.averagePower(forChannel: 0)
        onLevel?(max(0, min(1, (db + 40) / 40)))
    }

    nonisolated func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(finished)
        Task { @MainActor in
            guard let player = self.player, ObjectIdentifier(player) == id else { return }
            self.player = nil
            self.finish()
        }
    }
}
