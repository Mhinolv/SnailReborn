import XCTest
import SnailCore
@testable import SnailApp

final class ProfileModelTests: XCTestCase {
    @MainActor
    func testSelectStagesAllValuesAfterRelaunchWithoutPrompt() async throws {
        for mode in ThrottleConfig.Mode.allCases {
            for scope in ThrottleConfig.Scope.allCases {
                let fixture = try Fixture()
                defer { fixture.cleanUp() }
                let model = fixture.model()
                model.kbps = 64
                model.mode = mode
                model.scope = scope
                model.portsText = "1, 65535, 1"
                model.commitPorts()
                save("  Task  ", on: model)
                let profile = try XCTUnwrap(model.selectedProfile)
                XCTAssertEqual(profile.name, "Task")
                let restored = fixture.model(interface: "en13")
                XCTAssertEqual(restored.profiles, [profile])
                XCTAssertEqual(restored.kbps, 64)
                XCTAssertEqual(restored.mode, mode)
                XCTAssertEqual(restored.scope, scope)
                XCTAssertEqual(restored.ports, [1, 65535])
                restored.kbps = 5000
                restored.mode = mode == .total ? .perStream : .total
                restored.scope = scope == .web ? .all : .web
                restored.portsText = "invalid"
                let active = try XCTUnwrap(restored.desiredConfig)
                restored.debugSimulate(active: active, error: nil)
                restored.chooseProfile(profile.id)
                XCTAssertEqual(restored.kbps, 64)
                XCTAssertEqual(restored.mode, mode)
                XCTAssertEqual(restored.scope, scope)
                XCTAssertEqual(restored.ports, [1, 65535])
                XCTAssertEqual(restored.portsText, "1, 65535")
                XCTAssertEqual(restored.selectedProfile?.id, profile.id)
                XCTAssertEqual(restored.desiredConfig?.interface, "en13")
                XCTAssertEqual(restored.active, active)
                XCTAssertTrue(restored.hasPendingChanges)
                XCTAssertFalse(restored.isBusy)
                // Give any accidentally scheduled apply enough time to reach the runner.
                try await Task.sleep(nanoseconds: 100_000_000)
                XCTAssertTrue(fixture.runner.scripts.isEmpty)
            }
        }
    }

    @MainActor
    func testNameValidationRenameAndDeleteKeepValues() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.model()
        save("First", on: model)
        let firstID = try XCTUnwrap(model.selectedProfile?.id)
        XCTAssertFalse(model.canSaveProfile)
        model.kbps = 3000
        save("Second", on: model)
        let secondID = try XCTUnwrap(model.selectedProfile?.id)
        model.beginRenameProfile()
        for name in ["", " \n", " fIRSt ", String(repeating: "x", count: 33)] {
            model.profileName = name
            XCTAssertFalse(model.canConfirmProfile)
            model.confirmProfile()
            XCTAssertEqual(model.profiles.last?.name, "Second")
        }
        model.profileName = " Second "
        XCTAssertTrue(model.canConfirmProfile)
        model.profileName = " Renamed "
        model.confirmProfile()
        XCTAssertEqual(model.selectedProfile?.id, secondID)
        XCTAssertEqual(model.profiles.last?.name, "Renamed")
        XCTAssertEqual(fixture.model().profiles, model.profiles)
        let staged = model.desiredConfig
        model.beginDeleteProfile()
        model.deleteProfile()
        XCTAssertEqual(model.desiredConfig, staged)
        XCTAssertNil(model.selectedProfile)
        XCTAssertEqual(model.profiles.map(\.id), [firstID])
        XCTAssertEqual(fixture.model().profiles, model.profiles)
        XCTAssertTrue(fixture.runner.scripts.isEmpty)
    }

    @MainActor
    func testLimitInvalidDraftAndDerivedSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.model()
        model.scope = .custom
        model.portsText = "443, 80"
        save("First", on: model)
        let first = try XCTUnwrap(model.selectedProfile)
        model.portsText = "443 80 443"
        XCTAssertEqual(model.selectedProfile, first)
        XCTAssertFalse(model.canSaveProfile)
        model.portsText = "invalid"
        XCTAssertNil(model.selectedProfile)
        XCTAssertFalse(model.canSaveProfile)
        model.beginSaveProfile()
        XCTAssertFalse(model.profileEditorPresented)
        model.chooseProfile(first.id)
        model.chooseProfile(nil)
        XCTAssertEqual(model.selectedProfile, first)
        model.mode = .total
        XCTAssertNil(model.selectedProfile)
        model.mode = .perStream
        model.scope = .all
        XCTAssertNil(model.selectedProfile)
        model.scope = .custom
        model.portsText = "80, 443"
        XCTAssertNil(model.selectedProfile)
        for index in 1..<10 {
            model.kbps = 1500 + index
            save("Profile \(index)", on: model)
        }
        XCTAssertEqual(model.profiles.count, 10)
        model.kbps = 1_000_000
        XCTAssertFalse(model.canSaveProfile)
        model.beginSaveProfile()
        model.profileName = "Eleventh"
        model.confirmProfile()
        XCTAssertEqual(model.profiles.count, 10)
        XCTAssertEqual(fixture.model().profiles.count, 10)
    }

    @MainActor
    func testLegacyPreferencesLoadWithoutProfileDataAndWorkWithoutWifi() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(5000, forKey: "kbps")
        fixture.defaults.set("total", forKey: "mode")
        fixture.defaults.set("all", forKey: "scope")
        fixture.defaults.set(false, forKey: "turnOffOnQuit")
        let model = fixture.model(interface: nil)
        XCTAssertTrue(model.profiles.isEmpty)
        XCTAssertEqual(model.kbps, 5000)
        XCTAssertEqual(model.mode, .total)
        XCTAssertEqual(model.scope, .all)
        XCTAssertEqual(model.ports, [])
        XCTAssertFalse(model.turnOffOnQuit)
        save("Offline", on: model)
        model.kbps = 64
        model.chooseProfile(model.profiles.first?.id)
        XCTAssertEqual(model.kbps, 5000)
        XCTAssertNil(model.desiredConfig)
        XCTAssertTrue(fixture.runner.scripts.isEmpty)
    }

    @MainActor
    private func save(_ name: String, on model: SnailModel) {
        model.beginSaveProfile()
        model.profileName = name
        XCTAssertTrue(model.canConfirmProfile)
        model.confirmProfile()
    }

    @MainActor
    private final class Fixture {
        let name = "ProfileModelTests-\(UUID().uuidString)"
        let defaults: UserDefaults
        let runner = SpyRunner()
        let statePath = NSTemporaryDirectory() + UUID().uuidString

        init() throws {
            defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        }

        func model(interface: String? = "en12") -> SnailModel {
            SnailModel(defaults: defaults, controller: ThrottleController(runner: runner, statePath: statePath),
                       wifiInterface: interface, samplesAutomatically: false)
        }

        func cleanUp() { defaults.removePersistentDomain(forName: name) }
    }

    private final class SpyRunner: PrivilegedRunner {
        var scripts: [String] = []
        func run(_ script: String) { scripts.append(script) }
    }
}
