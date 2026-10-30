import XCTest
@testable import TESS

final class ApprovalTests: XCTestCase {
    func testClearYesIsApproval() {
        for text in ["Yes", "yes.", "Yes please", "Send it", "go ahead", "Yep, send it.", "OK", "okay",
                     "Sounds good", "Sure", "Ja", "ja send den", "yes send it to her", "Correct"] {
            XCTAssertTrue(Approval.isApproval(text), "“\(text)” should approve")
        }
    }

    func testAnythingElseIsNotApproval() {
        for text in ["", "No", "nope", "no, change it to six", "Yes but change the time", "yes, wait",
                     "What's the weather?", "what's the weather tomorrow", "is it raining?", "hmm",
                     "please", "maybe", "send it to Maria instead", "don't send it", "not yet", "hold on",
                     "actually make it shorter", "yes and also remind me to call mum tomorrow at nine",
                     "Nei", "vent litt", "ikke send", "how long is it", "Let me think"] {
            XCTAssertFalse(Approval.isApproval(text), "“\(text)” should not approve")
        }
    }

    func testRefusal() {
        for text in ["No", "nope", "no thanks", "cancel that", "don't", "Nei"] {
            XCTAssertTrue(Approval.isRefusal(text), "“\(text)” should be a refusal")
        }
        for text in ["yes", "what's the weather", "notes"] {
            XCTAssertFalse(Approval.isRefusal(text), "“\(text)” should not be a refusal")
        }
    }

    func testSmartApostrophe() {
        XCTAssertFalse(Approval.isApproval("Don\u{2019}t"))
        XCTAssertTrue(Approval.isRefusal("Don\u{2019}t"))
    }
}

final class ConfirmationGateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func check(armed: Int = 3, current: Int = 4, latest: Bool = true, text: String = "yes",
                       after seconds: TimeInterval = 10) -> ConfirmationGate.Verdict {
        ConfirmationGate.check(armedTurn: armed, armedAt: start, isLatest: latest,
                               currentTurn: current, lastUserText: text, now: start.addingTimeInterval(seconds))
    }

    private func isAskAgain(_ verdict: ConfirmationGate.Verdict) -> Bool {
        if case .askAgain = verdict { return true }
        return false
    }

    private func isDiscard(_ verdict: ConfirmationGate.Verdict) -> Bool {
        if case .discard = verdict { return true }
        return false
    }

    func testApprovedOnTheNextReply() {
        XCTAssertEqual(check(), .approved)
    }

    func testNoReplyYet() {
        XCTAssertTrue(isAskAgain(check(current: 3)))
    }

    func testOtherRepliesInBetween() {
        XCTAssertTrue(isAskAgain(check(current: 5)))
    }

    func testUnrelatedReply() {
        XCTAssertTrue(isAskAgain(check(text: "what's the weather tomorrow?")))
    }

    func testRefusalDiscards() {
        XCTAssertTrue(isDiscard(check(text: "no")))
    }

    func testExpired() {
        XCTAssertTrue(isDiscard(check(after: ConfirmationGate.lifetime + 1)))
    }

    func testReplacedDraft() {
        XCTAssertTrue(isDiscard(check(latest: false)))
    }
}

@MainActor
final class DraftBoxTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    func testNewDraftReplacesTheOldOne() throws {
        let box = DraftBox<String>(prefix: "d", noun: "draft")
        let first = box.add("hello", turn: 1, now: now)
        let second = box.add("hello again", turn: 1, now: now)
        XCTAssertThrowsError(try box.take(first, currentTurn: 2, lastUserText: "yes", now: now))
        XCTAssertEqual(try box.take(second, currentTurn: 2, lastUserText: "yes", now: now), "hello again")
    }

    func testCanOnlyBeSentOnce() throws {
        let box = DraftBox<String>(prefix: "d", noun: "draft")
        let id = box.add("hi", turn: 1, now: now)
        XCTAssertEqual(try box.take(id, currentTurn: 2, lastUserText: "send it", now: now), "hi")
        XCTAssertThrowsError(try box.take(id, currentTurn: 2, lastUserText: "send it", now: now))
    }

    func testAmbiguousReplyMeansAskAgainThenYesWorks() throws {
        let box = DraftBox<String>(prefix: "d", noun: "draft")
        let id = box.add("hi", turn: 1, now: now)
        XCTAssertThrowsError(try box.take(id, currentTurn: 2, lastUserText: "what's the weather?", now: now))
        // TESS asked again during turn 2; the reply in turn 3 can confirm.
        XCTAssertEqual(try box.take(id, currentTurn: 3, lastUserText: "yes", now: now), "hi")
    }

    func testNoCancelsTheDraft() {
        let box = DraftBox<String>(prefix: "d", noun: "draft")
        let id = box.add("hi", turn: 1, now: now)
        XCTAssertThrowsError(try box.take(id, currentTurn: 2, lastUserText: "no", now: now))
        XCTAssertThrowsError(try box.take(id, currentTurn: 3, lastUserText: "yes", now: now))
    }

    func testCannotSendInTheSameTurnItWasDrafted() {
        let box = DraftBox<String>(prefix: "d", noun: "draft")
        let id = box.add("hi", turn: 1, now: now)
        XCTAssertThrowsError(try box.take(id, currentTurn: 1, lastUserText: "text Maria hi and send it", now: now))
    }
}
