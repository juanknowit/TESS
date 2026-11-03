import AppKit
import SwiftUI

// Notices for TESS's data files that couldn't be read (see StorageAlerts).
// The same notice shows in the menu bar and on the matching Settings page; dismissing either clears both.

extension StorageAlerts.Alert {
    var title: String {
        switch kind {
        case .keptCopy: return "Couldn’t read your saved \(label)"
        case .notSaving: return "Not saving your \(label)"
        }
    }

    var detail: String {
        let app = AppFlavor.current.appName
        switch kind {
        case .keptCopy(let backup):
            return "\(app) kept it as \(backup.lastPathComponent) and started fresh."
        case .notSaving:
            let text = "\(app) can’t read \(file.lastPathComponent) or move it aside, so she won’t save over it. Changes made now are lost when you quit."
            return retryFailed ? text + " Still couldn’t move it." : text
        }
    }

    func showInFinder() {
        if case .keptCopy(let backup) = kind {
            NSWorkspace.shared.activateFileViewerSelecting([backup])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        }
    }
}

/// Menu bar version.
struct StorageAlertRow: View {
    let alert: StorageAlerts.Alert

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title).font(.callout.weight(.medium))
                    Text(alert.detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button("Show in Finder") { alert.showInFinder() }
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

/// Settings page version: shows the notice for one data file, e.g. `StorageNotice(file: "memory.json")`,
/// and nothing when that file is fine.
struct StorageNotice: View {
    let file: String
    @ObservedObject private var storage = StorageAlerts.shared

    var body: some View {
        if let alert = storage.alerts.first(where: { $0.file.lastPathComponent == file }) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.orange)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.orange.opacity(0.16)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(alert.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(alert.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    Button("Show in Finder") { alert.showInFinder() }
                        .buttonStyle(ThemedButtonStyle())
                    switch alert.kind {
                    case .keptCopy:
                        Button("Dismiss") { storage.dismiss(alert.id) }
                            .buttonStyle(ThemedButtonStyle())
                    case .notSaving:
                        Button("Try again") { storage.retry(alert.id) }
                            .buttonStyle(ThemedButtonStyle(kind: .primary))
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.orange.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.orange.opacity(0.35), lineWidth: 1))
        }
    }
}
