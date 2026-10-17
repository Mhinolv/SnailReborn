import AppKit
import SnailCore

/// All app state. Views read from here and call its intents; no shell or pf logic lives in views.
@MainActor
final class SnailModel: ObservableObject {
    enum AppSort: String, CaseIterable {
        case download, upload
    }

    // Preferences (persisted)
    @Published var kbps: Int { didSet { defaults.set(kbps, forKey: Keys.kbps) } }
    @Published var mode: ThrottleConfig.Mode { didSet { defaults.set(mode.rawValue, forKey: Keys.mode) } }
    @Published var scope: ThrottleConfig.Scope { didSet { defaults.set(scope.rawValue, forKey: Keys.scope) } }
    @Published var turnOffOnQuit: Bool { didSet { defaults.set(turnOffOnQuit, forKey: Keys.turnOffOnQuit) } }

    @Published var portsText: String
    @Published private(set) var ports: [Int] {
        didSet { defaults.set(ports, forKey: Keys.ports) }
    }

    @Published private(set) var appSort: AppSort

    // Live state
    @Published private(set) var active: ThrottleConfig?
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?
    @Published private(set) var wifiInterface: String?
    @Published private(set) var downKbps: Double = 0
    @Published private(set) var upKbps: Double = 0
    @Published private(set) var downHistory: [Double] = []
    @Published private(set) var sessionBytesIn: UInt64 = 0
    @Published private(set) var sessionBytesOut: UInt64 = 0
    /// Set when internet traffic isn't leaving over Wi‑Fi (e.g. a VPN), so the limit can't apply.
    @Published private(set) var bypass: RoutePath.Bypass?
    /// Busiest apps in the selected direction.
    @Published private(set) var topApps: [AppUsage] = []

    static let historyLength = 60
    static let topAppCount = 5

    private let defaults: UserDefaults
    private let controller: ThrottleController
    private var timer: Timer?
    private var lastCounters: (InterfaceCounters, Date)?
    private let appSampler = AppTrafficSampler()
    private let appQueue = DispatchQueue(label: "com.markhinojosa.SnailReborn.apps", qos: .utility)
    private var appSampleInFlight = false
    private var tick = 0

    private enum Keys {
        static let ports = "ports", appSort = "appSort"
        static let kbps = "kbps", mode = "mode", scope = "scope", turnOffOnQuit = "turnOffOnQuit"
    }

    init(defaults: UserDefaults = .standard,
         controller: ThrottleController = ThrottleController(runner: AdminPromptRunner()),
         wifiInterface: String? = WiFi.interfaceName(), samplesAutomatically: Bool = true) {
        self.defaults = defaults
        self.controller = controller
        let d = defaults
        kbps = (d.object(forKey: Keys.kbps) as? Int) ?? Preset.sd.kbps
        mode = d.string(forKey: Keys.mode).flatMap(ThrottleConfig.Mode.init(rawValue:)) ?? .perStream
        scope = d.string(forKey: Keys.scope).flatMap(ThrottleConfig.Scope.init(rawValue:)) ?? .web
        turnOffOnQuit = (d.object(forKey: Keys.turnOffOnQuit) as? Bool) ?? true
        let savedPorts = (d.array(forKey: Keys.ports) as? [Int]) ?? []
        ports = savedPorts
        portsText = savedPorts.map(String.init).joined(separator: ", ")
        appSort = d.string(forKey: Keys.appSort).flatMap(AppSort.init(rawValue:)) ?? .download
        self.wifiInterface = wifiInterface
        active = controller.activeConfig()
        if samplesAutomatically { startSampling() }
    }

    // MARK: Derived

    var isOn: Bool { active != nil }

    var desiredConfig: ThrottleConfig? {
        guard let wifiInterface else { return nil }
        return ThrottleConfig(kbps: kbps, mode: mode, scope: scope, interface: wifiInterface, ports: ports)
    }

    /// On, but with different settings than the ones chosen now.
    var hasPendingChanges: Bool {
        guard let active, let desiredConfig else { return false }
        return active != desiredConfig || (scope == .custom && portsText != ports.map(String.init).joined(separator: ", "))
    }

    var preset: Preset? { Preset.matching(kbps: kbps) }

    var portsValidationMessage: String? {
        guard scope == .custom else { return nil }
        return (try? ThrottleConfig.parsePorts(portsText)) == nil ? ThrottleConfig.portsError : nil
    }

    func commitPorts() {
        guard let parsed = try? ThrottleConfig.parsePorts(portsText) else { return }
        ports = parsed
        portsText = parsed.map(String.init).joined(separator: ", ")
    }

    // MARK: Intents

    func chooseAppSort(_ sort: AppSort) {
        guard appSort != sort else { return }
        appSort = sort
        defaults.set(sort.rawValue, forKey: Keys.appSort)
    }

    func updateApps(_ apps: [AppUsage]) {
        let sorted = apps.sorted { lhs, rhs in
            let left = appSort == .download
                ? (lhs.downKbps, lhs.upKbps, lhs.name)
                : (lhs.upKbps, lhs.downKbps, lhs.name)
            let right = appSort == .download
                ? (rhs.downKbps, rhs.upKbps, rhs.name)
                : (rhs.upKbps, rhs.downKbps, rhs.name)
            return left > right
        }
        topApps = Array(sorted.prefix(Self.topAppCount))
    }

    func setOn(_ on: Bool) {
        on ? apply() : turnOff()
    }

    func apply() {
        if let message = portsValidationMessage {
            errorMessage = message
            return
        }
        if scope == .custom { commitPorts() }
        guard let config = desiredConfig else {
            errorMessage = "No Wi‑Fi interface found on this Mac."
            return
        }
        perform { try self.controller.apply(config) }
    }

    func turnOff() {
        perform { try self.controller.remove() }
    }

    /// Picking a preset while on applies it right away; one click is one deliberate change.
    func choose(_ preset: Preset) {
        guard kbps != preset.kbps else { return }
        kbps = preset.kbps
        if isOn { apply() }
    }

    /// Called from applicationShouldTerminate. Returns false if the user cancelled the password prompt.
    func prepareToQuit() -> Bool {
        guard isOn, turnOffOnQuit else { return true }
        do {
            try controller.remove()
            return true
        } catch SnailError.cancelled {
            return false
        } catch {
            return true
        }
    }

    #if DEBUG
    func debugSimulate(active: ThrottleConfig?, error: String?, vpn: Bool = false, appSort: AppSort = .download) {
        timer?.invalidate()
        self.active = active
        errorMessage = error
        bypass = vpn ? .vpn(interface: "utun6") : nil
        self.appSort = appSort
        updateApps([
            AppUsage(id: "uhf", name: "UHF", downKbps: 13_800, upKbps: 4),
            AppUsage(id: "safari", name: "Safari", bundlePath: "/Applications/Safari.app", downKbps: 1_240, upKbps: 38),
            AppUsage(id: "slack", name: "Slack", downKbps: 21, upKbps: 6),
            AppUsage(id: "backup", name: "Backup", downKbps: 0, upKbps: 2_400),
            AppUsage(id: "mail", name: "Mail", downKbps: 12, upKbps: 2),
            AppUsage(id: "music", name: "Music", downKbps: 120, upKbps: 1),
        ])
        downHistory = (0..<Self.historyLength).map { (i: Int) -> Double in
            let wave: Double = 250 * sin(Double(i) / 4)
            return 1_350 + wave + Double(i % 7) * 30
        }
        downKbps = downHistory.last ?? 0
        upKbps = 96
        sessionBytesIn = 412_000_000
        sessionBytesOut = 23_000_000
    }
    #endif

    // MARK: Private

    private func perform(_ work: @escaping () throws -> Void) {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        // Let SwiftUI draw the busy state before the (main-thread) password prompt blocks.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [self] in
            do {
                try work()
            } catch SnailError.cancelled {
            } catch {
                errorMessage = error.localizedDescription
            }
            active = controller.activeConfig()
            isBusy = false
        }
    }

    private func startSampling() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        sample()
    }

    private func sample() {
        let iface = WiFi.interfaceName()
        if iface != wifiInterface {
            wifiInterface = iface
            lastCounters = nil
        }
        // Picks up changes made with `sudo snailctl` too.
        if !isBusy { active = controller.activeConfig() }
        bypass = iface.flatMap { RoutePath.bypass(wifi: $0) }
        tick += 1
        if tick % 2 == 0 { sampleApps() }

        guard let iface, let now = InterfaceStats.counters(for: iface) else {
            downKbps = 0
            upKbps = 0
            return
        }
        let date = Date()
        defer { lastCounters = (now, date) }
        guard let (prev, prevDate) = lastCounters else { return }
        let seconds = max(date.timeIntervalSince(prevDate), 0.001)
        let dIn = now.bytesIn >= prev.bytesIn ? now.bytesIn - prev.bytesIn : 0
        let dOut = now.bytesOut >= prev.bytesOut ? now.bytesOut - prev.bytesOut : 0
        sessionBytesIn += dIn
        sessionBytesOut += dOut
        downKbps = Double(dIn) * 8 / 1_000 / seconds
        upKbps = Double(dOut) * 8 / 1_000 / seconds
        downHistory.append(downKbps)
        if downHistory.count > Self.historyLength { downHistory.removeFirst(downHistory.count - Self.historyLength) }
    }

    /// nettop runs as a subprocess, so keep it off the main thread.
    private func sampleApps() {
        guard !appSampleInFlight else { return }
        appSampleInFlight = true
        let sampler = appSampler
        appQueue.async {
            let apps = sampler.sample().filter { $0.downKbps + $0.upKbps >= 1 }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                updateApps(apps)
                appSampleInFlight = false
            }
        }
    }
}

extension ThrottleConfig {
    var summary: String {
        switch mode {
        case .perStream: return "Each stream capped at \(Rate.format(kbps: kbps))"
        case .total: return "Wi‑Fi capped at \(Rate.format(kbps: kbps)) total"
        }
    }
}

extension Preset {
    var resolution: String {
        switch self {
        case .sd: return "about 480p, like AT&T Stream Saver"
        case .hd: return "about 720p"
        case .fullHD: return "about 1080p"
        }
    }
}
