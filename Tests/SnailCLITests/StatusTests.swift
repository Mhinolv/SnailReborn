import XCTest
import SnailCore
@testable import SnailCLI

final class StatusTests: XCTestCase {
    private var directory: URL!
    private var state: URL { directory.appendingPathComponent("state.json") }
    private var controller: ThrottleController {
        ThrottleController(runner: RejectRunner(), statePath: state.path)
    }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testJSONForEveryModeScopeAndRateBoundary() throws {
        for mode in ThrottleConfig.Mode.allCases {
            for scope in ThrottleConfig.Scope.allCases {
                for kbps in [ThrottleConfig.minKbps, ThrottleConfig.maxKbps] {
                    let config = ThrottleConfig(kbps: kbps, mode: mode, scope: scope,
                                                interface: "en12", ports: [1, 65535])
                    try JSONEncoder().encode(config).write(to: state)
                    let result = status(["--json"])
                    XCTAssertEqual(result.exitCode, 0)
                    XCTAssertEqual(result.stderr, "")
                    let data = Data(result.stdout.utf8)
                    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                    XCTAssertEqual(Set(json.keys), ["schemaVersion", "recordedConfig", "stateFile", "wifiInterface", "bypass"])
                    XCTAssertEqual(json["schemaVersion"] as? Int, 1)
                    XCTAssertEqual(json["stateFile"] as? String, state.path)
                    XCTAssertEqual(json["wifiInterface"] as? String, "en12")
                    XCTAssertTrue(json["bypass"] is NSNull)
                    let saved = try JSONSerialization.data(withJSONObject: XCTUnwrap(json["recordedConfig"]))
                    XCTAssertEqual(try JSONDecoder().decode(ThrottleConfig.self, from: saved), config)
                    let formatted = try JSONSerialization.data(withJSONObject: json,
                                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                    XCTAssertEqual(result.stdout, String(decoding: formatted, as: UTF8.self) + "\n")
                    XCTAssertTrue(result.stdout.contains("\n  \"recordedConfig\""))
                    XCTAssertFalse(result.stdout.hasSuffix("\n\n"))
                }
            }
        }
    }

    func testLegacyStateAndNullWiFi() throws {
        try write(#"{"kbps":1500,"mode":"perStream","scope":"web","interface":"en12"}"#)
        let result = SnailCLI.status(["--json"], controller: controller, wifiInterface: { nil }, bypass: { _ in
            XCTFail("No route lookup is needed without Wi-Fi")
            return nil
        })
        XCTAssertEqual(result.exitCode, 0)
        let json = try object(result.stdout)
        XCTAssertTrue(json["wifiInterface"] is NSNull)
        XCTAssertTrue(json["bypass"] is NSNull)
        XCTAssertEqual((json["recordedConfig"] as? [String: Any])?["ports"] as? [Int], [])
    }

    func testBypassKindsReplaceTextWarning() throws {
        try writeValidState()
        for (route, kind, interface) in [(RoutePath.Bypass.vpn(interface: "utun4"), "vpn", "utun4"),
                                        (.otherInterface("en7"), "otherInterface", "en7")] {
            let result = status(["--json"], route: route)
            let json = try object(result.stdout)
            let bypass = try XCTUnwrap(json["bypass"] as? [String: String])
            XCTAssertEqual(bypass, ["kind": kind, "interface": interface])
            XCTAssertEqual(result.stderr, "")
            XCTAssertFalse(result.stdout.contains("Warning:"))
        }
    }

    func testAbsentStateHasExitThreeAndOnlyStderr() {
        assertFailure(3, "snailctl: Off. No limit is recorded.\n")
        assertPlain("Off.\n")
    }

    func testInvalidStateHasExitFourAndOnlyStderr() throws {
        for contents in ["", "{", "null", "{}",
                         #"{"kbps":63,"mode":"perStream","scope":"web","interface":"en12"}"#,
                         #"{"kbps":1000001,"mode":"perStream","scope":"web","interface":"en12"}"#,
                         #"{"kbps":1500,"mode":"unknown","scope":"web","interface":"en12"}"#,
                         #"{"kbps":1500,"mode":"total","scope":"unknown","interface":"en12"}"#,
                         #"{"kbps":1500,"mode":"total","scope":"web","interface":"en12;id"}"#,
                         #"{"kbps":1500,"mode":"total","scope":"custom","interface":"en12","ports":[]}"#] {
            try write(contents)
            assertFailure(4, "snailctl: The state file \(state.path) is not valid.\n")
        }
        try write("{")
        assertPlain("Off.\n")
    }

    func testUnreadableStateHasExitFiveAndOnlyStderr() throws {
        // A directory fails as a data file, even when tests have root access.
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: false)
        let result = status(["--json"])
        XCTAssertEqual(result.exitCode, 5)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.hasPrefix("snailctl: Cannot read \(state.path): "))
        assertPlain("Off.\n")
    }

    func testPermissionDeniedIsUnreadable() throws {
        guard geteuid() != 0 else { throw XCTSkip("Root can read files without read permission") }
        try writeValidState()
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: state.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: state.path) }
        let result = status(["--json"])
        XCTAssertEqual(result.exitCode, 5)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.hasPrefix("snailctl: Cannot read \(state.path): "))
        assertPlain("Off.\n")
    }

    func testDefaultStatusPreservesTextAndWarning() throws {
        try writeValidState()
        assertPlain("On: 1.5 Mbps per stream, web & video (port 443, TCP+QUIC), on en12\n")
        let route = RoutePath.Bypass.vpn(interface: "utun4")
        let result = status([], route: route)
        XCTAssertEqual(result.stdout, "On: 1.5 Mbps per stream, web & video (port 443, TCP+QUIC), on en12\nWarning: \(route.explanation)\n")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
    }

    func testUnknownStatusOptionsHaveExit64AndOnlyStderr() {
        for args in [["--bogus"], ["--json", "--bogus"], ["--bogus", "--json"]] {
            let result = status(args)
            XCTAssertEqual(result.exitCode, 64)
            XCTAssertEqual(result.stdout, "")
            XCTAssertEqual(result.stderr, "Unknown option “--bogus”.\n")
        }
    }

    private func status(_ args: [String], route: RoutePath.Bypass? = nil) -> SnailCLI.StatusResult {
        SnailCLI.status(args, controller: controller, wifiInterface: { "en12" }, bypass: { _ in route })
    }

    private func assertFailure(_ code: Int32, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let result = status(["--json"])
        XCTAssertEqual(result.exitCode, code, file: file, line: line)
        XCTAssertEqual(result.stdout, "", file: file, line: line)
        XCTAssertEqual(result.stderr, message, file: file, line: line)
    }

    private func assertPlain(_ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let result = status([])
        XCTAssertEqual(result.stdout, expected, file: file, line: line)
        XCTAssertEqual(result.stderr, "", file: file, line: line)
        XCTAssertEqual(result.exitCode, 0, file: file, line: line)
    }

    private func write(_ text: String) throws {
        try Data(text.utf8).write(to: state)
    }

    private func writeValidState() throws {
        try JSONEncoder().encode(ThrottleConfig(interface: "en12")).write(to: state)
    }

    private func object(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private struct RejectRunner: PrivilegedRunner {
        func run(_ script: String) throws {
            XCTFail("Status must not run a root script")
        }
    }
}
