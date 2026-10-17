import Darwin
import Foundation

/// Cumulative bytes for one process, as reported by `nettop -P`.
public struct ProcessBytes: Equatable, Sendable {
    public var pid: Int32
    /// nettop's name, truncated to 15 characters.
    public var name: String
    public var bytesIn: UInt64
    public var bytesOut: UInt64
}

/// Which app a process belongs to. Helpers (e.g. "Google Chrome Helper") resolve to their outermost .app.
public struct AppIdentity: Equatable, Sendable {
    public var id: String
    public var name: String
    public var bundlePath: String?

    /// `/Applications/Foo.app/Contents/Frameworks/Bar.app/Contents/MacOS/Bar` → `/Applications/Foo.app`.
    public static func outermostBundle(inExecutablePath path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    public static func resolve(pid: Int32, fallbackName: String) -> AppIdentity {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else {
            return AppIdentity(id: fallbackName, name: fallbackName, bundlePath: nil)
        }
        let path = String(cString: buffer)
        if let bundle = outermostBundle(inExecutablePath: path) {
            let name = FileManager.default.displayName(atPath: bundle)
            return AppIdentity(id: bundle, name: (name as NSString).deletingPathExtension, bundlePath: bundle)
        }
        return AppIdentity(id: path, name: (path as NSString).lastPathComponent, bundlePath: nil)
    }
}

/// Live rate for one app.
public struct AppUsage: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var bundlePath: String?
    public var downKbps: Double
    public var upKbps: Double

    public init(id: String, name: String, bundlePath: String? = nil, downKbps: Double, upKbps: Double) {
        self.id = id
        self.name = name
        self.bundlePath = bundlePath
        self.downKbps = downKbps
        self.upKbps = upKbps
    }
}

/// Per-app network rates from `/usr/bin/nettop`, which needs no root.
/// pf can't match by process, so this is for showing who is using bandwidth, not for shaping.
/// Not thread-safe: call it from one serial queue.
public final class AppTrafficSampler: @unchecked Sendable {
    private let resolve: (Int32, String) -> AppIdentity
    private var identities: [Int32: AppIdentity] = [:]
    private var last: (counts: [Int32: ProcessBytes], date: Date)?

    public init(resolve: @escaping (Int32, String) -> AppIdentity = AppIdentity.resolve) {
        self.resolve = resolve
    }

    /// Runs nettop once (about 10 ms) and returns apps by download rate, busiest first.
    /// The first call only primes the counters and returns [].
    public func sample() -> [AppUsage] {
        guard let csv = Self.runNettop() else { return [] }
        return usage(from: Self.parse(csv), at: Date())
    }

    func usage(from current: [ProcessBytes], at date: Date) -> [AppUsage] {
        let counts = Dictionary(current.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        defer { last = (counts, date) }
        guard let last else { return [] }
        let seconds = max(date.timeIntervalSince(last.date), 0.001)

        var byApp: [String: AppUsage] = [:]
        for proc in current {
            // A new pid's counters are cumulative since it started, not since the last sample.
            guard let prev = last.counts[proc.pid] else { continue }
            // Counters drop when sockets close; treat that interval as unknown rather than negative.
            let dIn = proc.bytesIn >= prev.bytesIn ? proc.bytesIn - prev.bytesIn : 0
            let dOut = proc.bytesOut >= prev.bytesOut ? proc.bytesOut - prev.bytesOut : 0
            guard dIn + dOut > 0 else { continue }

            let identity = identities[proc.pid] ?? resolve(proc.pid, proc.name)
            identities[proc.pid] = identity
            var app = byApp[identity.id] ?? AppUsage(id: identity.id, name: identity.name,
                                                     bundlePath: identity.bundlePath, downKbps: 0, upKbps: 0)
            app.downKbps += Double(dIn) * 8 / 1_000 / seconds
            app.upKbps += Double(dOut) * 8 / 1_000 / seconds
            byApp[identity.id] = app
        }
        identities = identities.filter { counts[$0.key] != nil }
        return byApp.values.sorted { ($0.downKbps, $0.upKbps, $0.name) > ($1.downKbps, $1.upKbps, $1.name) }
    }

    /// Parses `nettop -P -L 1 -x -J bytes_in,bytes_out` output: a header line, then `name.pid,in,out,` rows.
    public static func parse(_ csv: String) -> [ProcessBytes] {
        csv.split(whereSeparator: \.isNewline).compactMap { line in
            var fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            if fields.last == "" { fields.removeLast() }
            guard fields.count >= 3,
                  let bytesOut = UInt64(fields.removeLast()),
                  let bytesIn = UInt64(fields.removeLast()) else { return nil }
            let label = fields.joined(separator: ",")
            guard let dot = label.lastIndex(of: "."), let pid = Int32(label[label.index(after: dot)...]) else { return nil }
            return ProcessBytes(pid: pid, name: String(label[..<dot]), bytesIn: bytesIn, bytesOut: bytesOut)
        }
    }

    static func runNettop() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-L", "1", "-x", "-n", "-t", "external", "-J", "bytes_in,bytes_out"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
