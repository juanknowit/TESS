import Foundation

struct ToolSpec {
    let name: String
    let description: String
    let parameters: JSONObject // JSON Schema object
}

struct ToolCall {
    let id: String
    let name: String
    let arguments: JSONObject
}

/// Provider-neutral conversation history.
enum ChatItem {
    case user(String)
    /// `raw` keeps Anthropic's original content blocks (needed to replay server-side web search results).
    case assistant(text: String, toolCalls: [ToolCall], raw: [JSONObject]?)
    /// `image` is a JPEG the tool captured (screenshot, document page) for the model to look at.
    case toolResult(id: String, name: String, content: String, image: Data?)
}

struct LLMReply {
    var text: String
    var toolCalls: [ToolCall]
    var raw: [JSONObject]? = nil
    /// Anthropic "pause_turn": the model wants another round to finish a long server-side operation.
    var needsContinuation = false
    var inputTokens = 0
    var outputTokens = 0
    var webSearches = 0
}

protocol LLMProvider {
    var name: String { get }
    var model: String { get }
    func complete(system: String, history: [ChatItem], tools: [ToolSpec]) async throws -> LLMReply
}
