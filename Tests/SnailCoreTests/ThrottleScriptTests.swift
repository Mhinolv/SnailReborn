import XCTest
@testable import SnailCore

final class ThrottleScriptTests: XCTestCase {
    let config = ThrottleConfig(kbps: 1_500, mode: .perStream, scope: .web, interface: "en0")

    func testValidation() {
        XCTAssertNoThrow(try config.validated())
        XCTAssertThrowsError(try ThrottleConfig(kbps: 10, interface: "en0").validated())
        XCTAssertThrowsError(try ThrottleConfig(kbps: 1_500, interface: "en0; rm -rf /").validated())
        XCTAssertThrowsError(try ThrottleConfig(kbps: 1_500, interface: "").validated())
        XCTAssertTrue(ThrottleConfig.isValidInterfaceName("en12"))
        XCTAssertFalse(ThrottleConfig.isValidInterfaceName("en0'"))
    }

    func testWebRulesTargetPort443OnInterface() {
        XCTAssertEqual(ThrottleScript.pfRules(for: config),
                       ["dummynet in on en0 proto { tcp udp } from any port 443 to any pipe 47101"])
    }

    func testAllTrafficRule() {
        var c = config
        c.scope = .all
        XCTAssertEqual(ThrottleScript.pfRules(for: c), ["dummynet in on en0 all pipe 47101"])
    }

    func testPerStreamUsesMaskTotalDoesNot() {
        XCTAssertEqual(ThrottleScript.pipeArguments(for: config),
                       ["pipe", "47101", "config", "bw", "1500Kbit/s", "mask", "dst-port", "0xffff"])
        var c = config
        c.mode = .total
        XCTAssertEqual(ThrottleScript.pipeArguments(for: c), ["pipe", "47101", "config", "bw", "1500Kbit/s"])
    }

    func testOnScriptUsesAppleAnchorAndOwnPipeOnly() throws {
        let script = try ThrottleScript.onScript(for: config)
        XCTAssertTrue(script.contains("-a com.apple/snailreborn -f -"))
        XCTAssertTrue(script.contains("pfctl -E"))
        XCTAssertFalse(script.contains("flush"), "must never flush pipes globally")
        XCTAssertFalse(script.contains("pfctl -d"), "must never disable pf for everyone")
    }

    func testOnScriptRejectsInvalidConfig() {
        XCTAssertThrowsError(try ThrottleScript.onScript(for: ThrottleConfig(kbps: 1_500, interface: "$(id)")))
    }

    func testOffScriptOnlyRemovesSnailState() {
        let script = ThrottleScript.offScript()
        XCTAssertTrue(script.contains("-a com.apple/snailreborn -F all"))
        XCTAssertTrue(script.contains("pipe delete 47101"))
        XCTAssertTrue(script.contains("pfctl -X"))
        XCTAssertFalse(script.contains("dnctl -f flush"))
    }

    func testAppleScriptEscaping() {
        let s = ThrottleScript.appleScript(running: "echo \"a\\b\"\nls", prompt: "p")
        XCTAssertEqual(s, #"do shell script "echo \"a\\b\"\nls" with prompt "p" with administrator privileges"#)
    }

    func testStateRoundTrip() throws {
        let path = NSTemporaryDirectory() + "snail-state-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let controller = ThrottleController(runner: RootShellRunner(), statePath: path)
        XCTAssertNil(controller.activeConfig())
        try JSONEncoder().encode(config).write(to: URL(fileURLWithPath: path))
        XCTAssertEqual(controller.activeConfig(), config)
    }

    /// `pfctl -n` parses without loading and works unprivileged, so this checks the real pf grammar.
    func testGeneratedRulesParseWithPfctl() throws {
        for scope in ThrottleConfig.Scope.allCases {
            var c = config
            c.scope = scope
            let rules = ThrottleScript.pfRules(for: c).joined(separator: "\n") + "\n"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/pfctl")
            process.arguments = ["-n", "-f", "-"]
            let input = Pipe(), output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = output
            try process.run()
            input.fileHandleForWriting.write(Data(rules.utf8))
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
            let out = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertEqual(process.terminationStatus, 0, "pfctl rejected \(scope) rules: \(out)")
        }
    }

    func testRateFormatting() {
        XCTAssertEqual(Rate.format(kbps: 1_500), "1.5 Mbps")
        XCTAssertEqual(Rate.format(kbps: 800), "800 Kbps")
        XCTAssertEqual(Rate.format(kbps: 250_000), "250 Mbps")
    }

    func testInterfaceCountersForLoopback() {
        XCTAssertNotNil(InterfaceStats.counters(for: "lo0"))
        XCTAssertNil(InterfaceStats.counters(for: "nope9"))
    }
}
