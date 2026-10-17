import XCTest
import SnailCore
@testable import SnailCLI

final class ConfigTests: XCTestCase {
    func testRejectsConflictingScopesInEitherOrder() {
        for args in [["--ports", "80", "--all-traffic"],
                     ["--all-traffic", "--ports", "80"]] {
            XCTAssertThrowsError(try SnailCLI.parseConfig(args + ["--interface", "en12"])) { error in
                XCTAssertEqual(error as? SnailError,
                               .invalidConfig("Use --ports or --all-traffic, not both."))
            }
        }
    }

    func testSingleScopeOptionsAndPortBoundaries() throws {
        for mode in ["--per-stream", "--total"] {
            for (args, scope, ports) in [
                ([], ThrottleConfig.Scope.web, []),
                (["--all-traffic"], .all, []),
                (["--ports", "1,65535,1"], .custom, [1, 65535])
            ] {
                let config = try SnailCLI.parseConfig(args + [mode, "--interface", "en12"])
                XCTAssertEqual(config.scope, scope)
                XCTAssertEqual(config.ports, ports)
                XCTAssertEqual(config.mode, mode == "--total" ? .total : .perStream)
            }
        }
    }
}
