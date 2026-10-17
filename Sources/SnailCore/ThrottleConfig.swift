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
    }

    public static let minKbps = 64
    public static let maxKbps = 1_000_000

    public var kbps: Int
    public var mode: Mode
    public var scope: Scope
    /// BSD interface name, e.g. "en0".
    public var interface: String

    public init(kbps: Int = Preset.sd.kbps, mode: Mode = .perStream, scope: Scope = .web, interface: String) {
        self.kbps = kbps
        self.mode = mode
        self.scope = scope
        self.interface = interface
    }

    public func validated() throws -> ThrottleConfig {
        guard (Self.minKbps...Self.maxKbps).contains(kbps) else {
            throw SnailError.invalidConfig("Speed must be between \(Self.minKbps) and \(Self.maxKbps) Kbps.")
        }
        guard Self.isValidInterfaceName(interface) else {
            throw SnailError.invalidConfig("“\(interface)” is not a valid network interface name.")
        }
        return self
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
