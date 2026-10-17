import XCTest
import SnailCore
@testable import SnailApp

final class AppSortTests: XCTestCase {
    func testSortsFullSampleBeforeFiveAppLimit() async {
        await MainActor.run {
            let suite = "SnailAppTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let model = SnailModel(defaults: defaults, samplesAutomatically: false)
            let apps = (1...6).map {
                AppUsage(id: "\($0)", name: "App \($0)", downKbps: Double(7 - $0), upKbps: Double($0))
            }
            model.updateApps(apps)
            XCTAssertEqual(model.topApps.map(\.id), ["1", "2", "3", "4", "5"])
            model.chooseAppSort(.upload)
            model.updateApps(apps)
            XCTAssertEqual(model.topApps.map(\.id), ["6", "5", "4", "3", "2"])
        }
    }

    func testEverySortUsesOtherDirectionThenNameForTies() async {
        await MainActor.run {
            let suite = "SnailAppTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let model = SnailModel(defaults: defaults, samplesAutomatically: false)
            let apps = [
                AppUsage(id: "a", name: "Alpha", downKbps: 100, upKbps: 100),
                AppUsage(id: "b", name: "Beta", downKbps: 100, upKbps: 100),
                AppUsage(id: "d", name: "Download", downKbps: 200, upKbps: 100),
                AppUsage(id: "u", name: "Upload", downKbps: 100, upKbps: 200),
            ]
            for sort in SnailModel.AppSort.allCases {
                model.chooseAppSort(sort)
                model.updateApps(apps.reversed())
                let expected = sort == .download ? ["d", "u", "b", "a"] : ["u", "d", "b", "a"]
                XCTAssertEqual(model.topApps.map(\.id), expected)
            }
        }
    }

    func testEmptySingleAndLargeSamplesInEverySort() async {
        await MainActor.run {
            let suite = "SnailAppTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let model = SnailModel(defaults: defaults, samplesAutomatically: false)
            let app = AppUsage(id: "zero", name: "Zero", downKbps: 0, upKbps: 0)
            for sort in SnailModel.AppSort.allCases {
                model.chooseAppSort(sort)
                model.updateApps([])
                XCTAssertEqual(model.topApps, [])
                model.updateApps([app])
                XCTAssertEqual(model.topApps, [app])
                let apps = (0..<10_000).map {
                    AppUsage(id: "\($0)", name: "App", downKbps: Double($0), upKbps: Double($0))
                }
                model.updateApps(apps)
                XCTAssertEqual(model.topApps.map(\.id), ["9999", "9998", "9997", "9996", "9995"])
            }
        }
    }

    func testSortPreferenceDefaultsAndPersistsBothChoices() async {
        await MainActor.run {
            let suite = "SnailAppTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            @MainActor func model() -> SnailModel { SnailModel(defaults: defaults, samplesAutomatically: false) }

            XCTAssertEqual(model().appSort, .download)
            defaults.set("unknown", forKey: "appSort")
            XCTAssertEqual(model().appSort, .download)
            defaults.set(42, forKey: "appSort")
            XCTAssertEqual(model().appSort, .download)
            let subject = model()
            for sort in [SnailModel.AppSort.upload, .download] {
                subject.chooseAppSort(sort)
                XCTAssertEqual(defaults.string(forKey: "appSort"), sort.rawValue)
                XCTAssertEqual(model().appSort, sort)
                // The next sample uses the current choice.
                subject.updateApps([
                    AppUsage(id: "down", name: "Down", downKbps: 100, upKbps: 0),
                    AppUsage(id: "up", name: "Up", downKbps: 0, upKbps: 100),
                ])
                XCTAssertEqual(subject.topApps.first?.id, sort == .download ? "down" : "up")
            }
        }
    }
}
