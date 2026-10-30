import SwiftUI

/// One thing TESS can do, with example phrases.
struct SkillInfo: Identifiable {
    let icon: String
    let title: String
    let summary: String
    let examples: [String]
    /// A harmless example the user can try with one click (read-only, no side effects).
    var tryIt: String? = nil
    var needs: [String] = []
    var tip: String? = nil
    var tint: Color = Theme.accent
    var id: String { title }

    func matches(_ query: String) -> Bool {
        let q = query.trimmed.lowercased()
        guard !q.isEmpty else { return true }
        return ([title, summary, tip ?? ""] + examples + needs).joined(separator: " ").lowercased().contains(q)
    }

    static let all: [SkillInfo] = [
        SkillInfo(icon: "sparkles", title: "Conversation",
                  summary: "Ask anything. Keep talking after she answers — no need to say her name again for a few seconds.",
                  examples: ["Explain how a heat pump works", "What can I cook with salmon and leeks?", "Hey Tess, stop"],
                  tryIt: "In one sentence, what can you help me with?"),
        SkillInfo(icon: "desktopcomputer", title: "Your Mac",
                  summary: "Open and quit apps, volume, dark mode, screen lock, screenshots, finding files and battery status.",
                  examples: ["Open Safari", "Set the volume to 30", "Switch to dark mode", "Find my tax return PDF", "How's my battery?"],
                  tryIt: "How's my battery?", needs: ["Automation", "Accessibility for screen lock"]),
        SkillInfo(icon: "timer", title: "Timers",
                  summary: "Countdown timers she announces out loud when they finish.",
                  examples: ["Set a ten minute timer for the pasta", "Timer for 30 seconds"]),
        SkillInfo(icon: "cloud.sun", title: "Weather",
                  summary: "Current conditions and forecasts — for your home city by default, or anywhere else.",
                  examples: ["What's the weather tomorrow?", "Will it rain in Bergen this weekend?"],
                  tryIt: "What's the weather like today?", tint: Theme.cyan),
        SkillInfo(icon: "newspaper", title: "News",
                  summary: "Local and national headlines for your home city, world news, or news on any topic.",
                  examples: ["What's the news?", "Any world news?", "News about electricity prices"],
                  tryIt: "What's the news?", tint: Theme.cyan),
        SkillInfo(icon: "globe", title: "Web search",
                  summary: "Looks things up online for current answers.",
                  examples: ["Who won the Nobel Prize in literature this year?", "When does the Apple store in Oslo open?"],
                  tint: Theme.cyan),
        SkillInfo(icon: "calendar", title: "Calendar & reminders",
                  summary: "Reads your schedule, adds events, and creates and completes reminders.",
                  examples: ["What's on my calendar today?", "Add lunch with Maria tomorrow at one", "Remind me to call the bank Friday at nine"],
                  tryIt: "What's on my calendar today?", needs: ["Calendars", "Reminders"], tint: Theme.green),
        SkillInfo(icon: "sunrise", title: "Morning briefing",
                  summary: "Weather, today's calendar, reminders and headlines in one short rundown — also automatically the first time you unlock your Mac each morning.",
                  examples: ["Good morning", "Brief me"],
                  tryIt: "Give me my morning briefing", tint: Theme.orange),
        SkillInfo(icon: "music.note", title: "Music",
                  summary: "Plays from your Apple Music library and controls Apple Music or Spotify.",
                  examples: ["Play some Daft Punk", "Pause", "Next track", "What's playing?"],
                  needs: ["Automation"], tint: Theme.claude),
        SkillInfo(icon: "rectangle.dashed.badge.record", title: "What am I looking at?",
                  summary: "Looks at the front window or your whole screen and explains, summarises or reads it.",
                  examples: ["What am I looking at?", "What does this error mean?", "Summarise what's on my screen"],
                  tryIt: "What am I looking at?", needs: ["Screen Recording"],
                  tip: "With Ollama, pick a model that can see images (e.g. qwen2.5vl)."),
        SkillInfo(icon: "doc.text.magnifyingglass", title: "Documents",
                  summary: "Finds and reads PDFs, Word, RTF, text and images — including the document you have open.",
                  examples: ["Summarise the PDF I just downloaded", "What's the total on this invoice?", "Read me the open document"],
                  needs: ["Files and Folders"]),
        SkillInfo(icon: "safari", title: "Web pages",
                  summary: "Reads the page open in Safari, Chrome, Edge, Arc or Brave so she can summarise it or answer questions about it.",
                  examples: ["Summarise this page", "What does this article say about prices?", "Give me the key points of this tab"],
                  tryIt: "Summarise the web page I have open", needs: ["Automation"],
                  tip: "For pages behind a login, turn on “Allow JavaScript from Apple Events” in your browser (Safari: Settings › Advanced › Show features for web developers, then Develop menu; Chrome/Edge: View › Developer)."),
        SkillInfo(icon: "keyboard", title: "Type for me",
                  summary: "Writes text wherever your cursor is. She never presses Return or sends anything.",
                  examples: ["Write a reply saying I'll be ten minutes late", "Type a polite no-thanks"],
                  needs: ["Accessibility"]),
        SkillInfo(icon: "message", title: "Messages",
                  summary: "Texts your contacts. She always reads the message back and only sends after you say yes.",
                  examples: ["Text Maria I'm running late", "Message Ola: see you at seven"],
                  needs: ["Contacts", "Automation"], tint: Theme.green),
        SkillInfo(icon: "envelope", title: "Mail",
                  summary: "Checks, searches and reads Apple Mail, and drafts emails and replies — always read back for your OK before sending.",
                  examples: ["Any new emails?", "Do I have anything from Maria this week?", "Read me the latest one", "Reply saying thanks, I'll look at it tomorrow"],
                  tryIt: "Do I have any unread emails?", needs: ["Automation (Mail)", "Contacts"], tint: Theme.openAI),
        SkillInfo(icon: "note.text", title: "Notes",
                  summary: "Creates, searches, reads and adds to Apple Notes.",
                  examples: ["Make a note: call the plumber Monday", "Add oat milk to my shopping list note", "What's in my packing note?"],
                  needs: ["Automation"], tint: Theme.orange),
        SkillInfo(icon: "bolt.circle", title: "Protocols",
                  summary: "Your own routines — open apps, set the volume, dark mode, music, Shortcuts and more in one go. Build them under Protocols.",
                  examples: ["Run work mode", "Start wind down", "What protocols do I have?"],
                  tryIt: "What protocols do I have?", tint: Theme.orange),
        SkillInfo(icon: "chart.line.uptrend.xyaxis", title: "Money & markets",
                  summary: "Live exchange rates and prices for stocks, funds, indices and crypto — including Oslo Børs.",
                  examples: ["What's 200 dollars in kroner?", "How is Equinor stock doing?", "What's Bitcoin at?"],
                  tryIt: "What's 100 euros in kroner?", tip: "Exchange rates by Exchange Rate API (exchangerate-api.com). Quotes from Yahoo Finance.",
                  tint: Theme.green),
        SkillInfo(icon: "sportscourt", title: "Sports",
                  summary: "Results, live scores and fixtures for Eliteserien, Premier League, La Liga, Bundesliga, Serie A, Ligue 1, Champions League, NBA, NFL, NHL, MLB and more.",
                  examples: ["Did Vålerenga win?", "Premier League scores", "When do the Lakers play next?"],
                  tryIt: "What are the latest Premier League scores?", tint: Theme.green),
        SkillInfo(icon: "bookmark", title: "Memory",
                  summary: "Remembers lasting facts about you. See and edit them under Memory.",
                  examples: ["Remember that I take my coffee black", "What do you remember about me?", "Forget my coffee order"],
                  tryIt: "What do you remember about me?"),
        SkillInfo(icon: "clock.arrow.circlepath", title: "History",
                  summary: "Every question and answer is kept on this Mac so you can look back. See it under History or in the menu bar."),
    ]
}

extension SkillInfo {
    init(icon: String, title: String, summary: String) {
        self.init(icon: icon, title: title, summary: summary, examples: [])
    }
}

struct SkillsPage: View {
    @EnvironmentObject var assistant: Assistant
    @ObservedObject private var ui = UIState.shared

    private var skills: [SkillInfo] { SkillInfo.all.filter { $0.matches(ui.skillsSearch) } }

    var body: some View {
        PageHeader("Skills", "Everything TESS can do. Just talk naturally — these are examples, not exact commands.")

        HStack(spacing: 14) {
            IconBadge(icon: "waveform", tint: Theme.cyan, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("Say “Hey Tess”, then your request")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Or type it in the menu bar panel. Press ▶ next to an example to try it now.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                TextField("Find a skill", text: $ui.skillsSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text)
                    .frame(width: 140)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.field))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.strokeStrong, lineWidth: 1))
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(colors: [Theme.card, Color(hex: 0x14243A)], startPoint: .leading, endPoint: .trailing)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))

        if skills.isEmpty {
            Text("No skill matches “\(ui.skillsSearch)”.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
        } else {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(skills) { skill in
                    SkillCard(skill: skill) { phrase in
                        assistant.submitTyped(phrase)
                    } openProtocols: {
                        ui.settingsPane = .routines
                    }
                }
            }
        }
    }
}

private struct SkillCard: View {
    let skill: SkillInfo
    let tryPhrase: (String) -> Void
    let openProtocols: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(icon: skill.icon, tint: skill.tint, size: 34)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(skill.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    if let phrase = skill.tryIt {
                        Button { tryPhrase(phrase) } label: {
                            Label("Try", systemImage: "play.fill")
                        }
                        .buttonStyle(ThemedButtonStyle())
                        .help("Ask TESS: “\(phrase)”")
                    }
                    if skill.title == "Protocols" {
                        Button("Edit", action: openProtocols)
                            .buttonStyle(ThemedButtonStyle())
                    }
                }
                Text(skill.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !skill.examples.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(skill.examples, id: \.self) { example in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "quote.opening")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(skill.tint.opacity(0.8))
                                    .padding(.top, 4)
                                Text(example)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Theme.text)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.field.opacity(0.7)))
                }

                if let tip = skill.tip {
                    Label(tip, systemImage: "lightbulb")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !skill.needs.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(skill.needs, id: \.self) { need in
                            Text(need)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Theme.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.07)))
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}
