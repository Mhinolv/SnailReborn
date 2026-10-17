import Foundation

public enum UsageCSV {
    public static func encode(_ days: [UsageDay], timeZone: TimeZone = .current) -> String {
        let header = "date,timezone,bytes_in,bytes_out,observed_seconds\n"
        return header + days.sorted { $0.id < $1.id }.map { day in
            let seconds = day.observedSeconds.isFinite ? max(0, day.observedSeconds.rounded(.down)) : 0
            let duration = String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), seconds)
            return [field(day.id), field(timeZone.identifier), String(day.bytesIn), String(day.bytesOut), duration]
                .joined(separator: ",") + "\n"
        }.joined()
    }

    public static func write(_ days: [UsageDay], to url: URL, timeZone: TimeZone = .current) throws {
        try Data(encode(days, timeZone: timeZone).utf8).write(to: url, options: .atomic)
    }

    private static func field(_ value: String) -> String {
        guard value.contains(where: { ",\"\r\n".contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
