import Foundation

public struct StatusReport: Encodable {
    public let recordedConfig: ThrottleConfig?
    public let stateFile: String
    public let wifiInterface: String?
    public let bypass: RoutePath.Bypass?

    public init(recordedConfig: ThrottleConfig?, stateFile: String, wifiInterface: String?, bypass: RoutePath.Bypass?) {
        self.recordedConfig = recordedConfig
        self.stateFile = stateFile
        self.wifiInterface = wifiInterface
        self.bypass = bypass
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, active, recordedConfig, stateFile, wifiInterface, bypass
    }

    private struct BypassReport: Encodable {
        let interface: String
        let kind: String
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(1, forKey: .schemaVersion)
        try values.encode(recordedConfig != nil, forKey: .active)
        try values.encode(recordedConfig, forKey: .recordedConfig)
        try values.encode(stateFile, forKey: .stateFile)
        try values.encode(wifiInterface, forKey: .wifiInterface)
        let report: BypassReport?
        switch bypass {
        case .vpn(let interface): report = BypassReport(interface: interface, kind: "vpn")
        case .otherInterface(let interface): report = BypassReport(interface: interface, kind: "otherInterface")
        case nil: report = nil
        }
        try values.encode(report, forKey: .bypass)
    }

    public func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self) + "\n"
    }
}

public enum RecordedStateError: LocalizedError {
    case absent
    case invalid(path: String)
    case unreadable(path: String, reason: String)

    public var exitCode: Int32 {
        switch self {
        case .absent: return 3
        case .invalid: return 4
        case .unreadable: return 5
        }
    }

    public var errorDescription: String? {
        switch self {
        case .absent: return "Off. No limit is recorded."
        case .invalid(let path): return "The state file \(path) is not valid."
        case .unreadable(let path, let reason): return "Cannot read \(path): \(reason)"
        }
    }
}
