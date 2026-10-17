#if DEBUG
import AppKit
import SwiftUI
import XCTest
import SnailCore
@testable import SnailApp

final class DebugSnapshotTests: XCTestCase {
    func testLiveApplyNowUsesNativeStyle() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/SnailApp/SettingsView.swift"))
        // SwiftUI has no public API to inspect the style of a button without a live window.
        var debugDepth = 0
        let liveSource = source.components(separatedBy: .newlines).filter { line in
            let directive = line.trimmingCharacters(in: .whitespaces)
            if directive == "#if DEBUG" { debugDepth += 1; return false }
            if directive == "#endif", debugDepth > 0 { debugDepth -= 1; return false }
            return debugDepth == 0
        }.joined(separator: "\n")
        XCTAssertTrue(liveSource.contains(".buttonStyle(.borderedProminent)"),
                      "Live Apply Now must use the native borderedProminent style.")
        XCTAssertTrue(liveSource.contains(".keyboardShortcut(.defaultAction)"))
        XCTAssertFalse(liveSource.contains("ApplyNowButtonStyle"),
                       "The snapshot stand-in must stay out of the live view.")
    }

    func testSnapshotStyleIsOffByDefault() {
        XCTAssertFalse(EnvironmentValues().isSnapshotCapture)
    }

    @MainActor
    func testCaptureKeepsTopAboveBottom() async throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("snail-orientation.png")
        DebugSnapshots.render(VStack(spacing: 0) {
            Color.red
            Color.blue
        }.frame(width: 80, height: 80), to: url.path, appearance: .aqua)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
        let top = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 4)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(top.redComponent, top.blueComponent, "The top of the PNG must stay red.")
    }

    @MainActor
    func testScenarioManifestListsEveryPNG() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("snail-13-fix-snapshots-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "SnailManifestTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = SnailModel(defaults: defaults, wifiInterface: "en12", samplesAutomatically: false)
        model.debugSimulate(active: nil, error: nil)
        try DebugSnapshots.renderAll(model: model, to: directory.path)
        let manifestURL = directory.appendingPathComponent("manifest.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path), "The snapshot directory must contain manifest.json.")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return }
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        let files = try XCTUnwrap(manifest["files"] as? [String])
        let pngs = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".png") }.sorted()
        XCTAssertEqual(files, pngs)
        XCTAssertTrue(files.contains("settings-pending.png"))
        XCTAssertTrue(files.contains("settings-pending-dark.png"))
    }

    @MainActor
    func testPendingCaptureShowsApplyNowInBothAppearances() async throws {
        _ = NSApplication.shared
        let suite = "SnailSnapshotTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = SnailModel(defaults: defaults, wifiInterface: "en12", samplesAutomatically: false)
        model.debugSimulate(active: ThrottleConfig(kbps: 3_000, interface: "en12"), error: nil)
        XCTAssertTrue(model.hasPendingChanges)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("snail-pending-\(name).png")
            DebugSnapshots.render(SettingsView(model: model).accentColor(.blue), to: url.path, appearance: appearance)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
            let scale = CGFloat(bitmap.pixelsWide) / 480
            var accentPixels = 0
            var brightPixels = 0
            // The interior of Apply Now excludes its border and the surrounding background.
            for y in Int(CGFloat(bitmap.pixelsHigh) - 28 * scale)..<Int(CGFloat(bitmap.pixelsHigh) - 18 * scale) {
                for x in Int(390 * scale)..<Int(450 * scale) {
                    let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    if color.saturationComponent > 0.4 { accentPixels += 1 }
                    if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.8 { brightPixels += 1 }
                }
            }
            XCTAssertGreaterThan(accentPixels, 100, "The \(name) Apply Now button must have an accent fill.")
            XCTAssertGreaterThan(brightPixels, 20, "The \(name) Apply Now label must contrast with its accent fill.")
        }
    }
}
#endif
