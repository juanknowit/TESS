import EventKit

/// Calendar and Reminders through EventKit (the same data as the Calendar and Reminders apps).
enum CalendarTools {
    static func all() -> [Tool] {
        [getEvents, createEvent, getReminders, createReminder, completeReminder]
    }

    private static var store: EKEventStore { CalendarService.shared.store }

    static let getEvents = Tool(
        name: "get_calendar_events",
        description: "List calendar events. Defaults to today.",
        properties: [
            "start_date": P.string("First day to include, YYYY-MM-DD (default today)"),
            "days": P.integer("Number of days to include (default 1, max 31)"),
        ]
    ) { args in
        try await CalendarService.shared.requireEvents()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: args.string("start_date").flatMap(DateParse.parse) ?? Date())
        let days = max(1, min(31, args.int("days") ?? 1))
        let end = calendar.date(byAdding: .day, value: days, to: start)!
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .sorted { $0.startDate < $1.startDate }
        guard !events.isEmpty else { return days == 1 ? "No events that day." : "No events in those \(days) days." }

        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: "en_US")
        dayFmt.dateFormat = "EEEE d MMMM"
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        return events.prefix(40).map { e in
            let when = e.isAllDay ? "all day" : "\(timeFmt.string(from: e.startDate))–\(timeFmt.string(from: e.endDate))"
            var line = "\(dayFmt.string(from: e.startDate)), \(when): \(e.title ?? "Untitled")"
            if let location = e.location, !location.isEmpty { line += " at \(location)" }
            return line
        }.joined(separator: "\n")
    }

    static let createEvent = Tool(
        name: "create_calendar_event",
        description: "Add an event to the user's default calendar.",
        properties: [
            "title": P.string("Event title"),
            "start": P.string("Local start date-time, YYYY-MM-DDTHH:MM (or YYYY-MM-DD for all-day)"),
            "duration_minutes": P.integer("Length in minutes (default 60)"),
            "all_day": P.boolean("Whether it is an all-day event"),
            "location": P.string("Optional location"),
            "notes": P.string("Optional notes"),
        ],
        required: ["title", "start"]
    ) { args in
        try await CalendarService.shared.requireEvents()
        guard let title = args.string("title"), let startText = args.string("start"), let start = DateParse.parse(startText) else {
            throw TESSError("I need a title and a valid start time.")
        }
        let allDay = args.bool("all_day") ?? !DateParse.hasTime(startText)
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = allDay ? start : start.addingTimeInterval(TimeInterval((args.int("duration_minutes") ?? 60) * 60))
        event.isAllDay = allDay
        event.location = args.string("location")
        event.notes = args.string("notes")
        guard let calendar = store.defaultCalendarForNewEvents else { throw TESSError("There's no default calendar to add events to.") }
        event.calendar = calendar
        try store.save(event, span: .thisEvent, commit: true)
        return "Added \"\(title)\" on \(DateParse.spoken(start)) to the \(calendar.title) calendar."
    }

    static let getReminders = Tool(
        name: "get_reminders",
        description: "List the user's incomplete reminders, soonest due first."
    ) { _ in
        try await CalendarService.shared.requireReminders()
        let reminders = await CalendarService.shared.incompleteReminders()
        guard !reminders.isEmpty else { return "No open reminders." }
        return reminders.prefix(25).map { r in
            let due = r.due.map { " (due \(DateParse.spoken($0)))" } ?? ""
            return "- \(r.title)\(due) [\(r.list)]"
        }.joined(separator: "\n")
    }

    static let createReminder = Tool(
        name: "create_reminder",
        description: "Create a reminder in the default Reminders list, optionally with a due date/time (alerts at that time).",
        properties: [
            "title": P.string("What to be reminded about"),
            "due": P.string("Optional local due date-time, YYYY-MM-DDTHH:MM, or YYYY-MM-DD"),
            "notes": P.string("Optional notes"),
        ],
        required: ["title"]
    ) { args in
        try await CalendarService.shared.requireReminders()
        guard let title = args.string("title") else { throw TESSError("Remind you about what?") }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = args.string("notes")
        guard let list = store.defaultCalendarForNewReminders() else { throw TESSError("There's no default Reminders list.") }
        reminder.calendar = list
        var dueText = ""
        if let text = args.string("due"), let due = DateParse.parse(text) {
            let timed = DateParse.hasTime(text)
            let fields: Set<Calendar.Component> = timed ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            reminder.dueDateComponents = Calendar.current.dateComponents(fields, from: due)
            if timed { reminder.addAlarm(EKAlarm(absoluteDate: due)) }
            dueText = timed ? " for \(DateParse.spoken(due))" : " for \(DateParse.spoken(due).components(separatedBy: " at").first ?? "")"
        }
        try store.save(reminder, commit: true)
        return "Reminder set: \(title)\(dueText)."
    }

    static let completeReminder = Tool(
        name: "complete_reminder",
        description: "Mark an open reminder as done, matching by its title.",
        properties: ["title": P.string("The reminder's title or part of it")],
        required: ["title"]
    ) { args in
        try await CalendarService.shared.requireReminders()
        guard let query = args.string("title")?.lowercased() else { throw TESSError("Which reminder?") }
        guard let title = try await CalendarService.shared.complete(matching: query) else {
            return "No open reminder matches \(query)."
        }
        return "Marked \"\(title)\" as done."
    }
}

final class CalendarService {
    static let shared = CalendarService()
    let store = EKEventStore()

    struct ReminderInfo {
        let title: String
        let due: Date?
        let list: String
    }

    func requireEvents() async throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return
        case .notDetermined:
            if try await store.requestFullAccessToEvents() { return }
            throw TESSError("Calendar access was declined. You can allow it in System Settings, Privacy and Security, Calendars.")
        default:
            throw TESSError("I don't have full calendar access. Allow it in System Settings, Privacy and Security, Calendars.")
        }
    }

    func requireReminders() async throws {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            return
        case .notDetermined:
            if try await store.requestFullAccessToReminders() { return }
            throw TESSError("Reminders access was declined. You can allow it in System Settings, Privacy and Security, Reminders.")
        default:
            throw TESSError("I don't have access to Reminders. Allow it in System Settings, Privacy and Security, Reminders.")
        }
    }

    func incompleteReminders() async -> [ReminderInfo] {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let infos = (reminders ?? []).map { r in
                    ReminderInfo(title: r.title ?? "Untitled",
                                 due: r.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                                 list: r.calendar?.title ?? "")
                }
                continuation.resume(returning: infos.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) })
            }
        }
    }

    /// Completes the first open reminder whose title contains `query`; returns its title.
    func complete(matching query: String) async throws -> String? {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let store = self.store
        return try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let all = reminders ?? []
                guard let match = all.first(where: { ($0.title ?? "").lowercased() == query })
                        ?? all.first(where: { ($0.title ?? "").lowercased().contains(query) }) else {
                    continuation.resume(returning: nil)
                    return
                }
                match.isCompleted = true
                do {
                    try store.save(match, commit: true)
                    continuation.resume(returning: match.title)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
