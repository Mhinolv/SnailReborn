import XCTest
@testable import SnailCore

final class UsageCSVTests: XCTestCase {
    private let timeZone = TimeZone(identifier: "America/Chicago")!
    private let header = "date,timezone,bytes_in,bytes_out,observed_seconds\n"

    func testFixtureHasOldestDayFirstAndNoRowsForGaps() {
        let days = [
            UsageDay(id: "2026-10-17", bytesIn: 1_234_567, bytesOut: 890, observedSeconds: 61.9),
            UsageDay(id: "2026-10-15", observedSeconds: 0.9)
        ]
        let expected = header + "2026-10-15,America/Chicago,0,0,0\n" +
            "2026-10-17,America/Chicago,1234567,890,61\n"
        XCTAssertEqual(UsageCSV.encode(days, timeZone: timeZone), expected)
        XCTAssertEqual(days.first?.id, "2026-10-17")
    }

    func testEmptyHistoryHasHeaderOnly() {
        XCTAssertEqual(UsageCSV.encode([], timeZone: timeZone), header)
    }

    func testLargestByteValuesAndASCIIIntegers() {
        let day = UsageDay(id: "2026-10-17", bytesIn: .max, bytesOut: .max, observedSeconds: 90_000)
        let csv = UsageCSV.encode([day], timeZone: timeZone)
        XCTAssertEqual(csv, header + "2026-10-17,America/Chicago,18446744073709551615,18446744073709551615,90000\n")
        let fields = csv.split(separator: "\n")[1].split(separator: ",")
        for field in fields.suffix(3) {
            XCTAssertTrue(field.utf8.allSatisfy { (48...57).contains($0) })
        }
    }

    func testDurationBoundsDoNotTrap() {
        for duration in [-1, Double.nan, .infinity, -.infinity, 0] {
            let day = UsageDay(id: "2026-10-17", observedSeconds: duration)
            XCTAssertEqual(UsageCSV.encode([day], timeZone: timeZone), header + "2026-10-17,America/Chicago,0,0,0\n")
        }
        let csv = UsageCSV.encode([UsageDay(id: "2026-10-17", observedSeconds: .greatestFiniteMagnitude)],
                                  timeZone: timeZone)
        let seconds = csv.split(separator: "\n")[1].split(separator: ",").last!
        XCTAssertTrue(seconds.utf8.allSatisfy { (48...57).contains($0) })
    }

    func testQuotedFieldsAndExplicitTimezone() {
        let day = UsageDay(id: "date,\"quoted\"\r\n")
        XCTAssertEqual(UsageCSV.encode([day], timeZone: timeZone),
                       header + "\"date,\"\"quoted\"\"\r\n\",America/Chicago,0,0,0\n")
        XCTAssertEqual(UsageCSV.encode([UsageDay(id: "2026-10-17")], timeZone: TimeZone(identifier: "Asia/Tokyo")!),
                       header + "2026-10-17,Asia/Tokyo,0,0,0\n")
    }

    func testFileUsesUTF8AndReplacesExistingContents() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("old contents".utf8).write(to: url)
        let days = [UsageDay(id: "2026-10-17", bytesIn: 12, bytesOut: 34, observedSeconds: 5)]
        try UsageCSV.write(days, to: url, timeZone: timeZone)
        XCTAssertEqual(try Data(contentsOf: url), Data((header + "2026-10-17,America/Chicago,12,34,5\n").utf8))
    }
}
