import AppKit

/// "Protocols": named routines of steps, run by voice ("Hey Tess, run work mode").
struct RoutineStep: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case openApp, quitApp, volume, appearance, playMusic, openURL, shortcut, say, wait
        var id: String { rawValue }

        var title: String {
            switch self {
            case .openApp: return "Open app"
            case .quitApp: return "Quit app"
            case .volume: return "Set volume"
            case .appearance: return "Appearance"
            case .playMusic: return "Play music"
            case .openURL: return "Open link or file"
            case .shortcut: return "Run Shortcut"
            case .say: return "Say"
            case .wait: return "Wait"
            }
        }

        var icon: String {
            switch self {
            case .openApp: return "arrow.up.forward.app"
            case .quitApp: return "xmark.app"
            case .volume: return "speaker.wave.2"
            case .appearance: return "circle.lefthalf.filled"
            case .playMusic: return "music.note"
            case .openURL: return "link"
            case .shortcut: return "square.stack.3d.up"
            case .say: return "text.bubble"
            case .wait: return "hourglass"
            }
        }

        var placeholder: String {
            switch self {
            case .openApp, .quitApp: return "App name, e.g. Slack"
            case .volume: return "0–100"
            case .appearance: return "dark or light"
            case .playMusic: return "Song, artist or playlist"
            case .openURL: return "https://… or ~/Documents/…"
            case .shortcut: return "Shortcut name, e.g. Do Not Disturb On"
            case .say: return "What TESS says"
            case .wait: return "Seconds, e.g. 2"
            }
        }
    }

    var id: UUID
    var kind: Kind
    var value: String

    init(_ kind: Kind, _ value: String) {
        id = UUID()
        self.kind = kind
        self.value = value
    }
}

struct Routine: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var steps: [RoutineStep]

    init(name: String, steps: [RoutineStep]) {
        id = UUID()
        self.name = name
        self.steps = steps
    }
}

@MainActor
final class RoutineStore: ObservableObject {
    static let shared = RoutineStore()

    @Published var routines: [Routine] { didSet { save() } }
    private let url: URL

    private init() {
        url = AppPaths.directory.appendingPathComponent("protocols.json")
        if let raw = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([Routine].self, from: raw) {
            routines = decoded
        } else {
            routines = Self.examples
        }
    }

    static let examples: [Routine] = [
        Routine(name: "Work mode", steps: [
            RoutineStep(.openApp, "Calendar"),
            RoutineStep(.openApp, "Notes"),
            RoutineStep(.volume, "30"),
            RoutineStep(.say, "Work mode engaged. Have a productive session."),
        ]),
        Routine(name: "Wind down", steps: [
            RoutineStep(.quitApp, "Calendar"),
            RoutineStep(.appearance, "dark"),
            RoutineStep(.volume, "25"),
            RoutineStep(.playMusic, "chill"),
            RoutineStep(.say, "Winding down. Enjoy your evening."),
        ]),
    ]

    func add() -> Routine {
        let routine = Routine(name: "New protocol", steps: [RoutineStep(.say, "Protocol complete.")])
        routines.append(routine)
        return routine
    }

    func delete(_ id: UUID) { routines.removeAll { $0.id == id } }

    /// Best match for a spoken name: exact, then contains, ignoring the words "protocol" and "mode".
    func find(_ spoken: String) -> Routine? {
        func clean(_ s: String) -> String {
            s.lowercased()
                .replacingOccurrences(of: "protocol", with: "")
                .replacingOccurrences(of: "routine", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        }
        let q = clean(spoken)
        guard !q.isEmpty else { return nil }
        return routines.first { clean($0.name) == q }
            ?? routines.first { clean($0.name).contains(q) || q.contains(clean($0.name)) }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(routines) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

enum RoutineRunner {
    struct Result {
        let done: [String]
        let failed: [String]
        let sayings: [String]

        /// Report for the AI to turn into a spoken reply.
        func report(for routine: Routine) -> String {
            var text = "Ran the “\(routine.name)” protocol."
            if !done.isEmpty { text += " Done: " + done.joined(separator: "; ") + "." }
            if !failed.isEmpty { text += " Problems: " + failed.joined(separator: "; ") + "." }
            if !sayings.isEmpty { text += "\nSay this to the user (you may phrase it naturally): " + sayings.joined(separator: " ") }
            else { text += "\nConfirm briefly that the protocol ran." }
            return text
        }

        /// What TESS says when a protocol is run straight from Settings.
        func spoken(for routine: Routine) -> String {
            var parts = sayings
            if !failed.isEmpty { parts.append("\(failed.count) step\(failed.count == 1 ? "" : "s") didn't work.") }
            return parts.isEmpty ? "\(routine.name) is done." : parts.joined(separator: " ")
        }
    }

    /// Runs every step in order.
    static func run(_ routine: Routine, context: ToolContext) async -> Result {
        var done: [String] = []
        var failed: [String] = []
        var sayings: [String] = []

        for step in routine.steps {
            let value = step.value.trimmed
            do {
                switch step.kind {
                case .openApp:
                    _ = try await SystemTools.openApp.text(["name": value])
                case .quitApp:
                    _ = try await SystemTools.quitApp.text(["name": value])
                case .volume:
                    _ = try await SystemTools.setVolume.text(["level": Int(value) ?? 50])
                case .appearance:
                    _ = try await SystemTools.setAppearance.text(["mode": value.lowercased().contains("light") ? "light" : "dark"])
                case .playMusic:
                    _ = try await MediaTools.playMusic(context).text(["query": value])
                case .openURL:
                    _ = try await SystemTools.openPathOrURL.text(["target": value])
                case .shortcut:
                    try await Shell.run("/usr/bin/shortcuts", ["run", value])
                case .say:
                    if !value.isEmpty { sayings.append(value) }
                    continue
                case .wait:
                    let seconds = min(30, max(0, Double(value) ?? 1))
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    continue
                }
                done.append("\(step.kind.title) \(value)".trimmed)
            } catch {
                failed.append("\(step.kind.title) \(value): \(error.localizedDescription)")
            }
        }
        return Result(done: done, failed: failed, sayings: sayings)
    }
}

enum RoutineTools {
    static func all(_ context: ToolContext) -> [Tool] { [runProtocol(context), listProtocols] }

    static func runProtocol(_ context: ToolContext) -> Tool {
        Tool(
            name: "run_protocol",
            description: "Run one of the user's protocols (named routines set up in TESS settings), e.g. 'work mode', 'wind down'. Use when the user says 'run …', 'start …', '… protocol' or '… mode'.",
            properties: ["name": P.string("The protocol's name as the user said it")],
            required: ["name"]
        ) { args in
            guard let name = args.string("name") else { throw TESSError("Which protocol?") }
            guard let routine = await RoutineStore.shared.find(name) else {
                let names = await RoutineStore.shared.routines.map(\.name)
                return "There's no protocol called \(name). Available: \(names.isEmpty ? "none yet" : names.joined(separator: ", ")). New ones are made in TESS settings › Protocols."
            }
            return await RoutineRunner.run(routine, context: context).report(for: routine)
        }
    }

    static let listProtocols = Tool(
        name: "list_protocols",
        description: "List the user's protocols and what each one does."
    ) { _ in
        let routines = await RoutineStore.shared.routines
        guard !routines.isEmpty else { return "No protocols yet. They're made in TESS settings › Protocols." }
        return routines.map { r in
            "- \(r.name): " + r.steps.map { "\($0.kind.title.lowercased()) \($0.value)".trimmed }.joined(separator: ", ")
        }.joined(separator: "\n")
    }
}
