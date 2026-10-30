import AppKit
import ApplicationServices

/// "Type for me": inserts text wherever the user's cursor is.
enum TypingTools {
    static func all() -> [Tool] { [typeText] }

    static let typeText = Tool(
        name: "type_text",
        description: "Type text into the app the user is working in, at their cursor (e.g. write a reply, fill a field, draft an email body). Compose the full text yourself first. Doesn't press Return or send anything. Afterwards just confirm briefly; don't read the whole text aloud.",
        properties: ["text": P.string("The exact text to insert")],
        required: ["text"]
    ) { args in
        guard let text = args["text"] as? String, !text.isEmpty else { throw TESSError("What should I type?") }
        let app = try await Typist.insert(text)
        return "Typed \(text.count) characters into \(app)."
    }
}

@MainActor
enum Typist {
    /// Pastes the text into the frontmost app, then restores the user's clipboard. Returns the app's name.
    static func insert(_ text: String) async throws -> String {
        guard AXIsProcessTrusted() else {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            throw TESSError("To type for you I need Accessibility permission. Allow TESS in System Settings, Privacy and Security, Accessibility, then try again.")
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw TESSError("Click where you want the text first, then ask me again.")
        }

        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        try await Task.sleep(nanoseconds: 60_000_000)

        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9 // "V" on QWERTY-family layouts
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        // Give the app time to read the clipboard before putting the user's back.
        try await Task.sleep(nanoseconds: 500_000_000)
        restore(saved, to: pasteboard)
        return app.localizedName ?? "the front app"
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { copy[type] = data }
            }
            return copy
        }
    }

    private static func restore(_ items: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored: [NSPasteboardItem] = items.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
