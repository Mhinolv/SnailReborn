import Foundation
import Darwin

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

    public let version = 3
    public var remoteAddress: String?
    public var ports: [Int]

    public var kbps: Int
    public var mode: Mode
    public var scope: Scope
    /// BSD interface name, e.g. "en0".
    public var interface: String

    public init(kbps: Int = Preset.sd.kbps, mode: Mode = .perStream, scope: Scope = .web, interface: String, ports: [Int] = [], remoteAddress: String? = nil) {
        self.kbps = kbps
        self.mode = mode
        self.scope = scope
        self.interface = interface
        self.ports = ports
        self.remoteAddress = remoteAddress
    }

    public func validated() throws -> ThrottleConfig {
        guard (Self.minKbps...Self.maxKbps).contains(kbps) else {
            throw SnailError.invalidConfig("Speed must be between \(Self.minKbps) and \(Self.maxKbps) Kbps.")
        }
        guard Self.isValidInterfaceName(interface) else {
            throw SnailError.invalidConfig("“\(interface)” is not a valid network interface name.")
        }
        var config = self
        config.remoteAddress = try Self.parseRemoteAddress(remoteAddress ?? "")
        config.ports = try Self.validatedPorts(ports, required: scope == .custom)
        return config
    }

    private enum CodingKeys: String, CodingKey {
        case version, kbps, mode, scope, interface, ports, remoteAddress
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kbps = try values.decode(Int.self, forKey: .kbps)
        mode = try values.decode(Mode.self, forKey: .mode)
        scope = try values.decode(Scope.self, forKey: .scope)
        interface = try values.decode(String.self, forKey: .interface)
        ports = try values.decodeIfPresent([Int].self, forKey: .ports) ?? []
        remoteAddress = try Self.parseRemoteAddress(values.decodeIfPresent(String.self, forKey: .remoteAddress) ?? "")
    }

    public static let remoteAddressError = "Enter one IPv4 or IPv6 address, for example 203.0.113.10."

    public static func parseRemoteAddress(_ text: String) throws -> String? {
        guard !text.isEmpty else { return nil }
        guard text.utf8.count < Int(INET6_ADDRSTRLEN), text.utf8.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) || $0 == 46 || $0 == 58
        }) else { throw SnailError.invalidConfig(remoteAddressError) }
        if text.contains(".") {
            let ipv4 = text.split(separator: ":").last ?? Substring(text)
            let octets = ipv4.split(separator: ".", omittingEmptySubsequences: false)
            guard octets.count == 4, octets.allSatisfy({ $0.count == 1 || $0.first != "0" }) else {
                throw SnailError.invalidConfig(remoteAddressError)
            }
        }
        for family in [AF_INET, AF_INET6] {
            var address = in6_addr()
            guard text.withCString({ inet_pton(family, $0, &address) }) == 1 else { continue }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(family, &address, &buffer, socklen_t(buffer.count)) != nil else { continue }
            return String(cString: buffer)
        }
        throw SnailError.invalidConfig(remoteAddressError)
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

    static func validatedPorts(_ ports: [Int], required: Bool) throws -> [Int] {
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
