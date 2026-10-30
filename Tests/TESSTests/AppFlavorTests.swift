import XCTest
@testable import TESS

final class AppFlavorTests: XCTestCase {
    /// Existing users' settings, data, keys and permissions live under these exact values.
    func testReleaseIdentityIsUnchanged() {
        let release = AppFlavor.release
        XCTAssertFalse(release.isDev)
        XCTAssertEqual(release.bundleID, "app.tess.assistant")
        XCTAssertEqual(release.appName, "TESS")
        XCTAssertEqual(release.supportFolderName, "TESS")
        XCTAssertEqual(release.keychainService, "app.tess.assistant")
        XCTAssertEqual(release.defaultWakeName, "Tess")
        XCTAssertTrue(release.briefingOnUnlockByDefault)
        XCTAssertTrue(release.checksForUpdates)
    }

    func testReleaseDataFolder() {
        let base = URL(fileURLWithPath: "/Users/someone/Library/Application Support")
        XCTAssertEqual(AppFlavor.release.supportDirectory(in: base).path, "/Users/someone/Library/Application Support/TESS")
        XCTAssertEqual(AppFlavor.dev.supportDirectory(in: base).path, "/Users/someone/Library/Application Support/TESS Dev")
    }

    func testDevIsIsolatedFromRelease() {
        let dev = AppFlavor.dev, release = AppFlavor.release
        XCTAssertTrue(dev.isDev)
        XCTAssertEqual(dev.bundleID, "app.tess.assistant.dev")
        XCTAssertNotEqual(dev.bundleID, release.bundleID)
        XCTAssertNotEqual(dev.supportFolderName, release.supportFolderName)
        XCTAssertNotEqual(dev.keychainService, release.keychainService)
        XCTAssertNotEqual(dev.appName, release.appName)
    }

    func testDevDefaults() {
        XCTAssertEqual(AppFlavor.dev.defaultWakeName, "Dev")
        XCTAssertFalse(AppFlavor.dev.briefingOnUnlockByDefault)
        XCTAssertFalse(AppFlavor.dev.checksForUpdates)
    }

    func testWakeWordsDoNotOverlap() {
        // Each app must ignore the other's wake word.
        let words = ["hey", "dev", "what", "time", "is", "it"]
        XCTAssertNotNil(WakeMatcher.matchEnd(in: words, name: AppFlavor.dev.defaultWakeName))
        XCTAssertNil(WakeMatcher.matchEnd(in: words, name: AppFlavor.release.defaultWakeName))
        let tess = ["hey", "tess", "what", "time", "is", "it"]
        XCTAssertNotNil(WakeMatcher.matchEnd(in: tess, name: AppFlavor.release.defaultWakeName))
        XCTAssertNil(WakeMatcher.matchEnd(in: tess, name: AppFlavor.dev.defaultWakeName))
    }

    func testFlavorFollowsTheBundleID() {
        XCTAssertEqual(AppFlavor.flavor(forBundleID: "app.tess.assistant.dev"), .dev)
        XCTAssertEqual(AppFlavor.flavor(forBundleID: "app.tess.assistant"), .release)
        XCTAssertEqual(AppFlavor.flavor(forBundleID: nil), .release)
        XCTAssertEqual(AppFlavor.flavor(forBundleID: "com.apple.dt.xctest.tool"), .release)
    }

    func testTestsRunAsRelease() {
        // The test runner isn't TESS Dev, so tests exercise the release paths.
        XCTAssertEqual(AppFlavor.current, .release)
        XCTAssertEqual(Keychain.service, "app.tess.assistant")
        XCTAssertEqual(AppPaths.directory.lastPathComponent, "TESS")
    }
}
