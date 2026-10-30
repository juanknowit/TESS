import Foundation

/// Runs the think → call tools → think loop and keeps short-term conversation memory.
@MainActor
final class Agent {
    private(set) var history: [ChatItem] = []
    private let maxItems = 40
    private let maxRounds = 8

    func reset() { history.removeAll() }

    /// Increases every time the user says something. Lets tools tell whether the user has replied
    /// since an earlier step (used to require confirmation before sending messages).
    static var currentTurn = 0

    private func stripImages() {
        history = history.map { item in
            if case .toolResult(let id, let name, let content, let image) = item, image != nil {
                return .toolResult(id: id, name: name, content: content + "\n[The image was shown earlier and is no longer attached.]", image: nil)
            }
            return item
        }
    }

    /// Number of things the user has said in the current conversation.
    var userTurns: Int {
        history.reduce(0) { count, item in
            if case .user = item { return count + 1 }
            return count
        }
    }

    func run(userText: String,
             provider: LLMProvider,
             system: String,
             tools: ToolRegistry,
             onToolUse: (String) -> Void) async throws -> String {
        repair()
        Agent.currentTurn += 1
        history.append(.user(userText))
        trim()
        // Images are only useful for the turn they were captured in; drop them afterwards to save tokens.
        defer { stripImages() }

        var lastText = ""
        for _ in 0..<maxRounds {
            try Task.checkCancellation()
            let reply = try await provider.complete(system: system, history: history, tools: tools.specs)
            UsageStore.shared.recordRequest(provider: provider.name,
                                            model: provider.model,
                                            input: reply.inputTokens,
                                            output: reply.outputTokens,
                                            webSearches: reply.webSearches)
            try Task.checkCancellation()

            history.append(.assistant(text: reply.text, toolCalls: reply.toolCalls, raw: reply.raw))
            if !reply.text.trimmed.isEmpty { lastText = reply.text }

            if reply.toolCalls.isEmpty {
                if reply.needsContinuation { continue }
                return reply.text.trimmed.isEmpty ? lastText : reply.text
            }

            for call in reply.toolCalls {
                onToolUse(call.name)
                UsageStore.shared.recordTool(call.name)
                let output = await tools.execute(call)
                history.append(.toolResult(id: call.id, name: call.name,
                                           content: String(output.text.prefix(output.limit)), image: output.image))
            }
        }
        return lastText.isEmpty ? "Sorry, that took more steps than I can manage in one go." : lastText
    }

    /// Drops the oldest turns, always leaving history starting at a user message.
    private func trim() {
        while history.count > maxItems { history.removeFirst() }
        while let first = history.first {
            if case .user = first { break }
            history.removeFirst()
        }
    }

    /// If a previous run was interrupted between a tool call and its result, cut the dangling turn.
    private func repair() {
        var i = 0
        while i < history.count {
            if case .assistant(_, let calls, _) = history[i], !calls.isEmpty {
                let expected = Set(calls.map(\.id))
                var found = Set<String>()
                var j = i + 1
                while j < history.count, case .toolResult(let id, _, _, _) = history[j] {
                    found.insert(id)
                    j += 1
                }
                if found != expected {
                    history.removeSubrange(i..<history.count)
                    return
                }
                i = j
            } else {
                i += 1
            }
        }
    }
}
