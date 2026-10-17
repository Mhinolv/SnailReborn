import Foundation

public struct SavedProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let kbps: Int
    public let mode: ThrottleConfig.Mode
    public let scope: ThrottleConfig.Scope
    public let ports: [Int]
    public let remoteAddress: String?

    public init(id: UUID = UUID(), name: String, kbps: Int, mode: ThrottleConfig.Mode,
                scope: ThrottleConfig.Scope, ports: [Int] = [], remoteAddress: String? = nil) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...32).contains(name.count) else {
            throw SnailError.invalidConfig("Enter a profile name with 1 to 32 characters.")
        }
        guard (ThrottleConfig.minKbps...ThrottleConfig.maxKbps).contains(kbps) else {
            throw SnailError.invalidConfig("The profile speed is outside the allowed range.")
        }
        self.id = id
        self.name = name
        self.kbps = kbps
        self.mode = mode
        self.scope = scope
        self.remoteAddress = try ThrottleConfig.parseRemoteAddress(remoteAddress ?? "")
        self.ports = try ThrottleConfig.validatedPorts(ports, required: scope == .custom)
    }

    public func matches(kbps: Int, mode: ThrottleConfig.Mode, scope: ThrottleConfig.Scope, ports: [Int], remoteAddress: String? = nil) -> Bool {
        self.kbps == kbps && self.mode == mode && self.scope == scope && self.ports == ports && self.remoteAddress == remoteAddress
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kbps, mode, scope, ports, remoteAddress
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(UUID.self, forKey: .id),
            name: values.decode(String.self, forKey: .name),
            kbps: values.decode(Int.self, forKey: .kbps),
            mode: values.decode(ThrottleConfig.Mode.self, forKey: .mode),
            scope: values.decode(ThrottleConfig.Scope.self, forKey: .scope),
            ports: values.decodeIfPresent([Int].self, forKey: .ports) ?? [],
            remoteAddress: values.decodeIfPresent(String.self, forKey: .remoteAddress)
        )
    }
}

/// Profiles use a separate format with defaults for fields absent from older files.
public enum SavedProfileStore {
    public static let limit = 10
    public static let key = "savedProfiles"

    public static func load(from defaults: UserDefaults) -> [SavedProfile] {
        guard let data = defaults.data(forKey: key),
              let document = try? JSONDecoder().decode(Document.self, from: data),
              (1...2).contains(document.version) else { return [] }
        return accepted(document.profiles.compactMap(\.profile))
    }

    public static func save(_ profiles: [SavedProfile], to defaults: UserDefaults) throws {
        let document = Document(profiles: accepted(profiles))
        defaults.set(try JSONEncoder().encode(document), forKey: key)
    }

    private static func accepted(_ profiles: [SavedProfile]) -> [SavedProfile] {
        var result: [SavedProfile] = []
        for profile in profiles {
            // Revalidate mutable names before each write, as well as at decode time.
            guard let valid = try? SavedProfile(id: profile.id, name: profile.name, kbps: profile.kbps,
                                               mode: profile.mode, scope: profile.scope, ports: profile.ports, remoteAddress: profile.remoteAddress),
                  !result.contains(where: {
                      $0.id == valid.id || $0.name.caseInsensitiveCompare(valid.name) == .orderedSame ||
                      $0.matches(kbps: valid.kbps, mode: valid.mode, scope: valid.scope, ports: valid.ports, remoteAddress: valid.remoteAddress)
                  }) else { continue }
            result.append(valid)
            if result.count == limit { break }
        }
        return result
    }

    private struct Entry: Codable {
        let profile: SavedProfile?

        init(profile: SavedProfile) { self.profile = profile }

        init(from decoder: Decoder) throws {
            profile = try? SavedProfile(from: decoder)
        }

        func encode(to encoder: Encoder) throws {
            try profile?.encode(to: encoder)
        }
    }

    private struct Document: Codable {
        let version: Int
        let profiles: [Entry]

        init(profiles: [SavedProfile]) {
            version = 2
            self.profiles = profiles.map(Entry.init)
        }

        private enum CodingKeys: String, CodingKey { case version, profiles }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
            profiles = try values.decodeIfPresent([Entry].self, forKey: .profiles) ?? []
        }
    }
}
