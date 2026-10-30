import AppKit
import Combine

/// The conductor: wake word → listen → think (LLM + tools) → speak → listen for a follow-up.
@MainActor
final class Assistant: ObservableObject {
    enum Phase: Equatable {
        case starting, idle, listening, thinking, speaking, paused
        case error(String)
    }

    @Published private(set) var phase: Phase = .starting
    @Published var heard = ""
    @Published var reply = ""
    @Published var status = ""
    @Published private(set) var isPaused = false

    let settings: AppSettings
    let meter = LevelMeter()

    private let listener = VoiceListener()
    private let speaker = VoiceSpeaker()
    private let agent = Agent()
    private lazy var hud = HUDController(assistant: self, meter: meter)
    private var work: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var lastInteraction = Date.distantPast
    private var pendingAnnouncements: [String] = []
    private var wired = false

    private static let dismissals: Set<String> = [
        "stop", "cancel", "never mind", "nevermind", "nothing", "no", "no thanks", "no thank you",
        "thats all", "that's all", "thank you thats all", "thanks thats all", "thank you", "thanks", "goodbye", "bye",
    ]

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: Startup

    func start() async {
        wireUp()
        let permissions = await VoiceListener.requestPermissions()
        guard permissions.mic else {
            fail("TESS needs microphone access. Open Settings › Permissions.")
            return
        }
        guard permissions.speech else {
            fail("TESS needs speech recognition access. Open Settings › Permissions.")
            return
        }
        startListening()
        if briefingDue() {
            startBriefing()
        } else if settings.greetOnLaunch, phase == .idle {
            await announce(greeting())
        }
    }

    // MARK: Morning briefing

    private static let lastBriefingKey = "lastBriefingDay"

    /// True once per day, in the morning, if automatic briefings are on.
    private func briefingDue() -> Bool {
        guard settings.briefingOnUnlock, !isPaused else { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        guard (5..<11).contains(hour) else { return false }
        return UserDefaults.standard.string(forKey: Self.lastBriefingKey) != UsageStore.key(Date())
    }

    private func screenUnlocked() {
        guard briefingDue() else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000) // let audio devices settle after wake
            guard let self, self.phase == .idle, self.briefingDue() else { return }
            self.startBriefing()
        }
    }

    private func startBriefing() {
        UserDefaults.standard.set(UsageStore.key(Date()), forKey: Self.lastBriefingKey)
        handleCommand("Good morning! Give me my morning briefing.", record: false)
    }

    private func wireUp() {
        guard !wired else { return }
        wired = true

        listener.onWake = { [weak self] trailing in self?.wakeDetected(trailing) }
        listener.onPartial = { [weak self] text in self?.heard = text }
        listener.onCommand = { [weak self] text in self?.handleCommand(text) }
        listener.onCommandTimeout = { [weak self] in self?.commandTimedOut() }
        listener.onLevel = { [weak self] level in
            guard let self, self.phase != .speaking else { return }
            self.meter.update(level)
        }
        listener.onError = { [weak self] message in self?.status = message }
        speaker.onLevel = { [weak self] level in self?.meter.update(level) }
        TimerCenter.shared.onFire = { [weak self] label in self?.timerFired(label) }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screenUnlocked() }
        }

        settings.$provider.dropFirst().sink { [weak self] _ in self?.agent.reset() }.store(in: &cancellables)
        settings.$wakeName.sink { [weak self] name in
            self?.listener.wakeName = name.trimmed.isEmpty ? "Tess" : name.trimmed
        }.store(in: &cancellables)
        settings.$recognitionLocale.dropFirst().removeDuplicates()
            .sink { [weak self] id in self?.listener.setLocale(id) }
            .store(in: &cancellables)
    }

    private func startListening() {
        do {
            try listener.start(localeID: settings.recognitionLocale)
            isPaused = false
            setPhase(.idle)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func fail(_ message: String) {
        status = message
        setPhase(.error(message))
    }

    // MARK: Voice events

    private func wakeDetected(_ trailing: String) {
        if isOwnEcho(trailing) {
            // The mic picked up TESS saying "hey Tess" herself — ignore it and keep talking.
            listener.listenForWake()
            return
        }
        work?.cancel()
        work = nil
        if phase == .speaking { speaker.stop() }
        chime("Tink")
        heard = trailing
        reply = ""
        status = ""
        setPhase(.listening)
    }

    private func commandTimedOut() {
        heard = ""
        goIdle()
    }

    private func handleCommand(_ raw: String, typed: Bool = false, record: Bool = true) {
        let text = raw.trimmed
        heard = text
        let normalized = text.lowercased().trimmingCharacters(in: .punctuationCharacters)
        guard !text.isEmpty else { goIdle(); return }

        if Self.dismissals.contains(normalized) {
            reply = ""
            chime("Pop")
            goIdle()
            return
        }
        if ["new conversation", "start over", "forget that", "clear the conversation"].contains(normalized) {
            agent.reset()
            work = Task { [weak self] in await self?.speakThen("Fresh start.", followUp: false) }
            return
        }

        if record { UsageStore.shared.recordCommand(typed: typed) }
        status = "Thinking…"
        reply = ""
        setPhase(.thinking)
        listener.listenForWake() // saying the wake phrase again cancels and starts over
        work = Task { [weak self] in await self?.process(text) }
    }

    private func process(_ text: String) async {
        if Date().timeIntervalSince(lastInteraction) > 600 { agent.reset() }
        lastInteraction = Date()

        let provider: LLMProvider
        do {
            provider = try settings.makeProvider()
        } catch {
            await speakThen(error.localizedDescription, followUp: false)
            return
        }

        do {
            let answer = try await agent.run(userText: text,
                                             provider: provider,
                                             system: settings.systemPrompt(memories: settings.memoryEnabled ? MemoryStore.shared.texts : nil),
                                             tools: ToolRegistry.standard(context: settings.toolContext)) { [weak self] tool in
                self?.status = ToolRegistry.statusText(for: tool)
            }
            guard !Task.isCancelled else { return }
            lastInteraction = Date()
            let spoken = SpeechText.clean(answer)
            await speakThen(spoken.isEmpty ? "Done." : spoken, followUp: true)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            await speakThen(Self.spokenError(error, provider: provider.name), followUp: false)
        }
    }

    /// - Parameter interruptible: whether saying the wake phrase can cut in. Announcements (greeting, timers)
    ///   keep the mic off until they finish, so TESS can't trigger herself.
    private func speakThen(_ text: String, followUp: Bool, interruptible: Bool = true) async {
        reply = text
        status = ""
        setPhase(.speaking)
        if interruptible && settings.allowBargeIn && !isPaused { listener.listenForWake() } else { listener.pause() }

        await speaker.speak(text, config: settings.voiceConfig)
        guard phase == .speaking else { return } // interrupted by the wake phrase

        // Let the last of her voice die away before the mic listens again.
        try? await Task.sleep(nanoseconds: 600_000_000)
        guard phase == .speaking else { return }

        if followUp && settings.followUpEnabled && !isPaused {
            heard = ""
            setPhase(.listening)
            listener.listenForCommand(timeout: settings.followUpSeconds)
        } else {
            goIdle()
        }
    }

    /// True when a wake phrase heard while TESS is talking is really her own voice coming back through the mic:
    /// she's saying her name, and the words after it are words she's saying too.
    private func isOwnEcho(_ trailing: String) -> Bool {
        guard phase == .speaking else { return false }
        let spoken = Self.normalized(reply)
        let name = Self.normalized(settings.wakeName.trimmed.isEmpty ? "Tess" : settings.wakeName)
        guard !name.isEmpty, spoken.contains(name) else { return false }
        let following = Self.normalized(trailing).split(separator: " ").prefix(3).joined(separator: " ")
        return following.isEmpty || spoken.contains(following)
    }

    private static func normalized(_ text: String) -> String {
        let letters = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(letters).split(separator: " ").joined(separator: " ")
    }

    private func goIdle() {
        status = ""
        if isPaused {
            setPhase(.paused)
        } else {
            setPhase(.idle)
            listener.listenForWake()
        }
        if !pendingAnnouncements.isEmpty {
            let next = pendingAnnouncements.removeFirst()
            Task { [weak self] in await self?.announce(next) }
        }
    }

    // MARK: Announcements (greeting, timers)

    func announce(_ text: String) async {
        switch phase {
        case .idle, .paused, .error, .starting:
            heard = ""
            await speakThen(text, followUp: false, interruptible: false)
        default:
            pendingAnnouncements.append(text)
        }
    }

    private func timerFired(_ label: String?) {
        chime("Glass")
        let name = settings.displayName
        var text = label.map { "Your \($0) timer is done." } ?? "Your timer is done."
        if !name.isEmpty {
            let lowered = text.prefix(1).lowercased() + String(text.dropFirst())
            text = "\(name), \(lowered)"
        }
        Task { [weak self] in await self?.announce(text) }
    }

    private func greeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 5 ? "Good evening" : hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        let name = settings.displayName
        let wake = settings.wakeName.trimmed.isEmpty ? "Tess" : settings.wakeName.trimmed
        return "\(part)\(name.isEmpty ? "" : ", \(name)"). All systems online. Just say hey \(wake) when you need me."
    }

    // MARK: Menu actions

    func talkNow() {
        if isPaused { startListening() }
        guard listener.isRunning else { return }
        work?.cancel()
        speaker.stop()
        chime("Tink")
        heard = ""
        reply = ""
        setPhase(.listening)
        listener.listenForCommand(timeout: 8)
    }

    func submitTyped(_ text: String) {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return }
        work?.cancel()
        speaker.stop()
        handleCommand(trimmed, typed: true)
    }

    func togglePaused() {
        if isPaused {
            startListening()
        } else {
            work?.cancel()
            speaker.stop()
            listener.stop()
            isPaused = true
            status = ""
            setPhase(.paused)
        }
    }

    /// Things said in the current conversation (short-term memory).
    var conversationTurns: Int { agent.userTurns }

    func newConversation() {
        agent.reset()
        heard = ""
        reply = ""
    }

    func testVoice() {
        Task { [weak self] in
            guard let self else { return }
            self.speaker.stop()
            await self.speakThen("Hello. I'm \(self.settings.wakeName.trimmed.isEmpty ? "TESS" : self.settings.wakeName). Voice systems are working perfectly.", followUp: false)
        }
    }

    /// Sends a tiny request to the selected AI and reports the result for the settings screen.
    func testBrain() async -> String {
        do {
            let provider = try settings.makeProvider()
            let reply = try await provider.complete(system: "You are a connectivity check. Reply with a short, friendly confirmation of at most eight words.",
                                                    history: [.user("Are you online?")],
                                                    tools: [])
            let text = SpeechText.clean(reply.text)
            return "✓ \(provider.name) replied: \(text.isEmpty ? "(empty)" : text)"
        } catch {
            return "✗ " + Self.spokenError(error, provider: settings.provider.shortName)
        }
    }

    // MARK: Presentation

    var statusLine: String {
        let wake = settings.wakeName.trimmed.isEmpty ? "Tess" : settings.wakeName.trimmed
        switch phase {
        case .starting: return "Starting up…"
        case .idle: return status.isEmpty ? "Say “Hey \(wake)”" : status
        case .listening: return "Listening…"
        case .thinking: return status.isEmpty ? "Thinking…" : status
        case .speaking: return "Speaking…"
        case .paused: return "Paused — microphone off"
        case .error(let message): return message
        }
    }

    var hudCaption: String? {
        switch phase {
        case .thinking: return status.isEmpty ? "Thinking…" : status
        case .speaking: return reply.isEmpty ? nil : reply
        case .error(let message): return message
        default: return nil
        }
    }

    var menuIcon: String {
        switch phase {
        case .listening, .speaking: return "waveform.circle.fill"
        case .thinking: return "ellipsis.circle.fill"
        case .paused: return "mic.slash.circle"
        case .error: return "exclamationmark.circle"
        default: return "waveform.circle"
        }
    }

    private func setPhase(_ newPhase: Phase) {
        phase = newPhase
        switch newPhase {
        case .listening, .thinking, .speaking:
            hideTask?.cancel()
            hud.show()
        case .error:
            hud.show()
            scheduleHide(after: 6)
        default:
            scheduleHide(after: 2.5)
        }
    }

    private func scheduleHide(after seconds: Double) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            switch self.phase {
            case .listening, .thinking, .speaking: return
            default: self.hud.hide()
            }
        }
    }

    private func chime(_ name: String) {
        guard settings.playChimes else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    static func spokenError(_ error: Error, provider: String) -> String {
        if let api = error as? APIError {
            switch api.status {
            case 401, 403: return "\(provider) rejected the API key. Please check it in settings."
            case 404: return "\(provider) doesn't recognise that model name. Please check it in settings."
            case 429: return "\(provider) says we're rate limited or out of credit. Try again shortly."
            case 500...599: return "\(provider) is having trouble right now. Try again in a moment."
            default: return "\(provider) returned an error: \(api.detail)"
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost:
                return provider == "Ollama" ? "I can't reach Ollama. Is it running?" : "I can't reach \(provider)."
            case .notConnectedToInternet: return "I seem to be offline."
            case .timedOut: return "\(provider) took too long to answer."
            default: break
            }
        }
        return error.localizedDescription
    }
}
