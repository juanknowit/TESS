import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var date: Date
    var question: String
    var answer: String
    var provider: String
    var failed: Bool

    init(question: String, answer: String, provider: String, failed: Bool) {
        id = UUID()
        date = Date()
        self.question = question
        self.answer = answer
        self.provider = provider
        self.failed = failed
    }
}

/// A log of what you asked TESS and what she answered, kept on this Mac.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    static let limit = 500

    @Published private(set) var entries: [HistoryEntry]
    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "historyEnabled") } }
    private let url: URL

    private init() {
        url = AppPaths.directory.appendingPathComponent("history.json")
        enabled = UserDefaults.standard.object(forKey: "historyEnabled") as? Bool ?? true
        if let raw = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: raw) {
            entries = decoded
        } else {
            entries = []
        }
    }

    func add(question: String, answer: String, provider: String, failed: Bool = false) {
        guard enabled, !question.trimmed.isEmpty else { return }
        entries.append(HistoryEntry(question: question.trimmed, answer: answer.trimmed, provider: provider, failed: failed))
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
        save()
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    /// Newest first, optionally filtered.
    func search(_ query: String) -> [HistoryEntry] {
        let q = query.trimmed.lowercased()
        let newest = entries.reversed()
        guard !q.isEmpty else { return Array(newest) }
        return newest.filter { $0.question.lowercased().contains(q) || $0.answer.lowercased().contains(q) }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
