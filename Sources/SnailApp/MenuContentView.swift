import SwiftUI
import SnailCore

/// The menu bar popover: one switch, a speed choice, and live Wi‑Fi throughput.
struct MenuContentView: View {
    @ObservedObject var model: SnailModel
    /// True when shown in the app window rather than the menu bar popover.
    var showsMenuBarHint = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(16)

            if let bypass = model.bypass {
                BypassBanner(bypass: bypass, isOn: model.isOn)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            if let error = model.errorMessage {
                ErrorBanner(message: error) { model.errorMessage = nil }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            if model.hasPendingChanges {
                pendingBanner
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            Divider()
            speedSection.padding(16)
            Divider()
            throughputSection.padding(16)
            Divider()
            appsSection.padding(16)
            Divider()
            if showsMenuBarHint {
                menuBarHint
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Divider()
            }
            footer.padding(6)
        }
        .frame(width: 320)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: SnailGlyph.image(filled: true, size: 22))
                .renderingMode(.template)
                .foregroundStyle(model.isOn ? Color.white : Color.secondary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(model.isOn ? Color.accentColor : Color.secondary.opacity(0.15)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Stream Saver")
                    .font(.headline)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 38)
            } else {
                Toggle("Stream Saver", isOn: Binding(get: { model.isOn }, set: { model.setOn($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(model.wifiInterface == nil && !model.isOn)
            }
        }
    }

    private var statusText: String {
        if model.isBusy { return "Updating…" }
        if let active = model.active { return active.summary }
        if model.wifiInterface == nil { return "No Wi‑Fi on this Mac" }
        return "Off · full Wi‑Fi speed"
    }

    private var pendingBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
            Text("Settings changed")
                .font(.callout)
            Spacer()
            Button("Apply") { model.apply() }
                .controlSize(.small)
                .disabled(model.isBusy)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
    }

    // MARK: Speed

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speed limit")
                .font(.subheadline.weight(.semibold))

            Picker("Speed limit", selection: Binding(
                get: { model.preset?.rawValue ?? "custom" },
                set: { if let p = Preset(rawValue: $0) { model.choose(p) } }
            )) {
                ForEach(Preset.allCases) { preset in
                    Text(preset.title).tag(preset.rawValue)
                }
                if model.preset == nil {
                    Text("Custom").tag("custom")
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(model.isBusy)

            Text(model.speedCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Throughput

    private var throughputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Wi‑Fi now")
                    .font(.subheadline.weight(.semibold))
                if let iface = model.wifiInterface {
                    Text(iface)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 20) {
                RateReadout(symbol: "arrow.down", label: "Download", kbps: model.downKbps)
                RateReadout(symbol: "arrow.up", label: "Upload", kbps: model.upKbps)
                Spacer()
            }

            ThroughputSparkline(
                samples: model.downHistory,
                capacity: SnailModel.historyLength,
                limitKbps: model.active?.mode == .total ? model.active.map { Double($0.kbps) } : nil
            )
            .frame(height: 44)

            Text("Since launch: \(bytes(model.sessionBytesIn)) down · \(bytes(model.sessionBytesOut)) up")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Apps

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Apps now")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Sort apps by", selection: Binding(
                    get: { model.appSort },
                    set: { model.chooseAppSort($0) }
                )) {
                    Image(systemName: "arrow.down")
                        .accessibilityLabel("Sort by download")
                        .help("Sort by download")
                        .tag(SnailModel.AppSort.download)
                    Image(systemName: "arrow.up")
                        .accessibilityLabel("Sort by upload")
                        .help("Sort by upload")
                        .tag(SnailModel.AppSort.upload)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel("Sort apps by")
                .frame(width: 64)
            }

            if model.topApps.isEmpty {
                Text("No apps are using the network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(model.topApps) { app in
                        AppUsageRow(app: app, sort: model.appSort)
                    }
                }
            }
        }
    }

    private func bytes(_ count: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: count), countStyle: .file)
    }

    private var menuBarHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "menubar.arrow.up.rectangle")
                .foregroundStyle(.secondary)
            Text("Snail keeps running in the menu bar. Click the snail icon at the top of your screen anytime.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            settingsButton
            Button {
                NSApp.terminate(nil)
            } label: {
                MenuRow(title: "Quit Snail", shortcut: "⌘Q")
            }
            .buttonStyle(MenuRowButtonStyle())
            .keyboardShortcut("q")
        }
    }

    @ViewBuilder
    private var settingsButton: some View {
        if #available(macOS 14, *) {
            SettingsLink {
                MenuRow(title: "Settings…", shortcut: "⌘,")
            }
            .buttonStyle(MenuRowButtonStyle())
            .keyboardShortcut(",")
        } else {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                MenuRow(title: "Settings…", shortcut: "⌘,")
            }
            .buttonStyle(MenuRowButtonStyle())
            .keyboardShortcut(",")
        }
    }
}

// MARK: - Components

struct RateReadout: View {
    let symbol: String
    let label: String
    let kbps: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(Rate.format(kbps: kbps))
                .font(.title3.weight(.medium).monospacedDigit())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(Rate.format(kbps: kbps))")
    }
}

struct AppUsageRow: View {
    let app: AppUsage
    let sort: SnailModel.AppSort

    var body: some View {
        HStack(spacing: 8) {
            icon
                .frame(width: 16, height: 16)
            Text(app.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text("↓ \(Rate.format(kbps: app.downKbps))")
                .monospacedDigit()
                .foregroundStyle(sort == .download ? Color.primary : Color.secondary)
                .frame(minWidth: 72, alignment: .trailing)
            Text("↑ \(Rate.format(kbps: app.upKbps))")
                .monospacedDigit()
                .foregroundStyle(sort == .upload ? Color.primary : Color.secondary)
                .frame(minWidth: 72, alignment: .trailing)
        }
        .font(.callout)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(app.name), download \(Rate.format(kbps: app.downKbps)), upload \(Rate.format(kbps: app.upKbps))")
    }

    @ViewBuilder
    private var icon: some View {
        if let path = app.bundlePath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
        } else {
            Image(systemName: "terminal")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Shown when internet traffic isn't leaving over Wi‑Fi, so Snail's rules never see it.
struct BypassBanner: View {
    let bypass: RoutePath.Bypass
    let isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.15)))
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        if case .vpn = bypass { return "lock.trianglebadge.exclamationmark" }
        return "cable.connector"
    }

    private var title: String {
        switch bypass {
        case .vpn: return isOn ? "A VPN is bypassing the limit" : "A VPN is on"
        case .otherInterface: return "Traffic isn't using Wi‑Fi"
        }
    }

    private var detail: String {
        switch bypass {
        case .vpn(let iface):
            return "Traffic is tunneled through \(iface), so Snail can't see individual streams. Disconnect the VPN for the limit to work."
        case .otherInterface(let iface):
            return "Internet traffic is going over \(iface). Snail only limits Wi‑Fi."
        }
    }
}

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss error")
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.15)))
    }
}

struct MenuRow: View {
    let title: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(shortcut).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

/// Native-menu-like row: highlights on hover.
struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverRow(configuration: configuration)
    }

    private struct HoverRow: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hovering || configuration.isPressed ? Color.primary.opacity(0.1) : .clear)
                )
                .onHover { hovering = $0 }
        }
    }
}
