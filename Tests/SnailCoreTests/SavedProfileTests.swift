import XCTest
@testable import SnailCore

final class SavedProfileTests: XCTestCase {
    func testAllValuesRoundTripAndNoInterfaceOrNameEntersScript() throws {
        for mode in ThrottleConfig.Mode.allCases {
            for scope in ThrottleConfig.Scope.allCases {
                for kbps in [ThrottleConfig.minKbps, ThrottleConfig.maxKbps] {
                    let ports = [1, 65535, 443, 80, 8080, 25461, 53, 123]
                    let profile = try SavedProfile(name: "  $(id); 'Profile'  ", kbps: kbps,
                                                   mode: mode, scope: scope, ports: ports)
                    let data = try JSONEncoder().encode(profile)
                    XCTAssertEqual(try JSONDecoder().decode(SavedProfile.self, from: data), profile)
                    XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("interface"))
                    let config = try ThrottleConfig(kbps: profile.kbps, mode: profile.mode,
                                                    scope: profile.scope, interface: "en12", ports: profile.ports).validated()
                    XCTAssertFalse(try ThrottleScript.onScript(for: config).contains(profile.name))
                }
            }
        }
    }

    func testNameSpeedAndPortBoundaries() throws {
        for name in ["", " \n ", String(repeating: "x", count: 33)] {
            XCTAssertThrowsError(try makeProfile(name: name))
        }
        for name in ["a", String(repeating: "🐌", count: 32)] {
            XCTAssertEqual(try makeProfile(name: " \(name) \n").name, name)
        }
        for kbps in [Int.min, 0, 63, 1_000_001, Int.max] {
            XCTAssertThrowsError(try makeProfile(kbps: kbps))
        }
        for scope in ThrottleConfig.Scope.allCases {
            for ports in [[0], [65536], Array(1...9)] {
                XCTAssertThrowsError(try makeProfile(scope: scope, ports: ports))
            }
        }
        XCTAssertThrowsError(try makeProfile(scope: .custom))
        XCTAssertEqual(try makeProfile(scope: .custom, ports: [443, 443, 80]).ports, [443, 80])
    }

    func testStoreLimitDuplicatesAndSaveOrder() throws {
        try withDefaults { defaults in
            let first = try makeProfile(name: "First")
            let profiles = try (0..<12).map { try makeProfile(name: "Profile \($0)", kbps: 2000 + $0) }
            let duplicateName = try makeProfile(name: "first", kbps: 4000)
            let duplicateValues = try makeProfile(name: "Same values")
            let duplicateID = try SavedProfile(id: first.id, name: "Same ID", kbps: 9000, mode: .total, scope: .all)
            try SavedProfileStore.save([first, duplicateName, duplicateValues, duplicateID] + profiles, to: defaults)
            let loaded = SavedProfileStore.load(from: defaults)
            XCTAssertEqual(loaded.count, 10)
            XCTAssertEqual(loaded, [first] + Array(profiles.prefix(9)))
            var invalid = first
            invalid.name = " "
            try SavedProfileStore.save([invalid], to: defaults)
            XCTAssertEqual(SavedProfileStore.load(from: defaults), [])
        }
    }

    func testTolerantDecodeRejectsDamagedEntriesAndKeepsValidOnes() throws {
        try withDefaults { defaults in
            let first = try makeProfile(name: "First")
            let second = try makeProfile(name: "Second", kbps: 3000)
            let encoder = JSONEncoder()
            let valid = try JSONSerialization.jsonObject(with: encoder.encode(first)) as! [String: Any]
            var legacy = try JSONSerialization.jsonObject(with: encoder.encode(second)) as! [String: Any]
            legacy.removeValue(forKey: "ports")
            var entries: [Any] = [valid]
            for (key, value) in [("kbps", 0 as Any), ("mode", "bad"), ("scope", "bad"),
                                 ("ports", [0]), ("name", " "), ("id", "bad")] {
                var invalid = valid
                invalid[key] = value
                entries.append(invalid)
            }
            entries += [NSNull(), "bad", legacy]
            defaults.set(try JSONSerialization.data(withJSONObject: ["profiles": entries]), forKey: SavedProfileStore.key)
            XCTAssertEqual(SavedProfileStore.load(from: defaults), [first, second])
            defaults.set(try JSONSerialization.data(withJSONObject: ["version": 99, "profiles": [valid]]),
                         forKey: SavedProfileStore.key)
            XCTAssertTrue(SavedProfileStore.load(from: defaults).isEmpty)
            defaults.set(Data("broken".utf8), forKey: SavedProfileStore.key)
            XCTAssertTrue(SavedProfileStore.load(from: defaults).isEmpty)
            defaults.set(try JSONSerialization.data(withJSONObject: ["version": 1]), forKey: SavedProfileStore.key)
            XCTAssertTrue(SavedProfileStore.load(from: defaults).isEmpty)
        }
    }

    func testLoadAlsoEnforcesLimitAndDuplicateRules() throws {
        try withDefaults { defaults in
            let profiles = try (0..<12).map { try makeProfile(name: "Profile \($0)", kbps: 2000 + $0) }
            let duplicateName = try makeProfile(name: "PROFILE 0", kbps: 9000)
            let duplicateValues = try makeProfile(name: "Duplicate", kbps: 2000)
            let entries = try ([profiles[0], duplicateName, duplicateValues] + profiles.dropFirst()).map {
                try JSONSerialization.jsonObject(with: JSONEncoder().encode($0))
            }
            defaults.set(try JSONSerialization.data(withJSONObject: ["version": 1, "profiles": entries]),
                         forKey: SavedProfileStore.key)
            XCTAssertEqual(SavedProfileStore.load(from: defaults), Array(profiles.prefix(10)))
        }
    }

    private func makeProfile(name: String = "Profile", kbps: Int = 1500,
                             scope: ThrottleConfig.Scope = .web, ports: [Int] = []) throws -> SavedProfile {
        try SavedProfile(name: name, kbps: kbps, mode: .perStream, scope: scope, ports: ports)
    }

    private func withDefaults(_ work: (UserDefaults) throws -> Void) throws {
        let name = "SavedProfileTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try work(defaults)
    }
}
