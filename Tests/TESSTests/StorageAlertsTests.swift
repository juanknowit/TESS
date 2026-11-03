import XCTest
@testable import TESS

/// Unreadable data files are reported to the user (menu bar + one spoken line), never handled silently.
@MainActor
final class StorageAlertsTests: XCTestCase {
    private func makeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("StorageAlertsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func file(in dir: URL, alerts: StorageAlerts, fileManager: FileManager = .default) -> GuardedFile {
        GuardedFile("memory.json", label: "memories", directory: dir, alerts: alerts, fileManager: fileManager)
    }

    // MARK: Loading

    func testReadableFileRaisesNoAlert() throws {
        let dir = try makeDirectory()
        try JSONEncoder().encode(["likes jazz"]).write(to: dir.appendingPathComponent("memory.json"))
        let alerts = StorageAlerts()
        let guarded = file(in: dir, alerts: alerts)

        XCTAssertEqual(guarded.load([String].self), ["likes jazz"])
        XCTAssertTrue(guarded.canSave)
        XCTAssertTrue(alerts.alerts.isEmpty)
        XCTAssertNil(alerts.takeAnnouncement())
    }

    func testMissingFileRaisesNoAlert() throws {
        let alerts = StorageAlerts()
        XCTAssertNil(file(in: try makeDirectory(), alerts: alerts).load([String].self))
        XCTAssertTrue(alerts.alerts.isEmpty)
    }

    func testUnreadableFileIsReportedAsKeptCopy() throws {
        let dir = try makeDirectory()
        try Data("this is not json".utf8).write(to: dir.appendingPathComponent("memory.json"))
        let alerts = StorageAlerts()
        let guarded = file(in: dir, alerts: alerts)

        XCTAssertNil(guarded.load([String].self))
        XCTAssertTrue(guarded.canSave)
        XCTAssertEqual(alerts.alerts.count, 1)
        guard case .keptCopy(let backup) = alerts.alerts[0].kind else { return XCTFail("expected keptCopy") }
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "this is not json")
        XCTAssertEqual(alerts.alerts[0].label, "memories")
    }

    func testFileThatCanNotBeMovedIsReportedAsNotSavingAndIsNeverWritten() throws {
        let dir = try makeDirectory()
        let url = dir.appendingPathComponent("memory.json")
        try Data("this is not json".utf8).write(to: url)
        let alerts = StorageAlerts()
        let guarded = file(in: dir, alerts: alerts, fileManager: SwitchableMoveFileManager())

        XCTAssertNil(guarded.load([String].self))
        XCTAssertFalse(guarded.canSave)
        XCTAssertEqual(alerts.alerts.map(\.kind), [.notSaving])

        guarded.write(try JSONEncoder().encode(["new"]))
        XCTAssertEqual(try Data(contentsOf: url), Data("this is not json".utf8))
    }

    // MARK: Speaking once

    func testAnnouncementIsSpokenOnlyOnce() throws {
        let dir = try makeDirectory()
        try Data("x".utf8).write(to: dir.appendingPathComponent("memory.json"))
        let alerts = StorageAlerts()
        _ = file(in: dir, alerts: alerts).load([String].self)

        let line = try XCTUnwrap(alerts.takeAnnouncement())
        XCTAssertEqual(line, "Heads up. I couldn't read your saved memories, so I kept a copy and started fresh.")
        XCTAssertNil(alerts.takeAnnouncement())
        XCTAssertEqual(alerts.alerts.count, 1, "the menu bar notice stays after it's been said")
    }

    func testSpokenLineCombinesFilesAndKinds() {
        func alert(_ label: String, _ kind: StorageAlerts.Kind) -> StorageAlerts.Alert {
            StorageAlerts.Alert(file: URL(fileURLWithPath: "/tmp/\(label).json"), label: label, kind: kind, announced: false)
        }
        let backup = URL(fileURLWithPath: "/tmp/backup.json")

        XCTAssertEqual(StorageAlerts.spokenLine(for: [alert("memories", .keptCopy(backup)), alert("history", .keptCopy(backup))]),
                       "Heads up. I couldn't read your saved memories and history, so I kept a copy and started fresh.")
        XCTAssertEqual(StorageAlerts.spokenLine(for: [alert("usage stats", .notSaving)]),
                       "Heads up. I couldn't read your saved usage stats, so I won't save over that file until it's sorted. The menu bar has details.")
        let mixed = StorageAlerts.spokenLine(for: [alert("memories", .keptCopy(backup)), alert("protocols", .notSaving)]) ?? ""
        XCTAssertTrue(mixed.contains("saved memories, so I kept a copy"))
        XCTAssertTrue(mixed.contains("saved protocols, so I won't save over that file"))
        XCTAssertNil(StorageAlerts.spokenLine(for: []))

        XCTAssertEqual(StorageAlerts.spokenList(["memories", "history", "protocols"]), "memories, history and protocols")
        XCTAssertFalse(mixed.contains("*") || mixed.contains("#") || mixed.contains(".json"), "spoken text stays plain")
    }

    // MARK: Dismiss and Try again

    func testOnlyKeptCopyNoticesCanBeDismissed() throws {
        let dir = try makeDirectory()
        try Data("x".utf8).write(to: dir.appendingPathComponent("memory.json"))
        let alerts = StorageAlerts()
        let stuck = GuardedFile("history.json", label: "history", directory: dir, alerts: alerts,
                                fileManager: SwitchableMoveFileManager())
        try Data("x".utf8).write(to: stuck.url)
        _ = file(in: dir, alerts: alerts).load([String].self)
        _ = stuck.load([String].self)
        XCTAssertEqual(alerts.alerts.count, 2)

        for alert in alerts.alerts { alerts.dismiss(alert.id) }
        XCTAssertEqual(alerts.alerts.map(\.kind), [.notSaving], "a file that isn't being saved can't be dismissed")
    }

    func testTryAgainThatStillFailsKeepsBlockingSaves() throws {
        let dir = try makeDirectory()
        try Data("x".utf8).write(to: dir.appendingPathComponent("memory.json"))
        let alerts = StorageAlerts()
        let guarded = file(in: dir, alerts: alerts, fileManager: SwitchableMoveFileManager())
        _ = guarded.load([String].self)

        alerts.retry(guarded.url)
        XCTAssertFalse(guarded.canSave)
        XCTAssertEqual(alerts.alerts.map(\.kind), [.notSaving])
        XCTAssertTrue(alerts.alerts[0].retryFailed)
    }

    func testTryAgainThatWorksResumesSavingAndSavesNow() throws {
        let dir = try makeDirectory()
        let url = dir.appendingPathComponent("memory.json")
        try Data("this is not json".utf8).write(to: url)
        let fileManager = SwitchableMoveFileManager()
        let alerts = StorageAlerts()
        let guarded = file(in: dir, alerts: alerts, fileManager: fileManager)
        _ = guarded.load([String].self)
        _ = alerts.takeAnnouncement()
        var resumed = 0
        guarded.onResume = { resumed += 1 }

        fileManager.canMove = true
        alerts.retry(guarded.url)

        XCTAssertTrue(guarded.canSave)
        XCTAssertEqual(resumed, 1, "the store saves what it has as soon as saving resumes")
        guard case .keptCopy(let backup) = alerts.alerts.first?.kind else { return XCTFail("expected keptCopy") }
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "this is not json")
        XCTAssertNil(alerts.takeAnnouncement(), "fixing it from the menu doesn't need to be said out loud")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testTryAgainAfterTheUserRemovedTheFileClearsTheAlert() throws {
        let dir = try makeDirectory()
        let url = dir.appendingPathComponent("memory.json")
        try Data("x".utf8).write(to: url)
        let alerts = StorageAlerts()
        let guarded = file(in: dir, alerts: alerts, fileManager: SwitchableMoveFileManager())
        _ = guarded.load([String].self)

        try FileManager.default.removeItem(at: url)
        alerts.retry(guarded.url)

        XCTAssertTrue(guarded.canSave)
        XCTAssertTrue(alerts.alerts.isEmpty)
    }
}

/// A file manager whose moves fail until `canMove` is set.
private final class SwitchableMoveFileManager: FileManager {
    var canMove = false

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        guard canMove else { throw CocoaError(.fileWriteNoPermission) }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}
