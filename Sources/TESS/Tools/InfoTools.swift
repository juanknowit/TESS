import Foundation

/// Live information: weather (Open-Meteo), news (Google News RSS) and web search (DuckDuckGo / Wikipedia).
/// All free and keyless.
enum InfoTools {
    static func all(_ context: ToolContext) -> [Tool] {
        var tools = [weather(context), news(context)]
        if context.includeWebSearch { tools.append(webSearch) }
        return tools
    }

    // MARK: Weather

    static func weather(_ context: ToolContext) -> Tool {
        Tool(
            name: "get_weather",
            description: "Current conditions and a daily forecast for a place. Omit location to use the user's home city.",
            properties: [
                "location": P.string("City or place, e.g. 'Oslo' or 'Portland, Maine'"),
                "days": P.integer("Forecast days, 1-7 (default 3)"),
            ]
        ) { args in
            let query = args.string("location") ?? context.homeCity
            guard !query.isEmpty else {
                return "No location was given and no home city is set. Ask the user which city, and mention they can set a home city in TESS settings."
            }
            let place = try await geocode(query)
            let days = max(1, min(7, args.int("days") ?? 3))
            let metric = context.units == .metric

            var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            comps.queryItems = [
                .init(name: "latitude", value: String(place.lat)),
                .init(name: "longitude", value: String(place.lon)),
                .init(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,precipitation"),
                .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"),
                .init(name: "timezone", value: "auto"),
                .init(name: "forecast_days", value: String(days)),
                .init(name: "temperature_unit", value: metric ? "celsius" : "fahrenheit"),
                .init(name: "wind_speed_unit", value: metric ? "kmh" : "mph"),
                .init(name: "precipitation_unit", value: metric ? "mm" : "inch"),
            ]
            guard let json = try await HTTP.getJSON(comps.url!) as? JSONObject else { throw TESSError("The weather service didn't answer.") }

            let deg = metric ? "°C" : "°F", speed = metric ? "km/h" : "mph"
            var lines = ["Weather for \(place.label):"]
            if let c = json["current"] as? JSONObject {
                let temp = c.double("temperature_2m").map { "\(Int($0.rounded()))\(deg)" } ?? "?"
                let feels = c.double("apparent_temperature").map { "\(Int($0.rounded()))\(deg)" } ?? "?"
                let wind = c.double("wind_speed_10m").map { "\(Int($0.rounded())) \(speed)" } ?? "?"
                let humidity = c.int("relative_humidity_2m").map { "\($0)%" } ?? "?"
                lines.append("Now (local time \(c.string("time") ?? "")): \(temp), feels like \(feels), \(describe(c.int("weather_code"))), wind \(wind), humidity \(humidity).")
            }
            if let d = json["daily"] as? JSONObject, let dates = d["time"] as? [String] {
                let codes = d["weather_code"] as? [Any] ?? []
                let highs = d["temperature_2m_max"] as? [Any] ?? []
                let lows = d["temperature_2m_min"] as? [Any] ?? []
                let rain = d["precipitation_probability_max"] as? [Any] ?? []
                let sunrise = d["sunrise"] as? [String] ?? [], sunset = d["sunset"] as? [String] ?? []
                for (i, date) in dates.enumerated() {
                    func n(_ arr: [Any]) -> Int? { i < arr.count ? (arr[i] as? NSNumber).map { Int($0.doubleValue.rounded()) } : nil }
                    let high = n(highs).map { String($0) } ?? "?"
                    let low = n(lows).map { String($0) } ?? "?"
                    var line = "\(date): \(describe(n(codes))), high \(high)\(deg), low \(low)\(deg)"
                    if let p = n(rain) { line += ", \(p)% chance of precipitation" }
                    if i < sunrise.count, i < sunset.count {
                        line += ", sunrise \(sunrise[i].suffix(5)), sunset \(sunset[i].suffix(5))"
                    }
                    lines.append(line + ".")
                }
            }
            return lines.joined(separator: "\n")
        }
    }

    struct Place {
        let label: String
        let lat: Double
        let lon: Double
        var name: String = ""
        var region: String = ""
        var country: String = ""
        var countryCode: String = ""
    }

    static func geocode(_ query: String) async throws -> Place {
        let parts = query.split(separator: ",").map { String($0).trimmed }
        let city = parts.first ?? query
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [
            .init(name: "name", value: city),
            .init(name: "count", value: "10"),
            .init(name: "language", value: "en"),
            .init(name: "format", value: "json"),
        ]
        let json = try await HTTP.getJSON(comps.url!) as? JSONObject
        let results = json?["results"] as? [JSONObject] ?? []
        guard var pick = results.first else { throw TESSError("I couldn't find a place called \(query).") }
        if parts.count > 1 {
            let hint = parts[1].lowercased()
            if let match = results.first(where: { r in
                [r.string("country"), r.string("country_code"), r.string("admin1")]
                    .compactMap { $0?.lowercased() }
                    .contains { $0 == hint || $0.contains(hint) }
            }) {
                pick = match
            }
        }
        let label = [pick.string("name"), pick.string("admin1"), pick.string("country")]
            .compactMap { $0 }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .joined(separator: ", ")
        return Place(label: label, lat: pick.double("latitude") ?? 0, lon: pick.double("longitude") ?? 0,
                     name: pick.string("name") ?? city, region: pick.string("admin1") ?? "",
                     country: pick.string("country") ?? "", countryCode: (pick.string("country_code") ?? "").uppercased())
    }

    static func describe(_ code: Int?) -> String {
        switch code ?? -1 {
        case 0: return "clear sky"
        case 1: return "mainly clear"
        case 2: return "partly cloudy"
        case 3: return "overcast"
        case 45, 48: return "fog"
        case 51, 53, 55: return "drizzle"
        case 56, 57: return "freezing drizzle"
        case 61: return "light rain"
        case 63: return "rain"
        case 65: return "heavy rain"
        case 66, 67: return "freezing rain"
        case 71: return "light snow"
        case 73: return "snow"
        case 75: return "heavy snow"
        case 77: return "snow grains"
        case 80: return "light showers"
        case 81: return "showers"
        case 82: return "violent showers"
        case 85, 86: return "snow showers"
        case 95: return "thunderstorms"
        case 96, 99: return "thunderstorms with hail"
        default: return "unknown conditions"
        }
    }

    // MARK: News

    static func news(_ context: ToolContext) -> Tool {
        Tool(
            name: "get_news",
            description: "Latest news headlines. By default focused on the user's home area (local and national news, as set in TESS settings). Use scope to ask for local, national or world news explicitly, or topic to search for something specific.",
            properties: [
                "topic": P.string("Optional topic or search terms, e.g. 'Formula 1' or 'electricity prices'"),
                "scope": P.oneOf(["local", "national", "world"], "Optional: which news. Omit to use the user's preferred focus."),
                "count": P.integer("How many headlines (default 6, max 12)"),
            ]
        ) { args in
            let count = max(1, min(12, args.int("count") ?? 6))
            let area = await NewsArea.resolve(homeCity: context.homeCity)
            let edition = NewsArea.edition(for: area.countryCode, language: context.newsLanguage)

            if let topic = args.string("topic") {
                let items = try await Headlines.fetch(.search(topic + " when:7d"), edition: edition)
                return Headlines.format(items.prefix(count), title: "News about \(topic)")
            }

            let scope = args.string("scope") ?? context.newsFocus.rawValue
            var sections: [String] = []
            switch scope {
            case "world":
                let items = try await Headlines.fetch(.topic("WORLD"), edition: edition)
                sections.append(Headlines.format(items.prefix(count), title: "World news"))
            case "national", "country":
                let items = try await area.national(edition: edition)
                sections.append(Headlines.format(items.prefix(count), title: "National news — \(area.countryName)"))
            default: // local
                if area.city.isEmpty {
                    sections.append("No home city is set, so there's no local news. Mention they can set one in TESS settings.")
                    let items = try await area.national(edition: edition)
                    sections.append(Headlines.format(items.prefix(count), title: "National news — \(area.countryName)"))
                } else {
                    let localCount = max(1, count - count / 3)
                    let local = (try? await area.local(edition: edition)) ?? []
                    let seen = Set(local.prefix(localCount).map(\.title))
                    let national = ((try? await area.national(edition: edition)) ?? []).filter { !seen.contains($0.title) }
                    sections.append(Headlines.format(local.prefix(localCount), title: "Local news — \(area.city)"))
                    sections.append(Headlines.format(national.prefix(count - localCount + (local.isEmpty ? localCount : 0)),
                                                     title: "National news — \(area.countryName)"))
                }
            }
            return sections.joined(separator: "\n\n")
        }
    }

    // MARK: Web search (used when the AI provider has no built-in search)

    static let webSearch = Tool(
        name: "web_search",
        description: "Search the web for current information. Returns titles and snippets of the top results.",
        properties: ["query": P.string("What to search for")],
        required: ["query"]
    ) { args in
        guard let query = args.string("query") else { throw TESSError("Search for what?") }
        if let results = try? await duckDuckGo(query), !results.isEmpty { return results }
        if let results = try? await wikipedia(query), !results.isEmpty { return results }
        return "No results found for \(query)."
    }

    static func duckDuckGo(_ query: String) async throws -> String {
        var comps = URLComponents(string: "https://html.duckduckgo.com/html/")!
        comps.queryItems = [.init(name: "q", value: query)]
        let data = try await HTTP.get(comps.url!)
        let html = String(decoding: data, as: UTF8.self)
        let titles = captures(#"class="result__a"[^>]*>(.*?)</a>"#, in: html)
        let snippets = captures(#"class="result__snippet"[^>]*>(.*?)</a>"#, in: html)
        return (0..<min(6, titles.count)).map { i in
            let snippet = i < snippets.count ? " — " + stripHTML(snippets[i]) : ""
            return "\(i + 1). \(stripHTML(titles[i]))\(snippet)"
        }.joined(separator: "\n")
    }

    static func wikipedia(_ query: String) async throws -> String {
        var comps = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        comps.queryItems = [
            .init(name: "action", value: "query"), .init(name: "list", value: "search"),
            .init(name: "srsearch", value: query), .init(name: "format", value: "json"),
            .init(name: "srlimit", value: "3"),
        ]
        let json = try await HTTP.getJSON(comps.url!) as? JSONObject
        let results = (json?["query"] as? JSONObject)?["search"] as? [JSONObject] ?? []
        return results.map { "Wikipedia — \($0.string("title") ?? ""): \(stripHTML($0.string("snippet") ?? ""))" }
            .joined(separator: "\n")
    }

    static func captures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    static func stripHTML(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&quot;": "\"", "&#x27;": "'", "&#39;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "]
        for (entity, char) in entities { s = s.replacingOccurrences(of: entity, with: char) }
        return s.trimmed
    }
}

/// Minimal RSS reader for headline titles and dates.
final class RSSParser: NSObject, XMLParserDelegate {
    struct Item {
        var title = ""
        var pubDate = ""
    }

    private var items: [Item] = []
    private var current: Item?
    private var text = ""

    static func parse(_ data: Data) -> [Item] {
        let delegate = RSSParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "item" { current = Item() }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard current != nil else { return }
        switch elementName {
        case "title": current?.title = text.trimmed
        case "pubDate": current?.pubDate = text.trimmed
        case "item":
            if let item = current { items.append(item) }
            current = nil
        default: break
        }
        text = ""
    }
}
