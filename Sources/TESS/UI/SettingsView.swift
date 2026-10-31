import AppKit
import AVFoundation
import Charts
import Contacts
import CoreGraphics
import EventKit
import ServiceManagement
import Speech
import SwiftUI

// NOTE: This file avoids `@State` and other SwiftUI macros so TESS builds with the Command Line Tools alone.
// View-local state lives in `UIState.shared`.

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, brain, voice, skills, routines, memory, history, usage, permissions, updates, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .brain: return "Brain"
        case .voice: return "Voice"
        case .skills: return "Skills"
        case .routines: return "Protocols"
        case .memory: return "Memory"
        case .history: return "History"
        case .usage: return "Usage"
        case .permissions: return "Permissions"
        case .updates: return "Updates"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .brain: return "brain.head.profile"
        case .voice: return "waveform"
        case .skills: return "sparkles"
        case .routines: return "bolt.circle"
        case .memory: return "bookmark"
        case .history: return "clock.arrow.circlepath"
        case .usage: return "chart.xyaxis.line"
        case .permissions: return "lock.shield"
        case .updates: return "arrow.down.circle"
        case .about: return "info.circle"
        }
    }

    var section: String {
        switch self {
        case .general, .brain, .voice: return "Essentials"
        case .skills, .routines, .memory, .history, .usage: return "Assistant"
        case .permissions, .updates, .about: return "System"
        }
    }

    var keywords: String {
        switch self {
        case .general: return "name city units wake word language follow-up greeting chimes personality music news login startup morning briefing"
        case .brain: return "ai provider claude openai ollama model api key web search local test connection"
        case .voice: return "speech tts speak voice rate speed openai marin cedar test"
        case .skills: return "skills examples help what can tess do commands mail web page currency stocks sports music weather news calendar notes messages screen documents typing"
        case .routines: return "protocols routines work mode wind down shortcuts automation steps"
        case .memory: return "remember forget facts"
        case .history: return "history conversations log past questions answers"
        case .usage: return "stats statistics tokens requests commands tools chart ram memory"
        case .permissions: return "microphone speech calendar reminders accessibility automation privacy screen recording contacts files"
        case .updates: return "update updates version upgrade release beta check download new install"
        case .about: return "version data folder"
        }
    }

    static let sections = ["Essentials", "Assistant", "System"]
}

enum UsageRange: String, CaseIterable, Identifiable {
    case today, week, month, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "Today"
        case .week: return "7 days"
        case .month: return "30 days"
        case .all: return "All time"
        }
    }
    var days: Int? {
        switch self {
        case .today: return 1
        case .week: return 7
        case .month: return 30
        case .all: return nil
        }
    }
    var chartDays: Int {
        switch self {
        case .today, .week: return 14
        case .month, .all: return 30
        }
    }
}

// MARK: - Window

@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show(settings: AppSettings, assistant: Assistant, pane: SettingsPane? = nil) {
        if let pane { UIState.shared.settingsPane = pane }
        if window == nil {
            let root = SettingsRoot()
                .environmentObject(settings)
                .environmentObject(assistant)
                .environmentObject(assistant.meter)
            let host = NSHostingController(rootView: root)
            let w = NSWindow(contentViewController: host)
            w.title = "\(AppFlavor.current.appName) Settings"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = NSColor(red: 0.055, green: 0.055, blue: 0.086, alpha: 1)
            w.setContentSize(NSSize(width: 940, height: 680))
            w.contentMinSize = NSSize(width: 820, height: 560)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsRoot: View {
    @ObservedObject private var ui = UIState.shared

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar()
                .frame(width: 236)
            Rectangle().fill(Theme.stroke).frame(width: 1)
            VStack(spacing: 0) {
                HStack {
                    Text(ui.settingsPane.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                }
                .padding(.horizontal, 28)
                .frame(height: 52)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        page
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 6)
                    .padding(.bottom, 32)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Theme.window)
        }
        .background(Theme.window)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    @ViewBuilder
    private var page: some View {
        switch ui.settingsPane {
        case .general: GeneralPage()
        case .brain: BrainPage()
        case .voice: VoicePage()
        case .skills: SkillsPage()
        case .routines: RoutinesPage()
        case .memory: MemoryPage()
        case .history: HistoryPage()
        case .usage: UsagePage()
        case .permissions: PermissionsPage()
        case .updates: UpdatesPage()
        case .about: AboutPage()
        }
    }
}

// MARK: - Sidebar

private struct SettingsSidebar: View {
    @EnvironmentObject var assistant: Assistant
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var ui = UIState.shared

    private func panes(in section: String) -> [SettingsPane] {
        let query = ui.settingsSearch.trimmed.lowercased()
        return SettingsPane.allCases.filter { pane in
            guard pane.section == section else { return false }
            guard !query.isEmpty else { return true }
            return pane.title.lowercased().contains(query) || pane.keywords.contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 44) // room for the window buttons

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                TextField("Search settings", text: $ui.settingsSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text)
                if !ui.settingsSearch.isEmpty {
                    Button { ui.settingsSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.tile))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(SettingsPane.sections, id: \.self) { section in
                        let items = panes(in: section)
                        if !items.isEmpty {
                            sectionHeader(section)
                            if !ui.collapsedSections.contains(section) || !ui.settingsSearch.isEmpty {
                                ForEach(items) { pane in sidebarItem(pane) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 0)
            sidebarFooter
        }
        .background(Theme.sidebar)
    }

    private func sectionHeader(_ section: String) -> some View {
        let collapsed = ui.collapsedSections.contains(section)
        return Button {
            if collapsed { ui.collapsedSections.remove(section) } else { ui.collapsedSections.insert(section) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                Text(section)
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sidebarItem(_ pane: SettingsPane) -> some View {
        let selected = ui.settingsPane == pane
        return Button { ui.settingsPane = pane } label: {
            HStack(spacing: 10) {
                Image(systemName: pane.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? Color.white : Theme.accent)
                    .frame(width: 18)
                Text(pane.title)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Color.white : Theme.text)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Theme.accent : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sidebarFooter: some View {
        HStack(spacing: 10) {
            OrbView(phase: assistant.phase, level: 0)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(AppFlavor.current.appName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("\(settings.provider.shortName) · \(settings.activeModel)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        .padding(12)
    }
}

// MARK: - General

private struct GeneralPage: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var assistant: Assistant
    @EnvironmentObject var meter: LevelMeter
    @ObservedObject private var ui = UIState.shared

    private var wake: String { settings.wakeName.trimmed.isEmpty ? "Tess" : settings.wakeName.trimmed }

    private var locales: [String] {
        var ids = SFSpeechRecognizer.supportedLocales().map { $0.identifier.replacingOccurrences(of: "_", with: "-") }
        if !ids.contains(settings.recognitionLocale) { ids.append(settings.recognitionLocale) }
        return Array(Set(ids)).sorted()
    }

    var body: some View {
        PageHeader("General", "Who you are, how TESS wakes up, and how she talks with you.")

        hero

        Card("You") {
            SettingRow("person.crop.circle", "Your name", subtitle: "How TESS addresses you.") {
                TextField("", text: $settings.userName, prompt: Text("e.g. Juan")).themedField()
            }
            RowDivider()
            SettingRow("location", "Home city", subtitle: "Used for weather when you don't name a place.") {
                TextField("", text: $settings.homeCity, prompt: Text("e.g. Oslo")).themedField()
            }
            RowDivider()
            SettingRow("ruler", "Units") {
                Picker("", selection: $settings.units) {
                    Text("Metric").tag(Units.metric)
                    Text("Imperial").tag(Units.imperial)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 180)
            }
        }

        Card("Wake word", footer: "Say “Hey \(wake)” and your request in one breath, or wait for the chime.") {
            SettingRow("textformat", "Assistant name", subtitle: "The name you call out.") {
                TextField("", text: $settings.wakeName, prompt: Text("Tess")).themedField(width: 160)
            }
            RowDivider()
            SettingRow("globe", "Speech language", subtitle: "Language TESS listens in.") {
                Picker("", selection: $settings.recognitionLocale) {
                    ForEach(locales, id: \.self) { id in
                        Text(Locale.current.localizedString(forIdentifier: id) ?? id).tag(id)
                    }
                }
                .themedMenu()
            }
        }

        Card("Conversation") {
            SettingRow("bubble.left.and.bubble.right", "Listen for a follow-up",
                       subtitle: "Keep listening after answering, so you can reply without the wake word.") {
                Toggle("", isOn: $settings.followUpEnabled).themedSwitch()
            }
            RowDivider()
            SettingRow("timer", "Follow-up window", subtitle: "How long TESS waits for you to continue.") {
                HStack(spacing: 8) {
                    Text("\(Int(settings.followUpSeconds)) s")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .frame(width: 34, alignment: .trailing)
                    Stepper("", value: $settings.followUpSeconds, in: 3...15).labelsHidden()
                }
                .disabled(!settings.followUpEnabled)
                .opacity(settings.followUpEnabled ? 1 : 0.4)
            }
            RowDivider()
            SettingRow("hand.raised", "Interrupt with her name", subtitle: "Say “Hey \(wake)” while she's talking to cut in.") {
                Toggle("", isOn: $settings.allowBargeIn).themedSwitch()
            }
            RowDivider()
            SettingRow("sun.max", "Greet me on launch") {
                Toggle("", isOn: $settings.greetOnLaunch).themedSwitch()
            }
            RowDivider()
            SettingRow("bell", "Chimes", subtitle: "Soft sounds when TESS starts and stops listening.") {
                Toggle("", isOn: $settings.playChimes).themedSwitch()
            }
        }

        Card("Morning briefing", footer: "Or just say “Hey \(wake), good morning” any time.") {
            SettingRow("sunrise", "Brief me when I unlock my Mac",
                       subtitle: "Once a day between 5 and 11 am: weather, today's calendar, reminders and headlines.") {
                Toggle("", isOn: $settings.briefingOnUnlock).themedSwitch()
            }
        }

        Card("Personality", footer: "Extra instructions TESS follows in every conversation.") {
            TextField("", text: $settings.personality,
                      prompt: Text("e.g. Be extra dry and sarcastic. Call me sir."), axis: .vertical)
                .lineLimit(3...6)
                .themedField(width: nil)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }

        Card("Media & news") {
            SettingRow("music.note", "Music app") {
                Picker("", selection: $settings.musicApp) {
                    ForEach(MusicApp.allCases) { Text($0.title).tag($0) }
                }
                .themedMenu()
            }
            RowDivider()
            SettingRow("newspaper", "News focus",
                       subtitle: settings.homeCity.trimmed.isEmpty
                           ? "Set your home city above for local news."
                           : "Local means news about \(settings.homeCity.trimmed) plus national headlines.") {
                Picker("", selection: $settings.newsFocus) {
                    ForEach(NewsFocus.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 210)
            }
            RowDivider()
            SettingRow("character.bubble", "News language",
                       subtitle: "Local language gives the most local coverage, e.g. Norwegian outlets for Oslo. TESS still speaks to you in English.") {
                Picker("", selection: $settings.newsLanguage) {
                    ForEach(NewsLanguage.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 210)
            }
        }

        Card("Startup") {
            SettingRow("power", "Launch TESS at login") {
                Toggle("", isOn: $ui.launchAtLogin).themedSwitch()
                    .onChange(of: ui.launchAtLogin) { _, enabled in
                        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            ui.launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .onAppear { ui.launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private var hero: some View {
        HStack(spacing: 20) {
            OrbView(phase: assistant.phase, level: meter.level)
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 8) {
                Text(wake.uppercased())
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(assistant.statusLine)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Pill(text: settings.provider.shortName, tint: Theme.providerColor(settings.provider.shortName))
                    Pill(text: settings.voiceEngine == .openai ? "OpenAI voice" : "macOS voice", tint: Theme.cyan)
                    if settings.memoryEnabled { Pill(text: "Memory on", tint: Theme.green) }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Button { assistant.talkNow() } label: { Label("Talk now", systemImage: "mic.fill") }
                    .buttonStyle(ThemedButtonStyle(kind: .primary))
                Button { assistant.togglePaused() } label: {
                    Label(assistant.isPaused ? "Resume" : "Pause", systemImage: assistant.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(ThemedButtonStyle())
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Theme.card, Color(hex: 0x14243A)], startPoint: .leading, endPoint: .trailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

// MARK: - Brain

private struct BrainPage: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var assistant: Assistant
    @ObservedObject private var ui = UIState.shared

    var body: some View {
        PageHeader("Brain", "The AI that understands you and decides what to do. Switch any time — the current conversation resets when you do.")

        HStack(spacing: 12) {
            OptionTile(icon: "sparkle", title: "Claude", subtitle: "Cloud · built-in web search",
                       selected: settings.provider == .anthropic, tint: Theme.claude) { settings.provider = .anthropic }
            OptionTile(icon: "circle.hexagongrid", title: "OpenAI", subtitle: "Cloud",
                       selected: settings.provider == .openai, tint: Theme.openAI) { settings.provider = .openai }
            OptionTile(icon: "desktopcomputer", title: "Ollama", subtitle: "Local · private · free",
                       selected: settings.provider == .ollama, tint: Theme.accent) { settings.provider = .ollama }
        }

        switch settings.provider {
        case .anthropic: claudeCard
        case .openai: openAICard
        case .ollama: ollamaCard
        }

        Card("Connection") {
            SettingRow("bolt.horizontal", "Test connection",
                       subtitle: ui.testResult.isEmpty ? "Sends a tiny request to check your setup." : ui.testResult,
                       tint: ui.testResult.hasPrefix("✓") ? Theme.green : ui.testResult.hasPrefix("✗") ? Theme.red : Theme.accent) {
                Button(ui.testing ? "Testing…" : "Run test") {
                    ui.testing = true
                    Task {
                        ui.testResult = await assistant.testBrain()
                        ui.testing = false
                    }
                }
                .buttonStyle(ThemedButtonStyle(kind: .primary))
                .disabled(ui.testing)
            }
        }
        .task { if settings.provider == .ollama { refreshOllama() } }
        .onChange(of: settings.provider) { _, provider in
            ui.testResult = ""
            if provider == .ollama { refreshOllama() }
        }
    }

    private var claudeCard: some View {
        Card("Claude", footer: "Get a key at console.anthropic.com. Keys are stored in your Mac's keychain.") {
            SettingRow("key", "API key", tint: Theme.claude) {
                SecureField("", text: $settings.anthropicKey, prompt: Text("sk-ant-…")).themedField()
            }
            RowDivider()
            SettingRow("cpu", "Model", subtitle: "Sonnet is the best balance; Haiku is fastest.", tint: Theme.claude) {
                ModelPicker(text: $settings.anthropicModel,
                            suggestions: ["claude-sonnet-5-5", "claude-haiku-5-5", "claude-opus-5-5"])
            }
            RowDivider()
            SettingRow("globe", "Built-in web search", subtitle: "Lets Claude search the web for current answers.", tint: Theme.claude) {
                Toggle("", isOn: $settings.anthropicWebSearch).themedSwitch()
            }
        }
    }

    private var openAICard: some View {
        Card("OpenAI", footer: "Get a key at platform.openai.com. The same key powers the OpenAI voice.") {
            SettingRow("key", "API key", tint: Theme.openAI) {
                SecureField("", text: $settings.openAIKey, prompt: Text("sk-…")).themedField()
            }
            RowDivider()
            SettingRow("cpu", "Model", tint: Theme.openAI) {
                ModelPicker(text: $settings.openAIModel,
                            suggestions: ["gpt-5.4-mini", "gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.5"])
            }
            RowDivider()
            SettingRow("link", "API base URL", subtitle: "Change only for OpenAI-compatible services.", tint: Theme.openAI) {
                TextField("", text: $settings.openAIBaseURL).themedField()
            }
        }
    }

    private var ollamaCard: some View {
        Card("Ollama", footer: "Pick a model that supports tool calling (e.g. qwen3 or llama3.1) so TESS can control your Mac. Download models with “ollama pull <name>” in Terminal.") {
            SettingRow(statusIcon, statusTitle, subtitle: ui.ollamaChecking ? "Checking…" : ui.ollamaMessage, tint: statusTint) {
                Button("Check again") { refreshOllama() }
                    .buttonStyle(ThemedButtonStyle())
                    .disabled(ui.ollamaChecking)
            }
            RowDivider()
            SettingRow("server.rack", "Server") {
                TextField("", text: $settings.ollamaURL)
                    .themedField()
                    .onSubmit { refreshOllama() }
            }
            RowDivider()
            SettingRow("cpu", "Model", subtitle: ui.ollamaModels.isEmpty ? nil : "\(ui.ollamaModels.count) installed") {
                if ui.ollamaModels.isEmpty {
                    TextField("", text: $settings.ollamaModel).themedField()
                } else {
                    Picker("", selection: $settings.ollamaModel) {
                        ForEach(ollamaChoices, id: \.self) { Text($0).tag($0) }
                    }
                    .themedMenu()
                }
            }
        }
    }

    private var ollamaChoices: [String] {
        var models = ui.ollamaModels
        if !models.contains(settings.ollamaModel) { models.insert(settings.ollamaModel, at: 0) }
        return models
    }

    private var statusIcon: String {
        if ui.ollamaChecking { return "arrow.triangle.2.circlepath" }
        return ui.ollamaModels.isEmpty ? "exclamationmark.triangle" : "checkmark.circle"
    }

    private var statusTitle: String {
        if ui.ollamaChecking { return "Checking Ollama" }
        return ui.ollamaModels.isEmpty ? "Not ready" : "Ready"
    }

    private var statusTint: Color {
        if ui.ollamaChecking { return Theme.secondary }
        return ui.ollamaModels.isEmpty ? Theme.orange : Theme.green
    }

    private func refreshOllama() {
        ui.ollamaChecking = true
        Task {
            let status = await OpenAICompatibleProvider.ollamaStatus(baseURL: settings.ollamaURL)
            ui.ollamaModels = status.models
            ui.ollamaMessage = status.message
            ui.ollamaChecking = false
            let current = settings.ollamaModel.trimmed
            let installed = status.models
            if let exact = installed.first(where: { $0 == current + ":latest" }) {
                settings.ollamaModel = exact
            } else if !installed.isEmpty && !installed.contains(current) {
                settings.ollamaModel = installed[0]
            }
        }
    }
}

private struct ModelPicker: View {
    @Binding var text: String
    let suggestions: [String]

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $text).themedField(width: 200)
            Menu {
                ForEach(suggestions, id: \.self) { model in
                    Button(model) { text = model }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.tile))
        }
    }
}

// MARK: - Voice

private struct VoicePage: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var assistant: Assistant

    private static let openAIVoices = ["marin", "cedar", "alloy", "ash", "ballad", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer", "verse"]

    private var voices: [AVSpeechSynthesisVoice] {
        VoiceSpeaker.availableVoices(languagePrefix: String(settings.recognitionLocale.prefix(2)))
    }

    var body: some View {
        PageHeader("Voice", "How TESS sounds when she answers.") {
            Button { assistant.testVoice() } label: { Label("Test voice", systemImage: "play.fill") }
                .buttonStyle(ThemedButtonStyle(kind: .primary))
        }

        HStack(spacing: 12) {
            OptionTile(icon: "laptopcomputer", title: "macOS voice", subtitle: "Free · works offline",
                       selected: settings.voiceEngine == .system) { settings.voiceEngine = .system }
            OptionTile(icon: "waveform.badge.plus", title: "OpenAI voice", subtitle: "Most natural · uses API credit",
                       selected: settings.voiceEngine == .openai, tint: Theme.openAI) { settings.voiceEngine = .openai }
        }

        if settings.voiceEngine == .system {
            Card("macOS voice", footer: "For a far more natural sound, download a Premium or Enhanced voice in System Settings › Accessibility › Spoken Content › System Voice › Manage Voices, then pick it here.") {
                SettingRow("person.wave.2", "Voice") {
                    Picker("", selection: $settings.systemVoiceID) {
                        Text("Automatic (best installed)").tag("")
                        ForEach(voices, id: \.identifier) { voice in
                            Text(label(for: voice)).tag(voice.identifier)
                        }
                    }
                    .themedMenu()
                }
                RowDivider()
                SettingRow("speedometer", "Speed") {
                    Slider(value: $settings.speechRate, in: 0.38...0.62).frame(width: 200)
                }
            }
        } else {
            Card("OpenAI voice", footer: "Works with any brain and uses the same key as Brain › OpenAI. Marin and Cedar sound most natural. If a request fails, TESS falls back to the macOS voice.") {
                SettingRow("key", "OpenAI API key", subtitle: settings.openAIKey.trimmed.isEmpty ? "Required for this voice." : nil,
                           tint: settings.openAIKey.trimmed.isEmpty ? Theme.orange : Theme.openAI) {
                    SecureField("", text: $settings.openAIKey, prompt: Text("sk-…")).themedField()
                }
                RowDivider()
                SettingRow("person.wave.2", "Voice", tint: Theme.openAI) {
                    Picker("", selection: $settings.openAIVoice) {
                        ForEach(Self.openAIVoices, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .themedMenu()
                }
                RowDivider()
                SettingRow("cpu", "Speech model", tint: Theme.openAI) {
                    TextField("", text: $settings.openAITTSModel).themedField(width: 180)
                }
            }
        }
    }

    private func label(for voice: AVSpeechSynthesisVoice) -> String {
        let quality: String
        switch voice.quality {
        case .premium: quality = " · Premium"
        case .enhanced: quality = " · Enhanced"
        default: quality = ""
        }
        return "\(voice.name) (\(voice.language))\(quality)"
    }
}

// MARK: - Memory

private struct MemoryPage: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var assistant: Assistant
    @ObservedObject private var memory = MemoryStore.shared
    @ObservedObject private var ui = UIState.shared

    var body: some View {
        PageHeader("Memory", "TESS can remember lasting facts about you — just say “remember that…”. She also keeps the current conversation in mind for follow-ups.") {
            Toggle("", isOn: $settings.memoryEnabled).themedSwitch().controlSize(.regular)
        }

        TimelineView(.periodic(from: .now, by: 2)) { _ in
            HStack(spacing: 12) {
                StatTile(icon: "bookmark.fill", tint: Theme.accent, value: "\(memory.items.count)",
                         title: "Long-term memories",
                         detail: settings.memoryEnabled ? "Included with every request to your AI" : "Memory is off")
                StatTile(icon: "bubble.left.and.text.bubble.right", tint: Theme.cyan, value: "\(assistant.conversationTurns)",
                         title: "In this conversation", detail: "Resets after 10 minutes of silence")
            }
        }

        Card("Teach TESS something") {
            HStack(spacing: 10) {
                IconBadge(icon: "plus")
                TextField("", text: $ui.newMemory, prompt: Text("e.g. I prefer meetings after 10 am"))
                    .themedField(width: nil)
                    .onSubmit { addMemory() }
                Button("Remember") { addMemory() }
                    .buttonStyle(ThemedButtonStyle(kind: .primary))
                    .disabled(ui.newMemory.trimmed.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .disabled(!settings.memoryEnabled)
        .opacity(settings.memoryEnabled ? 1 : 0.5)

        Card("What TESS remembers", trailing: memory.items.isEmpty ? nil : "\(memory.items.count) of \(MemoryStore.limit)") {
            if memory.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Theme.tertiary)
                    Text("Nothing yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Text("Try “Hey Tess, remember that my daughter's name is Sofia.”")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
            } else {
                ForEach(Array(memory.items.reversed().enumerated()), id: \.element.id) { index, item in
                    if index > 0 { RowDivider() }
                    SettingRow("sparkles", item.text, subtitle: relative(item.created)) {
                        Button { memory.remove(item.id) } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.secondary)
                                .padding(6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Forget this")
                    }
                }
            }
        }

        Card("Short-term memory") {
            SettingRow("arrow.counterclockwise", "Start a fresh conversation",
                       subtitle: "Clears the current back-and-forth. Long-term memories stay.") {
                Button("Start fresh") { assistant.newConversation() }
                    .buttonStyle(ThemedButtonStyle())
            }
        }

        if !memory.items.isEmpty {
            HStack {
                Spacer()
                Button("Forget everything…") { ui.confirmClearMemories = true }
                    .buttonStyle(ThemedButtonStyle(kind: .destructive))
            }
            .confirmationDialog("Forget all \(memory.items.count) memories?", isPresented: $ui.confirmClearMemories) {
                Button("Forget everything", role: .destructive) { memory.clear() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    private func addMemory() {
        if memory.add(ui.newMemory) { ui.newMemory = "" }
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return "Remembered " + f.localizedString(for: date, relativeTo: Date())
    }
}

struct StatTile: View {
    let icon: String
    var tint: Color = Theme.accent
    let value: String
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
            }
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
                .monospacedDigit()
            if let detail {
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

// MARK: - Usage

private struct ChartPoint: Identifiable {
    let date: Date
    let tokens: Int
    var id: Date { date }
}

private struct UsagePage: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var assistant: Assistant
    @ObservedObject private var usage = UsageStore.shared
    @ObservedObject private var sampler = MemorySampler.shared
    @ObservedObject private var memory = MemoryStore.shared
    @ObservedObject private var ui = UIState.shared

    private var total: DayUsage { usage.total(lastDays: ui.usageRange.days) }

    var body: some View {
        PageHeader("Usage", "What TESS has been up to. Token counts come straight from your AI provider's responses.") {
            RangeTabs(selection: $ui.usageRange)
        }

        HStack(alignment: .top, spacing: 12) {
            ProviderCard(name: "Claude", icon: "sparkle", tint: Theme.claude, total: total,
                         active: settings.provider == .anthropic)
            ProviderCard(name: "OpenAI", icon: "circle.hexagongrid", tint: Theme.openAI, total: total,
                         active: settings.provider == .openai)
            ProviderCard(name: "Ollama", icon: "desktopcomputer", tint: Theme.ollama, total: total,
                         active: settings.provider == .ollama)
        }

        HStack(alignment: .top, spacing: 12) {
            tokensCard
            nowCard
        }

        trendCard

        HStack(alignment: .top, spacing: 12) {
            activityCard
            topActionsCard
        }

        systemCard

        HStack {
            Text("Tracking since \(usage.data.since.formatted(.dateTime.day().month(.wide).year())). Stored on this Mac only.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.tertiary)
            Spacer()
            Button("Reset statistics…") { ui.confirmResetUsage = true }
                .buttonStyle(ThemedButtonStyle(kind: .destructive))
        }
        .confirmationDialog("Reset all usage statistics?", isPresented: $ui.confirmResetUsage) {
            Button("Reset", role: .destructive) { usage.reset() }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { MemorySampler.shared.start() }
        .onDisappear { MemorySampler.shared.stop() }
    }

    private var tokensCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Tokens", systemImage: "circle.grid.cross")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(ui.usageRange.title)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
            }
            Text(SystemStats.compact(total.totalTokens))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
                .monospacedDigit()
            StackedBar(segments: [
                (Double(total.tokensByProvider["Claude"] ?? 0), Theme.claude),
                (Double(total.tokensByProvider["OpenAI"] ?? 0), Theme.openAI),
                (Double(total.tokensByProvider["Ollama"] ?? 0), Theme.ollama),
            ])
            Text("\(SystemStats.compact(total.inputTokens)) in · \(SystemStats.compact(total.outputTokens)) out · \(total.requests) requests")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 140, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private var nowCard: some View {
        TimelineView(.periodic(from: .now, by: 5)) { _ in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Now", systemImage: "waveform.path.ecg")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Circle().fill(phaseColor).frame(width: 7, height: 7)
                }
                Text(assistant.statusLine)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if let last = usage.lastRequest {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.providerColor(last.provider)).frame(width: 6, height: 6)
                        Text("\(last.model) · \(SystemStats.compact(last.tokens)) tokens")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(ago(last.date))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Theme.orange)
                    }
                } else {
                    Text("No requests yet this session.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 140, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        }
    }

    private var phaseColor: Color {
        switch assistant.phase {
        case .listening, .speaking: return Theme.cyan
        case .thinking: return Theme.orange
        case .error: return Theme.red
        case .paused: return Theme.tertiary
        default: return Theme.green
        }
    }

    private var trendCard: some View {
        let points = usage.series(days: ui.usageRange.chartDays).map { ChartPoint(date: $0.date, tokens: $0.usage.totalTokens) }
        let stride = ui.usageRange.chartDays > 14 ? 5 : 2
        return Card("Trend", trailing: "Tokens per day · last \(ui.usageRange.chartDays) days") {
            Chart(points) { point in
                BarMark(x: .value("Day", point.date, unit: .day), y: .value("Tokens", point.tokens))
                    .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.6), Theme.cyan],
                                                    startPoint: .bottom, endPoint: .top))
                    .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: stride)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .foregroundStyle(Theme.tertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text(SystemStats.compact(v)).foregroundStyle(Theme.tertiary)
                        }
                    }
                }
            }
            .frame(height: 170)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var activityCard: some View {
        Card("Activity") {
            MetricRow(icon: "mic", title: "Commands",
                      detail: "\(total.commands - total.typedCommands) spoken · \(total.typedCommands) typed",
                      value: "\(total.commands)")
            RowDivider()
            MetricRow(icon: "wand.and.stars", title: "Actions taken", detail: "Tools TESS used for you", value: "\(total.toolCalls)")
            RowDivider()
            MetricRow(icon: "globe", title: "Web searches", detail: "Claude's built-in search", value: "\(total.webSearches)")
            RowDivider()
            MetricRow(icon: "speaker.wave.2", title: "Spoken",
                      detail: "\(SystemStats.compact(total.cloudVoiceCharacters)) characters via OpenAI voice",
                      value: SystemStats.compact(total.spokenCharacters) + " chars")
        }
        .frame(maxWidth: .infinity)
    }

    private var topActionsCard: some View {
        let tools = usage.topTools
        let maxCount = Double(tools.first?.count ?? 1)
        return Card("Top actions", trailing: "All time") {
            if tools.isEmpty {
                Text("TESS hasn't used any tools yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            } else {
                VStack(spacing: 12) {
                    ForEach(tools, id: \.name) { tool in
                        VStack(spacing: 5) {
                            HStack {
                                Text(Self.friendlyName(tool.name))
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Theme.text)
                                Spacer()
                                Text("\(tool.count)")
                                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.text)
                            }
                            MeterBar(value: Double(tool.count) / maxCount, tint: Theme.accent, height: 5)
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var systemCard: some View {
        let footprint = sampler.samples.last ?? Double(SystemStats.memoryFootprint())
        return Card("TESS right now") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "memorychip")
                        .foregroundStyle(Theme.orange)
                    Text("Memory in use")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text(SystemStats.bytes(UInt64(footprint)))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .monospacedDigit()
                }
                Sparkline(values: sampler.samples, tint: Theme.orange)
                    .frame(height: 46)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            RowDivider()
            TimelineView(.periodic(from: .now, by: 5)) { _ in
                VStack(spacing: 0) {
                    MetricRow(icon: "clock", title: "Running for", detail: "Since TESS last started",
                              value: SystemStats.duration(since: usage.launchedAt))
                    RowDivider()
                    MetricRow(icon: "bubble.left.and.text.bubble.right", title: "Conversation",
                              detail: "Things said in the current conversation",
                              value: "\(assistant.conversationTurns)")
                    RowDivider()
                    MetricRow(icon: "bookmark", title: "Long-term memories",
                              detail: settings.memoryEnabled ? "Memory on" : "Memory off",
                              value: "\(memory.items.count)")
                    RowDivider()
                    MetricRow(icon: "desktopcomputer", title: "This Mac", detail: "Installed memory",
                              value: SystemStats.bytes(SystemStats.physicalMemory))
                }
            }
        }
    }

    private func ago(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }

    static func friendlyName(_ tool: String) -> String {
        let names = [
            "open_app": "Open app", "quit_app": "Quit app", "set_volume": "Volume", "get_system_status": "System status",
            "set_appearance": "Dark / light mode", "lock_screen": "Lock screen", "search_files": "Find files",
            "open_path_or_url": "Open file or link", "take_screenshot": "Screenshot", "set_timer": "Timer",
            "get_weather": "Weather", "get_news": "News", "web_search": "Web search",
            "get_calendar_events": "Read calendar", "create_calendar_event": "Add event",
            "get_reminders": "Read reminders", "create_reminder": "Add reminder", "complete_reminder": "Complete reminder",
            "media_control": "Music controls", "play_music": "Play music",
            "remember": "Remember", "forget": "Forget", "list_memories": "Recall memories",
            "get_briefing": "Morning briefing", "look_at_screen": "Look at screen", "find_documents": "Find documents",
            "read_document": "Read document", "type_text": "Type for you", "draft_message": "Draft message",
            "send_message": "Send message", "create_note": "New note", "append_to_note": "Add to note",
            "search_notes": "Search notes", "read_note": "Read note",
            "check_mail": "Check mail", "read_email": "Read email", "draft_email": "Draft email", "send_email": "Send email",
            "run_protocol": "Run protocol", "list_protocols": "List protocols", "read_web_page": "Read web page",
            "convert_currency": "Currency", "stock_quote": "Stock quote", "sports_results": "Sports",
        ]
        return names[tool] ?? tool.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private struct ProviderCard: View {
    let name: String
    let icon: String
    let tint: Color
    let total: DayUsage
    let active: Bool

    private var tokens: Int { total.tokensByProvider[name] ?? 0 }
    private var share: Double { total.totalTokens > 0 ? Double(tokens) / Double(total.totalTokens) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                if active { Pill(text: "Active", tint: tint) }
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Tokens")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Text(SystemStats.compact(tokens))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .monospacedDigit()
            }
            MeterBar(value: share, tint: tint, height: 7)
            Text(total.totalTokens > 0 ? "\(Int((share * 100).rounded()))% of all tokens" : "No usage yet")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(active ? tint.opacity(0.45) : Theme.stroke, lineWidth: 1))
    }
}

private struct MetricRow: View {
    let icon: String
    let title: String
    var detail: String?
    let value: String

    var body: some View {
        SettingRow(icon, title, subtitle: detail) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
                .monospacedDigit()
        }
    }
}

private struct SparkPoint: Identifiable {
    let index: Int
    let value: Double
    var id: Int { index }
}

private struct Sparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        let points = values.enumerated().map { SparkPoint(index: $0.offset, value: $0.element) }
        Chart(points) { point in
            AreaMark(x: .value("t", point.index), y: .value("v", point.value))
                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("t", point.index), y: .value("v", point.value))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...59)
        .chartYScale(domain: .automatic(includesZero: false))
        .background(RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.04)))
    }
}

private struct RangeTabs: View {
    @Binding var selection: UsageRange

    var body: some View {
        HStack(spacing: 2) {
            ForEach(UsageRange.allCases) { range in
                tab(range)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.tile))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func tab(_ range: UsageRange) -> some View {
        let selected = selection == range
        return Button { selection = range } label: {
            Text(range.title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.text : Theme.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.14) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Permissions

private struct PermissionsPage: View {
    @ObservedObject private var center = PermissionCenter.shared
    @EnvironmentObject var settings: AppSettings

    private var automationFooter: String {
        var text = "Automation opens Mail, Notes, Messages, Music, Spotify and your browsers in the background if needed, so macOS can ask about each one, then closes them again. \(AppFlavor.current.appName) then appears in System Settings › Automation."
        if !center.automationUnanswered.isEmpty {
            text = "macOS didn't show its question for \(center.automationUnanswered.joined(separator: ", ")). Open those apps yourself, then press Allow on Automation to try again. " + text
        }
        return text
    }

    var body: some View {
        PageHeader("Permissions", "What macOS lets \(AppFlavor.current.appName) do. Press Allow to get each prompt, or set everything up in one go.")

        setupCard

        if center.needsRestart {
            Card {
                SettingRow("arrow.clockwise", "Restart TESS to finish",
                           subtitle: "Screen Recording takes effect after TESS restarts. Switch TESS on in System Settings first.",
                           tint: Theme.orange) {
                    Button("Restart \(AppFlavor.current.appName)") { center.relaunch() }
                        .buttonStyle(ThemedButtonStyle(kind: .primary))
                }
            }
        }

        Card("Listening", footer: "Speech recognition also needs Dictation turned on in System Settings › Keyboard › Dictation, which downloads the on-device language model.") {
            row(.microphone, "mic", "Hearing “Hey \(settings.wakeName.trimmed.isEmpty ? AppFlavor.current.defaultWakeName : settings.wakeName.trimmed)” and your requests")
            RowDivider()
            row(.speech, "waveform", "Turning your voice into text, on device")
        }

        Card("Seeing & reading", footer: "Screen Recording can't be granted from a pop-up: \(AppFlavor.current.appName) opens the right page in System Settings — switch \(AppFlavor.current.appName) on there, then press Restart. If it isn't in the list, press + below the list and choose \(AppFlavor.current.appName) from Applications. Permissions stay granted when \(AppFlavor.current.appName) is updated or rebuilt.") {
            row(.screen, "rectangle.dashed.badge.record", "“What am I looking at?”")
            RowDivider()
            row(.files, "folder", "Reading documents on your Desktop, in Documents and Downloads")
        }

        Card("Your data") {
            row(.contacts, "person.crop.circle", "Finding who to message")
            RowDivider()
            row(.calendars, "calendar", "Reading and adding events")
            RowDivider()
            row(.reminders, "checklist", "Reading, adding and completing reminders")
        }

        Card("Control", footer: automationFooter) {
            row(.accessibility, "lock", "Typing for you, reading the open document, and screen lock")
            RowDivider()
            row(.automation, "gearshape.2", "Controlling Mail, Messages, Notes, Music, Spotify, your browser, Finder and System Events")
        }
        .onAppear { center.startMonitoring() }
        .onDisappear { center.stopMonitoring() }
    }

    private var setupCard: some View {
        let total = PermissionKind.allCases.count
        let done = center.grantedCount
        return HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(done) / CGFloat(total))
                    .stroke(center.allGranted ? Theme.green : Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(done)/\(total)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(center.allGranted ? "All set" : "Set up \(AppFlavor.current.appName)'s permissions")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(center.busy && !center.progress.isEmpty ? center.progress :
                        center.allGranted ? "\(AppFlavor.current.appName) can use every skill." :
                        "Goes through each one: answer macOS's prompts as they appear. Screen Recording and Accessibility need a switch in System Settings — \(AppFlavor.current.appName) opens the page for you.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !center.allGranted {
                Button {
                    Task { await center.requestAll() }
                } label: {
                    Label(center.busy ? "Setting up…" : "Set up everything", systemImage: "checkmark.shield")
                }
                .buttonStyle(ThemedButtonStyle(kind: .primary))
                .disabled(center.busy)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Theme.card, Color(hex: 0x14243A)], startPoint: .leading, endPoint: .trailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func row(_ kind: PermissionKind, _ icon: String, _ subtitle: String) -> some View {
        let state = center.states[kind] ?? .notAsked
        let tint: Color
        switch state {
        case .granted: tint = Theme.green
        case .denied: tint = Theme.red
        case .notAsked: tint = Theme.accent
        case .partial: tint = Theme.orange
        }
        return SettingRow(icon, kind.title, subtitle: subtitle, tint: tint) {
            HStack(spacing: 10) {
                Pill(text: state.label, tint: state == .notAsked ? Theme.secondary : tint)
                if state == .granted {
                    Button("Open") { center.openSettings(kind) }
                        .buttonStyle(ThemedButtonStyle())
                } else if kind == .screen, case .partial = state {
                    // Switched on in System Settings but not active yet: TESS has to restart.
                    Button("Open") { center.openSettings(kind) }
                        .buttonStyle(ThemedButtonStyle())
                    Button("Restart \(AppFlavor.current.appName)") { center.relaunch() }
                        .buttonStyle(ThemedButtonStyle(kind: .primary))
                        .help("macOS only applies Screen Recording when TESS starts.")
                } else {
                    Button(state == .notAsked ? "Allow" : "Fix") {
                        Task { await center.request(kind) }
                    }
                    .buttonStyle(ThemedButtonStyle(kind: .primary))
                    .disabled(center.busy)
                    .help(state == .notAsked ? "Shows macOS's permission prompt." : "Opens the System Settings page where you can switch TESS on.")
                }
            }
        }
    }
}

// MARK: - About

private struct AboutPage: View {
    @ObservedObject private var ui = UIState.shared
    @ObservedObject private var updater = Updater.shared

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "TESSDisplayVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.9.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        if AppFlavor.current.isDev {
            return "Version \(short) (\(build)) · development build" + (AppFlavor.buildCommit.map { " from \($0)" } ?? "")
        }
        return "Version \(short) (\(build))"
    }

    var body: some View {
        HStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 4) {
                Text(AppFlavor.current.appName)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("Your voice assistant for macOS")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                Text(version)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiary)
            }
            Spacer()
            if AppFlavor.current.checksForUpdates {
                Button {
                    ui.settingsPane = .updates
                    Task { await updater.check(userInitiated: true) }
                } label: {
                    Label("Check for updates", systemImage: "arrow.down.circle")
                }
                .buttonStyle(ThemedButtonStyle())
            }
        }
        .padding(.top, 8)

        Card("Your data", footer: "Usage statistics and long-term memories are stored only on this Mac. API keys live in your keychain.") {
            SettingRow("folder", "Data folder", subtitle: "~/Library/Application Support/\(AppFlavor.current.supportFolderName)") {
                Button("Show in Finder") { NSWorkspace.shared.open(AppPaths.directory) }
                    .buttonStyle(ThemedButtonStyle())
            }
        }

        Card("Privacy") {
            SettingRow("waveform", "Speech stays on your Mac",
                       subtitle: "Your voice is transcribed on device. Only the text of your request goes to the AI you choose — or nowhere, with Ollama.") {
                EmptyView()
            }
        }
    }
}
