import Foundation

/// Decides whether something the user said approves sending a draft.
///
/// Deliberately strict: a short, clear yes ("yes", "send it", "go ahead") with no hesitation,
/// change request or question in it. Anything else is not an approval, and TESS asks again.
enum Approval {
    private static let positives: Set<String> = [
        "yes", "yeah", "yep", "yup", "yea", "sure", "ok", "okay", "send", "confirm", "confirmed",
        "correct", "perfect", "absolutely", "definitely", "please",
        // Norwegian ("send" is the same word)
        "ja", "jo", "jepp", "japp", "greit",
    ]
    private static let positivePhrases = ["go ahead", "do it", "sounds good", "looks good", "that's right", "all good"]

    private static let negatives: Set<String> = [
        "no", "nope", "nah", "not", "don't", "dont", "wait", "stop", "cancel", "change", "edit", "hold",
        "never", "later", "instead", "but", "actually", "hmm",
        "what", "when", "where", "who", "why", "how", "which",
        // Norwegian
        "nei", "ikke", "vent", "stopp", "avbryt", "endre", "men", "hva", "hvor", "hvem", "hvorfor", "hvordan",
    ]

    /// Words that only count as approval together with a real "yes" word ("please" alone isn't a yes).
    private static let weak: Set<String> = ["please"]

    static func isApproval(_ utterance: String) -> Bool {
        if utterance.contains("?") { return false }
        let words = Self.words(utterance)
        guard !words.isEmpty, words.count <= 6 else { return false }
        // "what's" counts as "what", "don't" is listed as itself.
        if words.contains(where: { negatives.contains($0) || negatives.contains(String($0.prefix { $0 != "'" })) }) {
            return false
        }
        let text = words.joined(separator: " ")
        if positivePhrases.contains(where: { text.contains($0) }) { return true }
        return words.contains { positives.contains($0) && !weak.contains($0) }
    }

    /// True when the user clearly said no, so the draft should be thrown away.
    static func isRefusal(_ utterance: String) -> Bool {
        let words = Self.words(utterance)
        return words.contains { ["no", "nope", "nah", "cancel", "don't", "dont", "nei", "avbryt"].contains($0) }
    }

    static func words(_ utterance: String) -> [String] {
        utterance.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split { !($0.isLetter || $0.isNumber || $0 == "'") }
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .filter { !$0.isEmpty }
    }
}

/// The rules a draft must pass before it's sent. Pure, so it can be tested.
enum ConfirmationGate {
    /// How long a read-back stays valid.
    static let lifetime: TimeInterval = 5 * 60

    enum Verdict: Equatable {
        /// Send it.
        case approved
        /// Don't send; keep the draft and ask the user again (their next reply can confirm).
        case askAgain(String)
        /// Don't send, and discard the draft.
        case discard(String)
    }

    /// - Parameters:
    ///   - armedTurn: the user turn during which the draft was read back
    ///   - armedAt: when it was read back
    ///   - isLatest: whether this is the newest draft (a newer one replaces it)
    ///   - currentTurn: the current user turn
    ///   - lastUserText: what the user said most recently
    static func check(armedTurn: Int, armedAt: Date, isLatest: Bool,
                      currentTurn: Int, lastUserText: String, now: Date = Date()) -> Verdict {
        guard isLatest else {
            return .discard("Not sent: a newer draft replaced this one. Read the newest draft back and ask the user to confirm it.")
        }
        guard currentTurn > armedTurn else {
            return .askAgain("Not sent: the user hasn't answered yet. Read the draft back and wait for their reply.")
        }
        guard now.timeIntervalSince(armedAt) <= lifetime else {
            return .discard("Not sent: the draft is more than five minutes old. Make a new draft and read it back.")
        }
        guard currentTurn == armedTurn + 1 else {
            return .askAgain("Not sent: the user said other things after the read-back. Read the draft back again and ask them to confirm.")
        }
        if Approval.isRefusal(lastUserText) {
            return .discard("Not sent: the user said no. The draft is cancelled. If they want changes, make a new draft.")
        }
        guard Approval.isApproval(lastUserText) else {
            return .askAgain("Not sent: “\(lastUserText)” isn't a clear yes. Ask the user plainly whether to send it. If they want changes, make a new draft.")
        }
        return .approved
    }
}

/// Drafts waiting for the user's go-ahead. Only the newest draft can be sent.
@MainActor
final class DraftBox<Draft> {
    private struct Entry {
        var draft: Draft
        var armedTurn: Int
        var armedAt: Date
    }

    private let prefix: String
    private let noun: String
    private var entries: [String: Entry] = [:]
    private var latestID: String?
    private var counter = 0

    init(prefix: String, noun: String) {
        self.prefix = prefix
        self.noun = noun
    }

    /// Stores a new draft (replacing any earlier one) and returns its id.
    func add(_ draft: Draft) -> String {
        add(draft, turn: Agent.currentTurn, now: Date())
    }

    func add(_ draft: Draft, turn: Int, now: Date) -> String {
        counter += 1
        let id = "\(prefix)\(counter)"
        entries = [id: Entry(draft: draft, armedTurn: turn, armedAt: now)]
        latestID = id
        return id
    }

    /// Returns the draft if the user's reply approved it; otherwise throws an explanation for the model.
    func take(_ id: String) throws -> Draft {
        try take(id, currentTurn: Agent.currentTurn, lastUserText: Agent.lastUserText, now: Date())
    }

    func take(_ id: String, currentTurn: Int, lastUserText: String, now: Date) throws -> Draft {
        guard var entry = entries[id] else {
            throw TESSError("There's no \(noun) \(id) waiting. Make a new draft and read it back first.")
        }
        switch ConfirmationGate.check(armedTurn: entry.armedTurn, armedAt: entry.armedAt, isLatest: id == latestID,
                                      currentTurn: currentTurn, lastUserText: lastUserText, now: now) {
        case .approved:
            entries[id] = nil
            return entry.draft
        case .askAgain(let reason):
            // The model is now asking again, so the user's next reply can confirm.
            entry.armedTurn = currentTurn
            entry.armedAt = now
            entries[id] = entry
            throw TESSError(reason)
        case .discard(let reason):
            entries[id] = nil
            throw TESSError(reason)
        }
    }
}
