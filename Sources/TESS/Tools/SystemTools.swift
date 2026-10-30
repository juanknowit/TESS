import AppKit

/// Controlling the Mac itself: apps, volume, appearance, files, screen, timers.
enum SystemTools {
    static func all() -> [Tool] {
        [openApp, quitApp, setVolume, systemStatus, setAppearance, lockScreen, searchFiles, openPathOrURL, screenshot, setTimer]
    }

    static let openApp = Tool(
        name: "open_app",
        description: "Launch a Mac application or bring it to the front, by name (e.g. Safari, Notes, Spotify, Xcode).",
        properties: ["name": P.string("The application's name")],
        required: ["name"]
    ) { args in
        guard let name = args.string("name") else { throw TESSError("Which app?") }
        do {
            try await Shell.run("/usr/bin/open", ["-a", name])
        } catch {
            throw TESSError("I couldn't find an app called \(name).")
        }
        return "Opened \(name)."
    }

    static let quitApp = Tool(
        name: "quit_app",
        description: "Quit a running application by name.",
        properties: ["name": P.string("The application's name")],
        required: ["name"]
    ) { args in
        guard let name = args.string("name")?.lowercased() else { throw TESSError("Which app?") }
        let quit: [String] = await MainActor.run {
            let mine = Bundle.main.bundleIdentifier
            let matches = NSWorkspace.shared.runningApplications.filter { app in
                guard app.activationPolicy == .regular, app.bundleIdentifier != mine,
                      let appName = app.localizedName?.lowercased() else { return false }
                return appName == name || appName.contains(name)
            }
            matches.forEach { $0.terminate() }
            return matches.compactMap(\.localizedName)
        }
        return quit.isEmpty ? "No running app matches \(name)." : "Quit \(quit.joined(separator: ", "))."
    }

    static let setVolume = Tool(
        name: "set_volume",
        description: "Get or change the Mac's output volume. Give a level, a relative change, or muted. With no arguments, reports the volume.",
        properties: [
            "level": P.integer("Absolute volume 0-100"),
            "change": P.oneOf(["up", "down"], "Nudge the volume up or down"),
            "muted": P.boolean("true to mute, false to unmute"),
        ]
    ) { args in
        if let muted = args.bool("muted") {
            try await Shell.appleScript(muted ? "set volume with output muted" : "set volume without output muted")
            if args.int("level") == nil && args.string("change") == nil { return muted ? "Muted." : "Unmuted." }
        }
        let currentText = try await Shell.appleScript("output volume of (get volume settings)")
        let current = Int(currentText) ?? 50
        var target = args.int("level")
        if let change = args.string("change") { target = current + (change == "up" ? 15 : -15) }
        guard let level = target.map({ max(0, min(100, $0)) }) else { return "Volume is at \(current) percent." }
        try await Shell.appleScript("set volume output volume \(level)\nset volume without output muted")
        return "Volume set to \(level) percent."
    }

    static let systemStatus = Tool(
        name: "get_system_status",
        description: "Battery level and charging state, free disk space, and uptime."
    ) { _ in
        var parts: [String] = []
        if let batt = try? await Shell.run("/usr/bin/pmset", ["-g", "batt"]),
           let line = batt.split(separator: "\n").first(where: { $0.contains("%") }) {
            let fields = line.split(separator: "\t").last.map(String.init) ?? String(line)
            parts.append("Battery: " + fields.components(separatedBy: " present").first!.trimmed)
        } else {
            parts.append("No battery (desktop Mac).")
        }
        let home = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let free = values.volumeAvailableCapacityForImportantUsage {
            parts.append("Free disk space: " + ByteCountFormatter.string(fromByteCount: free, countStyle: .file))
        }
        let uptime = Int(ProcessInfo.processInfo.systemUptime)
        parts.append("Uptime: \(uptime / 86400) days \((uptime % 86400) / 3600) hours")
        return parts.joined(separator: "\n")
    }

    static let setAppearance = Tool(
        name: "set_appearance",
        description: "Switch macOS between dark mode and light mode.",
        properties: ["mode": P.oneOf(["dark", "light", "toggle"], "Which appearance")],
        required: ["mode"]
    ) { args in
        let mode = args.string("mode") ?? "toggle"
        let value = mode == "dark" ? "true" : mode == "light" ? "false" : "not dark mode"
        try await Shell.appleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to \(value)")
        return mode == "toggle" ? "Appearance toggled." : "Switched to \(mode) mode."
    }

    static let lockScreen = Tool(
        name: "lock_screen",
        description: "Lock the Mac's screen."
    ) { _ in
        do {
            try await Shell.appleScript("tell application \"System Events\" to keystroke \"q\" using {control down, command down}")
            return "Screen locked."
        } catch {
            try await Shell.run("/usr/bin/pmset", ["displaysleepnow"])
            return "Display is asleep. It locks if a password is required on wake. For a true lock, grant TESS Accessibility access."
        }
    }

    static let searchFiles = Tool(
        name: "search_files",
        description: "Find files in the user's home folder whose names match a query (Spotlight). Returns up to 8 paths.",
        properties: ["query": P.string("Part of the file name")],
        required: ["query"]
    ) { args in
        guard let query = args.string("query") else { throw TESSError("What should I look for?") }
        let output = try await Shell.run("/usr/bin/mdfind", ["-onlyin", NSHomeDirectory(), "-name", query])
        let home = NSHomeDirectory()
        let paths = output.split(separator: "\n").prefix(8).map { $0.replacingOccurrences(of: home, with: "~") }
        return paths.isEmpty ? "No files named like \(query)." : paths.joined(separator: "\n")
    }

    static let openPathOrURL = Tool(
        name: "open_path_or_url",
        description: "Open a file, folder or web address with its default app (e.g. a path from search_files, or https://…).",
        properties: ["target": P.string("A path like ~/Documents/report.pdf or a full URL")],
        required: ["target"]
    ) { args in
        guard var target = args.string("target") else { throw TESSError("Open what?") }
        if target.hasPrefix("~") { target = (target as NSString).expandingTildeInPath }
        try await Shell.run("/usr/bin/open", [target])
        return "Opened it."
    }

    static let screenshot = Tool(
        name: "take_screenshot",
        description: "Save a screenshot of the whole screen to the Desktop."
    ) { _ in
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let path = NSHomeDirectory() + "/Desktop/TESS Screenshot \(f.string(from: Date())).png"
        try await Shell.run("/usr/sbin/screencapture", ["-x", path])
        return "Screenshot saved to the Desktop."
    }

    static let setTimer = Tool(
        name: "set_timer",
        description: "Start a countdown timer. TESS announces it aloud when it finishes.",
        properties: [
            "seconds": P.integer("Duration in seconds"),
            "label": P.string("Optional label, e.g. 'pasta'"),
        ],
        required: ["seconds"]
    ) { args in
        guard let seconds = args.int("seconds"), seconds > 0 else { throw TESSError("The timer needs a positive duration.") }
        let label = args.string("label")
        await MainActor.run { TimerCenter.shared.add(seconds: seconds, label: label) }
        return "Timer set for \(SpeechText.duration(seconds))" + (label.map { " (\($0))" } ?? "") + "."
    }
}

/// Keeps countdown timers alive and tells the assistant when one fires.
@MainActor
final class TimerCenter {
    static let shared = TimerCenter()
    var onFire: ((String?) -> Void)?
    private var timers: [UUID: Timer] = [:]

    func add(seconds: Int, label: String?) {
        let id = UUID()
        timers[id] = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { _ in
            Task { @MainActor in
                TimerCenter.shared.timers[id] = nil
                TimerCenter.shared.onFire?(label)
            }
        }
    }
}
