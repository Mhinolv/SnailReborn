import XCTest
import SnailCore
@testable import SnailCLI

final class RemoteAddressTests: XCTestCase {
    func testFromCombinesWithEveryScopeAndMode() throws {
        for address in ["203.0.113.10", "2001:0DB8:0:0::1"] {
            for scope in [[], ["--all-traffic"], ["--ports", "1,65535"]] {
                for mode in ["--per-stream", "--total"] {
                    let config = try SnailCLI.parseConfig(scope + [mode, "--from", address, "--interface", "en12"])
                    XCTAssertEqual(config.remoteAddress, try ThrottleConfig.parseRemoteAddress(address))
                    XCTAssertTrue(SnailCLI.describe(config).hasSuffix(", from \(config.remoteAddress!)"))
                }
            }
        }
    }

    func testRejectsMissingAndInvalidAddress() {
        for value in [[], [""], ["example.com"], ["192.0.2.0/24"], ["$(id)"], ["--total"]] {
            XCTAssertThrowsError(try SnailCLI.parseConfig(["--interface", "en12", "--from"] + value)) { error in
                XCTAssertEqual(error as? SnailError, .invalidConfig(ThrottleConfig.remoteAddressError))
            }
        }
    }
}
