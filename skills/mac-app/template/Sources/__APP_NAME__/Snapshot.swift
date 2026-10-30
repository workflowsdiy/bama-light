import AppKit
import IOKit.pwr_mgt
import SwiftUI

/// Screenshot mode for agents.
///   APP_STORE=/tmp/test.store APP_SNAPSHOT=/tmp/shots ~/Applications/__APP_NAME__.app/Contents/MacOS/__APP_NAME__
/// writes <page>-light.png and <page>-dark.png for every sidebar page, and
/// settings-<tab>-light.png and settings-<tab>-dark.png for every Settings tab, then quits.
/// APP_SNAPSHOT_PAGES=all,starred limits the pages. Add "settings" to include Settings.
enum Snapshot {
    static var requested: Bool { !(ProcessInfo.processInfo.environment["APP_SNAPSHOT"] ?? "").isEmpty }
    static var exitCode: Int32 = 1

    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",", omittingEmptySubsequences: false).map(String.init)) }
        setvbuf(stdout, nil, _IOLBF, 0)
        Task {
            do {
                let allowed = Set(SidebarItem.allCases.map(\.rawValue) + ["settings"])
                if let only, only.isEmpty || !only.isSubset(of: allowed) {
                    throw failure("APP_SNAPSHOT_PAGES must select from: \(allowed.sorted().joined(separator: ", "))")
                }
                let pages = SidebarItem.allCases.filter { only?.contains($0.rawValue) ?? true }
                let settingsRequested = only == nil || only?.contains("settings") == true
                let names = pages.map(\.rawValue) + (settingsRequested ? SettingsTab.allCases.map { "settings-\($0.rawValue)" } : [])
                guard !names.isEmpty else { throw failure("no snapshots selected") }
                for name in names { for mode in ["light", "dark"] { print("SNAPSHOT expected \(dir)/\(name)-\(mode).png") } }
                // A sleeping display gives screencapture nothing. Declaring user
                // activity wakes it; the assertion keeps it on until the run quits.
                var activity: IOPMAssertionID = 0
                IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
                var awake: IOPMAssertionID = 0
                IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                            IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
                defer { IOPMAssertionRelease(activity); IOPMAssertionRelease(awake) }
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                if env["APP_SNAPSHOT_FRONT"] != "1" { NSApp.windows.forEach { $0.orderBack(nil) } }
                try? await Task.sleep(for: .seconds(1.5))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for page in pages {
                        model.sidebar = page
                        model.selection = model.firstItem(on: page)
                        try? await Task.sleep(for: .seconds(0.8))
                        try capture(to: "\(dir)/\(page.rawValue)-\(mode).png")
                    }
                }
                if settingsRequested {
                    let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                    openSettings()
                    try? await Task.sleep(for: .seconds(1))
                    for mode in ["light", "dark"] {
                        NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                        for tab in SettingsTab.allCases {
                            model.settingsTab = tab
                            try? await Task.sleep(for: .seconds(0.8))
                            guard let settings = NSApp.windows.first(where: { $0.isVisible && $0 !== main && !$0.isSheet }) else {
                                throw failure("Settings window did not open")
                            }
                            try capture(to: "\(dir)/settings-\(tab.rawValue)-\(mode).png", window: settings)
                        }
                    }
                }
                print("SNAPSHOT done \(dir)")
                exitCode = 0
            } catch {
                print("SNAPSHOT failed: \(error.localizedDescription)")
            }
            // An open sheet refuses terminate, and the run would wait forever.
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            NSApp.terminate(nil)
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "Snapshot", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func validImage(at path: String) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let image = NSBitmapImageRep(data: data) else { return false }
        return image.pixelsWide > 0 && image.pixelsHigh > 0
    }

    /// Captures the real window with screencapture, including glass and sidebars.
    /// Without Screen Recording permission, drawing the view hierarchy is a lower-fidelity fallback.
    private static func capture(to path: String, window: NSWindow? = nil) throws {
        // Another app can hide this one while snapshots run (computer use hides
        // apps it does not control). Hidden windows cannot be captured.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = window ?? NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            throw failure("no window for \(path)")
        }
        if ProcessInfo.processInfo.environment["APP_SNAPSHOT_FRONT"] == "1" {
            // Active, like a window someone is using: real accent colors and focus
            // rings. This takes the keyboard from whoever is using the Mac.
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            // macOS may take a moment to bring the app forward, or refuse while another
            // app's dialog is in front. An inactive window shows gray traffic lights.
            for _ in 0..<30 where !(NSApp.isActive && window.isKeyWindow) {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            }
            if !window.isKeyWindow { print("SNAPSHOT warning: window not active for \(path)") }
        } else {
            // Behind every other window and never active, so the person at the
            // Mac keeps working. screencapture -l still sees the whole window;
            // it shows inactive chrome (gray traffic lights and selection).
            // A search field whose text was set in code keeps light text in dark
            // shots of a never-key window: set its stringValue again before capturing.
            // A panel at a floating level stays above other windows: set its
            // level to .normal first when you add a capture for one.
            window.orderBack(nil)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        }
        try? FileManager.default.removeItem(atPath: path)
        // The first capture of a run sometimes misses the window. Try three times.
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try shot.run()
            shot.waitUntilExit()
            if shot.terminationStatus == 0, validImage(at: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw failure("no bitmap for \(path)") }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw failure("PNG encoding failed for \(path)") }
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        guard validImage(at: path) else { throw failure("invalid PNG at \(path)") }
        print("SNAPSHOT \(path) (fallback: no Screen Recording permission, sidebars and glass are blank)")
    }
}
