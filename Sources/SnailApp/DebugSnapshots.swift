#if DEBUG
import AppKit
import SnailCore
import SwiftUI

/// Debug-only: `SNAIL_SNAPSHOT_DIR=/path swift run SnailApp` renders the popover and Settings
/// in light and dark mode to PNGs, then exits. Lets UI be reviewed without clicking the menu bar.
@MainActor
enum DebugSnapshots {
    static func runIfRequested(model: SnailModel) {
        guard let dir = ProcessInfo.processInfo.environment["SNAIL_SNAPSHOT_DIR"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {   // let a few throughput samples arrive
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
            exit(0)
        }
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

    private static func render<V: View>(_ view: V, to path: String, appearance: NSAppearance.Name) {
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
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
