import Foundation

public struct UsageDay: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var bytesIn: UInt64 = 0
    public var bytesOut: UInt64 = 0
    public var observedSeconds: Double = 0

    public init(id: String, bytesIn: UInt64 = 0, bytesOut: UInt64 = 0, observedSeconds: Double = 0) {
        self.id = id
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.observedSeconds = observedSeconds
    }

    private enum CodingKeys: String, CodingKey { case id, bytesIn, bytesOut, observedSeconds }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        bytesIn = try values.decodeIfPresent(UInt64.self, forKey: .bytesIn) ?? 0
        bytesOut = try values.decodeIfPresent(UInt64.self, forKey: .bytesOut) ?? 0
        observedSeconds = try values.decodeIfPresent(Double.self, forKey: .observedSeconds) ?? 0
    }
}

/// Only counter deltas from continuous observations enter the saved totals.
public struct UsageHistory {
    public private(set) var days: [UsageDay]
    private var previous: (interface: String, counters: InterfaceCounters, date: Date)?
    public static let key = "usageHistory"

    public init(days: [UsageDay] = []) { self.days = days }

    public static func dayID(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    public mutating func prune(at date: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: date)
        let oldest = Self.dayID(calendar.date(byAdding: .day, value: -29, to: today)!, calendar: calendar)
        let newest = Self.dayID(today, calendar: calendar)
        var seen = Set<String>()
        days.removeAll {
            $0.id < oldest || $0.id > newest ||
            $0.id.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) == nil ||
            !$0.observedSeconds.isFinite || $0.observedSeconds < 0 || !seen.insert($0.id).inserted
        }
        days.sort { $0.id > $1.id }
    }

    public mutating func sample(interface: String?, counters: InterfaceCounters?, at date: Date,
                                calendar: Calendar = .current) {
        let dayChanged = previous.map {
            Self.dayID($0.date, calendar: calendar) != Self.dayID(date, calendar: calendar)
        } ?? true
        if dayChanged { prune(at: date, calendar: calendar) }
        guard let interface, let counters else { previous = nil; return }
        let prior = previous
        previous = (interface, counters, date)
        guard let prior, prior.interface == interface else { return }
        let duration = date.timeIntervalSince(prior.date)
        guard duration > 0,
              counters.bytesIn >= prior.counters.bytesIn, counters.bytesOut >= prior.counters.bytesOut else { return }
        var remainingIn = counters.bytesIn - prior.counters.bytesIn
        var remainingOut = counters.bytesOut - prior.counters.bytesOut
        let oldest = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: date))!
        let startDate = max(prior.date, oldest)
        if startDate > prior.date {
            let retainedFraction = date.timeIntervalSince(startDate) / duration
            remainingIn = Self.portion(remainingIn, fraction: retainedFraction)
            remainingOut = Self.portion(remainingOut, fraction: retainedFraction)
        }
        var start = startDate
        while start < date {
            let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start))!
            let end = min(midnight, date)
            let fraction = end.timeIntervalSince(start) / date.timeIntervalSince(start)
            let down = end == date ? remainingIn : Self.portion(remainingIn, fraction: fraction)
            let up = end == date ? remainingOut : Self.portion(remainingOut, fraction: fraction)
            let id = Self.dayID(start, calendar: calendar)
            if !days.contains(where: { $0.id == id }) { days.append(UsageDay(id: id)) }
            let index = days.firstIndex(where: { $0.id == id })!
            days[index].bytesIn = Self.add(days[index].bytesIn, down)
            days[index].bytesOut = Self.add(days[index].bytesOut, up)
            days[index].observedSeconds += end.timeIntervalSince(start)
            remainingIn -= down
            remainingOut -= up
            start = end
        }
        if dayChanged { prune(at: date, calendar: calendar) }
    }

    public mutating func clear() { days = []; previous = nil }

    public static func load(from defaults: UserDefaults, at date: Date = Date(),
                            calendar: Calendar = .current) -> UsageHistory {
        guard let data = defaults.data(forKey: key),
              let document = try? JSONDecoder().decode(Document.self, from: data), document.version == 1 else {
            return UsageHistory()
        }
        var history = UsageHistory(days: document.days)
        history.prune(at: date, calendar: calendar)
        return history
    }

    public func save(to defaults: UserDefaults) throws {
        defaults.set(try JSONEncoder().encode(Document(days: days)), forKey: Self.key)
    }

    private static func portion(_ bytes: UInt64, fraction: Double) -> UInt64 {
        let value = Double(bytes) * fraction
        return value >= Double(UInt64.max) ? .max : UInt64(value)
    }

    private static func add(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? .max : sum
    }

    private struct Document: Codable {
        var version = 1
        var days: [UsageDay] = []

        init(days: [UsageDay]) { self.days = days }
        private enum CodingKeys: String, CodingKey { case version, days }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
            days = try values.decodeIfPresent([UsageDay].self, forKey: .days) ?? []
        }
    }
}
