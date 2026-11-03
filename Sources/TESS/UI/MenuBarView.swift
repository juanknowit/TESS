import AppKit
import SwiftUI

struct MenuBarIcon: View {
    @ObservedObject var assistant: Assistant
    @ObservedObject private var storage = StorageAlerts.shared

    var body: some View {
        // While idle, a data-file problem shows as a warning so it's noticed without opening the menu.
        Image(systemName: assistant.phase == .idle && !storage.alerts.isEmpty
              ? "exclamationmark.triangle" : assistant.menuIcon)
    }
}

/// A problem with one of TESS's data files: "kept a copy" (dismissable) or "not saving" (until fixed).
struct StorageAlertRow: View {
    let alert: StorageAlerts.Alert

    private var appName: String { AppFlavor.current.appName }

    private var title: String {
        switch alert.kind {
        case .keptCopy: return "Couldn’t read your saved \(alert.label)"
        case .notSaving: return "Not saving your \(alert.label)"
        }
    }

    private var detail: String {
        switch alert.kind {
        case .keptCopy(let backup):
            return "\(appName) kept it as \(backup.lastPathComponent) and started fresh."
        case .notSaving:
            let text = "\(appName) can’t read \(alert.file.lastPathComponent) or move it aside, so she won’t save over it. Changes made now are lost when you quit."
            return alert.retryFailed ? text + " Still couldn’t move it." : text
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button("Show in Finder") {
                    if case .keptCopy(let backup) = alert.kind {
                        NSWorkspace.shared.activateFileViewerSelecting([backup])
                    } else {
                        NSWorkspace.shared.activateFileViewerSelecting([alert.file])
                    }
                }
                switch alert.kind {
                case .keptCopy: Button("Dismiss") { StorageAlerts.shared.dismiss(alert.id) }
                case .notSaving: Button("Try again") { StorageAlerts.shared.retry(alert.id) }
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct MenuBarView: View {
    @EnvironmentObject var assistant: Assistant
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var meter: LevelMeter
    @ObservedObject private var ui = UIState.shared
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var updater = Updater.shared
    @ObservedObject private var storage = StorageAlerts.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                OrbView(phase: assistant.phase, level: meter.level)
                    .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppFlavor.current.appName).font(.headline)
                    Text(assistant.statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer()
            }

            if !assistant.heard.isEmpty || !assistant.reply.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !assistant.heard.isEmpty {
                        Text("“\(assistant.heard)”").italic()
                    }
                    if !assistant.reply.isEmpty {
                        Text(assistant.reply).foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }

            ForEach(storage.alerts) { alert in
                StorageAlertRow(alert: alert)
            }

            if let release = updater.latest {
                Button { UpdateWindow.shared.show() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
                        Text("TESS \(release.version.displayName) is available")
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text("Update…").font(.callout).foregroundStyle(Color.accentColor)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            if history.enabled && !history.entries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Recent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Button("History…") {
                            SettingsWindow.shared.show(settings: settings, assistant: assistant, pane: .history)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                    ForEach(Array(history.entries.suffix(3).reversed())) { entry in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.question).font(.caption.weight(.medium)).lineLimit(1)
                            Text(entry.answer).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            TextField("Type to TESS…", text: $ui.typed)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    assistant.submitTyped(ui.typed)
                    ui.typed = ""
                }

            HStack {
                Button { assistant.talkNow() } label: { Label("Talk now", systemImage: "mic.fill") }
                Button { assistant.togglePaused() } label: {
                    Label(assistant.isPaused ? "Resume" : "Pause",
                          systemImage: assistant.isPaused ? "play.fill" : "pause.fill")
                }
                Spacer()
                Button("New chat") { assistant.newConversation() }
            }

            Divider()

            HStack {
                Text("\(settings.provider.shortName) · \(settings.activeModel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Skills") { SettingsWindow.shared.show(settings: settings, assistant: assistant, pane: .skills) }
                Button("Settings…") { SettingsWindow.shared.show(settings: settings, assistant: assistant) }
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 340)
    }
}

/// View-local UI state, kept in an ObservableObject so the app builds with the Command Line Tools
/// (on recent SDKs `@State` is a macro whose plugin ships only with full Xcode).
final class UIState: ObservableObject {
    static let shared = UIState()
    @Published var typed = ""
    @Published var launchAtLogin = false
    @Published var testResult = ""
    @Published var testing = false
    @Published var ollamaModels: [String] = []
    @Published var ollamaMessage = ""
    @Published var ollamaChecking = false
    @Published var permissionsRefresh = 0
    @Published var settingsPane: SettingsPane = .general
    @Published var settingsSearch = ""
    @Published var collapsedSections: Set<String> = []
    @Published var usageRange: UsageRange = .week
    @Published var newMemory = ""
    @Published var confirmClearMemories = false
    @Published var confirmResetUsage = false
    @Published var skillsSearch = ""
    @Published var historySearch = ""
    @Published var confirmClearHistory = false
}
