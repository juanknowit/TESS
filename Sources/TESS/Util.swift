import Foundation

typealias JSONObject = [String: Any]

// MARK: - Errors

struct TESSError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// An HTTP error from a remote API, with the provider's own message extracted when possible.
struct APIError: LocalizedError {
    let status: Int
    let detail: String

    init(status: Int, body: Data) {
        self.status = status
        var message = String(data: body, encoding: .utf8) ?? ""
        if let obj = try? JSONSerialization.jsonObject(with: body) as? JSONObject {
            if let err = obj["error"] as? JSONObject, let m = err["message"] as? String {
                message = m
            } else if let m = obj["error"] as? String {
                message = m
            } else if let m = obj["message"] as? String {
                message = m
            }
        }
        detail = String(message.prefix(300))
    }

    var errorDescription: String? { "HTTP \(status): \(detail)" }
}

// MARK: - Argument helpers (tool arguments arrive as loosely-typed JSON)

extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? {
        if let s = self[key] as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let n = self[key] as? NSNumber { return n.stringValue }
        return nil
    }

    func double(_ key: String) -> Double? {
        if let n = self[key] as? NSNumber { return n.doubleValue }
        if let s = self[key] as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    func int(_ key: String) -> Int? {
        double(key).map { Int($0.rounded()) }
    }

    func bool(_ key: String) -> Bool? {
        if let b = self[key] as? Bool { return b }
        if let s = self[key] as? String { return ["true", "yes", "1", "on"].contains(s.lowercased()) }
        return nil
    }
}

enum JSONText {
    static func encode(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    static func decodeObject(_ s: String) -> JSONObject {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? JSONObject else { return [:] }
        return obj
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Escapes a string for safe use inside an AppleScript string literal.
    var appleScriptEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

// MARK: - HTTP

enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        return URLSession(configuration: config)
    }()

    static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static func postJSON(_ url: URL,
                         headers: [String: String] = [:],
                         body: JSONObject,
                         timeout: TimeInterval = 90) async throws -> JSONObject {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try check(response, data)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? JSONObject else {
            throw TESSError("Unexpected response from \(url.host ?? "the server").")
        }
        return obj
    }

    static func get(_ url: URL, headers: [String: String] = [:], timeout: TimeInterval = 20) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await session.data(for: request)
        try check(response, data)
        return data
    }

    static func getJSON(_ url: URL) async throws -> Any {
        let data = try await get(url)
        return try JSONSerialization.jsonObject(with: data)
    }

    static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else { throw APIError(status: http.statusCode, body: data) }
    }
}

// MARK: - Text for speech

enum SpeechText {
    /// Removes markdown, URLs and model "thinking" so the reply sounds natural when spoken.
    static func clean(_ input: String) -> String {
        var t = input
        t = t.replacingOccurrences(of: "(?s)<think>.*?</think>", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "https?://\\S+", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?m)^\\s*([-•*]|\\d+\\.)\\s+", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "[*_`#>]+", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\n{2,}", with: "\n", options: .regularExpression)
        return t.trimmed
    }

    static func duration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) hour\(h == 1 ? "" : "s")") }
        if m > 0 { parts.append("\(m) minute\(m == 1 ? "" : "s")") }
        if s > 0 || parts.isEmpty { parts.append("\(s) second\(s == 1 ? "" : "s")") }
        return parts.joined(separator: " and ")
    }
}

// MARK: - Dates

enum DateParse {
    /// Parses the date formats a model typically produces, interpreting times without a zone as local time.
    static func parse(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        for options in [[.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds]] as [ISO8601DateFormatter.Options] {
            iso.formatOptions = options
            if let d = iso.date(from: s) { return d }
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    static func hasTime(_ s: String) -> Bool { s.contains("T") || s.contains(":") }

    static func spoken(_ date: Date, includeDate: Bool = true) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = includeDate ? "EEEE d MMMM 'at' HH:mm" : "HH:mm"
        return f.string(from: date)
    }
}
