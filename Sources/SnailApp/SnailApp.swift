import SwiftUI
import SnailCore

@main
struct SnailApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // New status items appear leftmost, which on a crowded notched MacBook means hidden behind the notch.
        // Default to near the clock (points from the right edge); a Cmd-drag by the user overrides this.
        UserDefaults.standard.register(defaults: ["NSStatusItem Preferred Position Item-0": 200.0])
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: appDelegate.model)
        } label: {
            MenuBarIcon(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: appDelegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = SnailModel()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar utility: no Dock icon (also set by LSUIElement in the bundled app).
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        if ProcessInfo.processInfo.environment["SNAIL_SNAPSHOT_DIR"] != nil {
            DebugSnapshots.runIfRequested(model: model)
            return
        }
        #endif
        // Opening the app from Finder/Launchpad should show something, not just a menu bar icon
        // (which can also be hidden behind the notch on a crowded menu bar).
        showWindow()
    }

    /// Clicking the app again while it's running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    func showWindow() {
        if window == nil {
            let host = NSHostingView(rootView: MenuContentView(model: model, showsMenuBarHint: true))
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Snail"
            w.contentView = host
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("SnailMainWindow")
            if !w.setFrameUsingName("SnailMainWindow") { w.center() }
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.prepareToQuit() ? .terminateNow : .terminateCancel
    }
}

struct MenuBarIcon: View {
    @ObservedObject var model: SnailModel

    var body: some View {
        Image(nsImage: SnailGlyph.image(filled: model.isOn))
            .accessibilityLabel(model.isOn ? "Snail, Stream Saver on" : "Snail, Stream Saver off")
    }
}
