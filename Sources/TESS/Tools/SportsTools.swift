import Foundation

/// Scores, results and fixtures from ESPN's public scoreboard data.
enum SportsTools {
    static func all() -> [Tool] { [sportsResults] }

    struct League {
        let sport: String
        let slug: String
        let name: String
    }

    static let leagues: [String: League] = {
        let list: [(keys: [String], league: League)] = [
            (["eliteserien", "norway", "norwegian"], League(sport: "soccer", slug: "nor.1", name: "Eliteserien")),
            (["premier league", "epl", "england", "english"], League(sport: "soccer", slug: "eng.1", name: "Premier League")),
            (["championship"], League(sport: "soccer", slug: "eng.2", name: "Championship")),
            (["la liga", "laliga", "spain", "spanish"], League(sport: "soccer", slug: "esp.1", name: "La Liga")),
            (["bundesliga", "germany", "german"], League(sport: "soccer", slug: "ger.1", name: "Bundesliga")),
            (["serie a", "italy", "italian"], League(sport: "soccer", slug: "ita.1", name: "Serie A")),
            (["ligue 1", "france", "french"], League(sport: "soccer", slug: "fra.1", name: "Ligue 1")),
            (["allsvenskan", "sweden", "swedish"], League(sport: "soccer", slug: "swe.1", name: "Allsvenskan")),
            (["superliga", "denmark", "danish"], League(sport: "soccer", slug: "den.1", name: "Superliga")),
            (["champions league", "ucl"], League(sport: "soccer", slug: "uefa.champions", name: "Champions League")),
            (["europa league"], League(sport: "soccer", slug: "uefa.europa", name: "Europa League")),
            (["mls"], League(sport: "soccer", slug: "usa.1", name: "MLS")),
            (["nba", "basketball"], League(sport: "basketball", slug: "nba", name: "NBA")),
            (["nfl", "american football"], League(sport: "football", slug: "nfl", name: "NFL")),
            (["nhl", "hockey", "ice hockey"], League(sport: "hockey", slug: "nhl", name: "NHL")),
            (["mlb", "baseball"], League(sport: "baseball", slug: "mlb", name: "MLB")),
        ]
        var map: [String: League] = [:]
        for entry in list {
            for key in entry.keys { map[key] = entry.league }
            map[entry.league.slug] = entry.league
        }
        return map
    }()

    /// Searched in this order when only a team name is given.
    static let searchOrder = ["nor.1", "eng.1", "esp.1", "ger.1", "ita.1", "fra.1", "uefa.champions", "swe.1", "den.1",
                              "eng.2", "usa.1", "nba", "nfl", "nhl", "mlb"]

    static let sportsResults = Tool(
        name: "sports_results",
        description: "Latest results, live scores and upcoming fixtures. Give a team (e.g. 'Vålerenga', 'Arsenal', 'Lakers') for its recent results and next games, and/or a league (Eliteserien, Premier League, La Liga, Bundesliga, Serie A, Ligue 1, Champions League, Allsvenskan, MLS, NBA, NFL, NHL, MLB) for its current scoreboard.",
        properties: [
            "team": P.string("Optional team name"),
            "league": P.string("Optional league name"),
        ]
    ) { args in
        let leagueArg = args.string("league").flatMap { leagues[$0.lowercased()] ?? leagues[$0] }
        if args.string("league") != nil && leagueArg == nil {
            throw TESSError("I don't know that league. I cover Eliteserien, Premier League, La Liga, Bundesliga, Serie A, Ligue 1, Champions League, Allsvenskan, MLS, NBA, NFL, NHL and MLB.")
        }

        if let teamQuery = args.string("team") {
            let candidates = leagueArg.map { [$0] } ?? searchOrder.compactMap { leagues[$0] }
            for league in candidates {
                if let team = try? await findTeam(teamQuery, in: league) {
                    return try await teamSummary(team: team, league: league)
                }
            }
            throw TESSError("I couldn't find a team called \(teamQuery)\(leagueArg.map { " in the \($0.name)" } ?? "").")
        }

        guard let league = leagueArg else { throw TESSError("Which team or league?") }
        return try await scoreboard(league)
    }

    // MARK: ESPN

    static func url(_ league: League, _ path: String) -> URL {
        URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(league.sport)/\(league.slug)/\(path)")!
    }

    struct Team {
        let id: String
        let name: String
    }

    static func findTeam(_ query: String, in league: League) async throws -> Team? {
        guard let json = try await HTTP.getJSON(url(league, "teams")) as? JSONObject else { return nil }
        let sports = json["sports"] as? [JSONObject] ?? []
        let leagueList = (sports.first?["leagues"] as? [JSONObject])?.first
        let teams = (leagueList?["teams"] as? [JSONObject] ?? []).compactMap { $0["team"] as? JSONObject }
        let q = fold(query)
        func names(_ t: JSONObject) -> [String] {
            ["displayName", "shortDisplayName", "name", "nickname", "location", "abbreviation"].compactMap { t.string($0) }.map(fold)
        }
        let match = teams.first { names($0).contains(q) }
            ?? teams.first { names($0).contains { $0.contains(q) || (q.count >= 4 && q.contains($0) && $0.count >= 4) } }
        guard let team = match, let id = team.string("id") else { return nil }
        return Team(id: id, name: team.string("displayName") ?? query)
    }

    static func teamSummary(team: Team, league: League) async throws -> String {
        var events: [JSONObject] = []
        for path in ["teams/\(team.id)/schedule", "teams/\(team.id)/schedule?fixture=true"] {
            if let json = try? await HTTP.getJSON(url(league, path)) as? JSONObject {
                events += json["events"] as? [JSONObject] ?? []
            }
        }
        var seen = Set<String>()
        let games = events.compactMap { parseGame($0) }.filter { seen.insert($0.id).inserted }.sorted { $0.date < $1.date }
        let finished = games.filter { $0.state == "post" }.suffix(3)
        let live = games.filter { $0.state == "in" }
        let upcoming = games.filter { $0.state == "pre" && $0.date > Date().addingTimeInterval(-3 * 3600) }.prefix(2)

        var lines = ["\(team.name) (\(league.name)):"]
        if !live.isEmpty { lines.append("Live now:"); lines += live.map { "- " + $0.line(for: team.name) } }
        if !finished.isEmpty { lines.append("Recent results:"); lines += finished.reversed().map { "- " + $0.line(for: team.name) } }
        if !upcoming.isEmpty { lines.append("Next:"); lines += upcoming.map { "- " + $0.line(for: team.name) } }
        if lines.count == 1 { lines.append("No recent or upcoming games found.") }
        return lines.joined(separator: "\n")
    }

    static func scoreboard(_ league: League) async throws -> String {
        guard let json = try await HTTP.getJSON(url(league, "scoreboard")) as? JSONObject else {
            throw TESSError("The scores service didn't answer.")
        }
        let games = (json["events"] as? [JSONObject] ?? []).compactMap { parseGame($0) }.sorted { $0.date < $1.date }
        guard !games.isEmpty else { return "No \(league.name) games on the current scoreboard." }
        return "\(league.name) scoreboard:\n" + games.prefix(15).map { "- " + $0.line(for: nil) }.joined(separator: "\n")
    }

    // MARK: Parsing

    struct Game {
        let id: String
        let date: Date
        let state: String // pre, in, post
        let status: String
        let home: (name: String, score: String, winner: Bool)
        let away: (name: String, score: String, winner: Bool)

        func line(for team: String?) -> String {
            let when = DateParse.spoken(date)
            switch state {
            case "pre":
                return "\(when): \(home.name) vs \(away.name)"
            default:
                var result = ""
                if let team {
                    let mine = SportsTools.fold(home.name) == SportsTools.fold(team) ? home : away
                    let theirs = SportsTools.fold(home.name) == SportsTools.fold(team) ? away : home
                    if state == "post" {
                        result = mine.winner ? " — win" : theirs.winner ? " — loss" : " — draw"
                    }
                }
                let label = state == "in" ? " (\(status))" : ""
                return "\(when): \(home.name) \(home.score)–\(away.score) \(away.name)\(label)\(result)"
            }
        }
    }

    static func parseGame(_ event: JSONObject) -> Game? {
        guard let id = event.string("id"), let dateText = event.string("date"), let date = parseDate(dateText),
              let competition = (event["competitions"] as? [JSONObject])?.first,
              let competitors = competition["competitors"] as? [JSONObject], competitors.count >= 2 else { return nil }
        let statusType = ((competition["status"] as? JSONObject ?? event["status"] as? JSONObject)?["type"] as? JSONObject) ?? [:]
        func side(_ c: JSONObject) -> (name: String, score: String, winner: Bool) {
            let team = c["team"] as? JSONObject ?? [:]
            let name = team.string("displayName") ?? team.string("shortDisplayName") ?? "?"
            var score = c.string("score") ?? ""
            if let s = c["score"] as? JSONObject { score = s.string("displayValue") ?? s.string("value") ?? "" }
            if let value = Double(score), value == value.rounded() { score = String(Int(value)) }
            return (name, score.isEmpty ? "-" : score, c["winner"] as? Bool ?? false)
        }
        let home = competitors.first { $0.string("homeAway") == "home" } ?? competitors[0]
        let away = competitors.first { $0.string("homeAway") == "away" } ?? competitors[1]
        return Game(id: id, date: date,
                    state: statusType.string("state") ?? ((statusType["completed"] as? Bool ?? false) ? "post" : "pre"),
                    status: statusType.string("shortDetail") ?? statusType.string("description") ?? "",
                    home: side(home), away: side(away))
    }

    static func parseDate(_ text: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd'T'HH:mm'Z'", "yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"] {
            f.dateFormat = format
            if let d = f.date(from: text) { return d }
        }
        return DateParse.parse(text)
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "ø", with: "o").replacingOccurrences(of: "æ", with: "ae")
            .trimmed
    }
}
