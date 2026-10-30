import Foundation

/// TESS (the GitHub release) and TESS Dev (built locally with `build.sh --dev`) are separate apps.
///
/// Each has its own bundle ID, so macOS keeps their settings and permissions apart, and its own data
/// folder and keychain item, so nothing TESS Dev does can touch the release's data.
/// The release values below are what TESS has always used and must never change: existing users' data
/// lives there.
struct AppFlavor: Equatable {
    let isDev: Bool

    static let release = AppFlavor(isDev: false)
    static let dev = AppFlavor(isDev: true)

    static let releaseBundleID = "app.tess.assistant"
    static let devBundleID = "app.tess.assistant.dev"

    /// Decided by the bundle ID, because that's also what macOS uses to separate settings and permissions.
    static let current = flavor(forBundleID: Bundle.main.bundleIdentifier)

    static func flavor(forBundleID bundleID: String?) -> AppFlavor {
        bundleID == devBundleID ? .dev : .release
    }

    var bundleID: String { isDev ? Self.devBundleID : Self.releaseBundleID }

    /// Name shown in the menu bar panel, Settings and About.
    var appName: String { isDev ? "TESS Dev" : "TESS" }

    /// Folder in ~/Library/Application Support for memory, history, protocols and usage.
    var supportFolderName: String { isDev ? "TESS Dev" : "TESS" }

    /// Keychain service holding the API keys (and the older per-key items it migrates from).
    var keychainService: String { isDev ? Self.devBundleID : "app.tess.assistant" }

    /// Wake word on a fresh install. Different names keep the two apps from answering each other.
    var defaultWakeName: String { isDev ? "Dev" : "Tess" }

    /// The automatic morning briefing on the first unlock of the day.
    var briefingOnUnlockByDefault: Bool { !isDev }

    /// TESS Dev is updated by rebuilding it, never from GitHub.
    var checksForUpdates: Bool { !isDev }

    func supportDirectory(in applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent(supportFolderName, isDirectory: true)
    }

    /// The Git commit TESS Dev was built from (set by build.sh), if any.
    static var buildCommit: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "TESSCommit") as? String
        return value?.isEmpty == false ? value : nil
    }
}
