import XCTest
@testable import TESS

final class AnthropicParsingTests: XCTestCase {
    func testTextToolUseAndUsage() {
        let response: JSONObject = [
            "content": [
                ["type": "text", "text": "Checking. "],
                ["type": "server_tool_use", "id": "srv", "name": "web_search"],
                ["type": "tool_use", "id": "tu1", "name": "get_weather", "input": ["city": "Oslo"]],
                ["type": "text", "text": "Done."],
            ],
            "stop_reason": "tool_use",
            "usage": ["input_tokens": 10, "cache_read_input_tokens": 5, "cache_creation_input_tokens": 1,
                      "output_tokens": 7, "server_tool_use": ["web_search_requests": 2]],
        ]
        let reply = AnthropicProvider.parse(response)
        XCTAssertEqual(reply.text, "Checking. Done.")
        XCTAssertEqual(reply.toolCalls.map(\.id), ["tu1"])
        XCTAssertEqual(reply.toolCalls.first?.arguments["city"] as? String, "Oslo")
        XCTAssertEqual(reply.inputTokens, 16)
        XCTAssertEqual(reply.outputTokens, 7)
        XCTAssertEqual(reply.webSearches, 2)
        XCTAssertFalse(reply.needsContinuation)
        XCTAssertEqual(reply.raw?.count, 4, "raw blocks are kept to replay server tool results")
    }

    func testPauseTurnNeedsContinuation() {
        let reply = AnthropicProvider.parse(["content": [], "stop_reason": "pause_turn"])
        XCTAssertTrue(reply.needsContinuation)
    }

    func testToolResultsMergeIntoOneUserMessage() {
        let history: [ChatItem] = [
            .user("weather and time"),
            .assistant(text: "", toolCalls: [ToolCall(id: "a", name: "w", arguments: [:]),
                                             ToolCall(id: "b", name: "t", arguments: [:])], raw: nil),
            .toolResult(id: "a", name: "w", content: "sunny", image: nil),
            .toolResult(id: "b", name: "t", content: "noon", image: nil),
        ]
        let messages = AnthropicProvider.messages(from: history)
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["user", "assistant", "user"])
        let blocks = messages[2]["content"] as? [JSONObject] ?? []
        XCTAssertEqual(blocks.map { $0["tool_use_id"] as? String }, ["a", "b"])
    }

    func testImagesAreSentAsImageBlocks() {
        let history: [ChatItem] = [
            .user("look"),
            .assistant(text: "", toolCalls: [ToolCall(id: "s", name: "look_at_screen", arguments: [:])], raw: nil),
            .toolResult(id: "s", name: "look_at_screen", content: "screenshot", image: Data([0xFF, 0xD8])),
        ]
        let blocks = AnthropicProvider.messages(from: history)[2]["content"] as? [JSONObject] ?? []
        let inner = blocks.first?["content"] as? [JSONObject] ?? []
        XCTAssertEqual(inner.map { $0["type"] as? String }, ["text", "image"])
    }
}

final class OpenAIParsingTests: XCTestCase {
    func testTextAndToolCalls() throws {
        let response: JSONObject = [
            "choices": [["message": [
                "content": "<think>planning…</think>Here you go.",
                "tool_calls": [
                    ["id": "c1", "function": ["name": "get_weather", "arguments": "{\"city\":\"Bergen\"}"]],
                    ["id": "", "function": ["name": "get_time", "arguments": ["zone": "UTC"]]],
                    ["id": "c3", "function": ["arguments": "{}"]], // no name: ignored
                ],
            ]]],
            "usage": ["prompt_tokens": 12, "completion_tokens": 3],
        ]
        let reply = try OpenAICompatibleProvider.parse(response, provider: "OpenAI")
        XCTAssertEqual(reply.text, "Here you go.")
        XCTAssertEqual(reply.toolCalls.map(\.name), ["get_weather", "get_time"])
        XCTAssertEqual(reply.toolCalls[0].arguments["city"] as? String, "Bergen")
        XCTAssertEqual(reply.toolCalls[1].arguments["zone"] as? String, "UTC")
        XCTAssertTrue(reply.toolCalls[1].id.hasPrefix("call_"), "a missing id gets a generated one")
        XCTAssertEqual(reply.inputTokens, 12)
        XCTAssertEqual(reply.outputTokens, 3)
    }

    func testEmptyResponseThrows() {
        XCTAssertThrowsError(try OpenAICompatibleProvider.parse([:], provider: "Ollama"))
    }

    func testMalformedArgumentsDoNotCrash() throws {
        let response: JSONObject = ["choices": [["message": [
            "content": "",
            "tool_calls": [["id": "c1", "function": ["name": "x", "arguments": "{not json"]]],
        ]]]]
        let reply = try OpenAICompatibleProvider.parse(response, provider: "Ollama")
        XCTAssertEqual(reply.toolCalls.count, 1)
        XCTAssertTrue(reply.toolCalls[0].arguments.isEmpty)
    }
}
