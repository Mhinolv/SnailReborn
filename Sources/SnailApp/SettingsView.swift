import SwiftUI
import SnailCore

/// Settings (⌘,). Edits here are staged; if Stream Saver is on, "Apply Now" pushes them
/// so the user isn't asked for a password on every keystroke.
struct SettingsView: View {
    @ObservedObject var model: SnailModel
    @State private var showRules = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                limitSection
                wifiSection
                Section {
                    Toggle("Turn off the limit when Snail quits", isOn: $model.turnOffOnQuit)
                } footer: {
                    Text("If off, the limit stays in place until you turn it off or restart your Mac.")
                        .settingsFooter()
                }
                advancedSection
            }
            .formStyle(.grouped)

            if model.hasPendingChanges || model.errorMessage != nil {
                Divider()
                statusBar
            }
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    // MARK: Sections

    private var limitSection: some View {
        Section {
            Picker("Speed", selection: Binding(
                get: { model.preset?.rawValue ?? "custom" },
                set: { tag in
                    if let preset = Preset(rawValue: tag) {
                        model.kbps = preset.kbps
                    } else if model.preset != nil {
                        model.kbps = 2_000
                    }
                }
            )) {
                ForEach(Preset.allCases) { preset in
                    Text("\(preset.title) · \(Rate.format(kbps: preset.kbps))").tag(preset.rawValue)
                }
                Divider()
                Text("Custom").tag("custom")
            }

            if model.preset == nil {
                LabeledContent("Custom speed") {
                    HStack(spacing: 6) {
                        TextField("Kbps", value: Binding(
                            get: { model.kbps },
                            set: { model.kbps = min(max($0, ThrottleConfig.minKbps), ThrottleConfig.maxKbps) }
                        ), format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .labelsHidden()
                        Stepper("Custom speed", value: $model.kbps,
                                in: ThrottleConfig.minKbps...ThrottleConfig.maxKbps, step: 250)
                            .labelsHidden()
                        Text("Kbps").foregroundStyle(.secondary)
                    }
                }
            }

            Picker("Limit", selection: $model.mode) {
                Text("Each stream separately").tag(ThrottleConfig.Mode.perStream)
                Text("All Wi‑Fi traffic combined").tag(ThrottleConfig.Mode.total)
            }
            .pickerStyle(.radioGroup)

            Picker("Applies to", selection: $model.scope) {
                Text("Web & video (HTTPS and QUIC)").tag(ThrottleConfig.Scope.web)
                Text("All traffic").tag(ThrottleConfig.Scope.all)
            }
            .pickerStyle(.radioGroup)
        } header: {
            Text("Speed Limit")
        } footer: {
            Text(limitExplanation).settingsFooter()
        }
    }

    private var limitExplanation: String {
        switch model.mode {
        case .perStream:
            return "Like AT&T Stream Saver: each connection is capped, so video drops to a lower quality while pages and small downloads stay fast."
        case .total:
            return "Everything on Wi‑Fi shares one cap. Saves the most data, but browsing and downloads slow down too."
        }
    }

    private var wifiSection: some View {
        Section("Wi‑Fi") {
            LabeledContent("Interface", value: model.wifiInterface ?? "Not found")
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Image(systemName: model.isOn ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(model.isOn ? Color.accentColor : .secondary)
                    Text(model.active?.summary ?? "Off")
                }
            }
        }
    }

    private var advancedSection: some View {
        Section {
            DisclosureGroup("pf and dnctl rules", isExpanded: $showRules) {
                Text(rulesText)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            LabeledContent("Remove everything Snail added") {
                Button("Remove Rules") { model.turnOff() }
                    .disabled(model.isBusy)
            }
        } header: {
            Text("Advanced")
        } footer: {
            Text("Snail uses the built-in pf firewall and dummynet in the anchor \(ThrottleScript.anchor). No Network Extension is installed, and nothing outside that anchor is changed.")
                .settingsFooter()
        }
    }

    private var rulesText: String {
        guard let config = model.desiredConfig else { return "No Wi‑Fi interface found." }
        let rules = ThrottleScript.pfRules(for: config).joined(separator: "\n")
        let pipe = "dnctl " + ThrottleScript.pipeArguments(for: config).joined(separator: " ")
        return "\(rules)\n\(pipe)"
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            if let error = model.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(error).font(.callout).lineLimit(2)
            } else {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text("Stream Saver is on with different settings.").font(.callout)
            }
            Spacer()
            if model.isBusy {
                ProgressView().controlSize(.small)
            }
            if model.hasPendingChanges {
                Button("Apply Now") { model.apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isBusy)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private extension Text {
    func settingsFooter() -> some View {
        self.font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
