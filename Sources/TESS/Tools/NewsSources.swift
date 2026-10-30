import Foundation

enum NewsFocus: String, CaseIterable, Identifiable {
    case local, national, world
    var id: String { rawValue }
    var title: String {
        switch self {
        case .local: return "Local"
        case .national: return "Country"
        case .world: return "World"
        }
    }
}

enum NewsLanguage: String, CaseIterable, Identifiable {
    case english, local
    var id: String { rawValue }
    var title: String { self == .english ? "English" : "Local language" }
}

/// A Google News edition: language + country.
struct NewsEdition {
    let hl: String
    let gl: String
    let lang: String

    var queryItems: [URLQueryItem] {
        [.init(name: "hl", value: hl), .init(name: "gl", value: gl), .init(name: "ceid", value: "\(gl):\(lang)")]
    }

    static let us = NewsEdition(hl: "en-US", gl: "US", lang: "en")
}

/// Where the user is, for news purposes.
struct NewsArea {
    let city: String
    let region: String
    let countryName: String
    let countryCode: String

    private static var cache: [String: NewsArea] = [:]
    private static let lock = NSLock()

    /// Looks up the home city's country (cached). Falls back to the Mac's region when no city is set.
    static func resolve(homeCity: String) async -> NewsArea {
        let key = homeCity.lowercased()
        if let cached = lock.withLock({ cache[key] }) { return cached }

        var area: NewsArea
        if !homeCity.isEmpty, let place = try? await InfoTools.geocode(homeCity), !place.countryCode.isEmpty {
            area = NewsArea(city: place.name, region: place.region, countryName: place.country, countryCode: place.countryCode)
        } else {
            let code = Locale.current.region?.identifier ?? "US"
            let name = Locale(identifier: "en_US").localizedString(forRegionCode: code) ?? code
            area = NewsArea(city: homeCity.split(separator: ",").first.map { String($0).trimmed } ?? "",
                            region: "", countryName: name, countryCode: code)
        }
        lock.withLock { cache[key] = area }
        return area
    }

    /// The country's own edition when it matches the chosen language; otherwise an English edition.
    static func edition(for countryCode: String, language: NewsLanguage) -> NewsEdition {
        if language == .local, let local = localEditions[countryCode] { return local }
        return englishEditions[countryCode] ?? .us
    }

    /// Top stories from the country — its own edition if there is one in this language, otherwise a search.
    func national(edition: NewsEdition) async throws -> [Headlines.Item] {
        let items = try await nationalOnce(edition: edition)
        if items.isEmpty, let english = englishFallback(for: edition) { return try await nationalOnce(edition: english) }
        return items
    }

    func local(edition: NewsEdition) async throws -> [Headlines.Item] {
        let items = try await localOnce(edition: edition)
        if items.isEmpty, let english = englishFallback(for: edition) { return try await localOnce(edition: english) }
        return items
    }

    /// The English edition to retry with when a local-language feed comes back empty.
    private func englishFallback(for edition: NewsEdition) -> NewsEdition? {
        let english = NewsArea.edition(for: countryCode, language: .english)
        return english.hl == edition.hl ? nil : english
    }

    private func nationalOnce(edition: NewsEdition) async throws -> [Headlines.Item] {
        if edition.gl == countryCode {
            let items = try await Headlines.fetch(.top, edition: edition)
            if !items.isEmpty { return items }
        }
        return try await Headlines.fetch(.search("\"\(countryName)\" when:1d"), edition: edition)
    }

    /// News about the home city: Google's local section first, then a search.
    private func localOnce(edition: NewsEdition) async throws -> [Headlines.Item] {
        if let geo = try? await Headlines.fetch(.geo(city), edition: edition), geo.count >= 3 {
            return geo
        }
        var query = "\"\(city)\""
        // In English editions add the country so "Portland" or "Bergen" find the right place.
        if edition.gl != countryCode, !countryName.isEmpty { query += " \(countryName)" }
        return try await Headlines.fetch(.search(query + " when:3d"), edition: edition)
    }

    // Google News editions in each country's main language.
    static let localEditions: [String: NewsEdition] = {
        let local: [String: NewsEdition] = [
        "NO": .init(hl: "no", gl: "NO", lang: "no"),
        "SE": .init(hl: "sv", gl: "SE", lang: "sv"),
        "DK": .init(hl: "da", gl: "DK", lang: "da"),
        "FI": .init(hl: "fi-FI", gl: "FI", lang: "fi"),
        "DE": .init(hl: "de", gl: "DE", lang: "de"),
        "AT": .init(hl: "de", gl: "AT", lang: "de"),
        "CH": .init(hl: "de", gl: "CH", lang: "de"),
        "FR": .init(hl: "fr", gl: "FR", lang: "fr"),
        "BE": .init(hl: "fr", gl: "BE", lang: "fr"),
        "NL": .init(hl: "nl", gl: "NL", lang: "nl"),
        "ES": .init(hl: "es", gl: "ES", lang: "es"),
        "IT": .init(hl: "it", gl: "IT", lang: "it"),
        "PT": .init(hl: "pt-PT", gl: "PT", lang: "pt-150"),
        "BR": .init(hl: "pt-BR", gl: "BR", lang: "pt-419"),
        "MX": .init(hl: "es-419", gl: "MX", lang: "es-419"),
        "AR": .init(hl: "es-419", gl: "AR", lang: "es-419"),
        "CO": .init(hl: "es-419", gl: "CO", lang: "es-419"),
        "CL": .init(hl: "es-419", gl: "CL", lang: "es-419"),
        "PL": .init(hl: "pl", gl: "PL", lang: "pl"),
        "CZ": .init(hl: "cs", gl: "CZ", lang: "cs"),
        "HU": .init(hl: "hu", gl: "HU", lang: "hu"),
        "RO": .init(hl: "ro", gl: "RO", lang: "ro"),
        "GR": .init(hl: "el", gl: "GR", lang: "el"),
        "TR": .init(hl: "tr", gl: "TR", lang: "tr"),
        "UA": .init(hl: "uk", gl: "UA", lang: "uk"),
        "IL": .init(hl: "he", gl: "IL", lang: "he"),
        "JP": .init(hl: "ja", gl: "JP", lang: "ja"),
        "KR": .init(hl: "ko", gl: "KR", lang: "ko"),
        "TW": .init(hl: "zh-TW", gl: "TW", lang: "zh-Hant"),
        "HK": .init(hl: "zh-HK", gl: "HK", lang: "zh-Hant"),
        ]
        // English-speaking countries' "local language" edition is their English one.
        return local.merging(englishEditions) { mine, _ in mine }
    }()

    // Countries with an English-language Google News edition.
    static let englishEditions: [String: NewsEdition] = [
        "US": .us,
        "GB": .init(hl: "en-GB", gl: "GB", lang: "en"),
        "IE": .init(hl: "en-IE", gl: "IE", lang: "en"),
        "CA": .init(hl: "en-CA", gl: "CA", lang: "en"),
        "AU": .init(hl: "en-AU", gl: "AU", lang: "en"),
        "NZ": .init(hl: "en-NZ", gl: "NZ", lang: "en"),
        "IN": .init(hl: "en-IN", gl: "IN", lang: "en"),
        "ZA": .init(hl: "en-ZA", gl: "ZA", lang: "en"),
        "SG": .init(hl: "en-SG", gl: "SG", lang: "en"),
        "PH": .init(hl: "en-PH", gl: "PH", lang: "en"),
        "NG": .init(hl: "en-NG", gl: "NG", lang: "en"),
        "KE": .init(hl: "en-KE", gl: "KE", lang: "en"),
    ]
}

/// Google News RSS feeds.
enum Headlines {
    struct Item {
        let title: String
        let date: Date?
    }

    enum Feed {
        case top
        case topic(String)
        case geo(String)
        case search(String)
    }

    static func fetch(_ feed: Feed, edition: NewsEdition) async throws -> [Item] {
        var comps: URLComponents
        var items = edition.queryItems
        switch feed {
        case .top:
            comps = URLComponents(string: "https://news.google.com/rss")!
        case .topic(let name):
            comps = URLComponents(string: "https://news.google.com/rss/headlines/section/topic/\(name)")!
        case .geo(let place):
            comps = URLComponents()
            comps.scheme = "https"
            comps.host = "news.google.com"
            comps.path = "/rss/headlines/section/geo/\(place)"
        case .search(let query):
            comps = URLComponents(string: "https://news.google.com/rss/search")!
            items.insert(.init(name: "q", value: query), at: 0)
        }
        comps.queryItems = items
        guard let url = comps.url else { return [] }
        let data = try await HTTP.get(url)

        let rfc = DateFormatter()
        rfc.locale = Locale(identifier: "en_US_POSIX")
        rfc.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return RSSParser.parse(data).map { Item(title: $0.title, date: rfc.date(from: $0.pubDate)) }
    }

    static func format<S: Sequence>(_ items: S, title: String) -> String where S.Element == Item {
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        let lines = items.map { item -> String in
            let when = item.date.map { " (\(relative.localizedString(for: $0, relativeTo: Date())))" } ?? ""
            return "- \(item.title)\(when)"
        }
        return lines.isEmpty ? "\(title):\nNo headlines found." : "\(title):\n" + lines.joined(separator: "\n")
    }
}
