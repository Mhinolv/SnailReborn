import XCTest
@testable import SnailCore

final class RemoteAddressTests: XCTestCase {
    func testCanonicalAddressesAndBoundaries() throws {
        for (input, expected) in [("", nil), ("0.0.0.0", "0.0.0.0"),
                                  ("255.255.255.255", "255.255.255.255"),
                                  ("203.0.113.10", "203.0.113.10"), ("::", "::"), ("::1", "::1"),
                                  ("2001:0DB8:0000:0000:0000:0000:0000:0001", "2001:db8::1"),
                                  ("FFFF:FFFF:FFFF:FFFF:FFFF:FFFF:FFFF:FFFF", "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"),
                                  ("::ffff:192.0.2.1", "::ffff:192.0.2.1")] {
            XCTAssertEqual(try ThrottleConfig.parseRemoteAddress(input), expected)
        }
    }

    func testRejectsMalformedTargetsBeforeRunner() {
        let runner = SpyRunner()
        let controller = ThrottleController(runner: runner)
        for address in ["example.com", "203.0.113.0/24", "203.0.113.1,203.0.113.2", "256.0.0.1", "127.1",
                        "01.2.3.4", "2001:::1", "fe80::1%en12", "[::1]", "::1/128", " ::1", "::1\n",
                        "1.2.3.4\0;id", "$(id)", "1.2.3.4';id", "1.2.3.4 port 80", "１.2.3.4"] {
            XCTAssertThrowsError(try ThrottleConfig.parseRemoteAddress(address), address)
            XCTAssertThrowsError(try controller.apply(ThrottleConfig(interface: "en12", remoteAddress: address)), address)
        }
        XCTAssertTrue(runner.scripts.isEmpty)
    }

    func testRulesCombineTargetWithEveryScopeAndMode() throws {
        for address in [nil, "203.0.113.10", "2001:db8::1"] as [String?] {
            for scope in ThrottleConfig.Scope.allCases {
                for mode in ThrottleConfig.Mode.allCases {
                    let config = try ThrottleConfig(mode: mode, scope: scope, interface: "en12",
                                                    ports: [1, 65535], remoteAddress: address).validated()
                    let source = address ?? "any"
                    let expected: String
                    switch scope {
                    case .web: expected = "proto { tcp udp } from \(source) port 443 to any"
                    case .custom: expected = "proto { tcp udp } from \(source) port { 1 65535 } to any"
                    case .all: expected = address == nil ? "all" : "from \(source) to any"
                    }
                    XCTAssertEqual(ThrottleScript.pfRules(for: config), ["dummynet in on en12 \(expected) pipe 47101"])
                    XCTAssertEqual(ThrottleScript.pipeArguments(for: config).contains("mask"), mode == .perStream)
                    XCTAssertTrue(try ThrottleScript.onScript(for: config).contains(expected))
                }
            }
        }
    }

    func testAddressRulesParseWithPfctl() throws {
        for address in ["203.0.113.10", "2001:db8::1"] {
            for scope in ThrottleConfig.Scope.allCases {
                let config = try ThrottleConfig(scope: scope, interface: "en12", ports: [1, 65535],
                                                remoteAddress: address).validated()
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/sbin/pfctl")
                process.arguments = ["-n", "-f", "-"]
                let input = Pipe(), output = Pipe()
                process.standardInput = input
                process.standardOutput = output
                process.standardError = output
                try process.run()
                input.fileHandleForWriting.write(Data((ThrottleScript.pfRules(for: config).joined(separator: "\n") + "\n").utf8))
                try input.fileHandleForWriting.close()
                process.waitUntilExit()
                let result = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                XCTAssertEqual(process.terminationStatus, 0, result)
            }
        }
    }

    func testOldStateAndProfilesDefaultToAnyAddress() throws {
        for version in [1, 2] {
            let data = Data("{\"version\":\(version),\"kbps\":1500,\"mode\":\"perStream\",\"scope\":\"web\",\"interface\":\"en12\"}".utf8)
            XCTAssertNil(try JSONDecoder().decode(ThrottleConfig.self, from: data).remoteAddress)
        }
        let config = try ThrottleConfig(interface: "en12", remoteAddress: "2001:0DB8::1").validated()
        XCTAssertEqual(config.remoteAddress, "2001:db8::1")
        XCTAssertEqual(try JSONDecoder().decode(ThrottleConfig.self, from: JSONEncoder().encode(config)), config)
        let profile = try SavedProfile(name: "Server", kbps: 1500, mode: .perStream, scope: .web, remoteAddress: config.remoteAddress)
        XCTAssertEqual(try JSONDecoder().decode(SavedProfile.self, from: JSONEncoder().encode(profile)), profile)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
        old.removeValue(forKey: "remoteAddress")
        XCTAssertNil(try JSONDecoder().decode(SavedProfile.self, from: JSONSerialization.data(withJSONObject: old)).remoteAddress)
    }

    func testProfileStoreReadsOldFilesAndKeepsDifferentTargets() throws {
        let name = "SnailAddressStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let old = try SavedProfile(name: "Any server", kbps: 1500, mode: .perStream, scope: .web)
        let entry = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old))
        defaults.set(try JSONSerialization.data(withJSONObject: ["version": 1, "profiles": [entry]]),
                     forKey: SavedProfileStore.key)
        XCTAssertEqual(SavedProfileStore.load(from: defaults), [old])
        let target = try SavedProfile(name: "One server", kbps: 1500, mode: .perStream, scope: .web,
                                      remoteAddress: "203.0.113.10")
        try SavedProfileStore.save([old, target], to: defaults)
        XCTAssertEqual(SavedProfileStore.load(from: defaults), [old, target])
        let data = try XCTUnwrap(defaults.data(forKey: SavedProfileStore.key))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(document["version"] as? Int, 2)
    }

    private final class SpyRunner: PrivilegedRunner {
        var scripts: [String] = []
        func run(_ script: String) { scripts.append(script) }
    }
}
