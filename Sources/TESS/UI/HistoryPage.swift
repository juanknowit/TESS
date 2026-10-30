import AppKit
import SwiftUI

/// Settings › History: what you asked and what TESS answered.
struct HistoryPage: View {
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var ui = UIState.shared

    private static let shown = 150

    var body: some View {
        let results = history.search(ui.historySearch)

        PageHeader("History", "Your conversations with TESS, newest first. Kept only on this Mac.") {
            Toggle("", isOn: $history.enabled).themedSwitch().controlSize(.regular)
                .help(history.enabled ? "Keeping history" : "History is off")
        }

        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                TextField("Search history", text: $ui.historySearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.tile))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))

            Text("\(history.entries.count) of \(HistoryStore.limit) saved")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .fixedSize()
            if !history.entries.isEmpty {
                Button("Clear…") { ui.confirmClearHistory = true }
                    .buttonStyle(ThemedButtonStyle(kind: .destructive))
            }
        }
        .confirmationDialog("Delete all \(history.entries.count) conversations?", isPresented: $ui.confirmClearHistory) {
            Button("Delete all", role: .destructive) { history.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }

        if results.isEmpty {
            Card {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Theme.tertiary)
                    Text(history.entries.isEmpty ? "No conversations yet" : "Nothing matches “\(ui.historySearch)”")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                    if !history.enabled {
                        Text("History is switched off.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
            }
        } else {
            ForEach(Self.groups(Array(results.prefix(Self.shown))), id: \.title) { group in
                Card(group.title) {
                    ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { RowDivider() }
                        HistoryRow(entry: entry) { history.remove(entry.id) }
                    }
                }
            }
            if results.count > Self.shown {
                Text("Showing the newest \(Self.shown) of \(results.count). Search to find older ones.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }

    struct Group {
        let title: String
        let entries: [HistoryEntry]
    }

    static func groups(_ entries: [HistoryEntry]) -> [Group] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE d MMMM"
        var result: [Group] = []
        for entry in entries {
            let title: String
            if calendar.isDateInToday(entry.date) { title = "Today" }
            else if calendar.isDateInYesterday(entry.date) { title = "Yesterday" }
            else { title = formatter.string(from: entry.date) }
            if let last = result.last, last.title == title {
                result[result.count - 1] = Group(title: title, entries: last.entries + [entry])
            } else {
                result.append(Group(title: title, entries: [entry]))
            }
        }
        return result
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let delete: () -> Void

    private var time: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: entry.date)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(icon: entry.failed ? "exclamationmark.bubble" : "bubble.left.and.text.bubble.right",
                      tint: entry.failed ? Theme.orange : Theme.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.question)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                Text(entry.answer)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(time) · \(entry.provider)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(entry.question)\n\n\(entry.answer)", forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                    .help("Copy")
                Button(action: delete) { Image(systemName: "trash") }
                    .help("Delete")
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
