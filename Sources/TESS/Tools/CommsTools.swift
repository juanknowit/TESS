import Contacts
import Foundation

/// Messages (with a mandatory read-back before sending) and Apple Notes.
enum CommsTools {
    static func all() -> [Tool] {
        [draftMessage, sendMessage, createNote, appendToNote, searchNotes, readNote]
    }

    // MARK: Messages

    static let draftMessage = Tool(
        name: "draft_message",
        description: "Prepare an iMessage/SMS to a contact (by name, phone number or email). This does NOT send. Afterwards, read the recipient and message back to the user and ask them to confirm.",
        properties: [
            "to": P.string("Contact name, phone number or email"),
            "text": P.string("The message to send"),
        ],
        required: ["to", "text"]
    ) { args in
        guard let to = args.string("to"), let text = args["text"] as? String, !text.trimmed.isEmpty else {
            throw TESSError("I need a recipient and a message.")
        }
        let recipient = try await ContactResolver.resolve(to)
        let draft = await MessageDrafts.shared.add(handle: recipient.handle, name: recipient.name, text: text)
        return """
        Draft \(draft.id) ready (not sent). To: \(recipient.name) (\(recipient.handle)). Message: “\(text)”.
        Now read the recipient and message back and ask the user to confirm. Only after they say yes in their next reply, call send_message with draft_id \(draft.id).
        """
    }

    static let sendMessage = Tool(
        name: "send_message",
        description: "Send a message prepared with draft_message. Only call this after the user has explicitly confirmed the draft in a reply.",
        properties: ["draft_id": P.string("The id returned by draft_message")],
        required: ["draft_id"]
    ) { args in
        guard let id = args.string("draft_id") else { throw TESSError("Which draft?") }
        let draft = try await MessageDrafts.shared.takeConfirmed(id)
        let service = try await Shell.appleScript(sendScript(handle: draft.handle, text: draft.text))
        return "Sent to \(draft.name) via \(service.isEmpty ? "Messages" : service)."
    }

    static func sendScript(handle: String, text: String) -> String {
        let h = handle.appleScriptEscaped, t = text.appleScriptEscaped
        return """
        tell application "Messages"
            try
                set svc to 1st account whose service type = iMessage
                send "\(t)" to participant "\(h)" of svc
                return "iMessage"
            on error
                set svc to 1st account whose service type = SMS
                send "\(t)" to participant "\(h)" of svc
                return "SMS"
            end try
        end tell
        """
    }

    // MARK: Notes

    static let createNote = Tool(
        name: "create_note",
        description: "Create a new note in Apple Notes.",
        properties: [
            "title": P.string("Note title"),
            "body": P.string("Note text; use new lines for separate lines or list items"),
        ],
        required: ["title"]
    ) { args in
        guard let title = args.string("title") else { throw TESSError("What should the note be called?") }
        let body = args["body"] as? String ?? ""
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            line.isEmpty ? "<div><br></div>" : "<div>\(CommsTools.html(String(line)))</div>"
        }
        let markup = "<h1>\(CommsTools.html(title))</h1>" + lines.joined()
        try await Shell.appleScript("""
        tell application "Notes"
            make new note with properties {body:"\(markup.appleScriptEscaped)"}
        end tell
        """)
        return "Created the note “\(title)” in Notes."
    }

    static let appendToNote = Tool(
        name: "append_to_note",
        description: "Add text to the end of an existing Apple Note (e.g. add an item to a shopping list).",
        properties: [
            "title": P.string("The note's title, or part of it"),
            "text": P.string("Text to add; new lines become separate lines"),
        ],
        required: ["title", "text"]
    ) { args in
        guard let title = args.string("title"), let text = args["text"] as? String else { throw TESSError("Which note, and what should I add?") }
        let addition = text.split(separator: "\n").map { "<div>\(CommsTools.html(String($0)))</div>" }.joined()
        let result = try await Shell.appleScript("""
        tell application "Notes"
            set found to notes whose name contains "\(title.appleScriptEscaped)"
            if found is {} then return "NOT_FOUND"
            set n to item 1 of found
            set body of n to (body of n) & "\(addition.appleScriptEscaped)"
            return name of n
        end tell
        """)
        if result == "NOT_FOUND" { return "No note is called anything like “\(title)”. Offer to create it." }
        return "Added to “\(result)”."
    }

    static let searchNotes = Tool(
        name: "search_notes",
        description: "Find Apple Notes whose title or text contains the query. Returns titles and dates.",
        properties: ["query": P.string("Words to look for")],
        required: ["query"]
    ) { args in
        guard let query = args.string("query") else { throw TESSError("Search for what?") }
        let q = query.appleScriptEscaped
        let result = try await Shell.appleScript("""
        tell application "Notes"
            set found to notes whose name contains "\(q)" or plaintext contains "\(q)"
            set out to ""
            set counter to 0
            repeat with n in found
                set counter to counter + 1
                if counter > 10 then exit repeat
                set out to out & (name of n) & " — edited " & ((modification date of n) as string) & linefeed
            end repeat
            return out
        end tell
        """)
        return result.isEmpty ? "No notes mention \(query)." : result
    }

    static let readNote = Tool.rich(
        name: "read_note",
        description: "Read the text of an Apple Note by title.",
        properties: ["title": P.string("The note's title, or part of it")],
        required: ["title"]
    ) { args in
        guard let title = args.string("title") else { throw TESSError("Which note?") }
        let result = try await Shell.appleScript("""
        tell application "Notes"
            set found to notes whose name contains "\(title.appleScriptEscaped)"
            if found is {} then return "NOT_FOUND"
            set n to item 1 of found
            return (name of n) & linefeed & (plaintext of n)
        end tell
        """)
        if result == "NOT_FOUND" { return ToolOutput(text: "No note is called anything like “\(title)”.") }
        return ToolOutput(text: result, limit: 12_000)
    }

    static func html(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - Drafts that need the user's go-ahead

@MainActor
final class MessageDrafts {
    static let shared = MessageDrafts()

    struct Draft {
        let id: String
        let handle: String
        let name: String
        let text: String
        let turn: Int
    }

    private var drafts: [String: Draft] = [:]
    private var counter = 0

    func add(handle: String, name: String, text: String) -> Draft {
        counter += 1
        let draft = Draft(id: "d\(counter)", handle: handle, name: name, text: text, turn: Agent.currentTurn)
        drafts[draft.id] = draft
        return draft
    }

    /// Returns the draft only if the user has spoken since it was created (i.e. had a chance to confirm).
    func takeConfirmed(_ id: String) throws -> Draft {
        guard let draft = drafts[id] else { throw TESSError("There's no draft \(id). Make one with draft_message first.") }
        guard Agent.currentTurn > draft.turn else {
            throw TESSError("Not sent: the user hasn't confirmed yet. Read the draft back and wait for their answer.")
        }
        drafts[id] = nil
        return draft
    }
}

// MARK: - Contacts

enum ContactResolver {
    struct Recipient {
        let name: String
        let handle: String
    }

    static func resolve(_ query: String) async throws -> Recipient {
        let trimmed = query.trimmed
        let digits = trimmed.filter { $0.isNumber || $0 == "+" }
        if trimmed.contains("@") { return Recipient(name: trimmed, handle: trimmed) }
        if digits.count >= 6 && Double(digits.count) >= Double(trimmed.count) * 0.6 {
            return Recipient(name: trimmed, handle: digits)
        }

        let store = CNContactStore()
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            break
        case .notDetermined:
            guard (try? await store.requestAccess(for: .contacts)) == true else {
                throw TESSError("I need access to Contacts to find \(trimmed). Allow it in System Settings, Privacy and Security, Contacts.")
            }
        default:
            throw TESSError("I don't have access to Contacts. Allow TESS in System Settings, Privacy and Security, Contacts — or give me the number.")
        }

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactOrganizationNameKey,
            CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
        ].map { $0 as CNKeyDescriptor }
        let matches = try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: trimmed), keysToFetch: keys)
            .filter { !$0.phoneNumbers.isEmpty || !$0.emailAddresses.isEmpty }

        guard !matches.isEmpty else { throw TESSError("I couldn't find \(trimmed) in your contacts.") }

        func displayName(_ c: CNContact) -> String {
            let full = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            return full.isEmpty ? (c.organizationName.isEmpty ? trimmed : c.organizationName) : full
        }

        if matches.count > 1 {
            let exact = matches.filter { displayName($0).lowercased() == trimmed.lowercased() }
            if exact.count != 1 {
                let names = matches.prefix(5).map(displayName).joined(separator: ", ")
                throw TESSError("Several contacts match \(trimmed): \(names). Ask which one.")
            }
            return try recipient(exact[0], name: displayName(exact[0]))
        }
        return try recipient(matches[0], name: displayName(matches[0]))
    }

    private static func recipient(_ contact: CNContact, name: String) throws -> Recipient {
        let mobileLabels = [CNLabelPhoneNumberMobile, CNLabelPhoneNumberiPhone]
        if let mobile = contact.phoneNumbers.first(where: { mobileLabels.contains($0.label ?? "") }) {
            return Recipient(name: name, handle: mobile.value.stringValue)
        }
        if let phone = contact.phoneNumbers.first {
            return Recipient(name: name, handle: phone.value.stringValue)
        }
        if let email = contact.emailAddresses.first {
            return Recipient(name: name, handle: email.value as String)
        }
        throw TESSError("\(name) has no phone number or email in Contacts.")
    }
}
