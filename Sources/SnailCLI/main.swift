import Foundation
import SnailCore

@main
struct SnailCLI {
    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        guard !args.isEmpty else { printUsage(); exit(0) }
        let command = args.removeFirst()
        let controller = ThrottleController(runner: RootShellRunner())

        do {
            switch command {
            case "on":
                let config = try parseConfig(args)
                try controller.apply(config)
                print("Stream Saver on: \(describe(config))")

            case "off":
                try controller.remove()
                print("Stream Saver off. Snail's pf rules and pipe were removed.")

            case "status":
                if let config = controller.activeConfig() {
                    print("On: \(describe(config))")
                } else {
                    print("Off.")
                }
                if let wifi = WiFi.interfaceName(), let bypass = RoutePath.bypass(wifi: wifi) {
                    print("Warning: \(bypass.explanation)")
                }

            case "apps":
                let sampler = AppTrafficSampler()
                _ = sampler.sample()
                Thread.sleep(forTimeInterval: 2)
                let apps = sampler.sample().filter { $0.downKbps + $0.upKbps >= 1 }.prefix(10)
                if apps.isEmpty { print("No apps are using the network.") }
                for app in apps {
                    let name = app.name.padding(toLength: 28, withPad: " ", startingAt: 0)
                    print("\(name) ↓ \(Rate.format(kbps: app.downKbps))  ↑ \(Rate.format(kbps: app.upKbps))")
                }

            case "rules":
                let config = try parseConfig(args).validated()
                print("# pf anchor \(ThrottleScript.anchor)")
                ThrottleScript.pfRules(for: config).forEach { print($0) }
                print("\n# dnctl")
                print("dnctl " + ThrottleScript.pipeArguments(for: config).joined(separator: " "))

            case "script":
                let sub = args.first ?? "on"
                print(sub == "off" ? ThrottleScript.offScript() : try ThrottleScript.onScript(for: parseConfig(Array(args.dropFirst()))))

            case "help", "-h", "--help":
                printUsage()

            default:
                fputs("Unknown command “\(command)”.\n\n", stderr)
                printUsage()
                exit(64)
            }
        } catch {
            fputs("snailctl: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func parseConfig(_ args: [String]) throws -> ThrottleConfig {
        var config = ThrottleConfig(interface: WiFi.interfaceName() ?? "")
        var it = args.makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--kbps":
                guard let v = it.next(), let kbps = Int(v) else { throw SnailError.invalidConfig("--kbps needs a number.") }
                config.kbps = kbps
            case "--sd": config.kbps = Preset.sd.kbps
            case "--hd": config.kbps = Preset.hd.kbps
            case "--fullhd": config.kbps = Preset.fullHD.kbps
            case "--total": config.mode = .total
            case "--per-stream": config.mode = .perStream
            case "--all-traffic": config.scope = .all
            case "--interface":
                guard let v = it.next() else { throw SnailError.invalidConfig("--interface needs a name.") }
                config.interface = v
            default:
                throw SnailError.invalidConfig("Unknown option “\(arg)”.")
            }
        }
        if config.interface.isEmpty {
            throw SnailError.invalidConfig("No Wi‑Fi interface found. Pass --interface <name>.")
        }
        return try config.validated()
    }

    static func describe(_ c: ThrottleConfig) -> String {
        let mode = c.mode == .perStream ? "per stream" : "total"
        let scope = c.scope == .web ? "web & video (port 443, TCP+QUIC)" : "all traffic"
        return "\(Rate.format(kbps: c.kbps)) \(mode), \(scope), on \(c.interface)"
    }

    static func printUsage() {
        print("""
        snailctl: Wi‑Fi Stream Saver (pf + dummynet, no Network Extension)

        USAGE
          sudo snailctl on [options]   Start or update the limit
          sudo snailctl off            Remove Snail's rules (leaves everything else alone)
          snailctl status              Show whether a limit is active (and whether a VPN bypasses it)
          snailctl apps                Show which apps are using the network right now
          snailctl rules [options]     Print the pf/dnctl rules without applying them
          snailctl script on|off [options]  Print the exact root script

        OPTIONS
          --sd | --hd | --fullhd       1.5 / 3 / 5 Mbps (default --sd, like AT&T)
          --kbps <n>                   Custom speed (\(ThrottleConfig.minKbps)–\(ThrottleConfig.maxKbps))
          --per-stream | --total       Limit each connection (default) or all traffic combined
          --all-traffic                Limit everything, not just port 443 (HTTPS/QUIC)
          --interface <name>           Override the auto-detected Wi‑Fi interface
        """)
    }
}
