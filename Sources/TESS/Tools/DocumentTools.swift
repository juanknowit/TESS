import AppKit
import ApplicationServices
import PDFKit
import UniformTypeIdentifiers

/// Finding and reading the user's documents: PDFs, Word, RTF, text, images.
enum DocumentTools {
    static func all() -> [Tool] { [findDocuments, readDocument] }

    static let chunkSize = 24_000

    static let findDocuments = Tool(
        name: "find_documents",
        description: "Find the user's files. With a query, searches file names across their home folder; without one, lists the most recently changed files in Downloads, Desktop and Documents. Returns paths to pass to read_document.",
        properties: [
            "query": P.string("Optional part of the file name, e.g. 'invoice' or 'report.pdf'"),
            "count": P.integer("How many results (default 8, max 20)"),
        ]
    ) { args in
        let count = max(1, min(20, args.int("count") ?? 8))
        let home = NSHomeDirectory()
        var urls: [URL]
        if let query = args.string("query") {
            let output = try await Shell.run("/usr/bin/mdfind", ["-onlyin", home, "-name", query])
            urls = output.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
                .filter { !$0.path.contains("/Library/") && !$0.path.contains("/.") }
        } else {
            urls = ["Downloads", "Desktop", "Documents"].flatMap { folder -> [URL] in
                let dir = URL(fileURLWithPath: home).appendingPathComponent(folder)
                return (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
                                                                      options: [.skipsHiddenFiles])) ?? []
            }
        }
        let dated: [(URL, Date, Int, Bool)] = urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey])
            guard let date = values?.contentModificationDate else { return nil }
            return (url, date, values?.fileSize ?? 0, values?.isDirectory ?? false)
        }
        let sorted = dated.filter { !$0.3 || $0.0.pathExtension == "pages" }.sorted { $0.1 > $1.1 }.prefix(count)
        guard !sorted.isEmpty else { return args.string("query").map { "No files named like \($0)." } ?? "No recent files found." }

        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        return sorted.map { url, date, size, _ in
            let path = url.path.replacingOccurrences(of: home, with: "~")
            let sizeText = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            return "\(path) — changed \(relative.localizedString(for: date, relativeTo: Date())), \(sizeText)"
        }.joined(separator: "\n")
    }

    static let readDocument = Tool.rich(
        name: "read_document",
        description: "Read a document so you can summarise it or answer questions about it. Supports PDF, Word (.docx/.doc), RTF, OpenDocument, HTML, plain text/Markdown/CSV/JSON/code, and images. Pass a path from find_documents, or 'current' for the document open in the frontmost app (or selected in Finder). Long documents come in chunks; use offset to continue.",
        properties: [
            "path": P.string("File path (e.g. ~/Downloads/invoice.pdf) or 'current'"),
            "offset": P.integer("Character offset to continue reading from (default 0)"),
        ],
        required: ["path"]
    ) { args in
        guard var path = args.string("path") else { throw TESSError("Which document?") }
        if ["current", "front", "frontmost", "this", "selected"].contains(path.lowercased()) {
            guard let current = await currentDocumentPath() else {
                throw TESSError("I couldn't tell which document is open. Select the file in Finder, or tell me its name.")
            }
            path = current
        }
        if path.hasPrefix("~") { path = (path as NSString).expandingTildeInPath }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TESSError("There's no file at \(path). Try find_documents first.")
        }
        return try load(url, offset: max(0, args.int("offset") ?? 0))
    }

    // MARK: Loading

    static func load(_ url: URL, offset: Int) throws -> ToolOutput {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)

        if let type, type.conforms(to: .image) {
            guard let jpeg = ImageTools.jpeg(fromFile: url) else { throw TESSError("I couldn't open the image \(name).") }
            return ToolOutput(text: "The image \(name) is attached.", image: jpeg)
        }

        if ext == "pdf" {
            guard let pdf = PDFDocument(url: url) else { throw TESSError("I couldn't open the PDF \(name). It may be password-protected.") }
            let text = pdf.string ?? ""
            if text.trimmed.count < 40, let page = pdf.page(at: 0) {
                // Probably a scan: show the first page as an image instead.
                let thumbnail = page.thumbnail(of: NSSize(width: 1400, height: 1800), for: .mediaBox)
                if let cg = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil), let jpeg = ImageTools.jpeg(cg) {
                    return ToolOutput(text: "\(name) is a scanned PDF with \(pdf.pageCount) page(s) and no text layer. Page 1 is attached as an image.",
                                      image: jpeg)
                }
            }
            return chunk(text, name: name, kind: "PDF, \(pdf.pageCount) page\(pdf.pageCount == 1 ? "" : "s")", offset: offset)
        }

        if ["pages", "numbers", "key", "xlsx", "xls", "pptx"].contains(ext) {
            throw TESSError("I can't read .\(ext) files directly yet. Export \(name) as PDF and I'll read that.")
        }

        let richTypes = ["docx", "doc", "rtf", "rtfd", "odt", "html", "htm", "webarchive", "wordml"]
        if richTypes.contains(ext) {
            let attributed = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
            return chunk(attributed.string, name: name, kind: ext.uppercased() + " document", offset: offset)
        }

        let data = try Data(contentsOf: url)
        if data.prefix(4096).contains(0) { throw TESSError("\(name) looks like a binary file I can't read.") }
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return chunk(text, name: name, kind: (ext.isEmpty ? "text" : ext.uppercased()) + " file", offset: offset)
    }

    static func chunk(_ fullText: String, name: String, kind: String, offset: Int) -> ToolOutput {
        let text = fullText.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        guard !text.trimmed.isEmpty else {
            return ToolOutput(text: "\(name) (\(kind)) has no readable text.")
        }
        let total = text.count
        let start = min(offset, total)
        let startIndex = text.index(text.startIndex, offsetBy: start)
        let endIndex = text.index(startIndex, offsetBy: min(chunkSize, total - start))
        var header = "\(name) (\(kind)) — characters \(start)–\(start + text.distance(from: startIndex, to: endIndex)) of \(total)."
        let next = start + chunkSize
        if next < total { header += " More text follows: call read_document again with offset \(next) if needed." }
        return ToolOutput(text: header + "\n\n" + String(text[startIndex..<endIndex]), limit: chunkSize + 600)
    }

    // MARK: The document the user has open

    /// The frontmost app's open document (via Accessibility), or the file selected in Finder.
    static func currentDocumentPath() async -> String? {
        let fromWindow: String? = await MainActor.run {
            guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            var window: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
                  let window else { return nil }
            var document: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXDocumentAttribute as CFString, &document) == .success,
                  let urlString = document as? String, let url = URL(string: urlString), url.isFileURL else { return nil }
            return url.path
        }
        if let fromWindow { return fromWindow }

        let script = """
        tell application "Finder"
            set sel to selection
            if sel is {} then return ""
            return POSIX path of (item 1 of sel as alias)
        end tell
        """
        if let path = try? await Shell.appleScript(script), !path.isEmpty { return path }
        return nil
    }
}
