import XCTest
@testable import SnailCore

final class CustomPortsTests: XCTestCase {
    func testParsePortsPreservesOrderAndRemovesDuplicates() throws {
        XCTAssertEqual(try ThrottleConfig.parsePorts("25461, 8080 25461,1,65535"), [25461, 8080, 1, 65535])
        XCTAssertEqual(try ThrottleConfig.parsePorts("1 2 3 4 5 6 7 65535"), [1, 2, 3, 4, 5, 6, 7, 65535])
        XCTAssertEqual(try ThrottleConfig.parsePorts("443,443,443,443,443,443,443,443,443"), [443])
    }

    func testRejectsInvalidPortsAndShellText() {
        for text in ["", " , ", "0", "65536", "-1", "+1", "1.5", "80-90", "https", "８０",
                     "1 2 3 4 5 6 7 8 9", "80;id", "$(id)", "80\n443", "9999999999999999999999"] {
            XCTAssertThrowsError(try ThrottleConfig.parsePorts(text), text)
        }
        for ports in [[], [0], [65536], [-1], Array(1...9)] {
            let config = ThrottleConfig(scope: .custom, interface: "en12", ports: ports)
            XCTAssertThrowsError(try config.validated())
            XCTAssertThrowsError(try ThrottleScript.onScript(for: config))
        }
    }

    func testCustomRulesAndEveryModeScopeCombination() throws {
        for scope in ThrottleConfig.Scope.allCases {
            for mode in ThrottleConfig.Mode.allCases {
                let config = try ThrottleConfig(mode: mode, scope: scope, interface: "en12",
                                                ports: [25461, 8080, 25461]).validated()
                XCTAssertEqual(config.ports, [25461, 8080])
                let rules = ThrottleScript.pfRules(for: config).joined()
                XCTAssertTrue(rules.contains("in on en12"))
                XCTAssertEqual(ThrottleScript.pipeArguments(for: config).contains("mask"), mode == .perStream)
                if scope == .custom {
                    XCTAssertEqual(rules, "dummynet in on en12 proto { tcp udp } from any port { 25461 8080 } to any pipe 47101")
                    XCTAssertFalse(rules.contains("443"))
                }
                XCTAssertNoThrow(try ThrottleScript.onScript(for: config))
            }
        }
    }

    func testOldStateDefaultsAndVersionedRoundTrip() throws {
        let data = Data(#"{"kbps":1500,"mode":"perStream","scope":"web","interface":"en12"}"#.utf8)
        let old = try JSONDecoder().decode(ThrottleConfig.self, from: data)
        XCTAssertEqual(old.ports, [])
        XCTAssertNoThrow(try old.validated())
        let config = ThrottleConfig(scope: .custom, interface: "en12", ports: [1, 65535])
        let encoded = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(ThrottleConfig.self, from: encoded), config)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 3)
    }

    func testControllerRejectsPortsBeforeRunner() {
        let runner = SpyRunner()
        let controller = ThrottleController(runner: runner)
        XCTAssertThrowsError(try controller.apply(ThrottleConfig(scope: .custom, interface: "en12", ports: [0])))
        XCTAssertEqual(runner.scripts, [])
    }

    private final class SpyRunner: PrivilegedRunner {
        var scripts: [String] = []
        func run(_ script: String) { scripts.append(script) }
    }
}
