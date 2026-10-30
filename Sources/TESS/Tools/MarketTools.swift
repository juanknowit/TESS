import Foundation

/// Live exchange rates (Exchange Rate API, open access) and stock / crypto quotes (Yahoo Finance).
enum MarketTools {
    static func all() -> [Tool] { [convertCurrency, stockQuote] }

    // MARK: Currency

    static let convertCurrency = Tool(
        name: "convert_currency",
        description: "Convert money between currencies at today's exchange rate, e.g. 200 USD to NOK. Use ISO codes (USD, EUR, NOK, GBP, SEK, JPY…).",
        properties: [
            "amount": ["type": "number", "description": "Amount to convert (default 1)"],
            "from": P.string("Currency code to convert from, e.g. USD"),
            "to": P.string("Currency code to convert to, e.g. NOK"),
        ],
        required: ["from", "to"]
    ) { args in
        guard let from = args.string("from")?.uppercased(), let to = args.string("to")?.uppercased(),
              from.count == 3, to.count == 3 else {
            throw TESSError("I need three-letter currency codes, like USD and NOK.")
        }
        let amount = args.double("amount") ?? 1
        let table = try await RateCache.shared.rates(base: from)
        guard let rate = table.rates[to] else { throw TESSError("I don't have a rate for \(to).") }
        let result = amount * rate
        return "\(format(amount)) \(from) = \(format(result)) \(to) (1 \(from) = \(format(rate, digits: 4)) \(to); rates updated \(table.updated)). Rates by Exchange Rate API."
    }

    actor RateCache {
        static let shared = RateCache()
        struct Table {
            let rates: [String: Double]
            let updated: String
            let fetched: Date
        }
        private var tables: [String: Table] = [:]

        func rates(base: String) async throws -> Table {
            if let cached = tables[base], Date().timeIntervalSince(cached.fetched) < 3600 { return cached }
            guard let url = URL(string: "https://open.er-api.com/v6/latest/\(base)"),
                  let json = try await HTTP.getJSON(url) as? JSONObject else { throw TESSError("The exchange rate service didn't answer.") }
            guard json.string("result") == "success", let raw = json["rates"] as? JSONObject else {
                throw TESSError("I don't recognise the currency \(base).")
            }
            var rates: [String: Double] = [:]
            for (code, value) in raw { if let n = value as? NSNumber { rates[code] = n.doubleValue } }
            let table = Table(rates: rates, updated: json.string("time_last_update_utc") ?? "today", fetched: Date())
            tables[base] = table
            return table
        }
    }

    // MARK: Stocks

    static let stockQuote = Tool(
        name: "stock_quote",
        description: "Current price and today's change for a stock, index, fund or cryptocurrency. Accepts a ticker (AAPL, EQNR.OL, ^GSPC, BTC-USD) or a company name (Apple, Equinor).",
        properties: ["symbol": P.string("Ticker symbol or company name")],
        required: ["symbol"]
    ) { args in
        guard let input = args.string("symbol") else { throw TESSError("Which stock?") }
        var symbol = input.uppercased()
        var quote = try? await chart(symbol)
        if quote == nil {
            guard let found = try await search(input) else { throw TESSError("I couldn't find a stock called \(input).") }
            symbol = found
            quote = try await chart(found)
        }
        guard let q = quote else { throw TESSError("No price available for \(symbol).") }

        let change = q.price - q.previousClose
        let percent = q.previousClose > 0 ? change / q.previousClose * 100 : 0
        let direction = change >= 0 ? "up" : "down"
        let time = q.time.map { " as of \(DateParse.spoken($0))" } ?? ""
        return "\(q.name) (\(symbol), \(q.exchange)): \(format(q.price)) \(q.currency), \(direction) \(format(abs(change))) (\(format(abs(percent), digits: 2))%) from the previous close of \(format(q.previousClose))\(time)."
    }

    struct Quote {
        let name: String
        let price: Double
        let previousClose: Double
        let currency: String
        let exchange: String
        let time: Date?
    }

    static func chart(_ symbol: String) async throws -> Quote {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?range=1d&interval=1d"),
              let json = try await HTTP.getJSON(url) as? JSONObject,
              let chart = json["chart"] as? JSONObject,
              let result = (chart["result"] as? [JSONObject])?.first,
              let meta = result["meta"] as? JSONObject,
              let price = meta.double("regularMarketPrice") else {
            throw TESSError("No quote for \(symbol).")
        }
        let previous = meta.double("chartPreviousClose") ?? meta.double("previousClose") ?? price
        return Quote(name: meta.string("longName") ?? meta.string("shortName") ?? symbol,
                     price: price,
                     previousClose: previous,
                     currency: meta.string("currency") ?? "",
                     exchange: meta.string("fullExchangeName") ?? meta.string("exchangeName") ?? "",
                     time: meta.double("regularMarketTime").map { Date(timeIntervalSince1970: $0) })
    }

    static func search(_ query: String) async throws -> String? {
        var comps = URLComponents(string: "https://query1.finance.yahoo.com/v1/finance/search")!
        comps.queryItems = [.init(name: "q", value: query), .init(name: "quotesCount", value: "5"), .init(name: "newsCount", value: "0")]
        guard let url = comps.url, let json = try await HTTP.getJSON(url) as? JSONObject else { return nil }
        let quotes = json["quotes"] as? [JSONObject] ?? []
        let preferred = quotes.first { ["EQUITY", "ETF", "INDEX", "CRYPTOCURRENCY", "MUTUALFUND"].contains($0.string("quoteType") ?? "") }
        return (preferred ?? quotes.first)?.string("symbol")
    }

    // MARK: Formatting

    static func format(_ value: Double, digits: Int? = nil) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        let places = digits ?? (abs(value) >= 100 ? 2 : abs(value) >= 1 ? 2 : 4)
        f.minimumFractionDigits = min(2, places)
        f.maximumFractionDigits = places
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }
}
