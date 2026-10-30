import AppKit

/// Reads the page open in the user's browser (Safari and Chromium browsers).
enum WebPageTools {
    static func all() -> [Tool] { [readWebPage] }

    struct Browser {
        let bundleID: String
        let name: String
        let isSafari: Bool
    }

    static let browsers: [Browser] = [
        Browser(bundleID: "com.apple.Safari", name: "Safari", isSafari: true),
        Browser(bundleID: "com.google.Chrome", name: "Google Chrome", isSafari: false),
        Browser(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge", isSafari: false),
        Browser(bundleID: "company.thebrowser.Browser", name: "Arc", isSafari: false),
        Browser(bundleID: "com.brave.Browser", name: "Brave Browser", isSafari: false),
    ]

    static let readWebPage = Tool.rich(
        name: "read_web_page",
        description: "Read the web page the user has open (front tab of Safari, Chrome, Edge, Arc or Brave) so you can summarise it or answer questions about it. Use for 'this page', 'this article', 'this tab'.",
        properties: ["offset": P.integer("Character offset to continue reading a long page (default 0)")]
    ) { args in
        guard let browser = await activeBrowser() else {
            throw TESSError("I can't see a supported browser with a page open. I can read Safari, Chrome, Edge, Arc and Brave — Firefox doesn't let other apps read its tabs.")
        }
        let info = try await Shell.appleScript(urlScript(browser))
        let parts = info.components(separatedBy: "\n")
        let url = parts.first?.trimmed ?? ""
        let title = parts.dropFirst().joined(separator: " ").trimmed
        guard url.hasPrefix("http") else { throw TESSError("The front tab in \(browser.name) isn't a web page.") }

        // Best: the text as the user sees it (works for pages behind a login). Needs the browser's
        // "Allow JavaScript from Apple Events" setting; otherwise fetch the page ourselves.
        var text = (try? await Shell.appleScript(textScript(browser)))?.trimmed ?? ""
        var source = "from \(browser.name)"
        if text.count < 200, let pageURL = URL(string: url) {
            let data = try await HTTP.get(pageURL)
            text = readableText(fromHTML: String(decoding: data, as: UTF8.self))
            source = "downloaded (pages behind a login may be incomplete)"
        }
        guard !text.isEmpty else { throw TESSError("I couldn't get any text from that page.") }

        let offset = max(0, args.int("offset") ?? 0)
        let chunk = DocumentTools.chunk(text, name: title.isEmpty ? url : title, kind: "web page \(source), \(url)", offset: offset)
        return chunk
    }

    // MARK: Browser access

    /// The frontmost browser if the user is in one, otherwise the first running supported browser.
    static func activeBrowser() async -> Browser? {
        await MainActor.run {
            if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
               let browser = browsers.first(where: { $0.bundleID == front }) {
                return browser
            }
            return browsers.first { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty }
        }
    }

    static func urlScript(_ browser: Browser) -> String {
        if browser.isSafari {
            return "tell application \"Safari\" to return (URL of front document) & linefeed & (name of front document)"
        }
        return "tell application \"\(browser.name)\" to return (URL of active tab of front window) & linefeed & (title of active tab of front window)"
    }

    static func textScript(_ browser: Browser) -> String {
        let js = "document.body.innerText"
        if browser.isSafari {
            return "tell application \"Safari\" to do JavaScript \"\(js)\" in front document"
        }
        return "tell application \"\(browser.name)\" to execute active tab of front window javascript \"\(js)\""
    }

    // MARK: HTML → text

    static func readableText(fromHTML html: String) -> String {
        var s = html
        // Prefer the main content when the page marks it.
        for tag in ["article", "main"] {
            if let start = s.range(of: "<\(tag)", options: .caseInsensitive),
               let end = s.range(of: "</\(tag)>", options: [.caseInsensitive, .backwards]),
               start.lowerBound < end.lowerBound {
                s = String(s[start.lowerBound..<end.upperBound])
                break
            }
        }
        for tag in ["script", "style", "noscript", "svg", "nav", "footer", "header", "form"] {
            s = s.replacingOccurrences(of: "(?is)<\(tag)[^>]*>.*?</\(tag)>", with: " ", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: "(?i)<(br|/p|/div|/li|/h[1-6]|/tr)[^>]*>", with: "\n", options: .regularExpression)
        s = InfoTools.stripHTML(s)
        s = s.replacingOccurrences(of: "&[a-zA-Z]+;", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\n\\s*\\n+", with: "\n\n", options: .regularExpression)
        return s.trimmed
    }
}
