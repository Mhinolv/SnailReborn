import XCTest
import SnailCore
@testable import SnailApp

final class UsageHistoryModelTests: XCTestCase {
    @MainActor
    func testQuitSavesRestartRestoresAndClearRemovesOnlyHistory() async throws {
        let suite = "UsageHistoryModelTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runner = SpyRunner()
        let controller = ThrottleController(runner: runner, statePath: NSTemporaryDirectory() + UUID().uuidString)
        func model() -> SnailModel {
            SnailModel(defaults: defaults, controller: controller, wifiInterface: "en12", samplesAutomatically: false)
        }
        let first = model()
        let date = Date()
        first.kbps = 3000
        first.recordUsage(interface: "en12", counters: InterfaceCounters(bytesIn: 100, bytesOut: 200), at: date)
        first.recordUsage(interface: "en12", counters: InterfaceCounters(bytesIn: 400, bytesOut: 220),
                          at: date.addingTimeInterval(1))
        XCTAssertTrue(first.prepareToQuit())
        let restored = model()
        XCTAssertEqual(restored.usageDays, first.usageDays)
        XCTAssertEqual(restored.usageDays.first?.bytesIn, 300)
        restored.usageClearPresented = true
        restored.clearUsageHistory()
        XCTAssertFalse(restored.usageClearPresented)
        XCTAssertTrue(restored.usageRows.isEmpty)
        XCTAssertEqual(restored.todayUsageText, "No data yet")
        XCTAssertNil(defaults.object(forKey: UsageHistory.key))
        XCTAssertTrue(model().usageDays.isEmpty)
        XCTAssertEqual(model().kbps, 3000)
        XCTAssertTrue(runner.scripts.isEmpty)
    }

    @MainActor
    func testGapRowsZeroDataAndRolloverWithoutCounters() async throws {
        let suite = "UsageHistoryModelTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runner = SpyRunner()
        let model = SnailModel(defaults: defaults,
                               controller: ThrottleController(runner: runner, statePath: NSTemporaryDirectory() + UUID().uuidString),
                               wifiInterface: nil, samplesAutomatically: false)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date()).addingTimeInterval(3600)
        let oldest = calendar.date(byAdding: .day, value: -3, to: today)!
        let counters = InterfaceCounters(bytesIn: 100, bytesOut: 100)
        model.recordUsage(interface: "en12", counters: counters, at: oldest)
        model.recordUsage(interface: "en12", counters: counters, at: oldest.addingTimeInterval(1))
        model.recordUsage(interface: nil, counters: nil, at: today)
        XCTAssertEqual(model.usageRows.count, 4)
        XCTAssertEqual(model.usageRows.map(\.label).prefix(2), ["Today", "Yesterday"])
        XCTAssertNil(model.usageRows.first?.totals)
        XCTAssertEqual(model.usageRows.last?.totals?.bytesIn, 0)
        XCTAssertEqual(model.todayUsageText, "No data yet")
        model.recordUsage(interface: "en12", counters: counters, at: today.addingTimeInterval(1))
        model.recordUsage(interface: "en12", counters: counters, at: today.addingTimeInterval(2))
        XCTAssertEqual(model.usageRows.first?.totals?.bytesIn, 0)
        XCTAssertNotEqual(model.todayUsageText, "No data yet")
        XCTAssertTrue(runner.scripts.isEmpty)
    }

    private final class SpyRunner: PrivilegedRunner {
        var scripts: [String] = []
        func run(_ script: String) { scripts.append(script) }
    }
}
