import Foundation

/// One of TESS's own data files (memory, history, protocols, usage).
///
/// Loads through `StoredFile`, tells `StorageAlerts` when a file couldn't be read, and refuses to
/// write while an unreadable file is still in place, so it can never be overwritten.
@MainActor
final class GuardedFile {
    let url: URL
    /// What the file holds, as TESS would say it: "memories", "history", "protocols", "usage stats".
    let label: String
    private(set) var canSave = true
    /// Called when saving resumes after "Try again", so the store can write what it has now.
    var onResume: (() -> Void)?

    private let alerts: StorageAlerts
    private let fileManager: FileManager

    init(_ name: String, label: String, directory: URL? = nil,
         alerts: StorageAlerts? = nil, fileManager: FileManager = .default) {
        url = (directory ?? AppPaths.directory).appendingPathComponent(name)
        self.label = label
        self.alerts = alerts ?? .shared
        self.fileManager = fileManager
    }

    func load<Value: Decodable>(_ type: Value.Type) -> Value? {
        let loaded = StoredFile.load(type, from: url, fileManager: fileManager)
        canSave = loaded.canSave
        if !loaded.canSave {
            alerts.report(.notSaving, for: self)
        } else if let backup = loaded.backup {
            alerts.report(.keptCopy(backup), for: self)
        }
        return loaded.value
    }

    func write(_ data: Data) {
        guard canSave else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Tries again to move the unreadable file aside. Returns true when saving has resumed.
    @discardableResult
    func retry() -> Bool {
        guard !canSave else { return true }
        if fileManager.fileExists(atPath: url.path) {
            guard let backup = StoredFile.moveAside(url, fileManager: fileManager) else { return false }
            alerts.report(.keptCopy(backup), for: self, announced: true)
        } else {
            alerts.resolve(self) // the user moved or removed it themselves
        }
        canSave = true
        onResume?()
        return true
    }
}

/// Problems with TESS's own data files, shown in the menu bar and spoken once.
@MainActor
final class StorageAlerts: ObservableObject {
    static let shared = StorageAlerts()

    enum Kind: Equatable {
        /// The file couldn't be read, so it was kept under this name and the store started fresh.
        case keptCopy(URL)
        /// The file couldn't be read or moved aside, so nothing is saved to it until "Try again" works.
        case notSaving
    }

    struct Alert: Identifiable, Equatable {
        let file: URL
        let label: String
        var kind: Kind
        var announced: Bool
        var retryFailed = false
        var id: URL { file }
    }

    @Published private(set) var alerts: [Alert] = []
    private var files: [URL: GuardedFile] = [:]

    func report(_ kind: Kind, for file: GuardedFile, announced: Bool = false) {
        files[file.url] = file
        let alert = Alert(file: file.url, label: file.label, kind: kind, announced: announced)
        if let i = alerts.firstIndex(where: { $0.id == file.url }) {
            alerts[i] = alert
        } else {
            alerts.append(alert)
        }
    }

    func resolve(_ file: GuardedFile) {
        alerts.removeAll { $0.id == file.url }
    }

    /// Hides a "kept a copy" notice. Files that aren't being saved stay until they're fixed.
    func dismiss(_ id: URL) {
        alerts.removeAll { $0.id == id && $0.kind != .notSaving }
    }

    func retry(_ id: URL) {
        guard let file = files[id], let i = alerts.firstIndex(where: { $0.id == id }) else { return }
        if !file.retry() { alerts[i].retryFailed = true }
    }

    /// One spoken line for every problem not mentioned yet, or nil. Each problem is only said once.
    func takeAnnouncement() -> String? {
        let pending = alerts.filter { !$0.announced }
        guard !pending.isEmpty else { return nil }
        for i in alerts.indices { alerts[i].announced = true }
        return Self.spokenLine(for: pending)
    }

    static func spokenLine(for alerts: [Alert]) -> String? {
        let kept = alerts.filter { $0.kind != .notSaving }.map(\.label)
        let stuck = alerts.filter { $0.kind == .notSaving }.map(\.label)
        var sentences: [String] = []
        if !kept.isEmpty {
            sentences.append("I couldn't read your saved \(spokenList(kept)), so I kept a copy and started fresh.")
        }
        if !stuck.isEmpty {
            let files = stuck.count == 1 ? "that file" : "those files"
            sentences.append("I couldn't read your saved \(spokenList(stuck)), so I won't save over \(files) until it's sorted. The menu bar has details.")
        }
        return sentences.isEmpty ? nil : "Heads up. " + sentences.joined(separator: " ")
    }

    /// "memories", "memories and history", "memories, history and protocols".
    static func spokenList(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items.last!
    }
}
