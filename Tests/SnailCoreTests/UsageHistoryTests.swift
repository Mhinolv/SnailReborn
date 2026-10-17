import XCTest
@testable import SnailCore

final class UsageHistoryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    private func sample(_ history: inout UsageHistory, _ date: Date, _ down: UInt64, _ up: UInt64,
                        interface: String = "en12") {
        history.sample(interface: interface, counters: InterfaceCounters(bytesIn: down, bytesOut: up),
                       at: date, calendar: calendar)
    }

    func testDeltasPersistAcrossRestartWithoutCountingOfflineBytes() throws {
        let suite = "UsageHistoryTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = date("2026-10-17T14:00:00Z")
        var history = UsageHistory()
        sample(&history, start, 1_000, 2_000)
        XCTAssertTrue(history.days.isEmpty)
        sample(&history, start.addingTimeInterval(1), 1_300, 2_020)
        try history.save(to: defaults)
        var restored = UsageHistory.load(from: defaults, at: start, calendar: calendar)
        XCTAssertEqual(restored.days, history.days)
        sample(&restored, start.addingTimeInterval(2), 50_000, 60_000)
        sample(&restored, start.addingTimeInterval(3), 50_100, 60_010)
        XCTAssertEqual(restored.days.first?.bytesIn, 400)
        XCTAssertEqual(restored.days.first?.bytesOut, 30)
        XCTAssertEqual(restored.days.first?.observedSeconds, 2)
    }

    func testResetMissingSampleInterfaceChangeAndBackwardClock() {
        let start = date("2026-10-17T14:00:00Z")
        var history = UsageHistory()
        sample(&history, start, 100, 100)
        sample(&history, start.addingTimeInterval(1), 200, 200)
        sample(&history, start.addingTimeInterval(2), 10, 300)
        sample(&history, start.addingTimeInterval(3), 20, 310, interface: "en13")
        history.sample(interface: nil, counters: nil, at: start.addingTimeInterval(4), calendar: calendar)
        sample(&history, start.addingTimeInterval(5), 1_000, 1_000)
        sample(&history, start.addingTimeInterval(99), 20_000, 20_000)
        sample(&history, start.addingTimeInterval(98), 25_000, 25_000)
        sample(&history, start.addingTimeInterval(98), 30_000, 30_000)
        XCTAssertEqual(history.days.first?.bytesIn, 19_100)
        XCTAssertEqual(history.days.first?.bytesOut, 19_100)
        sample(&history, start.addingTimeInterval(100), 30_010, 30_020)
        XCTAssertEqual(history.days.first?.bytesIn, 19_110)
        XCTAssertEqual(history.days.first?.bytesOut, 19_120)
    }

    func testMidnightSplitsDeltaWithoutLoss() {
        let start = date("2026-10-17T03:59:59Z")
        var history = UsageHistory()
        sample(&history, start, 0, 0)
        sample(&history, start.addingTimeInterval(2), 101, 11)
        XCTAssertEqual(history.days.map(\.id), ["2026-10-17", "2026-10-16"])
        XCTAssertEqual(history.days.map(\.bytesIn), [51, 50])
        XCTAssertEqual(history.days.map(\.bytesOut), [6, 5])
        XCTAssertEqual(history.days.map(\.observedSeconds), [1, 1])
    }

    func testThirtyCalendarDaysAcrossDSTAndFutureRows() {
        let today = date("2026-11-15T17:00:00Z")
        var history = UsageHistory(days: [
            UsageDay(id: "2026-11-16"), UsageDay(id: "2026-11-15"),
            UsageDay(id: "2026-10-17"), UsageDay(id: "2026-10-16")
        ])
        history.prune(at: today, calendar: calendar)
        XCTAssertEqual(history.days.map(\.id), ["2026-11-15", "2026-10-17"])
    }

    func testLongIntervalRetainsOnlyThirtyDays() {
        let start = date("2026-09-01T04:00:00Z")
        let end = date("2026-10-17T04:00:00Z")
        var history = UsageHistory()
        sample(&history, start, 0, 0)
        sample(&history, end, 46_000, 92_000)
        XCTAssertEqual(history.days.count, 29)
        XCTAssertEqual(history.days.first?.id, "2026-10-16")
        XCTAssertEqual(history.days.last?.id, "2026-09-18")
        XCTAssertEqual(history.days.reduce(0) { $0 + $1.bytesIn }, 29_000)
        XCTAssertEqual(history.days.reduce(0) { $0 + $1.bytesOut }, 58_000)
    }

    func testZeroAndLargestCountersAndSaturation() {
        let start = date("2026-10-17T14:00:00Z")
        var history = UsageHistory()
        sample(&history, start, 0, 0)
        sample(&history, start.addingTimeInterval(1), 0, 0)
        XCTAssertEqual(history.days.first?.bytesIn, 0)
        sample(&history, start.addingTimeInterval(2), .max, .max)
        XCTAssertEqual(history.days.first?.bytesIn, .max)
        sample(&history, start.addingTimeInterval(3), 0, 0)
        sample(&history, start.addingTimeInterval(4), 1, 1)
        XCTAssertEqual(history.days.first?.bytesIn, .max)
    }

    func testClearResetsBaselineAndLegacyPreferencesStillLoad() throws {
        let suite = "UsageHistoryTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = date("2026-10-17T14:00:00Z")
        defaults.set(3000, forKey: "kbps")
        XCTAssertTrue(UsageHistory.load(from: defaults, at: start).days.isEmpty)
        for json in ["{}", "{\"version\":2}", "broken"] {
            defaults.set(Data(json.utf8), forKey: UsageHistory.key)
            XCTAssertTrue(UsageHistory.load(from: defaults, at: start).days.isEmpty)
        }
        defaults.set(Data(#"{"days":[{"id":"2026-10-17","bytesIn":12}]}"#.utf8), forKey: UsageHistory.key)
        var history = UsageHistory.load(from: defaults, at: start, calendar: calendar)
        XCTAssertEqual(history.days.first?.bytesIn, 12)
        XCTAssertEqual(history.days.first?.bytesOut, 0)
        sample(&history, start, 100, 100)
        history.clear()
        sample(&history, start.addingTimeInterval(1), 200, 200)
        XCTAssertTrue(history.days.isEmpty)
        XCTAssertEqual(defaults.integer(forKey: "kbps"), 3000)
    }
}
