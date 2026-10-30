import Foundation

/// Claude via the Anthropic Messages API, with optional server-side web search.
struct AnthropicProvider: LLMProvider {
    let name = "Claude"
    let apiKey: String
    let model: String
    let webSearch: Bool

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func complete(system: String, history: [ChatItem], tools: [ToolSpec]) async throws -> LLMReply {
        var toolDefs: [JSONObject] = tools.map {
            ["name": $0.name, "description": $0.description, "input_schema": $0.parameters]
        }
        if webSearch {
            toolDefs.append(["type": "web_search_20250305", "name": "web_search", "max_uses": 3])
        }

        var body: JSONObject = [
            "model": model,
            "max_tokens": 1024,
            "system": system,
            "messages": Self.messages(from: history),
        ]
        if !toolDefs.isEmpty { body["tools"] = toolDefs }

        let response = try await HTTP.postJSON(Self.endpoint,
                                               headers: ["x-api-key": apiKey, "anthropic-version": "2023-06-01"],
                                               body: body)

        return Self.parse(response)
    }

    /// Turns a Messages API response into an `LLMReply`.
    static func parse(_ response: JSONObject) -> LLMReply {
        let content = response["content"] as? [JSONObject] ?? []
        var text = ""
        var calls: [ToolCall] = []
        for block in content {
            switch block["type"] as? String {
            case "text":
                text += block["text"] as? String ?? ""
            case "tool_use":
                calls.append(ToolCall(id: block["id"] as? String ?? UUID().uuidString,
                                      name: block["name"] as? String ?? "",
                                      arguments: block["input"] as? JSONObject ?? [:]))
            default:
                break // server_tool_use, web_search_tool_result, etc. are kept in `raw`
            }
        }
        let usage = response["usage"] as? JSONObject ?? [:]
        let serverTools = usage["server_tool_use"] as? JSONObject ?? [:]
        return LLMReply(text: text,
                        toolCalls: calls,
                        raw: content,
                        needsContinuation: (response["stop_reason"] as? String) == "pause_turn",
                        inputTokens: (usage.int("input_tokens") ?? 0)
                            + (usage.int("cache_read_input_tokens") ?? 0)
                            + (usage.int("cache_creation_input_tokens") ?? 0),
                        outputTokens: usage.int("output_tokens") ?? 0,
                        webSearches: serverTools.int("web_search_requests") ?? 0)
    }

    /// Converts history to Anthropic messages, merging consecutive same-role turns.
    static func messages(from history: [ChatItem]) -> [JSONObject] {
        var messages: [JSONObject] = []

        func append(_ role: String, _ blocks: [JSONObject]) {
            guard !blocks.isEmpty else { return }
            if let last = messages.last, last["role"] as? String == role, var existing = last["content"] as? [JSONObject] {
                existing.append(contentsOf: blocks)
                messages[messages.count - 1]["content"] = existing
            } else {
                messages.append(["role": role, "content": blocks])
            }
        }

        for item in history {
            switch item {
            case .user(let text):
                append("user", [["type": "text", "text": text]])
            case .assistant(let text, let calls, let raw):
                if let raw, !raw.isEmpty {
                    append("assistant", raw)
                } else {
                    var blocks: [JSONObject] = []
                    if !text.isEmpty { blocks.append(["type": "text", "text": text]) }
                    for call in calls {
                        blocks.append(["type": "tool_use", "id": call.id, "name": call.name, "input": call.arguments])
                    }
                    if blocks.isEmpty { blocks.append(["type": "text", "text": "…"]) }
                    append("assistant", blocks)
                }
            case .toolResult(let id, _, let content, let image):
                if let image {
                    let blocks: [JSONObject] = [
                        ["type": "text", "text": content],
                        ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg",
                                                     "data": image.base64EncodedString()]],
                    ]
                    append("user", [["type": "tool_result", "tool_use_id": id, "content": blocks]])
                } else {
                    append("user", [["type": "tool_result", "tool_use_id": id, "content": content]])
                }
            }
        }
        return messages
    }
}
