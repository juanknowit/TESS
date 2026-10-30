import Foundation

/// What a tool hands back to the model: text, optionally an image, and how much text to keep.
struct ToolOutput {
    var text: String
    var image: Data? = nil
    var limit: Int = 6000
}

/// A capability the model can call: a JSON-schema description plus the Swift code that runs it.
struct Tool {
    let spec: ToolSpec
    let execute: (JSONObject) async throws -> ToolOutput

    init(name: String,
         description: String,
         properties: [String: JSONObject] = [:],
         required: [String] = [],
         run: @escaping (JSONObject) async throws -> String) {
        spec = Self.makeSpec(name, description, properties, required)
        execute = { args in ToolOutput(text: try await run(args)) }
    }

    private init(spec: ToolSpec, execute: @escaping (JSONObject) async throws -> ToolOutput) {
        self.spec = spec
        self.execute = execute
    }

    /// A tool that can return images or long text.
    static func rich(name: String,
                     description: String,
                     properties: [String: JSONObject] = [:],
                     required: [String] = [],
                     run: @escaping (JSONObject) async throws -> ToolOutput) -> Tool {
        Tool(spec: makeSpec(name, description, properties, required), execute: run)
    }

    private static func makeSpec(_ name: String, _ description: String,
                                 _ properties: [String: JSONObject], _ required: [String]) -> ToolSpec {
        ToolSpec(name: name,
                 description: description,
                 parameters: ["type": "object", "properties": properties, "required": required])
    }

    /// Runs the tool and returns only its text (for composing tools like the briefing).
    func text(_ args: JSONObject = [:]) async throws -> String {
        try await execute(args).text
    }
}

/// JSON-schema property shorthands.
enum P {
    static func string(_ description: String) -> JSONObject { ["type": "string", "description": description] }
    static func integer(_ description: String) -> JSONObject { ["type": "integer", "description": description] }
    static func boolean(_ description: String) -> JSONObject { ["type": "boolean", "description": description] }
    static func oneOf(_ values: [String], _ description: String) -> JSONObject {
        ["type": "string", "enum": values, "description": description]
    }
}

final class ToolRegistry {
    private var order: [String] = []
    private var tools: [String: Tool] = [:]

    func add(_ list: [Tool]) {
        for tool in list {
            if tools[tool.spec.name] == nil { order.append(tool.spec.name) }
            tools[tool.spec.name] = tool
        }
    }

    var specs: [ToolSpec] { order.compactMap { tools[$0]?.spec } }

    func execute(_ call: ToolCall) async -> ToolOutput {
        guard let tool = tools[call.name] else { return ToolOutput(text: "Error: there is no tool called \(call.name).") }
        do {
            return try await tool.execute(call.arguments)
        } catch {
            return ToolOutput(text: "Error: \(error.localizedDescription)")
        }
    }

    static func standard(context: ToolContext) -> ToolRegistry {
        let registry = ToolRegistry()
        registry.add(SystemTools.all())
        registry.add(InfoTools.all(context))
        registry.add(CalendarTools.all())
        registry.add(MediaTools.all(context))
        if context.memoryEnabled { registry.add(MemoryTools.all()) }
        registry.add(BriefingTools.all(context))
        registry.add(ScreenTools.all())
        registry.add(DocumentTools.all())
        registry.add(TypingTools.all())
        registry.add(CommsTools.all())
        registry.add(MailTools.all())
        registry.add(RoutineTools.all(context))
        registry.add(WebPageTools.all())
        registry.add(MarketTools.all())
        registry.add(SportsTools.all())
        return registry
    }

    /// What the HUD shows while a tool runs.
    static func statusText(for tool: String) -> String {
        switch tool {
        case "get_weather": return "Checking the weather…"
        case "get_news": return "Scanning the headlines…"
        case "web_search": return "Searching the web…"
        case "get_calendar_events", "create_calendar_event": return "Checking your calendar…"
        case "get_reminders", "create_reminder", "complete_reminder": return "Checking your reminders…"
        case "media_control", "play_music": return "Cueing the music…"
        case "open_app", "quit_app", "open_path_or_url": return "On it…"
        case "search_files": return "Searching your files…"
        case "take_screenshot": return "Capturing the screen…"
        case "remember", "forget", "list_memories": return "Updating memory…"
        case "get_briefing": return "Preparing your briefing…"
        case "look_at_screen": return "Looking at your screen…"
        case "find_documents": return "Looking for your files…"
        case "read_document": return "Reading the document…"
        case "type_text": return "Typing…"
        case "draft_message": return "Drafting your message…"
        case "send_message": return "Sending…"
        case "create_note", "append_to_note": return "Updating Notes…"
        case "search_notes", "read_note": return "Checking your notes…"
        case "check_mail", "read_email": return "Checking your mail…"
        case "draft_email": return "Drafting your email…"
        case "send_email": return "Sending…"
        case "run_protocol": return "Running protocol…"
        case "list_protocols": return "Checking your protocols…"
        case "read_web_page": return "Reading the page…"
        case "convert_currency": return "Checking exchange rates…"
        case "stock_quote": return "Checking the markets…"
        case "sports_results": return "Checking the scores…"
        default: return "Working on it…"
        }
    }
}

// MARK: - Shell

enum Shell {
    /// Runs a process off the main thread and returns trimmed stdout, throwing stderr on failure.
    @discardableResult
    static func run(_ path: String, _ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(data: outData, encoding: .utf8)?.trimmed ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    let message = String(data: errData, encoding: .utf8)?.trimmed ?? ""
                    continuation.resume(throwing: TESSError(message.isEmpty ? "Command failed (\(process.terminationStatus))." : message))
                }
            }
        }
    }

    @discardableResult
    static func appleScript(_ source: String) async throws -> String {
        try await run("/usr/bin/osascript", ["-e", source])
    }
}
