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
        model.budgetAmountText = "100"
        model.commitBudgetAmount()
        model.setBudgetEnabled(true)
        let date = Date()
        model.recordUsage(interface: "en12", counters: InterfaceCounters(bytesIn: 100, bytesOut: 100), at: date)
        model.recordUsage(interface: "en12", counters: InterfaceCounters(bytesIn: 90_000_100, bytesOut: 10_000_100),
                          at: date.addingTimeInterval(1))
        XCTAssertTrue(model.budget.showsAlert)
        XCTAssertEqual(makeModel().budget.usedBytes, 100_000_000)
        model.dismissBudgetAlert()
        XCTAssertFalse(makeModel().budget.showsAlert)
        XCTAssertTrue(makeModel().budget.dismissed)
        model.setBudgetEnabled(false)
        model.setBudgetEnabled(true)
        XCTAssertFalse(model.budget.showsAlert)
        model.clearUsageHistory()
        XCTAssertEqual(model.budget.usedBytes, 100_000_000)
        model.recordUsage(interface: "en12", counters: InterfaceCounters(bytesIn: 100_000_100, bytesOut: 10_000_100),
                          at: date.addingTimeInterval(2))
        let history = model.usageDays
        model.resetBudget()
        XCTAssertEqual(model.usageDays, history)
        XCTAssertEqual(makeModel().budget.usedBytes, 0)
        XCTAssertFalse(makeModel().budget.dismissed)
        model.recordUsage(interface: "en12", counters: InterfaceCounters(bytesIn: 200_000_100, bytesOut: 10_000_100),
                          at: date.addingTimeInterval(3))
        model.recordUsage(interface: "en12", counters: InterfaceCounters(bytesIn: 300_000_100, bytesOut: 10_000_100),
                          at: date.addingTimeInterval(4))
        XCTAssertTrue(model.budget.showsAlert)
        model.budgetAmountText = "invalid"
        model.commitBudgetAmount()
        XCTAssertNotNil(model.budgetValidationMessage)
        XCTAssertEqual(model.budget.amount, 100)
        model.budgetAmountText = "2"
        model.chooseBudgetUnit(.gb)
        XCTAssertEqual(model.budget.limitBytes, 2_000_000_000)
        model.recordUsage(interface: "en12", counters: InterfaceCounters(bytesIn: 300_000_200, bytesOut: 10_000_100),
                          at: date.addingTimeInterval(5))
        XCTAssertTrue(model.prepareToQuit())
        XCTAssertEqual(makeModel().budget, model.budget)
        XCTAssertTrue(runner.scripts.isEmpty)
    }

    @MainActor
    func testOverBudgetTextAndValidation() async throws {
        let suite = "DataBudgetTextTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = SnailModel(defaults: defaults, wifiInterface: "en12", samplesAutomatically: false)
        model.budgetAmountText = "100"
        model.commitBudgetAmount()
        model.setBudgetEnabled(true)
        XCTAssertEqual(model.budgetRemainingText, "100 MB")
        XCTAssertEqual(model.budgetCaption, "Budget: 100 MB left")
        let date = Date()
        model.recordUsage(interface: "en12", counters: InterfaceCounters(bytesIn: 0, bytesOut: 0), at: date)
        model.recordUsage(interface: "en12", counters: InterfaceCounters(bytesIn: 80_000_000, bytesOut: 20_000_000),
                          at: date.addingTimeInterval(1))
        XCTAssertEqual(model.budgetRemainingText, "0 bytes")
        XCTAssertEqual(model.budgetCaption, "Budget: 0 bytes left")
        model.recordUsage(interface: "en12", counters: InterfaceCounters(bytesIn: 90_000_000, bytesOut: 30_000_000),
                          at: date.addingTimeInterval(2))
        XCTAssertEqual(model.budgetRemainingText, "0 bytes (20 MB over)")
        XCTAssertEqual(model.budgetCaption, "Budget: 20 MB over")
        XCTAssertEqual(model.budgetAlertDetail, "You used 120 MB of Wi-Fi data. Snail does not stop traffic.")
        model.budgetAmountText = "99"
        XCTAssertEqual(model.budgetValidationMessage, "Enter a whole number from 100 MB to 10,000 GB.")
        model.commitBudgetAmount()
        XCTAssertEqual(model.budget.amount, 100)
    }

    @MainActor
    func testUnitChangesValidateTheSelectedUnit() async throws {
        let suite = "DataBudgetUnitTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = SnailModel(defaults: defaults, wifiInterface: "en12", samplesAutomatically: false)
        let message = "Enter a whole number from 100 MB to 10,000 GB."
        for (unit, minimum, maximum) in [(DataBudget.Unit.mb, 100, 10_000_000), (.gb, 1, 10_000)] {
            model.chooseBudgetUnit(unit)
            for amount in [minimum, maximum] {
                model.budgetAmountText = String(amount)
                XCTAssertNil(model.budgetValidationMessage)
                model.commitBudgetAmount()
                XCTAssertEqual(model.budget.limitBytes, UInt64(amount) * unit.bytes)
            }
            for text in [String(minimum - 1), String(maximum + 1), "-1", "1.5", "", "invalid", String(Int.max)] {
                model.budgetAmountText = text
                XCTAssertEqual(model.budgetValidationMessage, message)
                model.commitBudgetAmount()
                XCTAssertEqual(model.budget.amount, maximum)
            }
        }
        model.budgetAmountText = "10000000"
        model.chooseBudgetUnit(.mb)
        XCTAssertNil(model.budgetValidationMessage)
        model.chooseBudgetUnit(.gb)
        XCTAssertEqual(model.budgetUnit, .gb)
        XCTAssertEqual(model.budgetValidationMessage, message)
        XCTAssertEqual(model.budget.unit, .mb)
        XCTAssertEqual(DataBudget.load(from: defaults).unit, .mb)
        model.budgetAmountText = "10000"
        model.commitBudgetAmount()
        XCTAssertEqual(model.budget.unit, .gb)
        XCTAssertNil(model.budgetValidationMessage)
    }

    private final class SpyRunner: PrivilegedRunner {
        var scripts: [String] = []
        func run(_ script: String) { scripts.append(script) }
    }
}
