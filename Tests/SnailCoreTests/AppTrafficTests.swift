import XCTest
@testable import SnailCore

final class AppTrafficTests: XCTestCase {
    func testParseNettopCSV() {
        let csv = """
        ,bytes_in,bytes_out,
        UHF.41096,84232630,4000,
        2.1.282.40799,14627,4821,
        Google Chrome H.52478,200537,30139,
        garbage
        """
        XCTAssertEqual(AppTrafficSampler.parse(csv), [
            ProcessBytes(pid: 41096, name: "UHF", bytesIn: 84_232_630, bytesOut: 4_000),
            ProcessBytes(pid: 40799, name: "2.1.282", bytesIn: 14_627, bytesOut: 4_821),
            ProcessBytes(pid: 52478, name: "Google Chrome H", bytesIn: 200_537, bytesOut: 30_139),
        ])
    }

    func testOutermostBundle() {
        XCTAssertEqual(AppIdentity.outermostBundle(inExecutablePath:
            "/Applications/Google Chrome.app/Contents/Frameworks/x/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"),
            "/Applications/Google Chrome.app")
        XCTAssertNil(AppIdentity.outermostBundle(inExecutablePath: "/usr/sbin/mDNSResponder"))
    }

    func testUsageDiffsByPidAndGroupsHelpersIntoTheirApp() {
        let sampler = AppTrafficSampler { pid, name in
            pid == 3 ? AppIdentity(id: "chrome", name: "Google Chrome", bundlePath: nil)
                     : AppIdentity(id: name, name: name, bundlePath: nil)
        }
        let t0 = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(sampler.usage(from: [
            ProcessBytes(pid: 1, name: "UHF", bytesIn: 1_000_000, bytesOut: 0),
            ProcessBytes(pid: 2, name: "Chrome", bytesIn: 0, bytesOut: 0),
            ProcessBytes(pid: 3, name: "Chrome H", bytesIn: 500, bytesOut: 0),
        ], at: t0), [], "first sample only primes counters")

        let apps = sampler.usage(from: [
            ProcessBytes(pid: 1, name: "UHF", bytesIn: 1_250_000, bytesOut: 0),     // +250 KB in 1 s = 2000 Kbps
            ProcessBytes(pid: 2, name: "Chrome", bytesIn: 0, bytesOut: 0),          // idle: omitted
            ProcessBytes(pid: 3, name: "Chrome H", bytesIn: 100, bytesOut: 1_000),  // in dropped (socket closed) → 0
            ProcessBytes(pid: 4, name: "New", bytesIn: 9_999_999, bytesOut: 0),     // first seen: no rate yet
        ], at: t0.addingTimeInterval(1))
        XCTAssertEqual(apps, [
            AppUsage(id: "UHF", name: "UHF", downKbps: 2_000, upKbps: 0),
            AppUsage(id: "chrome", name: "Google Chrome", downKbps: 0, upKbps: 8),
        ])
    }

    func testRouteClassification() {
        XCTAssertNil(RoutePath.classify(outbound: ["en0", "en0"], wifi: "en0"))
        XCTAssertNil(RoutePath.classify(outbound: [], wifi: "en0"))
        XCTAssertEqual(RoutePath.classify(outbound: ["en0", "utun6"], wifi: "en0"), .vpn(interface: "utun6"))
        XCTAssertEqual(RoutePath.classify(outbound: ["ipsec0"], wifi: "en0"), .vpn(interface: "ipsec0"))
        XCTAssertEqual(RoutePath.classify(outbound: ["en7"], wifi: "en0"), .otherInterface("en7"))
    }
}
