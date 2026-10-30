import Foundation

struct MemoryItem: Codable, Identifiable, Equatable {
    var id: UUID
    var text: String
    var created: Date

    init(text: String) {
        id = UUID()
        self.text = text
        created = Date()
    }
}

/// Long-term facts TESS keeps about the user, stored in ~/Library/Application Support/TESS/memory.json.
@MainActor
final class MemoryStore: ObservableObject {
    static let shared = MemoryStore()
    static let limit = 200

    @Published private(set) var items: [MemoryItem]
    private let url: URL

    private init() {
        url = AppPaths.directory.appendingPathComponent("memory.json")
        if let raw = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([MemoryItem].self, from: raw) {
            items = decoded
        } else {
            items = []
        }
    }

    /// Adds a fact unless an identical one exists. Returns false for duplicates or empty text.
    @discardableResult
    func add(_ text: String) -> Bool {
        let clean = text.trimmed
        guard !clean.isEmpty else { return false }
        guard !items.contains(where: { $0.text.lowercased() == clean.lowercased() }) else { return false }
        items.append(MemoryItem(text: clean))
        if items.count > Self.limit { items.removeFirst(items.count - Self.limit) }
        save()
        return true
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    /// Removes every memory containing the query; returns what was removed.
    func remove(matching query: String) -> [String] {
        let q = query.trimmed.lowercased()
        guard !q.isEmpty else { return [] }
        let removed = items.filter { $0.text.lowercased().contains(q) }
        guard !removed.isEmpty else { return [] }
        items.removeAll { $0.text.lowercased().contains(q) }
        save()
        return removed.map(\.text)
    }

    func clear() {
        items.removeAll()
        save()
    }

    var texts: [String] { items.map(\.text) }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

enum MemoryTools {
    static func all() -> [Tool] { [remember, forget, listMemories] }

    static let remember = Tool(
        name: "remember",
        description: "Save a lasting fact or preference about the user to long-term memory, written as a short third-person sentence (e.g. 'Juan's daughter is called Sofia'). Use when the user asks you to remember something, or shares a durable personal detail. Never store passwords or other secrets.",
        properties: ["fact": P.string("The fact to remember")],
        required: ["fact"]
    ) { args in
        guard let fact = args.string("fact") else { throw TESSError("What should I remember?") }
        let added = await MemoryStore.shared.add(fact)
        return added ? "Saved to memory: \(fact)" : "That was already in memory."
    }

    static let forget = Tool(
        name: "forget",
        description: "Delete memories that contain the given words.",
        properties: ["query": P.string("Words that appear in the memory to delete")],
        required: ["query"]
    ) { args in
        guard let query = args.string("query") else { throw TESSError("What should I forget?") }
        let removed = await MemoryStore.shared.remove(matching: query)
        return removed.isEmpty ? "No memory matches \(query)." : "Forgot: " + removed.joined(separator: "; ")
    }

    static let listMemories = Tool(
        name: "list_memories",
        description: "List everything in long-term memory about the user."
    ) { _ in
        let texts = await MemoryStore.shared.texts
        return texts.isEmpty ? "Memory is empty." : texts.map { "- \($0)" }.joined(separator: "\n")
    }
}
