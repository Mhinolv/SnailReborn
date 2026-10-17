import XCTest
@testable import SnailCore

final class DataBudgetTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_000)

    private func sample(_ budget: inout DataBudget, _ down: UInt64, _ up: UInt64 = 0,
                        second: Double, interface: String? = "en12") {
        budget.sample(interface: interface, counters: InterfaceCounters(bytesIn: down, bytesOut: up),
                      at: date.addingTimeInterval(second))
    }

    func testSIUnitsBoundsAndThreshold() {
        for unit in DataBudget.Unit.allCases {
            var budget = DataBudget()
            XCTAssertTrue(budget.setAmount(1, unit: unit))
            XCTAssertEqual(budget.limitBytes, unit == .mb ? 1_000_000 : 1_000_000_000)
            budget.setEnabled(true)
            sample(&budget, 0, second: 0)
            sample(&budget, budget.limitBytes * 9 / 10, second: 1)
            XCTAssertFalse(budget.showsAlert)
            XCTAssertEqual(budget.progress, 0.9, accuracy: 0.0001)
            sample(&budget, budget.limitBytes - 1, 1, second: 2)
            XCTAssertTrue(budget.showsAlert)
            XCTAssertEqual(budget.remainingBytes, 0)
            XCTAssertEqual(budget.progress, 1)
            sample(&budget, budget.limitBytes + 1, 1, second: 3)
            XCTAssertEqual(budget.remainingBytes, 0)
            budget.dismiss()
            XCTAssertFalse(budget.showsAlert)
            budget.setEnabled(false)
            budget.setEnabled(true)
            XCTAssertFalse(budget.showsAlert)
            budget.reset()
            XCTAssertEqual(budget.usedBytes, 0)
            XCTAssertFalse(budget.dismissed)
            sample(&budget, 10, second: 4)
            sample(&budget, budget.limitBytes + 10, second: 5)
            XCTAssertTrue(budget.showsAlert)
            XCTAssertTrue(budget.setAmount(DataBudget.maximumAmount, unit: unit))
            XCTAssertEqual(budget.limitBytes, UInt64(DataBudget.maximumAmount) * unit.bytes)
            for invalid in [Int.min, -1, 0, DataBudget.maximumAmount + 1, Int.max] {
                XCTAssertFalse(budget.setAmount(invalid, unit: unit))
                XCTAssertEqual(budget.amount, DataBudget.maximumAmount)
            }
        }
    }

    func testCounterGapsResetsInterfacesAndDisabledSamples() {
        var budget = DataBudget()
        sample(&budget, 10, second: 0)
        sample(&budget, 100, second: 1)
        XCTAssertEqual(budget.usedBytes, 0)
        budget.setEnabled(true)
        sample(&budget, 1_000, second: 2)
        sample(&budget, 1_100, 50, second: 3)
        XCTAssertEqual(budget.usedBytes, 150)
        sample(&budget, 100_000, second: 4, interface: "en13")
        sample(&budget, 100_001, second: 5, interface: "en13")
        XCTAssertEqual(budget.usedBytes, 151)
        sample(&budget, 2, second: 6, interface: "en13")
        sample(&budget, 3, second: 7, interface: "en13")
        XCTAssertEqual(budget.usedBytes, 152)
        sample(&budget, 3, second: 8, interface: nil)
        sample(&budget, 200_000, second: 9)
        sample(&budget, 200_001, second: 10)
        XCTAssertEqual(budget.usedBytes, 153)
        budget.sample(interface: "en12", counters: nil, at: date.addingTimeInterval(11))
        sample(&budget, 300_000, second: 12)
        sample(&budget, 300_001, second: 12)
        sample(&budget, 300_002, second: 11)
        XCTAssertEqual(budget.usedBytes, 153)
        budget.setEnabled(false)
        sample(&budget, 400_000, second: 13)
        budget.setEnabled(true)
        sample(&budget, 500_000, second: 14)
        XCTAssertEqual(budget.usedBytes, 153)
    }

    func testOverflowSaturates() {
        var budget = DataBudget()
        budget.setEnabled(true)
        sample(&budget, 0, second: 0)
        sample(&budget, .max, .max, second: 1)
        XCTAssertEqual(budget.usedBytes, .max)
        XCTAssertEqual(budget.remainingBytes, 0)
        XCTAssertEqual(budget.progress, 1)
        XCTAssertTrue(budget.showsAlert)
    }

    func testPersistenceDefaultsAndInvalidDocuments() throws {
        let suite = "DataBudgetTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(DataBudget.load(from: defaults), DataBudget())
        var budget = DataBudget()
        budget.setEnabled(true)
        budget.setAmount(1, unit: .gb)
        sample(&budget, 0, second: 0)
        sample(&budget, 1_000_000_000, second: 1)
        budget.dismiss()
        try budget.save(to: defaults)
        var restored = DataBudget.load(from: defaults)
        XCTAssertEqual(restored, budget)
        sample(&restored, 2_000_000_000, second: 2)
        XCTAssertEqual(restored.usedBytes, budget.usedBytes)
        XCTAssertFalse(restored.showsAlert)
        restored.reset()
        try restored.save(to: defaults)
        XCTAssertEqual(DataBudget.load(from: defaults).usedBytes, 0)
        for document in ["{}", "{\"version\":1}"] {
            defaults.set(Data(document.utf8), forKey: DataBudget.key)
            XCTAssertEqual(DataBudget.load(from: defaults), DataBudget())
        }
        for document in ["garbage", "{\"version\":2}", "{\"amount\":0}",
                         "{\"amount\":1000001}", "{\"unit\":\"TB\"}", "{\"usedBytes\":-1}"] {
            defaults.set(Data(document.utf8), forKey: DataBudget.key)
            XCTAssertEqual(DataBudget.load(from: defaults), DataBudget())
        }
    }
}
