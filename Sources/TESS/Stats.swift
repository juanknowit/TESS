import Darwin
import Foundation

/// One day's worth of activity.
struct DayUsage: Codable {
    var requests = 0
    var inputTokens = 0
    var outputTokens = 0
    var commands = 0
    var typedCommands = 0
    var toolCalls = 0
    var webSearches = 0
    var spokenCharacters = 0
    var cloudVoiceCharacters = 0
    /// Total tokens per provider name ("Claude", "OpenAI", "Ollama").
    var tokensByProvider: [String: Int] = [:]

    var totalTokens: Int { inputTokens + outputTokens }

    mutating func add(_ other: DayUsage) {
        requests += other.requests
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        commands += other.commands
        typedCommands += other.typedCommands
        toolCalls += other.toolCalls
        webSearches += other.webSearches
        spokenCharacters += other.spokenCharacters
        cloudVoiceCharacters += other.cloudVoiceCharacters
        for (key, value) in other.tokensByProvider { tokensByProvider[key, default: 0] += value }
    }
}

struct UsageData: Codable {
    var days: [String: DayUsage] = [:]
    var tools: [String: Int] = [:]
    var models: [String: Int] = [:]
    var since: Date = Date()
}

/// Records what TESS does (AI requests, tokens, commands, tools, speech) and keeps it on disk.
@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published private(set) var data: UsageData
    @Published private(set) var lastRequest: LastRequest?
    let launchedAt = Date()

    struct LastRequest {
        let provider: String
        let model: String
        let tokens: Int
        let date: Date
    }

    private let url: URL
    private var saveScheduled = false

    private init() {
        url = AppPaths.directory.appendingPathComponent("usage.json")
        if let raw = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(UsageData.self, from: raw) {
            data = decoded
        } else {
            data = UsageData()
        }
    }

    // MARK: Recording

    func recordRequest(provider: String, model: String, input: Int, output: Int, webSearches: Int) {
        update { day in
            day.requests += 1
            day.inputTokens += input
            day.outputTokens += output
            day.webSearches += webSearches
            day.tokensByProvider[provider, default: 0] += input + output
        }
        data.models["\(provider) · \(model)", default: 0] += 1
        lastRequest = LastRequest(provider: provider, model: model, tokens: input + output, date: Date())
    }

    func recordTool(_ name: String) {
        update { $0.toolCalls += 1 }
        data.tools[name, default: 0] += 1
    }

    func recordCommand(typed: Bool) {
        update { day in
            day.commands += 1
            if typed { day.typedCommands += 1 }
        }
    }

    func recordSpeech(characters: Int, cloud: Bool) {
        update { day in
            day.spokenCharacters += characters
            if cloud { day.cloudVoiceCharacters += characters }
        }
    }

    func reset() {
        data = UsageData()
        scheduleSave()
    }

    // MARK: Reading

    var today: DayUsage { data.days[Self.key(Date())] ?? DayUsage() }

    func total(lastDays days: Int? = nil) -> DayUsage {
        var sum = DayUsage()
        if let days {
            for date in Self.recentDates(days) { if let d = data.days[Self.key(date)] { sum.add(d) } }
        } else {
            for d in data.days.values { sum.add(d) }
        }
        return sum
    }

    /// Oldest first, including days with no activity.
    func series(days: Int) -> [(date: Date, usage: DayUsage)] {
        Self.recentDates(days).reversed().map { ($0, data.days[Self.key($0)] ?? DayUsage()) }
    }

    var topTools: [(name: String, count: Int)] {
        data.tools.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
    }

    var topModels: [(name: String, count: Int)] {
        data.models.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }

    // MARK: Internals

    private func update(_ change: (inout DayUsage) -> Void) {
        let key = Self.key(Date())
        var day = data.days[key] ?? DayUsage()
        change(&day)
        data.days[key] = day
        scheduleSave()
    }

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self else { return }
            self.saveScheduled = false
            if let encoded = try? JSONEncoder().encode(self.data) {
                try? encoded.write(to: self.url, options: .atomic)
            }
        }
    }

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ date: Date) -> String { keyFormatter.string(from: date) }

    /// Today first.
    static func recentDates(_ days: Int) -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<max(1, days)).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }
}

/// Where TESS keeps its own files: ~/Library/Application Support/TESS (TESS Dev: …/TESS Dev).
/// Every file TESS writes for itself must live in here.
enum AppPaths {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = AppFlavor.current.supportDirectory(in: base)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}

/// Live numbers about the running app.
enum SystemStats {
    /// Memory TESS is using right now, as Activity Monitor reports it.
    static func memoryFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    static var physicalMemory: UInt64 { ProcessInfo.processInfo.physicalMemory }

    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    static func compact(_ n: Int) -> String {
        switch n {
        case ..<1_000: return "\(n)"
        case ..<1_000_000: return String(format: "%.1fK", Double(n) / 1_000).replacingOccurrences(of: ".0K", with: "K")
        default: return String(format: "%.2fM", Double(n) / 1_000_000)
        }
    }

    static func duration(since date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        let d = seconds / 86400, h = (seconds % 86400) / 3600, m = (seconds % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(max(m, 0))m"
    }
}

/// Samples TESS's memory use every two seconds for the live sparkline.
@MainActor
final class MemorySampler: ObservableObject {
    static let shared = MemorySampler()
    @Published private(set) var samples: [Double] = []
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in MemorySampler.shared.sample() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        samples.append(Double(SystemStats.memoryFootprint()))
        if samples.count > 60 { samples.removeFirst(samples.count - 60) }
    }
}
