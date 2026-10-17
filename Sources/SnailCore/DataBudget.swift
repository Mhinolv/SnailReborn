import Foundation

/// A separate total keeps history deletion and retention independent of the budget.
public struct DataBudget: Codable, Equatable {
    public enum Unit: String, Codable, CaseIterable {
        case mb = "MB", gb = "GB"
        public var bytes: UInt64 { self == .mb ? 1_000_000 : 1_000_000_000 }
    }

    public static let key = "dataBudget"
    public static func amountRange(for unit: Unit) -> ClosedRange<Int> {
        unit == .mb ? 100...10_000_000 : 1...10_000
    }

    public static func isValidAmount(_ amount: Int, unit: Unit) -> Bool {
        amountRange(for: unit).contains(amount)
    }
    public private(set) var enabled = false
    public private(set) var amount = 1_000
    public private(set) var unit = Unit.mb
    public private(set) var usedBytes: UInt64 = 0
    public private(set) var dismissed = false
    private var previous: (interface: String, counters: InterfaceCounters, date: Date)?

    public init() { }

    public var limitBytes: UInt64 { UInt64(amount) * unit.bytes }
    public var remainingBytes: UInt64 { usedBytes >= limitBytes ? 0 : limitBytes - usedBytes }
    public var progress: Double { min(Double(usedBytes) / Double(limitBytes), 1) }
    public var showsAlert: Bool { enabled && usedBytes >= limitBytes && !dismissed }

    public mutating func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        previous = nil
    }

    @discardableResult
    public mutating func setAmount(_ value: Int, unit: Unit) -> Bool {
        guard Self.isValidAmount(value, unit: unit) else { return false }
        amount = value
        self.unit = unit
        return true
    }

    public mutating func dismiss() { dismissed = true }

    public mutating func reset() {
        usedBytes = 0
        dismissed = false
        previous = nil
    }

    public mutating func sample(interface: String?, counters: InterfaceCounters?, at date: Date) {
        guard enabled, let interface, let counters else { previous = nil; return }
        let prior = previous
        previous = (interface, counters, date)
        guard let prior, prior.interface == interface, date > prior.date,
              counters.bytesIn >= prior.counters.bytesIn, counters.bytesOut >= prior.counters.bytesOut else { return }
        usedBytes = Self.add(usedBytes, Self.add(counters.bytesIn - prior.counters.bytesIn,
                                              counters.bytesOut - prior.counters.bytesOut))
    }

    private static func add(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? .max : sum
    }

    public static func load(from defaults: UserDefaults) -> DataBudget {
        guard let data = defaults.data(forKey: key),
              let budget = try? JSONDecoder().decode(Self.self, from: data) else { return DataBudget() }
        return budget
    }

    public func save(to defaults: UserDefaults) throws {
        defaults.set(try JSONEncoder().encode(self), forKey: Self.key)
    }

    private enum CodingKeys: String, CodingKey { case version, enabled, amount, unit, usedBytes, dismissed }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard version == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: values, debugDescription: "Unsupported budget version")
        }
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        amount = try values.decodeIfPresent(Int.self, forKey: .amount) ?? 1_000
        unit = try values.decodeIfPresent(Unit.self, forKey: .unit) ?? .mb
        usedBytes = try values.decodeIfPresent(UInt64.self, forKey: .usedBytes) ?? 0
        dismissed = try values.decodeIfPresent(Bool.self, forKey: .dismissed) ?? false
        guard amount > 0, amount <= max(Self.amountRange(for: unit).upperBound, 1_000_000) else {
            throw DecodingError.dataCorruptedError(forKey: .amount, in: values, debugDescription: "Invalid budget amount")
        }
        // Keep totals and dismissal from version 1 budgets outside the corrected range.
        let range = Self.amountRange(for: unit)
        amount = min(max(amount, range.lowerBound), range.upperBound)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(1, forKey: .version)
        try values.encode(enabled, forKey: .enabled)
        try values.encode(amount, forKey: .amount)
        try values.encode(unit, forKey: .unit)
        try values.encode(usedBytes, forKey: .usedBytes)
        try values.encode(dismissed, forKey: .dismissed)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.enabled == rhs.enabled && lhs.amount == rhs.amount && lhs.unit == rhs.unit &&
        lhs.usedBytes == rhs.usedBytes && lhs.dismissed == rhs.dismissed
    }
}
