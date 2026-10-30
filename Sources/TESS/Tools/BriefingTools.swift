import Foundation

/// Morning briefing: weather, today's calendar, reminders and headlines gathered in one call.
enum BriefingTools {
    static func all(_ context: ToolContext) -> [Tool] { [briefing(context)] }

    static func briefing(_ context: ToolContext) -> Tool {
        Tool.rich(
            name: "get_briefing",
            description: "Everything for a morning briefing in one call: today's weather, calendar, open reminders and top headlines. Use when the user says good morning or asks for a briefing or a rundown of their day."
        ) { _ in
            let weatherTool = InfoTools.weather(context)
            let newsTool = InfoTools.news(context)

            async let weather = section("Weather", weatherTool, ["days": 1])
            async let calendar = section("Today's calendar", CalendarTools.getEvents, [:])
            async let reminders = section("Open reminders (soonest first)", CalendarTools.getReminders, [:], maxLines: 8)
            async let news = section("Top headlines", newsTool, ["count": 5])

            let parts = await [weather, calendar, reminders, news]
            let intro = """
            Deliver a spoken morning briefing of about six short sentences: a greeting, the weather, \
            the calendar highlights (times and the first meeting), anything due today from reminders, \
            and one or two headlines. Skip any section that's unavailable without dwelling on it.
            """
            return ToolOutput(text: intro + "\n\n" + parts.joined(separator: "\n\n"), limit: 9000)
        }
    }

    private static func section(_ title: String, _ tool: Tool, _ args: JSONObject, maxLines: Int? = nil) async -> String {
        do {
            var text = try await tool.text(args)
            if let maxLines {
                text = text.split(separator: "\n").prefix(maxLines).joined(separator: "\n")
            }
            return "## \(title)\n\(text)"
        } catch {
            return "## \(title)\nUnavailable: \(error.localizedDescription)"
        }
    }
}
