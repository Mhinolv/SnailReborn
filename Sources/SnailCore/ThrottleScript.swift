import Foundation

/// Pure builders for the pf rules and the root shell scripts that apply/remove them.
/// Nothing here has side effects, so it is fully unit-testable.
///
/// The caller validates config before use. Scripts also validate all fields, including numeric addresses.
public enum ThrottleScript {
    /// `/etc/pf.conf` only evaluates `dummynet-anchor "com.apple/*"`.
    public static let anchor = "com.apple/snailreborn"
    /// Snail-owned dummynet pipe. Never flush pipes globally.
    public static let pipeID = 47_101
    /// Root-owned state in /var/run, which is cleared at boot (as are pf rules), so state can't go stale across reboots.
    public static let tokenPath = "/var/run/snailreborn.token"
    public static let statePath = "/var/run/snailreborn.json"

    static let dnctl = "/usr/sbin/dnctl"
    static let pfctl = "/sbin/pfctl"

    public static func pfRules(for config: ThrottleConfig) -> [String] {
        let iface = config.interface
        let source = config.remoteAddress ?? "any"
        switch config.scope {
        case .web:
            return ["dummynet in on \(iface) proto { tcp udp } from \(source) port 443 to any pipe \(pipeID)"]
        case .custom:
            let ports = config.ports.map(String.init).joined(separator: " ")
            return ["dummynet in on \(iface) proto { tcp udp } from \(source) port { \(ports) } to any pipe \(pipeID)"]
        case .all:
            return [config.remoteAddress == nil
                ? "dummynet in on \(iface) all pipe \(pipeID)"
                : "dummynet in on \(iface) from \(source) to any pipe \(pipeID)"]
        }
    }

    public static func pipeArguments(for config: ThrottleConfig) -> [String] {
        var args = ["pipe", "\(pipeID)", "config", "bw", "\(config.kbps)Kbit/s"]
        if config.mode == .perStream {
            // Inbound packets: dst-port is our local ephemeral port, so each connection gets its own pipe.
            args += ["mask", "dst-port", "0xffff"]
        }
        return args
    }

    /// Script that turns throttling on, or updates it in place if already on.
    /// Takes a pf enable reference (`pfctl -E`) only once and keeps its token so `off` can release it.
    public static func onScript(for config: ThrottleConfig) throws -> String {
        let config = try config.validated()
        let rules = pfRules(for: config).map { "'\($0)'" }.joined(separator: " ")
        let state = try String(decoding: JSONEncoder.sorted.encode(config), as: UTF8.self)
        return """
        set -e
        \(dnctl) pipe delete \(pipeID) >/dev/null 2>&1 || true
        \(dnctl) \(pipeArguments(for: config).joined(separator: " "))
        out=$(printf '%s\\n' \(rules) | \(pfctl) -q -a \(anchor) -f - 2>&1) || { echo "$out" >&2; exit 1; }
        if [ ! -s \(tokenPath) ]; then \(pfctl) -E 2>&1 | sed -n 's/^Token : //p' > \(tokenPath); fi
        printf '%s' '\(state)' > \(statePath)
        """
    }

    /// Script that removes only what Snail added. Safe to run when nothing is active.
    public static func offScript() -> String {
        """
        \(pfctl) -q -a \(anchor) -F all >/dev/null 2>&1 || true
        \(dnctl) pipe delete \(pipeID) >/dev/null 2>&1 || true
        if [ -s \(tokenPath) ]; then \(pfctl) -X "$(cat \(tokenPath))" >/dev/null 2>&1 || true; fi
        rm -f \(tokenPath) \(statePath)
        """
    }

    /// Wraps a shell script in AppleScript that asks for an administrator password.
    public static func appleScript(running script: String, prompt: String) -> String {
        "do shell script \"\(escapeForAppleScript(script))\" with prompt \"\(escapeForAppleScript(prompt))\" with administrator privileges"
    }

    static func escapeForAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

extension JSONEncoder {
    static var sorted: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }
}
