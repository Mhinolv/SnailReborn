import Foundation

/// What Snail asks the kernel to do. Every field is validated before it reaches a shell.
public struct ThrottleConfig: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        /// Every connection gets its own pipe at `kbps` (how AT&T Stream Saver behaves).
        case perStream
        /// All matching Wi-Fi traffic shares one pipe at `kbps`.
        case total
    }

    public enum Scope: String, Codable, CaseIterable, Sendable {
        /// Inbound TCP and UDP (QUIC) from port 443: streaming and web.
        case web
        /// All inbound traffic on the interface.
        case all
        case custom
    }

    public static let minKbps = 64
    public static let maxKbps = 1_000_000

    public let version = 2
    public var ports: [Int]

    public var kbps: Int
    public var mode: Mode
    public var scope: Scope
    /// BSD interface name, e.g. "en0".
    public var interface: String

    public init(kbps: Int = Preset.sd.kbps, mode: Mode = .perStream, scope: Scope = .web, interface: String, ports: [Int] = []) {
        self.kbps = kbps
        self.mode = mode
        self.scope = scope
        self.interface = interface
        self.ports = ports
    }

    public func validated() throws -> ThrottleConfig {
        guard (Self.minKbps...Self.maxKbps).contains(kbps) else {
            throw SnailError.invalidConfig("Speed must be between \(Self.minKbps) and \(Self.maxKbps) Kbps.")
        }
        guard Self.isValidInterfaceName(interface) else {
            throw SnailError.invalidConfig("“\(interface)” is not a valid network interface name.")
        }
        var config = self
        config.ports = try Self.validatedPorts(ports, required: scope == .custom)
        return config
    }

    private enum CodingKeys: String, CodingKey {
        case version, kbps, mode, scope, interface, ports
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kbps = try values.decode(Int.self, forKey: .kbps)
        mode = try values.decode(Mode.self, forKey: .mode)
        scope = try values.decode(Scope.self, forKey: .scope)
        interface = try values.decode(String.self, forKey: .interface)
        ports = try values.decodeIfPresent([Int].self, forKey: .ports) ?? []
    }

    public static let portsError = "Enter 1 to 8 port numbers from 1 to 65535, separated by commas."

    public static func parsePorts(_ text: String) throws -> [Int] {
        let tokens = text.split { $0 == "," || $0 == " " }
        let ports = try tokens.map { token -> Int in
            guard token.utf8.allSatisfy({ (48...57).contains($0) }), let port = Int(token) else {
                throw SnailError.invalidConfig(portsError)
            }
            return port
        }
        return try validatedPorts(ports, required: true)
    }

    private static func validatedPorts(_ ports: [Int], required: Bool) throws -> [Int] {
        var seen = Set<Int>()
        let unique = ports.filter { seen.insert($0).inserted }
        guard (!required || !unique.isEmpty), unique.count <= 8,
              unique.allSatisfy({ (1...65535).contains($0) }) else {
            throw SnailError.invalidConfig(portsError)
        }
        return unique
    }

    public static func isValidInterfaceName(_ name: String) -> Bool {
        name.range(of: "^[a-z]{1,8}[0-9]{1,3}$", options: .regularExpression) != nil
    }
}

/// Quick picks, named after the video quality an adaptive player will settle on.
public enum Preset: String, CaseIterable, Identifiable, Sendable {
    case sd, hd, fullHD

    public var id: String { rawValue }

    public var kbps: Int {
        switch self {
        case .sd: return 1_500
        case .hd: return 3_000
        case .fullHD: return 5_000
        }
    }

    public var title: String {
        switch self {
        case .sd: return "SD"
        case .hd: return "HD"
        case .fullHD: return "Full HD"
        }
    }

    public static func matching(kbps: Int) -> Preset? {
        allCases.first { $0.kbps == kbps }
    }
}

public enum SnailError: LocalizedError, Equatable {
    case invalidConfig(String)
    case cancelled
    case commandFailed(String)
    case notRoot

    public var errorDescription: String? {
        switch self {
        case .invalidConfig(let msg): return msg
        case .cancelled: return "Cancelled."
        case .commandFailed(let msg): return msg
        case .notRoot: return "This command must be run with sudo."
        }
    }
}

public enum Rate {
    /// SI formatting, matching dnctl's Kbit/s: 1500 → "1.5 Mbps".
    public static func format(kbps: Double) -> String {
        if kbps >= 1_000 {
            let mbps = kbps / 1_000
            return mbps >= 100 ? String(format: "%.0f Mbps", mbps) : String(format: "%.1f Mbps", mbps)
        }
        return String(format: "%.0f Kbps", kbps)
    }

    public static func format(kbps: Int) -> String {
        format(kbps: Double(kbps))
    }
}
