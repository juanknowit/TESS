import XCTest
@testable import TESS

/// Issue #14: an unreadable memory.json (or history, protocols, usage) must never be overwritten.
final class StoredFileTests: XCTestCase {
    private struct Item: Codable, Equatable {
        var text: String
    }

    private var directory: URL!
    private var file: URL { directory.appendingPathComponent("memory.json") }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoredFileTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func contents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    func testMissingFileStartsEmptyAndCanSave() throws {
        let loaded = StoredFile.load([Item].self, from: file)
        XCTAssertNil(loaded.value)
        XCTAssertTrue(loaded.canSave)
        XCTAssertNil(loaded.backup)
        XCTAssertEqual(try contents(), [])
    }

    func testValidFileLoadsAndStaysPut() throws {
        let items = [Item(text: "Juan takes his coffee black")]
        try JSONEncoder().encode(items).write(to: file)

        let loaded = StoredFile.load([Item].self, from: file)
        XCTAssertEqual(loaded.value, items)
        XCTAssertTrue(loaded.canSave)
        XCTAssertNil(loaded.backup)
        XCTAssertEqual(try contents(), ["memory.json"])
    }

    func testUndecodableFileIsMovedAsideWithItsBytes() throws {
        let original = Data(#"[{"text": "Sofia is Juan's daughter"}, {"text": "#.utf8)  // half-written
        try original.write(to: file)

        let loaded = StoredFile.load([Item].self, from: file, now: now)
        XCTAssertNil(loaded.value)
        XCTAssertTrue(loaded.canSave)
        let backup = try XCTUnwrap(loaded.backup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "the bad file must not stay where save() writes")
        XCTAssertEqual(try Data(contentsOf: backup), original, "the backup must keep every byte")
        XCTAssertTrue(backup.lastPathComponent.hasPrefix("memory-unreadable-"))
        XCTAssertEqual(backup.pathExtension, "json")
    }

    func testNewerFormatIsKeptNotWiped() throws {
        // A later release added a field this version doesn't know as required.
        struct Old: Codable { var text: String; var created: Date }
        try Data(#"[{"text": "likes jazz"}]"#.utf8).write(to: file)

        let loaded = StoredFile.load([Old].self, from: file, now: now)
        XCTAssertNil(loaded.value)
        XCTAssertNotNil(loaded.backup)
        XCTAssertEqual(try contents().count, 1)
    }

    func testEarlierBackupsAreNeverReplaced() throws {
        try Data("first".utf8).write(to: file)
        let first = try XCTUnwrap(StoredFile.load([Item].self, from: file, now: now).backup)

        try Data("second".utf8).write(to: file)
        let second = try XCTUnwrap(StoredFile.load([Item].self, from: file, now: now).backup)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "second")
    }

    func testBackupNameKeepsExtensionAndAddsCounter() throws {
        let url = StoredFile.backupURL(for: file, now: now)
        try Data().write(to: url)
        let next = StoredFile.backupURL(for: file, now: now)
        XCTAssertEqual(next.lastPathComponent, url.deletingPathExtension().lastPathComponent + "-2.json")
    }

    func testFileThatCanNotBeMovedBlocksSaving() throws {
        try Data("not json".utf8).write(to: file)
        let loaded = StoredFile.load([Item].self, from: file, fileManager: NoMoveFileManager(), now: now)
        XCTAssertNil(loaded.value)
        XCTAssertFalse(loaded.canSave, "if the bad file is still in place, saving would destroy it")
        XCTAssertEqual(try Data(contentsOf: file), Data("not json".utf8))
    }
}

private final class NoMoveFileManager: FileManager {
    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}
