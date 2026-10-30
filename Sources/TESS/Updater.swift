import AppKit
import CryptoKit
import Foundation
import Security

/// A semantic version such as 0.9.1, 0.9.1-beta or 1.0.0-rc.2.
struct AppVersion: Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: [String]

    init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        text = text.replacingOccurrences(of: " ", with: "-")
        let parts = text.split(separator: "-", maxSplits: 1).map(String.init)
        let numbers = parts.first?.split(separator: ".").map { Int($0) } ?? []
        guard (1...3).contains(numbers.count), numbers.allSatisfy({ $0 != nil }) else { return nil }
        major = numbers[0]!
        minor = numbers.count > 1 ? numbers[1]! : 0
        patch = numbers.count > 2 ? numbers[2]! : 0
        prerelease = parts.count > 1 ? parts[1].split(separator: ".").map(String.init) : []
    }

    var isPrerelease: Bool { !prerelease.isEmpty }

    /// "0.9.1-beta"
    var description: String {
        "\(major).\(minor).\(patch)" + (prerelease.isEmpty ? "" : "-" + prerelease.joined(separator: "."))
    }

    /// "0.9.1 beta"
    var displayName: String {
        "\(major).\(minor).\(patch)" + (prerelease.isEmpty ? "" : " " + prerelease.joined(separator: " "))
    }

    static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }

    static func < (a: AppVersion, b: AppVersion) -> Bool {
        if a.major != b.major { return a.major < b.major }
        if a.minor != b.minor { return a.minor < b.minor }
        if a.patch != b.patch { return a.patch < b.patch }
        // A release is newer than its pre-releases: 1.0.0-beta < 1.0.0.
        if a.prerelease.isEmpty || b.prerelease.isEmpty { return !a.prerelease.isEmpty && b.prerelease.isEmpty }
        for (x, y) in zip(a.prerelease, b.prerelease) where x != y {
            switch (Int(x), Int(y)) {
            case let (i?, j?): return i < j
            case (_?, nil): return true
            case (nil, _?): return false
            default: return x < y
            }
        }
        return a.prerelease.count < b.prerelease.count
    }

    /// The version of the running app.
    static var current: AppVersion {
        let info = Bundle.main.infoDictionary ?? [:]
        let candidates = [info["TESSVersion"], info["TESSDisplayVersion"], info["CFBundleShortVersionString"]]
        for case let value as String in candidates {
            if let version = AppVersion(value) { return version }
        }
        return AppVersion("0.0.0")!
    }
}

/// Checks GitHub for new TESS releases and installs them.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    static let repository = "juanknowit/TESS"
    static let releasesPage = URL(string: "https://github.com/\(repository)/releases")!

    struct Release: Equatable {
        let version: AppVersion
        let tag: String
        let name: String
        let notes: String
        let page: URL
        let dmg: URL
        let dmgName: String
        let dmgSize: Int
        let checksums: URL?
        let date: Date?
        let isPrerelease: Bool

        static func == (a: Release, b: Release) -> Bool { a.tag == b.tag }
    }

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(Release, Double)
        case installing(Release)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastChecked: Date? = UserDefaults.standard.object(forKey: Keys.lastChecked) as? Date
    /// The newest release found, even while it is downloading or installing.
    @Published private(set) var latest: Release?

    @Published var automaticChecks: Bool = UserDefaults.standard.object(forKey: Keys.automatic) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(automaticChecks, forKey: Keys.automatic)
            scheduleChecks()
        }
    }

    /// Include pre-releases (betas). On by default while you're running a beta.
    @Published var includeBetas: Bool = UserDefaults.standard.object(forKey: Keys.betas) as? Bool ?? AppVersion.current.isPrerelease {
        didSet { UserDefaults.standard.set(includeBetas, forKey: Keys.betas) }
    }

    private var skippedVersion: String? {
        get { UserDefaults.standard.string(forKey: Keys.skipped) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.skipped) }
    }

    private enum Keys {
        static let lastChecked = "updateLastChecked"
        static let automatic = "updateAutomaticChecks"
        static let betas = "updateIncludeBetas"
        static let skipped = "updateSkippedVersion"
    }

    private var timer: Timer?
    private static let interval: TimeInterval = 6 * 60 * 60

    var currentVersion: AppVersion { AppVersion.current }

    var currentBuild: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–" }

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    // MARK: Checking

    /// Starts checking in the background: shortly after launch and then every few hours.
    func start() {
        scheduleChecks()
        guard automaticChecks else { return }
        Task {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            await check(userInitiated: false)
        }
    }

    private func scheduleChecks() {
        timer?.invalidate()
        timer = nil
        guard automaticChecks else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { _ in
            Task { @MainActor in await Updater.shared.check(userInitiated: false) }
        }
    }

    /// Looks for a newer release. Automatic checks only prompt for versions you haven't skipped.
    func check(userInitiated: Bool) async {
        guard !isBusy else { return }
        phase = .checking
        do {
            let release = try await Self.newestRelease(includeBetas: includeBetas)
            lastChecked = Date()
            UserDefaults.standard.set(lastChecked, forKey: Keys.lastChecked)
            guard let release, release.version > currentVersion else {
                latest = nil
                phase = .upToDate
                return
            }
            latest = release
            phase = .available(release)
            if !userInitiated && skippedVersion != release.version.description {
                UpdateWindow.shared.show()
            }
        } catch {
            phase = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    func skip(_ release: Release) {
        skippedVersion = release.version.description
        UpdateWindow.shared.close()
    }

    func remindLater() {
        UpdateWindow.shared.close()
    }

    private static func newestRelease(includeBetas: Bool) async throws -> Release? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=20")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TESS/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 403 || status == 429 { throw TESSError("GitHub is busy right now. Try again in a few minutes.") }
        guard status == 200 else { throw TESSError("GitHub didn't answer (HTTP \(status)).") }
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw TESSError("GitHub sent something unexpected.")
        }

        let dates = ISO8601DateFormatter()
        var best: Release?
        for item in list {
            if item["draft"] as? Bool == true { continue }
            let prerelease = item["prerelease"] as? Bool ?? false
            if prerelease && !includeBetas { continue }
            guard let tag = item["tag_name"] as? String, let version = AppVersion(tag) else { continue }
            let assets = item["assets"] as? [[String: Any]] ?? []
            guard let dmg = assets.first(where: { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }),
                  let dmgURL = (dmg["browser_download_url"] as? String).flatMap(URL.init(string:)) else { continue }
            let sums = assets.first { ($0["name"] as? String) == "SHA256SUMS.txt" }
            let release = Release(
                version: version,
                tag: tag,
                name: item["name"] as? String ?? "TESS \(version.displayName)",
                notes: item["body"] as? String ?? "",
                page: (item["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPage,
                dmg: dmgURL,
                dmgName: dmg["name"] as? String ?? dmgURL.lastPathComponent,
                dmgSize: dmg["size"] as? Int ?? 0,
                checksums: (sums?["browser_download_url"] as? String).flatMap(URL.init(string:)),
                date: (item["published_at"] as? String).flatMap(dates.date(from:)),
                isPrerelease: prerelease)
            if best == nil || release.version > best!.version { best = release }
        }
        return best
    }

    // MARK: Installing

    /// Downloads the release, checks it, swaps it into place and relaunches TESS.
    func install(_ release: Release) async {
        guard !isBusy else { return }
        phase = .downloading(release, 0)
        do {
            let dmg = try await download(release) { fraction in
                Task { @MainActor in
                    let updater = Updater.shared
                    if case .downloading = updater.phase { updater.phase = .downloading(release, fraction) }
                }
            }
            phase = .installing(release)
            try await verifyChecksum(of: dmg, release: release)
            try await installFromDiskImage(dmg, release: release)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func download(_ release: Release, progress: @escaping (Double) -> Void) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TESS-update-\(release.version)", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(release.dmgName)
        let delegate = DownloadDelegate(destination: destination, progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            session.downloadTask(with: release.dmg).resume()
        }
    }

    private func verifyChecksum(of file: URL, release: Release) async throws {
        guard let checksums = release.checksums else { return }
        let (data, _) = try await URLSession.shared.data(from: checksums)
        let list = String(decoding: data, as: UTF8.self)
        guard let line = list.split(separator: "\n").first(where: { $0.hasSuffix(release.dmgName) }),
              let expected = line.split(separator: " ").first.map({ String($0).lowercased() }) else {
            throw TESSError("The release has no checksum for \(release.dmgName).")
        }
        let actual = try await Task.detached(priority: .userInitiated) { () throws -> String in
            let digest = SHA256.hash(data: try Data(contentsOf: file, options: .mappedIfSafe))
            return digest.map { String(format: "%02x", $0) }.joined()
        }.value
        guard actual == expected else { throw TESSError("The download was damaged (checksum mismatch). Please try again.") }
    }

    private func installFromDiskImage(_ dmg: URL, release: Release) async throws {
        let current = Bundle.main.bundleURL
        let folder = current.deletingLastPathComponent()

        // Not somewhere TESS can write (or running from the disk image): let the user drag it over.
        if current.path.contains("/AppTranslocation/") || current.path.hasPrefix("/Volumes/")
            || !FileManager.default.isWritableFile(atPath: folder.path) {
            NSWorkspace.shared.open(dmg)
            throw TESSError("TESS can't replace itself in \(folder.path). The installer is open: drag TESS onto Applications to update.")
        }

        let mount = try await Self.attach(dmg)
        defer { Task.detached { try? await Shell.run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"]) } }

        guard let newApp = try FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            throw TESSError("The installer doesn't contain TESS.")
        }
        guard Bundle(url: newApp)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw TESSError("The installer contains a different app.")
        }
        guard Self.isSignedLikeThisApp(newApp) else {
            // Typically a locally built TESS updating to a release: the signatures differ, so let the user decide.
            NSWorkspace.shared.open(dmg)
            throw TESSError("This copy of TESS is signed differently from the release (for example, because you built it yourself). The installer is open: drag TESS onto Applications to update. macOS will ask for permissions again once.")
        }

        // Copy next to the current app first, so the final swap is a quick rename on the same disk.
        let staged = folder.appendingPathComponent(".TESS-\(release.version).app")
        try? FileManager.default.removeItem(at: staged)
        try await Shell.run("/usr/bin/ditto", [newApp.path, staged.path])

        try Self.relaunch(replacing: current, with: staged)
    }

    private static func attach(_ dmg: URL) async throws -> URL {
        let output = try await Shell.run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-plist"])
        guard let data = output.data(using: .utf8),
              let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let path = entities.compactMap({ $0["mount-point"] as? String }).first else {
            throw TESSError("Couldn't open the installer disk image.")
        }
        return URL(fileURLWithPath: path)
    }

    /// True when the new app satisfies this app's designated requirement, i.e. it's signed with the same certificate.
    /// That's also what keeps macOS permissions working after the update.
    nonisolated static func isSignedLikeThisApp(_ app: URL) -> Bool {
        var me: SecCode?
        var meStatic: SecStaticCode?
        var requirement: SecRequirement?
        var candidate: SecStaticCode?
        guard SecCodeCopySelf(SecCSFlags(), &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, SecCSFlags(), &meStatic) == errSecSuccess, let meStatic,
              SecCodeCopyDesignatedRequirement(meStatic, SecCSFlags(), &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(app as CFURL, SecCSFlags(), &candidate) == errSecSuccess, let candidate else {
            return false
        }
        // Ad-hoc builds have a requirement that only matches themselves, so they never auto-update.
        let checkAllArchitectures = SecCSFlags(rawValue: 1 << 0)
        return SecStaticCodeCheckValidity(candidate, checkAllArchitectures, requirement) == errSecSuccess
    }

    /// Hands over to a small script that waits for TESS to quit, swaps the apps and opens the new one.
    private static func relaunch(replacing current: URL, with staged: URL) throws {
        let backup = current.deletingLastPathComponent().appendingPathComponent(".TESS-previous.app")
        let script = """
        #!/bin/sh
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(backup.path)"
        if mv "\(current.path)" "\(backup.path)"; then
          if mv "\(staged.path)" "\(current.path)"; then
            rm -rf "\(backup.path)"
          else
            mv "\(backup.path)" "\(current.path)"
          fi
        fi
        xattr -dr com.apple.quarantine "\(current.path)" 2>/dev/null
        open "\(current.path)"
        rm -f "$0"
        """
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("tess-update-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path]
        try process.run()
        NSApp.terminate(nil)
    }
}

/// Reports download progress and moves the finished file somewhere that outlives the callback.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let destination: URL
    let progress: (Double) -> Void
    var continuation: CheckedContinuation<URL, Error>?
    private let lock = NSLock()

    init(destination: URL, progress: @escaping (Double) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        guard status == 200 else {
            finish(.failure(TESSError("The download failed (HTTP \(status)).")))
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
}
