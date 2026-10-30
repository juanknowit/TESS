import AVFoundation
import Speech

/// Thread-safe holder for the current recognition request, fed from the audio thread.
final class AudioRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ newRequest: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        let old = request
        request = newRequest
        lock.unlock()
        if let old, old !== newRequest { old.endAudio() }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let current = request
        lock.unlock()
        current?.append(buffer)
    }
}

/// Always-on microphone with on-device speech recognition.
///
/// Modes:
/// - `.wake`: transcribe quietly and watch for "Hey <name>".
/// - `.command`: capture what follows until the user stops talking, then deliver it.
@MainActor
final class VoiceListener {
    enum Mode { case off, idle, wake, command }

    var wakeName = "Tess"
    var commandSilence: TimeInterval = 1.3

    var onWake: ((String) -> Void)?
    var onPartial: ((String) -> Void)?
    var onCommand: ((String) -> Void)?
    var onCommandTimeout: (() -> Void)?
    var onLevel: ((Float) -> Void)?
    var onError: ((String) -> Void)?

    private(set) var mode: Mode = .off
    var isRunning: Bool { engineRunning }

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private let box = AudioRequestBox()
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var engineRunning = false
    private var configObserver: NSObjectProtocol?

    private var transcript = ""
    private var commandText = ""
    private var enteredByWake = false
    private var lastChange = Date()
    private var taskStarted = Date()
    private var quickFailures = 0

    private var silenceTimer: Timer?
    private var startTimer: Timer?
    private var recycleTimer: Timer?

    // MARK: Permissions

    nonisolated static func requestPermissions() async -> (mic: Bool, speech: Bool) {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        return (mic, speech)
    }

    // MARK: Lifecycle

    func start(localeID: String) throws {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            throw TESSError("Speech recognition isn't available for \(localeID). Turn on Dictation in System Settings › Keyboard.")
        }
        try startEngine()
        listenForWake()
    }

    func setLocale(_ id: String) {
        guard let newRecognizer = SFSpeechRecognizer(locale: Locale(identifier: id)) else { return }
        recognizer = newRecognizer
        if mode == .wake { listenForWake() }
    }

    func stop() {
        pause()
        if engineRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engineRunning = false
        }
        mode = .off
    }

    /// Stop recognizing but keep the microphone open.
    func pause() {
        cancelTimers()
        stopTask()
        if mode != .off { mode = .idle }
    }

    func listenForWake() {
        guard engineRunning else { return }
        cancelTimers()
        mode = .wake
        startTask()
        recycleTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recycleIfQuiet() }
        }
    }

    /// Listen for a command without needing the wake phrase (follow-ups, "Talk now").
    func listenForCommand(timeout: TimeInterval) {
        guard engineRunning else { return }
        cancelTimers()
        mode = .command
        enteredByWake = false
        commandText = ""
        startTask()
        armStartTimer(timeout)
    }

    // MARK: Engine

    private func startEngine() throws {
        guard !engineRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw TESSError("No microphone input is available.")
        }
        input.removeTap(onBus: 0)
        let levelSink: @Sendable (Float) -> Void = { [weak self] level in
            Task { @MainActor in self?.onLevel?(level) }
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTap(box: box, level: levelSink))
        engine.prepare()
        try engine.start()
        engineRunning = true

        if configObserver == nil {
            configObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.handleConfigurationChange() }
            }
        }
    }

    /// Headphones plugged in, AirPods connected, etc. Rebuild the tap with the new format.
    private func handleConfigurationChange() {
        guard engineRunning else { return }
        let previous = mode
        stop()
        do {
            try startEngine()
            if previous == .command { listenForCommand(timeout: 6) } else if previous != .off && previous != .idle { listenForWake() } else { mode = .idle }
        } catch {
            onError?("Microphone changed and couldn't restart: \(error.localizedDescription)")
        }
    }

    nonisolated private static func makeTap(box: AudioRequestBox, level: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        return { buffer, _ in
            box.append(buffer)
            level(rms(buffer))
        }
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        let db = 20 * log10(max(sqrt(sum / Float(count)), 1e-6))
        return max(0, min(1, (db + 55) / 45))
    }

    // MARK: Recognition tasks

    private func startTask() {
        stopTask()
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        request.contextualStrings = ["Hey \(wakeName)", wakeName]
        request.addsPunctuation = false
        box.set(request)

        transcript = ""
        lastChange = Date()
        taskStarted = Date()
        generation += 1
        task = recognizer.recognitionTask(with: request, resultHandler: Self.makeHandler(generation: generation) { [weak self] gen, text, ended, errorText in
            Task { @MainActor in self?.receive(gen: gen, text: text, ended: ended, errorText: errorText) }
        })
    }

    nonisolated private static func makeHandler(
        generation: Int,
        forward: @escaping @Sendable (Int, String?, Bool, String?) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        return { result, error in
            let text = result?.bestTranscription.formattedString
            let ended = (result?.isFinal ?? false) || error != nil
            forward(generation, text, ended, error?.localizedDescription)
        }
    }

    private func stopTask() {
        generation += 1
        task?.cancel()
        task = nil
        box.set(nil)
    }

    private func receive(gen: Int, text: String?, ended: Bool, errorText: String?) {
        guard gen == generation else { return }
        if let text { handleTranscript(text) }
        if ended { taskEnded(errorText: errorText) }
    }

    private func handleTranscript(_ text: String) {
        guard text != transcript else { return }
        transcript = text
        lastChange = Date()
        quickFailures = 0
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        switch mode {
        case .wake:
            if let end = WakeMatcher.matchEnd(in: words, name: wakeName) {
                mode = .command
                enteredByWake = true
                commandText = words[end...].joined(separator: " ")
                recycleTimer?.invalidate()
                onWake?(commandText)
                if commandText.isEmpty { armStartTimer(7) } else { armSilenceTimer() }
            } else {
                // Clear the transcript after a pause so it never grows unbounded.
                armSilenceTimer(interval: 2.5)
            }
        case .command:
            if let end = WakeMatcher.matchEnd(in: words, name: wakeName) {
                commandText = words[end...].joined(separator: " ")
            } else if !enteredByWake {
                // Direct-command mode: the whole utterance is the command.
                commandText = text
            }
            onPartial?(commandText)
            if !commandText.trimmed.isEmpty {
                startTimer?.invalidate()
                startTimer = nil
                armSilenceTimer()
            }
        default:
            break
        }
    }

    private func taskEnded(errorText: String?) {
        let gen = generation
        switch mode {
        case .command where !commandText.trimmed.isEmpty:
            finishCommand()
            return
        case .wake, .command:
            break
        default:
            return
        }
        // Restart, backing off if the recognizer keeps failing immediately.
        if Date().timeIntervalSince(taskStarted) < 1.5 { quickFailures += 1 } else { quickFailures = 0 }
        if quickFailures >= 6 {
            let reason = errorText.map { ": " + $0 } ?? ""
            onError?("Speech recognition keeps stopping" + reason + ". Check that Dictation is on in System Settings › Keyboard.")
        }
        let delay = min(8.0, 0.25 * pow(2.0, Double(max(0, quickFailures - 1))))
        let wasCommand = mode == .command
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.generation == gen else { return }
            if wasCommand && self.mode == .command {
                self.enteredByWake = false
                self.startTask()
            } else if self.mode == .wake {
                self.startTask()
            }
        }
    }

    private func recycleIfQuiet() {
        guard mode == .wake else { return }
        if Date().timeIntervalSince(lastChange) > 1.5 { startTask() }
    }

    // MARK: Timers

    private func armSilenceTimer(interval: TimeInterval? = nil) {
        silenceTimer?.invalidate()
        let wait = interval ?? commandSilence
        silenceTimer = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.silenceElapsed() }
        }
    }

    private func silenceElapsed() {
        switch mode {
        case .command: finishCommand()
        case .wake: if !transcript.isEmpty { startTask() }
        default: break
        }
    }

    private func armStartTimer(_ timeout: TimeInterval) {
        startTimer?.invalidate()
        startTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.startTimedOut() }
        }
    }

    private func startTimedOut() {
        guard mode == .command, commandText.trimmed.isEmpty else { return }
        cancelTimers()
        stopTask()
        mode = .idle
        onCommandTimeout?()
    }

    private func finishCommand() {
        guard mode == .command else { return }
        let command = commandText.trimmed
        cancelTimers()
        stopTask()
        mode = .idle
        if command.isEmpty { onCommandTimeout?() } else { onCommand?(command) }
    }

    private func cancelTimers() {
        silenceTimer?.invalidate(); silenceTimer = nil
        startTimer?.invalidate(); startTimer = nil
        recycleTimer?.invalidate(); recycleTimer = nil
    }
}

/// Finds "hey <name>" (and close mis-hearings like "hey test" or "hi tessa") in a transcript.
enum WakeMatcher {
    static let greetings: Set<String> = ["hey", "hi", "hello", "ok", "okay", "hay", "yo"]

    /// Returns the index just past the last wake phrase, or nil.
    static func matchEnd(in words: [String], name: String) -> Int? {
        let target = normalize(name)
        guard !target.isEmpty, words.count >= 2 else { return nil }
        let norm = words.map(normalize)
        var found: Int?
        for i in 0..<(norm.count - 1) where greetings.contains(norm[i]) && isName(norm[i + 1], target) {
            found = i + 2
        }
        if found == nil {
            // Recognizers sometimes fuse the phrase: "heytess".
            for (i, w) in norm.enumerated() where w == "hey" + target {
                found = i + 1
            }
        }
        return found
    }

    static func normalize(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func isName(_ word: String, _ target: String) -> Bool {
        if word == target { return true }
        if target.count >= 4 { return levenshtein(word, target) <= 1 }
        return false
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
