import Foundation

/// OpenAI Chat Completions. Also used for Ollama, which serves the same API at http://localhost:11434/v1.
struct OpenAICompatibleProvider: LLMProvider {
    let name: String
    let baseURL: URL
    let apiKey: String?
    let model: String

    func complete(system: String, history: [ChatItem], tools: [ToolSpec]) async throws -> LLMReply {
        var headers: [String: String] = [:]
        if let apiKey, !apiKey.isEmpty { headers["Authorization"] = "Bearer \(apiKey)" }
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        let timeout: TimeInterval = name == "Ollama" ? 180 : 90

        var includeTools = !tools.isEmpty
        var includeImages = true
        var response: JSONObject = [:]
        // Retry once per capability a local model may lack (tool calling, image input).
        for attempt in 0..<3 {
            let body = makeBody(system: system, history: history, tools: includeTools ? tools : [], includeImages: includeImages)
            do {
                response = try await HTTP.postJSON(endpoint, headers: headers, body: body, timeout: timeout)
                break
            } catch let error as APIError where attempt < 2 {
                let detail = error.detail.lowercased()
                if includeTools && detail.contains("support tools") {
                    includeTools = false // answer as plain conversation instead
                } else if includeImages && Self.hasImages(history)
                            && (detail.contains("image") || detail.contains("vision") || detail.contains("multimodal")) {
                    includeImages = false // this model can't see images
                } else {
                    throw error
                }
            }
        }

        return try Self.parse(response, provider: name)
    }

    /// Turns a Chat Completions response into an `LLMReply` (also strips `<think>` reasoning).
    static func parse(_ response: JSONObject, provider name: String) throws -> LLMReply {
        guard let choice = (response["choices"] as? [JSONObject])?.first,
              let message = choice["message"] as? JSONObject else {
            throw TESSError("\(name) sent back an empty response.")
        }

        var text = message["content"] as? String ?? ""
        text = text.replacingOccurrences(of: "(?s)<think>.*?</think>", with: "", options: .regularExpression).trimmed

        var calls: [ToolCall] = []
        for raw in message["tool_calls"] as? [JSONObject] ?? [] {
            guard let function = raw["function"] as? JSONObject, let fname = function["name"] as? String else { continue }
            let args: JSONObject
            if let s = function["arguments"] as? String {
                args = JSONText.decodeObject(s)
            } else {
                args = function["arguments"] as? JSONObject ?? [:]
            }
            let id = (raw["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "call_\(UUID().uuidString.prefix(8))"
            calls.append(ToolCall(id: id, name: fname, arguments: args))
        }
        let usage = response["usage"] as? JSONObject ?? [:]
        return LLMReply(text: text,
                        toolCalls: calls,
                        inputTokens: usage.int("prompt_tokens") ?? 0,
                        outputTokens: usage.int("completion_tokens") ?? 0)
    }

    private func makeBody(system: String, history: [ChatItem], tools: [ToolSpec], includeImages: Bool) -> JSONObject {
        var messages: [JSONObject] = [["role": "system", "content": system]]
        var pendingImages: [Data] = []

        func flushImages() {
            guard !pendingImages.isEmpty else { return }
            var parts: [JSONObject] = [["type": "text", "text": "Image(s) returned by the tool call above:"]]
            for image in pendingImages {
                parts.append(["type": "image_url",
                              "image_url": ["url": "data:image/jpeg;base64," + image.base64EncodedString()]])
            }
            messages.append(["role": "user", "content": parts])
            pendingImages.removeAll()
        }

        for item in history {
            if case .toolResult = item {} else { flushImages() }
            switch item {
            case .user(let text):
                messages.append(["role": "user", "content": text])
            case .assistant(let text, let calls, _):
                var message: JSONObject = ["role": "assistant"]
                if text.isEmpty && !calls.isEmpty {
                    message["content"] = NSNull()
                } else {
                    message["content"] = text
                }
                if !calls.isEmpty {
                    message["tool_calls"] = calls.map { call -> JSONObject in
                        ["id": call.id,
                         "type": "function",
                         "function": ["name": call.name, "arguments": JSONText.encode(call.arguments)]]
                    }
                }
                messages.append(message)
            case .toolResult(let id, _, let content, let image):
                var text = content
                if let image {
                    if includeImages {
                        pendingImages.append(image)
                    } else {
                        text += "\n[An image was captured, but the current model can't see images. Tell the user to pick a vision-capable model (e.g. qwen2.5vl or llama3.2-vision in Ollama).]"
                    }
                }
                messages.append(["role": "tool", "tool_call_id": id, "content": text])
            }
        }
        flushImages()

        var body: JSONObject = ["model": model, "messages": messages]
        if !tools.isEmpty {
            body["tools"] = tools.map { spec -> JSONObject in
                ["type": "function",
                 "function": ["name": spec.name, "description": spec.description, "parameters": spec.parameters]]
            }
        }
        // Keep GPT-5-family reasoning short so voice replies stay snappy.
        if name == "OpenAI", model.hasPrefix("gpt-5") || model.hasPrefix("o") {
            body["reasoning_effort"] = "low"
        }
        return body
    }

    private static func hasImages(_ history: [ChatItem]) -> Bool {
        history.contains { item in
            if case .toolResult(_, _, _, let image) = item { return image != nil }
            return false
        }
    }

    struct OllamaStatus {
        var reachable = false
        var version = ""
        var models: [String] = []
        var message = ""
    }

    /// Checks a local Ollama server and lists its installed models, explaining any failure.
    static func ollamaStatus(baseURL: String) async -> OllamaStatus {
        var status = OllamaStatus()
        guard let base = URL(string: baseURL.trimmed), base.scheme != nil, base.host != nil else {
            status.message = "The server address isn't valid. Use http://127.0.0.1:11434"
            return status
        }
        do {
            if let json = try await HTTP.getJSON(base.appendingPathComponent("api/version")) as? JSONObject {
                status.version = json.string("version") ?? ""
            }
            status.reachable = true
            let tags = try await HTTP.getJSON(base.appendingPathComponent("api/tags")) as? JSONObject
            let models = tags?["models"] as? [JSONObject] ?? []
            status.models = models.compactMap { $0["name"] as? String }.sorted()
            let version = status.version.isEmpty ? "" : " \(status.version)"
            if status.models.isEmpty {
                status.message = "Connected to Ollama\(version), but no models are downloaded yet. In Terminal run: ollama pull llama3.1"
            } else {
                let count = status.models.count
                status.message = "Connected to Ollama\(version) — \(count) model\(count == 1 ? "" : "s") installed."
            }
        } catch let error as URLError {
            switch error.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
                status.message = "Can't reach Ollama at \(base.absoluteString). Is the Ollama app running?"
            case .appTransportSecurityRequiresSecureConnection:
                status.message = "macOS blocked the plain-HTTP connection to Ollama (App Transport Security)."
            case .timedOut:
                status.message = "Ollama at \(base.absoluteString) didn't answer in time."
            default:
                status.message = "Couldn't talk to Ollama: \(error.localizedDescription) (code \(error.code.rawValue))"
            }
        } catch {
            status.message = "Ollama answered, but unexpectedly: \(error.localizedDescription)"
        }
        return status
    }

    /// Lists models installed in a local Ollama server.
    static func ollamaModels(baseURL: String) async -> [String] {
        await ollamaStatus(baseURL: baseURL).models
    }
}
