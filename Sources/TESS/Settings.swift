import Foundation

enum ProviderKind: String, CaseIterable, Identifiable {
    case anthropic, openai, ollama
    var id: String { rawValue }

    var title: String {
        switch self {
        case .anthropic: return "Claude (Anthropic)"
        case .openai: return "OpenAI"
        case .ollama: return "Local model (Ollama)"
        }
    }

    var shortName: String {
        switch self {
        case .anthropic: return "Claude"
        case .openai: return "OpenAI"
        case .ollama: return "Ollama"
        }
    }
}

enum VoiceEngine: String, CaseIterable, Identifiable {
    case system, openai
    var id: String { rawValue }
    var title: String { self == .system ? "macOS voice (free, offline)" : "OpenAI voice (natural, uses API)" }
}

enum MusicApp: String, CaseIterable, Identifiable {
    case auto, music, spotify
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Automatic"
        case .music: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }
}

enum Units: String, CaseIterable, Identifiable {
    case metric, imperial
    var id: String { rawValue }
    var title: String { self == .metric ? "Metric (°C, km/h)" : "Imperial (°F, mph)" }
}

/// Everything a tool needs to know about the user's preferences, captured once per request.
struct ToolContext {
    let homeCity: String
    let units: Units
    let musicApp: MusicApp
    let newsFocus: NewsFocus
    let newsLanguage: NewsLanguage
    let includeWebSearch: Bool
    let memoryEnabled: Bool
}

/// User preferences, persisted in UserDefaults (API keys in the keychain).
final class AppSettings: ObservableObject {
    private static let defaults = UserDefaults.standard
    private func save(_ value: Any, _ key: String) { Self.defaults.set(value, forKey: key) }

    // Brain
    @Published var provider: ProviderKind { didSet { save(provider.rawValue, "provider") } }
    @Published var anthropicKey: String { didSet { Keychain.set(anthropicKey.trimmed, for: "anthropic") } }
    @Published var anthropicModel: String { didSet { save(anthropicModel, "anthropicModel") } }
    @Published var anthropicWebSearch: Bool { didSet { save(anthropicWebSearch, "anthropicWebSearch") } }
    @Published var openAIKey: String { didSet { Keychain.set(openAIKey.trimmed, for: "openai") } }
    @Published var openAIModel: String { didSet { save(openAIModel, "openAIModel") } }
    @Published var openAIBaseURL: String { didSet { save(openAIBaseURL, "openAIBaseURL") } }
    @Published var ollamaURL: String { didSet { save(ollamaURL, "ollamaURL") } }
    @Published var ollamaModel: String { didSet { save(ollamaModel, "ollamaModel") } }

    // You & wake word
    @Published var userName: String { didSet { save(userName, "userName") } }
    @Published var wakeName: String { didSet { save(wakeName, "wakeName") } }
    @Published var recognitionLocale: String { didSet { save(recognitionLocale, "recognitionLocale") } }
    @Published var homeCity: String { didSet { save(homeCity, "homeCity") } }
    @Published var units: Units { didSet { save(units.rawValue, "units") } }
    @Published var personality: String { didSet { save(personality, "personality") } }

    // Conversation
    @Published var followUpEnabled: Bool { didSet { save(followUpEnabled, "followUpEnabled") } }
    @Published var followUpSeconds: Double { didSet { save(followUpSeconds, "followUpSeconds") } }
    @Published var allowBargeIn: Bool { didSet { save(allowBargeIn, "allowBargeIn") } }
    @Published var greetOnLaunch: Bool { didSet { save(greetOnLaunch, "greetOnLaunch") } }
    @Published var playChimes: Bool { didSet { save(playChimes, "playChimes") } }
    @Published var memoryEnabled: Bool { didSet { save(memoryEnabled, "memoryEnabled") } }
    @Published var briefingOnUnlock: Bool { didSet { save(briefingOnUnlock, "briefingOnUnlock") } }

    // Voice
    @Published var voiceEngine: VoiceEngine { didSet { save(voiceEngine.rawValue, "voiceEngine") } }
    @Published var systemVoiceID: String { didSet { save(systemVoiceID, "systemVoiceID") } }
    @Published var speechRate: Double { didSet { save(speechRate, "speechRate") } }
    @Published var openAIVoice: String { didSet { save(openAIVoice, "openAIVoice") } }
    @Published var openAITTSModel: String { didSet { save(openAITTSModel, "openAITTSModel") } }

    // Media & news
    @Published var musicApp: MusicApp { didSet { save(musicApp.rawValue, "musicApp") } }
    @Published var newsFocus: NewsFocus { didSet { save(newsFocus.rawValue, "newsFocus") } }
    @Published var newsLanguage: NewsLanguage { didSet { save(newsLanguage.rawValue, "newsLanguage") } }

    init() {
        let d = Self.defaults
        func str(_ key: String, _ fallback: String) -> String { d.string(forKey: key) ?? fallback }
        func flag(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: key) as? Bool ?? fallback }
        func num(_ key: String, _ fallback: Double) -> Double { d.object(forKey: key) as? Double ?? fallback }

        provider = ProviderKind(rawValue: str("provider", "")) ?? .anthropic
        anthropicKey = Keychain.get("anthropic")
        anthropicModel = str("anthropicModel", "claude-sonnet-5-5")
        anthropicWebSearch = flag("anthropicWebSearch", true)
        openAIKey = Keychain.get("openai")
        openAIModel = str("openAIModel", "gpt-5.4-mini")
        openAIBaseURL = str("openAIBaseURL", "https://api.openai.com/v1")
        ollamaURL = str("ollamaURL", "http://127.0.0.1:11434")
        ollamaModel = str("ollamaModel", "llama3.1")

        userName = str("userName", "")
        wakeName = str("wakeName", AppFlavor.current.defaultWakeName)
        recognitionLocale = str("recognitionLocale", "en-US")
        homeCity = str("homeCity", "")
        let usesImperial = Locale.current.measurementSystem == .us
        units = Units(rawValue: str("units", "")) ?? (usesImperial ? .imperial : .metric)
        personality = str("personality", "")

        followUpEnabled = flag("followUpEnabled", true)
        followUpSeconds = num("followUpSeconds", 6)
        allowBargeIn = flag("allowBargeIn", true)
        greetOnLaunch = flag("greetOnLaunch", true)
        playChimes = flag("playChimes", true)
        memoryEnabled = flag("memoryEnabled", true)
        briefingOnUnlock = flag("briefingOnUnlock", AppFlavor.current.briefingOnUnlockByDefault)

        voiceEngine = VoiceEngine(rawValue: str("voiceEngine", "")) ?? .system
        systemVoiceID = str("systemVoiceID", "")
        speechRate = num("speechRate", 0.52)
        openAIVoice = str("openAIVoice", "marin")
        openAITTSModel = str("openAITTSModel", "gpt-4o-mini-tts")

        musicApp = MusicApp(rawValue: str("musicApp", "")) ?? .auto
        newsFocus = NewsFocus(rawValue: str("newsFocus", "")) ?? .local
        newsLanguage = NewsLanguage(rawValue: str("newsLanguage", "")) ?? .english
    }

    // MARK: Derived

    var activeModel: String {
        switch provider {
        case .anthropic: return anthropicModel
        case .openai: return openAIModel
        case .ollama: return ollamaModel
        }
    }

    func makeProvider() throws -> LLMProvider {
        switch provider {
        case .anthropic:
            guard !anthropicKey.trimmed.isEmpty else {
                throw TESSError("I need a Claude API key. Add one in TESS settings, under Brain.")
            }
            return AnthropicProvider(apiKey: anthropicKey.trimmed, model: anthropicModel.trimmed, webSearch: anthropicWebSearch)
        case .openai:
            guard !openAIKey.trimmed.isEmpty else {
                throw TESSError("I need an OpenAI API key. Add one in TESS settings, under Brain.")
            }
            let base = URL(string: openAIBaseURL.trimmed) ?? URL(string: "https://api.openai.com/v1")!
            return OpenAICompatibleProvider(name: "OpenAI", baseURL: base, apiKey: openAIKey.trimmed, model: openAIModel.trimmed)
        case .ollama:
            guard let base = URL(string: ollamaURL.trimmed) else { throw TESSError("The Ollama address in settings isn't valid.") }
            return OpenAICompatibleProvider(name: "Ollama", baseURL: base.appendingPathComponent("v1"), apiKey: nil, model: ollamaModel.trimmed)
        }
    }

    var toolContext: ToolContext {
        ToolContext(homeCity: homeCity.trimmed,
                    units: units,
                    musicApp: musicApp,
                    newsFocus: newsFocus,
                    newsLanguage: newsLanguage,
                    includeWebSearch: !(provider == .anthropic && anthropicWebSearch),
                    memoryEnabled: memoryEnabled)
    }

    var voiceConfig: VoiceSpeaker.Config {
        VoiceSpeaker.Config(engine: voiceEngine,
                            systemVoiceID: systemVoiceID,
                            rate: Float(speechRate),
                            openAIKey: openAIKey.trimmed,
                            openAIVoice: openAIVoice,
                            openAIModel: openAITTSModel)
    }

    var displayName: String { userName.trimmed }

    func systemPrompt(now: Date = Date(), memories: [String]? = nil) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US")
        df.dateFormat = "EEEE d MMMM yyyy, HH:mm"
        let who = displayName.isEmpty ? "the user" : displayName
        let assistantName = AppFlavor.current.isDev ? "TESS Dev"
            : (wakeName.trimmed.isEmpty ? "TESS" : wakeName.trimmed.uppercased())

        var prompt = """
        You are \(assistantName), a voice assistant living on \(who)'s Mac. Your manner: calm, quick, quietly witty and unfailingly competent, \
        like a seasoned butler who also happens to be a brilliant engineer. You speak with \(who).

        Everything you write is read aloud by a text-to-speech voice, so:
        - Answer in one to three short sentences unless asked for more detail.
        - Never use markdown, lists, emoji, URLs or code.
        - Write numbers, times and units the way a person would say them.
        - Don't narrate your tool use. Just use the tool and give the result.

        You can act on the Mac and the world through your tools: apps, volume, appearance, files, screenshots, timers, \
        calendar, reminders, weather, news, web search, music, morning briefings, seeing the screen, reading documents, \
        typing into the current app, Messages, Apple Notes, Apple Mail, the user's protocols, the web page they have open, \
        exchange rates, stock prices and sports results. Use them whenever they help rather than guessing. \
        If a request is ambiguous, ask one short question. Confirm before anything destructive. If a tool fails, say so plainly.

        - "Good morning" or "brief me": call get_briefing.
        - News: get_news already focuses on the user's home area. Headlines may be in the local language; translate and summarise them into the language you're speaking, and drop outlet names unless asked.
        - Questions about what's on screen ("what am I looking at", "what does this error say", "summarise this page"): call look_at_screen.
        - "This document", "the PDF I just downloaded", "summarise my report": find it with find_documents (or use path 'current' for the open one), then read_document.
        - "Write / type …" into the app the user is in: compose the text and call type_text.
        - Texting someone: call draft_message, read the recipient and message back, and wait for a clear yes before send_message. Never send without that yes. The yes must be their very next reply (TESS enforces this); if they want changes, make a new draft and read it back.
        - Email: check_mail to list or search, read_email to read one. To send or reply, call draft_email, tell the user who it's to and summarise it, and wait for a clear yes before send_email. Never send without that yes; the same rules as for messages apply.
        - "Run …", "start …", "… mode" or "… protocol": call run_protocol.
        - "This page", "this article", "this tab": call read_web_page.
        - Money: convert_currency for exchange rates, stock_quote for shares, funds, indices and crypto. Sports results, scores and fixtures: sports_results.

        Current local date and time: \(df.string(from: now)) (\(TimeZone.current.identifier)).
        Preferred units: \(units == .metric ? "metric" : "imperial").
        """
        if !homeCity.trimmed.isEmpty { prompt += "\nHome city: \(homeCity.trimmed)." }
        if !displayName.isEmpty { prompt += "\nAddress the user as \(displayName) occasionally, not in every reply." }
        if !personality.trimmed.isEmpty { prompt += "\n\nAdditional instructions from the user: \(personality.trimmed)" }
        if let memories {
            prompt += "\n\nLong-term memory: when the user asks you to remember something, or shares a lasting personal detail or preference, save it with the remember tool. Use forget when asked to forget. Never store secrets such as passwords."
            if memories.isEmpty {
                prompt += "\nYou don't remember anything about the user yet."
            } else {
                prompt += "\nWhat you remember about the user:\n" + memories.map { "- \($0)" }.joined(separator: "\n")
            }
        }
        return prompt
    }
}
