import XCTest
import SnailCore
@testable import SnailApp

final class CustomPortsModelTests: XCTestCase {
    @MainActor
    func testInvalidDraftKeepsLastPortsAndBlocksApply() async throws {
        let name = "SnailPortsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let runner = SpyRunner()
        let path = NSTemporaryDirectory() + UUID().uuidString
        let controller = ThrottleController(runner: runner, statePath: path)
        let model = SnailModel(defaults: defaults, controller: controller, wifiInterface: "en12", sample: false)
        XCTAssertEqual(model.scope, .web)
        XCTAssertEqual(model.ports, [])
        model.scope = .custom
        model.portsText = "25461 8080,25461"
        XCTAssertNil(model.portsValidationMessage)
        model.commitPorts()
        XCTAssertEqual(model.ports, [25461, 8080])
        XCTAssertEqual(model.portsText, "25461, 8080")
        model.portsText = "80;id"
        model.commitPorts()
        XCTAssertEqual(model.ports, [25461, 8080])
        model.apply()
        XCTAssertEqual(model.errorMessage, ThrottleConfig.portsError)
        XCTAssertFalse(model.isBusy)
        XCTAssertTrue(runner.scripts.isEmpty)
        let restored = SnailModel(defaults: defaults, controller: controller, wifiInterface: "en12", sample: false)
        XCTAssertEqual(restored.scope, .custom)
        XCTAssertEqual(restored.portsText, "25461, 8080")
    }

    @MainActor
    func testApplyUsesCurrentDraftAndOtherScopesIgnoreInvalidDraft() async throws {
        for scope in ThrottleConfig.Scope.allCases {
            let name = "SnailPortsTests-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let called = expectation(description: "The runner receives the script for \(scope)")
            let runner = SpyRunner()
            runner.onRun = { called.fulfill() }
            let controller = ThrottleController(runner: runner, statePath: NSTemporaryDirectory() + UUID().uuidString)
            let model = SnailModel(defaults: defaults, controller: controller, wifiInterface: "en12", sample: false)
            model.scope = scope
            model.portsText = scope == .custom ? "1,65535,1" : "invalid"
            model.apply()
            await fulfillment(of: [called], timeout: 2)
            XCTAssertEqual(runner.scripts.count, 1)
            let script = try XCTUnwrap(runner.scripts.first)
            XCTAssertFalse(script.contains("invalid"))
            if scope == .custom {
                XCTAssertEqual(model.ports, [1, 65535])
                XCTAssertTrue(script.contains("from any port { 1 65535 } to any"))
            }
        }
    }

    private final class SpyRunner: PrivilegedRunner {
        var scripts: [String] = []
        var onRun: (() -> Void)?
        func run(_ script: String) {
            scripts.append(script)
            onRun?()
        }
    }
}
