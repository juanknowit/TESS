import AppKit
import SwiftUI

// MARK: - Settings › Updates

struct UpdatesPage: View {
    @ObservedObject private var updater = Updater.shared

    private var lastChecked: String {
        guard let date = updater.lastChecked else { return "Never checked" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = Date().timeIntervalSince(date) < 60 ? "just now" : formatter.localizedString(for: date, relativeTo: Date())
        return "Last checked \(relative)"
    }

    var body: some View {
        if AppFlavor.current.isDev {
            devBody
        } else {
            releaseBody
        }
    }

    /// TESS Dev never updates itself: it's rebuilt from source.
    @ViewBuilder private var devBody: some View {
        PageHeader("Updates", "This is TESS Dev, a development build. It doesn't check GitHub for updates.")
        Card {
            SettingRow("hammer", "TESS Dev \(updater.currentVersion.displayName)",
                       subtitle: "Build \(updater.currentBuild)" + (AppFlavor.buildCommit.map { " from commit \($0)" } ?? "")
                           + ". To update it, run Build TESS.command. Your everyday TESS updates itself from GitHub.",
                       tint: Theme.orange) {
                EmptyView()
            }
        }
    }

    @ViewBuilder private var releaseBody: some View {
        PageHeader("Updates", "TESS checks GitHub for new versions and installs them for you.") {
            Button {
                Task { await updater.check(userInitiated: true) }
            } label: {
                Label("Check for updates", systemImage: "arrow.clockwise")
            }
            .buttonStyle(ThemedButtonStyle(kind: .primary))
            .disabled(updater.isBusy)
        }

        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("TESS \(updater.currentVersion.displayName)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.text)
                    if updater.currentVersion.isPrerelease {
                        Pill(text: "Beta", tint: Theme.orange)
                    }
                }
                Text("Build \(updater.currentBuild)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                Text(lastChecked)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiary)
            }
            Spacer()
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(colors: [Theme.card, Color(hex: 0x14243A)], startPoint: .leading, endPoint: .trailing)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))

        Card {
            UpdateStatusView()
                .padding(16)
        }

        Card("Preferences") {
            SettingRow("arrow.triangle.2.circlepath", "Check automatically",
                       subtitle: "Shortly after TESS starts and every few hours. Nothing is installed without asking you.") {
                Toggle("", isOn: $updater.automaticChecks).themedSwitch()
            }
            RowDivider()
            SettingRow("testtube.2", "Include beta versions",
                       subtitle: "Get new features early. Betas may have rough edges.", tint: Theme.orange) {
                Toggle("", isOn: $updater.includeBetas).themedSwitch()
            }
        }

        Card("About updates") {
            SettingRow("checkmark.shield", "Safe by design",
                       subtitle: "An update is only installed if it matches its published checksum and is signed with the same certificate as this copy of TESS. Settings, memory, history and permissions are kept.",
                       tint: Theme.green) {
                EmptyView()
            }
            RowDivider()
            SettingRow("safari", "All releases", subtitle: "Release notes and downloads on GitHub") {
                Button("Open") { NSWorkspace.shared.open(Updater.releasesPage) }
                    .buttonStyle(ThemedButtonStyle())
            }
        }
    }
}

// MARK: - Status (shared by the Settings page and the update window)

struct UpdateStatusView: View {
    @ObservedObject private var updater = Updater.shared
    var showNotes = true

    var body: some View {
        switch updater.phase {
        case .idle:
            status("arrow.down.circle", "Press Check for updates to look for a new version.", Theme.secondary)
        case .checking:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Checking for updates…").font(.system(size: 13)).foregroundStyle(Theme.text)
                Spacer()
            }
        case .upToDate:
            status("checkmark.circle.fill", "You're up to date. TESS \(updater.currentVersion.displayName) is the newest version.", Theme.green)
        case .available(let release):
            available(release)
        case .downloading(let release, let fraction):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Downloading TESS \(release.version.displayName)…")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                    Spacer()
                    Text("\(Int(fraction * 100))%")
                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.secondary)
                }
                ProgressView(value: fraction).tint(Theme.accent)
            }
        case .installing(let release):
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Installing TESS \(release.version.displayName). TESS will restart in a moment…")
                    .font(.system(size: 13)).foregroundStyle(Theme.text)
                Spacer()
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                status("exclamationmark.triangle.fill", message, Theme.orange)
                HStack(spacing: 8) {
                    if let release = updater.latest {
                        Button("Try again") { Task { await updater.install(release) } }
                            .buttonStyle(ThemedButtonStyle(kind: .primary))
                        Button("Download from GitHub") { NSWorkspace.shared.open(release.page) }
                            .buttonStyle(ThemedButtonStyle())
                    } else {
                        Button("Try again") { Task { await updater.check(userInitiated: true) } }
                            .buttonStyle(ThemedButtonStyle())
                    }
                }
            }
        }
    }

    private func status(_ icon: String, _ text: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).font(.system(size: 15))
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func available(_ release: Updater.Release) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Pill(text: "New", tint: Theme.cyan)
                Text("TESS \(release.version.displayName) is available")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                if release.dmgSize > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(release.dmgSize), countStyle: .file))
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
            }
            if showNotes && !release.notes.trimmed.isEmpty {
                ScrollView {
                    ReleaseNotesView(notes: release.notes)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.field.opacity(0.7)))
            }
            HStack(spacing: 8) {
                Button("Install and Relaunch") { Task { await updater.install(release) } }
                    .buttonStyle(ThemedButtonStyle(kind: .primary))
                Button("Release notes") { NSWorkspace.shared.open(release.page) }
                    .buttonStyle(ThemedButtonStyle())
                Spacer()
                Button("Skip this version") { updater.skip(release) }
                    .buttonStyle(ThemedButtonStyle())
            }
        }
    }
}

/// Renders the bits of Markdown GitHub release notes use: headings, bullets, bold and links.
struct ReleaseNotesView: View {
    let notes: String

    private var lines: [String] {
        var text = notes.replacingOccurrences(of: "\r\n", with: "\n")
        // The install instructions at the end are for new users, not for updating.
        if let range = text.range(of: "\n## Install") { text = String(text[..<range.lowerBound]) }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                row(line)
            }
        }
    }

    @ViewBuilder
    private func row(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") {
            Text(trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.text)
                .padding(.top, 6)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 6) {
                Text("•").foregroundStyle(Theme.cyan)
                Text(Self.inline(String(trimmed.dropFirst(2))))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 12))
        } else if !trimmed.isEmpty {
            Text(Self.inline(trimmed))
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

// MARK: - Update window

/// The "A new version of TESS is available" prompt.
@MainActor
final class UpdateWindow {
    static let shared = UpdateWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: UpdatePromptView())
            host.sizingOptions = .preferredContentSize
            let w = NSWindow(contentViewController: host)
            w.title = "Software Update"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = NSColor(red: 0.055, green: 0.055, blue: 0.086, alpha: 1)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}

private struct UpdatePromptView: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.text)
                if let release = updater.latest {
                    Text("TESS \(release.version.displayName) is available. You have \(updater.currentVersion.displayName). Your settings, memory and permissions are kept.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                switch updater.phase {
                case .available(let release):
                    if !release.notes.trimmed.isEmpty {
                        Text("What's new")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        ScrollView {
                            ReleaseNotesView(notes: release.notes)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 200)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.field))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                    }
                    HStack(spacing: 8) {
                        Button("Skip This Version") { updater.skip(release) }
                            .buttonStyle(ThemedButtonStyle())
                        Spacer()
                        Button("Remind Me Later") { updater.remindLater() }
                            .buttonStyle(ThemedButtonStyle())
                        Button("Install and Relaunch") { Task { await updater.install(release) } }
                            .buttonStyle(ThemedButtonStyle(kind: .primary))
                            .keyboardShortcut(.defaultAction)
                    }
                    .padding(.top, 4)
                default:
                    UpdateStatusView(showNotes: false)
                    HStack {
                        Spacer()
                        Button("Close") { updater.remindLater() }
                            .buttonStyle(ThemedButtonStyle())
                            .disabled(updater.isBusy)
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 30)
        .padding(.bottom, 20)
        .frame(width: 560)
        .background(Theme.window)
        .preferredColorScheme(.dark)
    }

    private var title: String {
        switch updater.phase {
        case .downloading, .installing: return "Updating TESS"
        case .upToDate: return "TESS is up to date"
        default: return "A new version of TESS is available"
        }
    }
}
