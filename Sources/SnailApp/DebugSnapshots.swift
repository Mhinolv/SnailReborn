#if DEBUG
import AppKit
import SnailCore
import SwiftUI

private struct SnapshotCaptureKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isSnapshotCapture: Bool {
        get { self[SnapshotCaptureKey.self] }
        set { self[SnapshotCaptureKey.self] = newValue }
    }
}

// AppKit omits the native default bezel from offscreen captures.
struct SnapshotApplyNowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .foregroundStyle(.white)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 5))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
    }
}

/// Debug-only: `SNAIL_SNAPSHOT_DIR=/path swift run SnailApp` renders the popover and Settings
/// in light and dark mode to PNGs, then exits. Lets UI be reviewed without clicking the menu bar.
@MainActor
enum DebugSnapshots {
    static func runIfRequested(model: SnailModel) {
        guard let dir = ProcessInfo.processInfo.environment["SNAIL_SNAPSHOT_DIR"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {   // let a few throughput samples arrive
            do {
                try renderAll(model: model, to: dir)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Snapshot failed: \(error)\n".utf8))
                exit(1)
            }
        }
    }

    static func renderAll(model: SnailModel, to dir: String) throws {
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            render(MenuContentView(model: model), to: "\(dir)/menu-\(name).png", appearance: appearance)
            render(SettingsView(model: model), to: "\(dir)/settings-\(name).png", appearance: appearance)
        }
        for sort in SnailModel.AppSort.allCases {
            model.debugSimulate(active: nil, error: nil, appSort: sort)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                render(MenuContentView(model: model),
                       to: "\(dir)/menu-apps-\(sort.rawValue)-\(name).png", appearance: appearance)
            }
        }
        render(GlyphSheet(), to: "\(dir)/glyph.png", appearance: .aqua)
        let iface = model.wifiInterface ?? "en0"
        model.debugSimulate(active: ThrottleConfig(kbps: 1_500, mode: .total, scope: .web, interface: iface), error: nil)
        render(MenuContentView(model: model), to: "\(dir)/menu-on-total.png", appearance: .aqua)
        model.debugSimulate(active: ThrottleConfig(kbps: 1_500, interface: iface), error: nil, vpn: true)
        render(MenuContentView(model: model), to: "\(dir)/menu-vpn-dark.png", appearance: .darkAqua)
        render(MenuContentView(model: model), to: "\(dir)/menu-vpn-light.png", appearance: .aqua)
        model.debugSimulate(active: ThrottleConfig(kbps: 3_000, interface: iface),
                            error: "pfctl: DIOCADDRULE: Operation not permitted")
        render(MenuContentView(model: model), to: "\(dir)/menu-pending-error.png", appearance: .darkAqua)
        render(SettingsView(model: model), to: "\(dir)/settings-pending.png", appearance: .aqua)
        render(SettingsView(model: model), to: "\(dir)/settings-pending-dark.png", appearance: .darkAqua)
        model.kbps = Preset.sd.kbps
        model.scope = .custom
        model.portsText = "25461, 8080"
        model.commitPorts()
        model.debugSimulate(active: model.desiredConfig, error: nil)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            render(SettingsView(model: model), to: "\(dir)/settings-custom-\(name).png", appearance: appearance)
            render(MenuContentView(model: model), to: "\(dir)/menu-custom-\(name).png", appearance: appearance)
            model.portsText = "0, 65536"
            render(SettingsView(model: model), to: "\(dir)/settings-custom-invalid-\(name).png", appearance: appearance)
            model.portsText = "25461, 8080"
        }
        renderProfiles(to: dir)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir)
            .filter { $0.hasSuffix(".png") }.sorted()
        let manifest = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "files": files],
                                                  options: [.prettyPrinted, .sortedKeys])
        try manifest.write(to: URL(fileURLWithPath: "\(dir)/manifest.json"), options: .atomic)
    }

    private static func renderProfiles(to dir: String) {
        let suite = "SnailProfileSnapshots-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return }
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = SnailModel(defaults: defaults, wifiInterface: "en12", samplesAutomatically: false)
        model.debugSimulate(active: nil, error: nil)
        func renderState(_ state: String) {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                render(SettingsView(model: model), to: "\(dir)/settings-profiles-\(state)-\(name).png",
                       appearance: appearance)
            }
        }
        renderState("empty")
        for (name, kbps, mode, scope, ports) in [
            ("Video", 1500, ThrottleConfig.Mode.perStream, ThrottleConfig.Scope.web, ""),
            ("Data saver", 3000, .total, .all, ""),
            ("IPTV", 5000, .perStream, .custom, "25461, 8080")
        ] {
            model.kbps = kbps
            model.mode = mode
            model.scope = scope
            model.portsText = ports
            if scope == .custom { model.commitPorts() }
            model.beginSaveProfile()
            model.profileName = name
            model.confirmProfile()
        }
        renderState("selected")
        model.debugSimulate(active: model.desiredConfig, error: nil)
        model.kbps = 3000
        renderState("edited")
    }

    /// The menu bar glyph off/on, large and at real size, on light and dark bars.
    private struct GlyphSheet: View {
        var body: some View {
            VStack(spacing: 12) {
                HStack(spacing: 24) {
                    ForEach([false, true], id: \.self) { on in
                        Image(nsImage: SnailGlyph.image(filled: on, size: 144)).renderingMode(.template)
                    }
                }
                ForEach([Color.white, Color.black], id: \.self) { bar in
                    HStack(spacing: 14) {
                        ForEach([false, true], id: \.self) { on in
                            Image(nsImage: SnailGlyph.image(filled: on)).renderingMode(.template)
                        }
                        Image(systemName: "wifi"); Image(systemName: "battery.75")
                    }
                    .foregroundStyle(bar == .white ? Color.black : Color.white)
                    .padding(6).frame(maxWidth: .infinity).background(bar)
                }
            }
            .padding(16).frame(width: 360)
        }
    }

    static func render<V: View>(_ view: V, to path: String, appearance: NSAppearance.Name) {
        let host = NSHostingView(rootView: view
            .environment(\.isSnapshotCapture, true)
            .background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: appearance)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        host.display()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif
