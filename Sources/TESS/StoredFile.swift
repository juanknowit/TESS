import Foundation

/// Loads TESS's own JSON files (memory, history, protocols, usage) without ever losing them.
///
/// If a file exists but can't be read or decoded (a half-written file, a hand edit, or a format
/// from a newer release), it is moved aside to a backup next to it before the store starts empty,
/// so the next save can't overwrite it. If it can't even be moved aside, `canSave` is false and the
/// store must not write that file this session.
enum StoredFile {
    struct Loaded<Value> {
        /// The decoded contents, or nil when the file is missing or unreadable.
        let value: Value?
        /// False only when an unreadable file is still in place; saving would destroy it.
        let canSave: Bool
        /// Where an unreadable file was moved to, if it was.
        let backup: URL?
    }

    static func load<Value: Decodable>(
        _ type: Value.Type,
        from url: URL,
        decoder: JSONDecoder = JSONDecoder(),
        fileManager: FileManager = .default,
        now: Date = Date()
    ) -> Loaded<Value> {
        guard fileManager.fileExists(atPath: url.path) else {
            return Loaded(value: nil, canSave: true, backup: nil)
        }
        do {
            let raw = try Data(contentsOf: url)
            return Loaded(value: try decoder.decode(Value.self, from: raw), canSave: true, backup: nil)
        } catch {
            NSLog("TESS: couldn't read \(url.lastPathComponent): \(error)")
        }
        let backup = backupURL(for: url, fileManager: fileManager, now: now)
        do {
            try fileManager.moveItem(at: url, to: backup)
            NSLog("TESS: kept the unreadable \(url.lastPathComponent) as \(backup.lastPathComponent)")
            return Loaded(value: nil, canSave: true, backup: backup)
        } catch {
            NSLog("TESS: couldn't move \(url.lastPathComponent) aside (\(error)); not saving it this session")
            return Loaded(value: nil, canSave: false, backup: nil)
        }
    }

    /// memory.json → memory-unreadable-2026-11-03-140312.json, never replacing an earlier backup.
    static func backupURL(for url: URL, fileManager: FileManager = .default, now: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let directory = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "" : "." + url.pathExtension
        let base = "\(name)-unreadable-\(formatter.string(from: now))"
        var candidate = directory.appendingPathComponent(base + ext)
        var n = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(n)\(ext)")
            n += 1
        }
        return candidate
    }
}
