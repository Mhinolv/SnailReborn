import XCTest
import SnailCore
@testable import SnailApp

final class RemoteAddressModelTests: XCTestCase {
    @MainActor
    func testStageCanonicalTargetClearAndRestorePreferences() async throws {
        let name = "SnailAddressTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let controller = ThrottleController(runner: SpyRunner(), statePath: NSTemporaryDirectory() + UUID().uuidString)
        let model = SnailModel(defaults: defaults, controller: controller, wifiInterface: "en12", samplesAutomatically: false)
        model.debugSimulate(active: model.desiredConfig, error: nil)
        model.remoteAddressText = "2001:0DB8:0:0::1"
        XCTAssertFalse(model.hasPendingChanges)
        model.commitRemoteAddress()
        XCTAssertEqual(model.remoteAddressText, "2001:db8::1")
        XCTAssertTrue(model.hasPendingChanges)
        let restored = SnailModel(defaults: defaults, controller: controller, wifiInterface: "en12", samplesAutomatically: false)
        XCTAssertEqual(restored.remoteAddress, "2001:db8::1")
        XCTAssertTrue(try XCTUnwrap(model.desiredConfig).summary.hasSuffix(" · from 2001:db8::1"))
        model.beginSaveProfile()
        model.profileName = "Server"
        model.confirmProfile()
        let profile = try XCTUnwrap(model.selectedProfile)
        model.remoteAddressText = ""
        model.commitRemoteAddress()
        XCTAssertNil(model.remoteAddress)
        XCTAssertFalse(model.hasPendingChanges)
        XCTAssertNil(model.selectedProfile)
        model.chooseProfile(profile.id)
        XCTAssertEqual(model.remoteAddressText, "2001:db8::1")
    }

    @MainActor
    func testInvalidTextKeepsTargetAndBlocksApplyForEveryScope() async throws {
        let name = "SnailAddressTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let runner = SpyRunner()
        let controller = ThrottleController(runner: runner, statePath: NSTemporaryDirectory() + UUID().uuidString)
        let model = SnailModel(defaults: defaults, controller: controller, wifiInterface: "en12", samplesAutomatically: false)
        model.remoteAddressText = "203.0.113.10"
        model.commitRemoteAddress()
        for scope in ThrottleConfig.Scope.allCases {
            model.scope = scope
            model.portsText = "443"
            model.commitPorts()
            model.debugSimulate(active: model.desiredConfig, error: nil)
            model.remoteAddressText = "host.example.com"
            model.commitRemoteAddress()
            XCTAssertEqual(model.remoteAddress, "203.0.113.10")
            XCTAssertFalse(model.hasPendingChanges)
            model.apply()
            XCTAssertEqual(model.errorMessage, ThrottleConfig.remoteAddressError)
            XCTAssertFalse(model.isBusy)
            XCTAssertTrue(runner.scripts.isEmpty)
        }
    }

    @MainActor
    func testApplyUsesCurrentValidDraft() async throws {
        let name = "SnailAddressTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let called = expectation(description: "The runner receives the target")
        let runner = SpyRunner()
        runner.onRun = { called.fulfill() }
        let controller = ThrottleController(runner: runner, statePath: NSTemporaryDirectory() + UUID().uuidString)
        let model = SnailModel(defaults: defaults, controller: controller, wifiInterface: "en12", samplesAutomatically: false)
        model.remoteAddressText = "2001:0DB8::1"
        model.apply()
        await fulfillment(of: [called], timeout: 2)
        XCTAssertTrue(try XCTUnwrap(runner.scripts.first).contains("from 2001:db8::1 port 443 to any"))
    }

    private final class SpyRunner: PrivilegedRunner {
        var scripts: [String] = []
        var onRun: (() -> Void)?
        func run(_ script: String) { scripts.append(script); onRun?() }
    }
}
