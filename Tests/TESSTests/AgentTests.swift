import XCTest
@testable import TESS

/// Plays back scripted replies and records what it was sent.
private final class FakeProvider: LLMProvider {
    let name = "Fake"
    let model = "fake-1"
    var replies: [LLMReply]
    private(set) var receivedHistories: [[ChatItem]] = []

    init(_ replies: [LLMReply]) { self.replies = replies }

    func complete(system: String, history: [ChatItem], tools: [ToolSpec]) async throws -> LLMReply {
        receivedHistories.append(history)
        guard !replies.isEmpty else { throw TESSError("No more scripted replies") }
        return replies.removeFirst()
    }
}

private func call(_ id: String, _ name: String = "echo", _ args: JSONObject = [:]) -> ToolCall {
    ToolCall(id: id, name: name, arguments: args)
}

@MainActor
final class AgentTests: XCTestCase {
    // MARK: History repair

    func testCompleteHistoryIsUntouched() {
        let history: [ChatItem] = [
            .user("hi"),
            .assistant(text: "", toolCalls: [call("a")], raw: nil),
            .toolResult(id: "a", name: "echo", content: "ok", image: nil),
            .assistant(text: "done", toolCalls: [], raw: nil),
        ]
        XCTAssertEqual(Agent.repaired(history).count, 4)
    }

    func testDanglingToolCallIsCut() {
        let history: [ChatItem] = [
            .user("one"),
            .assistant(text: "", toolCalls: [call("a")], raw: nil),
            .toolResult(id: "a", name: "echo", content: "ok", image: nil),
            .assistant(text: "first answer", toolCalls: [], raw: nil),
            .user("two"),
            .assistant(text: "", toolCalls: [call("b")], raw: nil), // interrupted before its result
        ]
        let repaired = Agent.repaired(history)
        XCTAssertEqual(repaired.count, 5)
        guard case .user("two") = repaired.last! else { return XCTFail("should end at the user's message") }
    }

    func testMissingOneOfSeveralResultsIsCut() {
        let history: [ChatItem] = [
            .user("go"),
            .assistant(text: "", toolCalls: [call("a"), call("b")], raw: nil),
            .toolResult(id: "a", name: "echo", content: "ok", image: nil),
        ]
        XCTAssertEqual(Agent.repaired(history).count, 1)
    }

    func testTrimStartsAtAUserMessage() {
        var history: [ChatItem] = []
        for i in 0..<10 {
            history.append(.user("q\(i)"))
            history.append(.assistant(text: "", toolCalls: [call("c\(i)")], raw: nil))
            history.append(.toolResult(id: "c\(i)", name: "echo", content: "ok", image: nil))
            history.append(.assistant(text: "a\(i)", toolCalls: [], raw: nil))
        }
        let trimmed = Agent.trimmed(history, maxItems: 10)
        XCTAssertLessThanOrEqual(trimmed.count, 10)
        guard case .user = trimmed.first! else { return XCTFail("trimmed history must start with the user") }
    }

    // MARK: Tool loop

    func testRunsToolsAndReturnsTheFinalAnswer() async throws {
        let provider = FakeProvider([
            LLMReply(text: "", toolCalls: [call("t1", "echo", ["text": "ping"])]),
            LLMReply(text: "The tool said pong.", toolCalls: []),
        ])
        let tools = ToolRegistry()
        var ran: [String] = []
        tools.add([Tool(name: "echo", description: "Echoes", properties: ["text": P.string("Text")]) { args in
            ran.append(args["text"] as? String ?? "")
            return "pong"
        }])

        let turnBefore = Agent.currentTurn
        let answer = try await Agent().run(userText: "use the tool", provider: provider, system: "", tools: tools) { _ in }

        XCTAssertEqual(answer, "The tool said pong.")
        XCTAssertEqual(ran, ["ping"])
        XCTAssertEqual(Agent.currentTurn, turnBefore + 1)
        XCTAssertEqual(Agent.lastUserText, "use the tool")

        // The second request carries the tool result back to the model.
        let second = provider.receivedHistories[1]
        guard case .toolResult(let id, _, let content, _) = second.last! else { return XCTFail("expected a tool result") }
        XCTAssertEqual(id, "t1")
        XCTAssertEqual(content, "pong")
    }

    func testUnknownToolBecomesAnErrorResultNotACrash() async throws {
        let provider = FakeProvider([
            LLMReply(text: "", toolCalls: [call("t1", "does_not_exist")]),
            LLMReply(text: "Sorry.", toolCalls: []),
        ])
        let answer = try await Agent().run(userText: "x", provider: provider, system: "", tools: ToolRegistry()) { _ in }
        XCTAssertEqual(answer, "Sorry.")
        guard case .toolResult(_, _, let content, _) = provider.receivedHistories[1].last! else { return XCTFail() }
        XCTAssertTrue(content.contains("no tool called"))
    }

    func testStopsAfterTooManyRounds() async throws {
        let replies = (0..<20).map { LLMReply(text: "", toolCalls: [call("r\($0)")]) }
        let tools = ToolRegistry()
        tools.add([Tool(name: "echo", description: "Echoes") { _ in "again" }])
        let answer = try await Agent().run(userText: "loop", provider: FakeProvider(replies), system: "", tools: tools) { _ in }
        XCTAssertTrue(answer.contains("more steps"))
    }
}
