import AppKit
import ApplicationServices
import AVFoundation
import Contacts
import CoreGraphics
import EventKit
import Speech

enum PermissionKind: String, CaseIterable, Identifiable {
    case microphone, speech, screen, files, contacts, calendars, reminders, accessibility, automation
    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .speech: return "Speech Recognition"
        case .screen: return "Screen Recording"
        case .files: return "Files and Folders"
        case .contacts: return "Contacts"
        case .calendars: return "Calendars"
        case .reminders: return "Reminders"
        case .accessibility: return "Accessibility"
        case .automation: return "Automation"
        }
    }

    /// System Settings › Privacy & Security pane.
    var settingsPane: String {
        switch self {
        case .microphone: return "Privacy_Microphone"
        case .speech: return "Privacy_SpeechRecognition"
        case .screen: return "Privacy_ScreenCapture"
        case .files: return "Privacy_FilesAndFolders"
        case .contacts: return "Privacy_Contacts"
        case .calendars: return "Privacy_Calendars"
        case .reminders: return "Privacy_Reminders"
        case .accessibility: return "Privacy_Accessibility"
        case .automation: return "Privacy_Automation"
        }
    }

    /// These can only be switched on by the user in System Settings; macOS has no in-app "Allow" dialog for them.
    var needsSystemSettingsToggle: Bool { self == .screen || self == .accessibility }
}

enum PermissionState: Equatable {
    case granted
    case denied
    case notAsked
    case partial(String)

    var label: String {
        switch self {
        case .granted: return "Allowed"
        case .denied: return "Not allowed"
        case .notAsked: return "Not set up"
        case .partial(let detail): return detail
        }
    }
}

/// Checks and requests every macOS permission TESS uses.
@MainActor
final class PermissionCenter: ObservableObject {
    static let shared = PermissionCenter()

    @Published private(set) var states: [PermissionKind: PermissionState] = [:]
    @Published private(set) var busy = false
    @Published private(set) var progress = ""
    /// Screen Recording only takes effect after TESS restarts.
    @Published var needsRestart = false

    private var timer: Timer?
    nonisolated static let filesAskedKey = "filesPermissionAsked"
    private static let screenAskedKey = "screenPermissionAsked"

    /// Apps TESS sends Apple Events to.
    static let automationTargets: [(bundleID: String, name: String)] = [
        ("com.apple.systemevents", "System Events"),
        ("com.apple.finder", "Finder"),
        ("com.apple.Notes", "Notes"),
        ("com.apple.MobileSMS", "Messages"),
        ("com.apple.Music", "Music"),
        ("com.spotify.client", "Spotify"),
    ]

    var grantedCount: Int { PermissionKind.allCases.filter { states[$0] == .granted }.count }
    var allGranted: Bool { grantedCount == PermissionKind.allCases.count }

    // MARK: Live status

    func startMonitoring() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
            Task { @MainActor in PermissionCenter.shared.refresh() }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        var next = states
        next[.microphone] = Self.state(AVCaptureDevice.authorizationStatus(for: .audio))
        next[.speech] = {
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized:
                // Allowed, but TESS also needs the on-device model that comes with Dictation.
                let locale = UserDefaults.standard.string(forKey: "recognitionLocale") ?? "en-US"
                guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else {
                    return .partial("Dictation off")
                }
                return recognizer.supportsOnDeviceRecognition ? .granted : .partial("Model not downloaded")
            case .notDetermined: return .notAsked
            default: return .denied
            }
        }()
        if CGPreflightScreenCaptureAccess() {
            next[.screen] = .granted
        } else {
            // macOS only re-checks Screen Recording when TESS starts, so after switching it on TESS needs a restart.
            next[.screen] = UserDefaults.standard.bool(forKey: Self.screenAskedKey) ? .partial("Restart needed?") : .notAsked
        }
        next[.contacts] = {
            switch CNContactStore.authorizationStatus(for: .contacts) {
            case .authorized: return .granted
            case .notDetermined: return .notAsked
            default: return .denied
            }
        }()
        next[.calendars] = Self.state(EKEventStore.authorizationStatus(for: .event))
        next[.reminders] = Self.state(EKEventStore.authorizationStatus(for: .reminder))
        next[.accessibility] = AXIsProcessTrusted() ? .granted : .notAsked
        next[.files] = filesState()
        if next != states { states = next }

        Task {
            let automation = await Self.automationState()
            if self.states[.automation] != automation { self.states[.automation] = automation }
        }
    }

    private static func state(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    private static func state(_ status: EKAuthorizationStatus) -> PermissionState {
        switch status {
        case .fullAccess: return .granted
        case .notDetermined: return .notAsked
        case .writeOnly: return .partial("Add-only")
        default: return .denied
        }
    }

    private func filesState() -> PermissionState {
        guard UserDefaults.standard.bool(forKey: Self.filesAskedKey) else { return .notAsked }
        let readable = Self.userFolders.filter { (try? FileManager.default.contentsOfDirectory(atPath: $0.path)) != nil }
        if readable.count == Self.userFolders.count { return .granted }
        return readable.isEmpty ? .denied : .partial("\(readable.count) of \(Self.userFolders.count) folders")
    }

    private static var userFolders: [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return ["Desktop", "Documents", "Downloads"].map { home.appendingPathComponent($0) }
    }

    // MARK: Automation (Apple Events)

    /// -1744: not asked yet, -1743: denied, -600: app not running.
    nonisolated private static func automationStatus(_ bundleID: String, ask: Bool) -> OSStatus {
        var target = AEAddressDesc()
        let created = bundleID.withCString { pointer in
            AECreateDesc(typeApplicationBundleID, pointer, strlen(pointer), &target)
        }
        guard created == OSErr(noErr) else { return OSStatus(created) }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, ask)
    }

    nonisolated private static func installedTargets() -> [(bundleID: String, name: String)] {
        automationTargets.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    nonisolated private static func automationState() async -> PermissionState {
        await Task.detached(priority: .utility) {
            let targets = installedTargets()
            var granted = 0, denied = 0, notAsked = 0
            for target in targets {
                switch automationStatus(target.bundleID, ask: false) {
                case OSStatus(noErr): granted += 1
                case -1743: denied += 1
                case -1744: notAsked += 1
                default: break // -600: app isn't running, so macOS can't say yet
                }
            }
            if denied > 0 { return PermissionState.partial("\(denied) app\(denied == 1 ? "" : "s") blocked") }
            if notAsked > 0 { return granted == 0 ? PermissionState.notAsked : PermissionState.partial("\(granted) of \(granted + notAsked) apps") }
            // Everything macOS could check is allowed. If nothing could be checked, remember the last setup.
            if granted > 0 { return PermissionState.granted }
            return UserDefaults.standard.bool(forKey: "automationSetUp") ? PermissionState.granted : PermissionState.notAsked
        }.value
    }

    /// Opens each target quietly in the background if needed, then asks macOS for permission to control it.
    private func requestAutomation() async {
        var allAllowed = true
        for target in Self.installedTargets() {
            progress = "Asking to control \(target.name)…"
            let launched = await Self.launchHidden(target.bundleID)
            let result = await Task.detached { Self.automationStatus(target.bundleID, ask: true) }.value
            if result != OSStatus(noErr) { allAllowed = false }
            // Close apps that were only opened to ask the question.
            if launched {
                NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).forEach { $0.terminate() }
            }
        }
        UserDefaults.standard.set(allAllowed, forKey: "automationSetUp")
    }

    /// Returns true if the app had to be opened.
    nonisolated private static func launchHidden(_ bundleID: String) async -> Bool {
        let running = await MainActor.run {
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        }
        guard !running, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        return true
    }

    // MARK: Requesting

    /// Shows macOS's own prompt where possible; otherwise opens the right System Settings page.
    func request(_ kind: PermissionKind) async {
        busy = true
        defer {
            busy = false
            progress = ""
            refresh()
        }
        let current = states[kind] ?? .notAsked

        switch kind {
        case .microphone:
            if current == .notAsked { _ = await AVCaptureDevice.requestAccess(for: .audio) } else { openSettings(kind) }
        case .speech:
            if case .partial = current {
                // Allowed, but Dictation (and its on-device model) is off: that lives in Keyboard settings.
                if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            } else if current == .notAsked {
                _ = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                    SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
                }
            } else { openSettings(kind) }
        case .contacts:
            if current == .notAsked { _ = try? await CNContactStore().requestAccess(for: .contacts) } else { openSettings(kind) }
        case .calendars:
            if current == .notAsked { _ = try? await CalendarService.shared.store.requestFullAccessToEvents() } else { openSettings(kind) }
        case .reminders:
            if current == .notAsked { _ = try? await CalendarService.shared.store.requestFullAccessToReminders() } else { openSettings(kind) }
        case .files:
            if current == .notAsked {
                UserDefaults.standard.set(true, forKey: Self.filesAskedKey)
                for folder in Self.userFolders {
                    progress = "Asking for your \(folder.lastPathComponent) folder…"
                    _ = await Task.detached { try? FileManager.default.contentsOfDirectory(atPath: folder.path) }.value
                }
                if filesState() != .granted { openSettings(kind) }
            } else { openSettings(kind) }
        case .automation:
            await requestAutomation()
            if case .partial(let detail) = await Self.automationState(), detail.contains("blocked") { openSettings(kind) }
        case .screen:
            if !CGPreflightScreenCaptureAccess() {
                UserDefaults.standard.set(true, forKey: Self.screenAskedKey)
                _ = CGRequestScreenCaptureAccess()
                needsRestart = true
                openSettings(kind)
            }
        case .accessibility:
            if !AXIsProcessTrusted() {
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                openSettings(kind)
            }
        }
    }

    /// Walks through every permission that isn't granted yet.
    func requestAll() async {
        refresh()
        // Pop-up prompts first; the two that need a System Settings switch go last.
        let order: [PermissionKind] = [.microphone, .speech, .contacts, .calendars, .reminders, .files, .automation, .accessibility, .screen]
        for (index, kind) in order.enumerated() where states[kind] != .granted {
            progress = "\(index + 1) of \(order.count): \(kind.title)…"
            busy = true
            await request(kind)
            busy = true
            if kind.needsSystemSettingsToggle { break } // let the user flip the switch; they can press the button again
        }
        busy = false
        progress = ""
        refresh()
    }

    func openSettings(_ kind: PermissionKind) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(kind.settingsPane)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Quits and reopens TESS (needed after granting Screen Recording).
    func relaunch() {
        let path = Bundle.main.bundlePath.replacingOccurrences(of: "'", with: "'\\''")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; open '\(path)'"]
        try? process.run()
        NSApp.terminate(nil)
    }
}
