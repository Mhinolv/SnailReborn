import XCTest
import SnailCore
@testable import SnailApp

final class DataBudgetModelTests: XCTestCase {
    @MainActor
    func testBudgetPersistsDismissalResetAndHistoryIndependence() async throws {
        let suite = "DataBudgetModelTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runner = SpyRunner()
        let controller = ThrottleController(runner: runner, statePath: NSTemporaryDirectory() + UUID().uuidString)
        func makeModel() -> SnailModel {
            SnailModel(defaults: defaults, controller: controller, wifiInterface: "en12", samplesAutomatically: false)
        }
        let model = makeModel()
        XCTAssertFalse(model.budget.enabled)
        model.budgetAmountText = "1"
        model.commitBudgetAmount()
        model.setBudgetEnabled(true)
        let date = Date()
        model.recordUsage(interface: "en12", counters: InterfaceCounters(bytesIn: 100, bytesOut: 100), at: date)
        model.recordUsage(interface: "en12", counters: InterfaceCounters(bytesIn: 900_100, bytesOut: 100_100),
                          at: date.addingTimeInterval(1))
        XCTAssertTrue(model.budget.showsAlert)
        XCTAssertEqual(makeModel().budget.usedBytes, 1_000_000)
        model.dismissBudgetAlert()
        XCTAssertFalse(makeModel().budget.showsAlert)
        XCTAssertTrue(makeModel().budget.dismissed)
        model.setBudgetEnabled(false)
        model.setBudgetEnabled(true)
        XCTAssertFalse(model.budget.showsAlert)
        model.clearUsageHistory()
        XCTAssertEqual(model.budget.usedBytes, 1_000_000)
        model.recordUsage(interface: "en12", counters: InterfaceCounters(bytesIn: 1_000_100, bytesOut: 100_100),
                          at: date.addingTimeInterval(2))
        let history = model.usageDays
        model.resetBudget()
        XCTAssertEqual(model.usageDays, history)
        XCTAssertEqual(makeModel().budget.usedBytes, 0)
        XCTAssertFalse(makeModel().budget.dismissed)
        model.recordUsage(interface: "en12", counters: InterfaceCounters(bytesIn: 2_000_100, bytesOut: 100_100),
                          at: date.addingTimeInterval(3))
        model.recordUsage(interface: "en12", counters: InterfaceCounters(bytesIn: 3_000_100, bytesOut: 100_100),
                          at: date.addingTimeInterval(4))
        XCTAssertTrue(model.budget.showsAlert)
        model.budgetAmountText = "invalid"
        model.commitBudgetAmount()
        XCTAssertNotNil(model.budgetValidationMessage)
        XCTAssertEqual(model.budget.amount, 1)
        model.budgetAmountText = "2"
        model.chooseBudgetUnit(.gb)
        XCTAssertEqual(model.budget.limitBytes, 2_000_000_000)
        model.recordUsage(interface: "en12", counters: InterfaceCounters(bytesIn: 3_000_200, bytesOut: 100_100),
                          at: date.addingTimeInterval(5))
        XCTAssertTrue(model.prepareToQuit())
        XCTAssertEqual(makeModel().budget, model.budget)
        XCTAssertTrue(runner.scripts.isEmpty)
    }

    private final class SpyRunner: PrivilegedRunner {
        var scripts: [String] = []
        func run(_ script: String) { scripts.append(script) }
    }
}
