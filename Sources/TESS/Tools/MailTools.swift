import Foundation

/// Apple Mail: check, search and read mail, and send emails only after the user confirms a read-back.
enum MailTools {
    static func all() -> [Tool] { [checkMail, readEmail, draftEmail, sendEmail] }

    static let checkMail = Tool.rich(
        name: "check_mail",
        description: "List recent emails from the Apple Mail inbox, newest first. Filter by unread, by sender or subject text, and by how many days back. Returns ids to use with read_email or as reply_to_id.",
        properties: [
            "query": P.string("Optional text to match in the sender or subject, e.g. 'Maria' or 'invoice'"),
            "unread_only": P.boolean("Only unread emails (default false)"),
            "days": P.integer("How many days back to look (default 7, max 60)"),
            "count": P.integer("Maximum emails to list (default 10, max 30)"),
        ]
    ) { args in
        let days = max(1, min(60, args.int("days") ?? 7))
        let count = max(1, min(30, args.int("count") ?? 10))
        var conditions = ["date received > ((current date) - \(days) * days)"]
        if args.bool("unread_only") == true { conditions.append("read status is false") }
        if let query = args.string("query")?.appleScriptEscaped {
            conditions.append("(sender contains \"\(query)\" or subject contains \"\(query)\")")
        }
        let script = """
        tell application "Mail"
            set found to (messages of inbox whose \(conditions.joined(separator: " and ")))
            set out to ""
            repeat with m in found
                set secondsAgo to ((current date) - (date received of m)) as integer
                set flag to "read"
                if read status of m is false then set flag to "unread"
                set out to out & (id of m) & tab & secondsAgo & tab & flag & tab & (sender of m) & tab & (subject of m) & linefeed
            end repeat
            return out
        end tell
        """
        let raw = try await Shell.appleScript(script)
        struct Row { let id: String; let ago: Int; let flag: String; let sender: String; let subject: String }
        let rows: [Row] = raw.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
            guard f.count == 5 else { return nil }
            return Row(id: f[0], ago: Int(f[1]) ?? 0, flag: f[2], sender: f[3], subject: f[4])
        }.sorted { $0.ago < $1.ago }
        guard !rows.isEmpty else {
            return ToolOutput(text: "No matching emails in the last \(days) day\(days == 1 ? "" : "s").")
        }
        let lines = rows.prefix(count).map { r in
            "- id \(r.id) · \(agoText(r.ago)) · \(r.flag) · from \(cleanSender(r.sender)) · “\(r.subject)”"
        }
        let more = rows.count > count ? "\n(\(rows.count - count) more not shown)" : ""
        return ToolOutput(text: "\(rows.count) email\(rows.count == 1 ? "" : "s") found:\n" + lines.joined(separator: "\n") + more,
                          limit: 8000)
    }

    static let readEmail = Tool.rich(
        name: "read_email",
        description: "Read one email's full text by the id from check_mail.",
        properties: ["id": P.string("The email id from check_mail")],
        required: ["id"]
    ) { args in
        guard let id = args.string("id"), Int(id) != nil else { throw TESSError("I need the email's id from check_mail.") }
        let script = """
        tell application "Mail"
            set found to (messages of inbox whose id is \(id))
            if found is {} then return "NOT_FOUND"
            set m to item 1 of found
            set read status of m to true
            return "From: " & (sender of m) & linefeed & "Subject: " & (subject of m) & linefeed & "Received: " & ((date received of m) as string) & linefeed & linefeed & (content of m)
        end tell
        """
        let text = try await Shell.appleScript(script)
        if text == "NOT_FOUND" { return ToolOutput(text: "That email isn't in the inbox any more.") }
        return ToolOutput(text: text, limit: 14_000)
    }

    static let draftEmail = Tool(
        name: "draft_email",
        description: "Prepare an email (new, or a reply when reply_to_id is given). This does NOT send. Afterwards read the recipient, subject and a short summary of the body back to the user and ask them to confirm.",
        properties: [
            "to": P.string("Recipient name or email address (not needed for replies)"),
            "subject": P.string("Subject (not needed for replies)"),
            "body": P.string("The full email text, written in the user's voice"),
            "reply_to_id": P.string("Optional id of the email being replied to, from check_mail"),
        ],
        required: ["body"]
    ) { args in
        guard let body = args["body"] as? String, !body.trimmed.isEmpty else { throw TESSError("What should the email say?") }
        let replyID = args.string("reply_to_id")
        if let replyID, Int(replyID) == nil { throw TESSError("reply_to_id must be an id from check_mail.") }

        var toName = "", toAddress = ""
        if replyID == nil {
            guard let to = args.string("to") else { throw TESSError("Who should the email go to?") }
            let recipient = try await ContactResolver.resolve(to, preferEmail: true)
            guard recipient.handle.contains("@") else { throw TESSError("I couldn't find an email address for \(to).") }
            toName = recipient.name
            toAddress = recipient.handle
        } else {
            let sender = (try? await Shell.appleScript("""
            tell application "Mail"
                set found to (messages of inbox whose id is \(replyID!))
                if found is {} then return ""
                return sender of (item 1 of found)
            end tell
            """)) ?? ""
            guard !sender.isEmpty else { throw TESSError("I couldn't find the email to reply to.") }
            toName = cleanSender(sender)
            toAddress = sender
        }
        let subject = args.string("subject") ?? ""
        let id = await EmailDrafts.box.add(.init(toName: toName, toAddress: toAddress,
                                                 subject: subject, body: body, replyToID: replyID))
        let what = replyID == nil ? "Email to \(toName) <\(toAddress)>, subject “\(subject)”" : "Reply to \(toName)"
        return """
        Draft \(id) ready (not sent). \(what).
        Body: “\(body)”
        Now tell the user who it's to and summarise it in a sentence, then ask if you should send it. Call send_email with draft_id \(id) only if their very next reply is a clear yes; TESS checks this and refuses otherwise. If they want changes, make a new draft.
        """
    }

    static let sendEmail = Tool(
        name: "send_email",
        description: "Send an email prepared with draft_email. Only call this when the user's reply right after the read-back is a clear yes. TESS checks their words and refuses otherwise.",
        properties: ["draft_id": P.string("The id returned by draft_email")],
        required: ["draft_id"]
    ) { args in
        guard let id = args.string("draft_id") else { throw TESSError("Which draft?") }
        let draft = try await EmailDrafts.box.take(id)
        let body = draft.body.appleScriptEscaped
        let script: String
        if let replyID = draft.replyToID {
            script = """
            tell application "Mail"
                set found to (messages of inbox whose id is \(replyID))
                if found is {} then error "The original email is gone."
                set r to reply (item 1 of found) without opening window
                set content of r to "\(body)"
                send r
            end tell
            """
        } else {
            script = """
            tell application "Mail"
                set m to make new outgoing message with properties {subject:"\(draft.subject.appleScriptEscaped)", content:"\(body)", visible:false}
                tell m to make new to recipient at end of to recipients with properties {address:"\(draft.toAddress.appleScriptEscaped)"}
                send m
            end tell
            """
        }
        try await Shell.appleScript(script)
        return "Sent to \(draft.toName)."
    }

    // MARK: Helpers

    /// "Maria Nilsen <maria@example.com>" → "Maria Nilsen"
    static func cleanSender(_ sender: String) -> String {
        if let range = sender.range(of: " <") {
            let name = sender[..<range.lowerBound].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            if !name.isEmpty { return name }
        }
        return sender.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
    }

    static func agoText(_ seconds: Int) -> String {
        switch seconds {
        case ..<3600: return "\(max(1, seconds / 60)) min ago"
        case ..<86_400: return "\(seconds / 3600) h ago"
        default: return "\(seconds / 86_400) d ago"
        }
    }
}

/// Emails waiting for the user's go-ahead. See `ConfirmationGate` for the rules.
@MainActor
enum EmailDrafts {
    struct Draft {
        let toName: String
        let toAddress: String
        let subject: String
        let body: String
        let replyToID: String?
    }

    static let box = DraftBox<Draft>(prefix: "e", noun: "email draft")
}
