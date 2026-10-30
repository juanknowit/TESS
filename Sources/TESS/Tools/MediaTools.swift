import AppKit

/// Music playback via AppleScript for Apple Music and Spotify.
enum MediaTools {
    static func all(_ context: ToolContext) -> [Tool] {
        [mediaControl(context), playMusic(context)]
    }

    static func mediaControl(_ context: ToolContext) -> Tool {
        Tool(
            name: "media_control",
            description: "Control music playback: play, pause, toggle, next, previous, or ask what's playing.",
            properties: [
                "action": P.oneOf(["play", "pause", "toggle", "next", "previous", "now_playing"], "What to do"),
                "app": P.oneOf(["music", "spotify"], "Optional: which player. Omit to pick automatically."),
            ],
            required: ["action"]
        ) { args in
            let action = args.string("action") ?? "toggle"
            let app = await resolveApp(args.string("app"), preference: context.musicApp)
            if action == "now_playing" {
                guard await isRunning(app) else { return "\(app) isn't open, so nothing is playing." }
                let result = try await Shell.appleScript(nowPlayingScript(app))
                return result == "NOTHING" ? "Nothing is playing in \(app)." : "Now playing in \(app): \(result)."
            }
            let command: String
            switch action {
            case "play": command = "play"
            case "pause": command = "pause"
            case "next": command = "next track"
            case "previous": command = "previous track"
            default: command = "playpause"
            }
            try await Shell.appleScript("tell application \"\(app)\" to \(command)")
            if action == "next" || action == "previous" {
                try? await Task.sleep(nanoseconds: 700_000_000)
                if let now = try? await Shell.appleScript(nowPlayingScript(app)), now != "NOTHING" {
                    return "Skipped. Now playing: \(now)."
                }
            }
            return "Done (\(app): \(action))."
        }
    }

    static func playMusic(_ context: ToolContext) -> Tool {
        Tool(
            name: "play_music",
            description: "Play a song, artist, album or playlist by name. In Apple Music this searches the user's library and plays the best match.",
            properties: [
                "query": P.string("Song, artist, album or playlist"),
                "app": P.oneOf(["music", "spotify"], "Optional: which player. Omit to pick automatically."),
            ],
            required: ["query"]
        ) { args in
            guard let query = args.string("query") else { throw TESSError("Play what?") }
            let app = await resolveApp(args.string("app"), preference: context.musicApp)

            if app == "Spotify" {
                let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
                try await Shell.run("/usr/bin/open", ["spotify:search:\(encoded)"])
                return "Opened a Spotify search for \(query). Spotify doesn't let other apps start a search result directly, so the user may need to pick one."
            }

            let q = query.appleScriptEscaped
            let script = """
            tell application "Music"
                set found to (search library playlist 1 for "\(q)")
                if found is {} then
                    try
                        play playlist "\(q)"
                        return "playlist \(q)"
                    end try
                    return "NOT_FOUND"
                end if
                play item 1 of found
                delay 0.4
                return (name of current track) & " by " & (artist of current track)
            end tell
            """
            let result = try await Shell.appleScript(script)
            if result == "NOT_FOUND" {
                let term = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
                _ = try? await Shell.run("/usr/bin/open", ["music://music.apple.com/search?term=\(term)"])
                return "\(query) isn't in the user's Music library. I opened an Apple Music search for it instead."
            }
            return "Playing \(result)."
        }
    }

    // MARK: Helpers

    static func resolveApp(_ requested: String?, preference: MusicApp) async -> String {
        if let r = requested?.lowercased() {
            if r.contains("spot") { return "Spotify" }
            if r.contains("music") || r.contains("apple") { return "Music" }
        }
        switch preference {
        case .spotify: return "Spotify"
        case .music: return "Music"
        case .auto: break
        }
        return await isRunning("Spotify") ? "Spotify" : "Music"
    }

    static func isRunning(_ app: String) async -> Bool {
        let bundleID = app == "Spotify" ? "com.spotify.client" : "com.apple.Music"
        return await MainActor.run {
            NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
        }
    }

    static func nowPlayingScript(_ app: String) -> String {
        """
        tell application "\(app)"
            if player state is playing then
                return (name of current track) & " by " & (artist of current track)
            else
                return "NOTHING"
            end if
        end tell
        """
    }
}
