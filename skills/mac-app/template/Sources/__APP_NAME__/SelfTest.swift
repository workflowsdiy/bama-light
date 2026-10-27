import AppKit
import ApplicationServices
import CoreData
import __APP_NAME__Kit

/// Self-test for agents: runs the app's real functions on a test store,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/__APP_NAME__-self.store ~/Applications/__APP_NAME__.app/Contents/MacOS/__APP_NAME__ --selftest
/// (tools/selftest.sh does this.) Add a check for every feature with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            let context = model.context
            func items() -> [Item] { (try? context.fetch(Item.all())) ?? [] }

            let before = items().count
            model.addItem()
            check("New Item adds one item", items().count == before + 1)
            check("the new item is selected", model.selection != nil)

            if let item = items().first(where: { $0.objectID == model.selection }) {
                item.isStarred.toggle()
                check("starring an item marks it starred", item.isStarred)
                let undo = UndoManager()
                undo.groupsByEvent = false
                undo.beginUndoGrouping()
                model.delete(item, undoManager: undo)
                undo.endUndoGrouping()
                check("deleting the item removes it", items().count == before)
                undo.undo()
                check("Undo brings the item back", items().count == before + 1)
                undo.redo()
                check("Redo deletes it again", items().count == before)
            }
            check("titles are cleaned", ItemTitle.clean("  Buy   milk ") == "Buy milk")

            // An item deleted outside the window while the window shows it (the agent
            // CLI does this) must not crash the window's views on their next update.
            model.addItem()
            // Put the window on screen behind the others, as a snapshot does: views
            // of a window that is never shown do not update.
            NSApp.windows.forEach { $0.orderBack(nil) }
            if let id = model.selection, let item = try? context.existingObject(with: id) as? Item {
                try? await Task.sleep(for: .seconds(0.5))
                context.delete(item)
                try? model.save()
                try? await Task.sleep(for: .seconds(0.5))
                check("deleting the shown item from outside keeps the window alive", items().count == before)
            }

            // What VoiceOver would read: sidebar pages and a list row.
            model.addItem()
            if let item = items().first(where: { $0.objectID == model.selection }) { item.title = "Labelled row" }
            AXText.enable()
            try? await Task.sleep(for: .seconds(0.5))
            let spoken = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }.map(AXText.texts) ?? []
            check("sidebar pages are labelled", spoken.contains("All Items") && spoken.contains("Starred"), "\(spoken.prefix(8))")
            check("list rows are labelled", spoken.contains("Labelled row"))

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}

/// Text the accessibility tree exposes for a window, for checks that read labels.
/// SwiftUI builds its tree only for an assistive app, so set AXManualAccessibility first
/// (the call returns -25205 and still works). Sidebar and list text is an
/// AccessibilityNode's value, not its label; list rows sit under the table's row views.
@MainActor
enum AXText {
    static func enable() {
        _ = AXUIElementSetAttributeValue(AXUIElementCreateApplication(getpid()), "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    static func texts(in window: NSWindow) -> [String] {
        var out: [String] = []
        var seen = Set<ObjectIdentifier>()
        func value(_ object: NSObject, _ name: String) -> Any? {
            let selector = NSSelectorFromString(name)
            return object.responds(to: selector) ? object.perform(selector)?.takeUnretainedValue() : nil
        }
        func walk(_ object: NSObject) {
            guard seen.insert(ObjectIdentifier(object)).inserted else { return }
            for name in ["accessibilityLabel", "accessibilityValue"] {
                if let text = value(object, name) as? String, !text.isEmpty { out.append(text) }
            }
            for child in value(object, "accessibilityChildren") as? [Any] ?? [] {
                if let node = child as? NSObject { walk(node) }
            }
            if let view = object as? NSView { view.subviews.forEach(walk) }
            if let table = object as? NSTableView {
                for row in 0..<table.numberOfRows {
                    if let rowView = table.rowView(atRow: row, makeIfNecessary: false) { walk(rowView) }
                }
            }
        }
        if let content = window.contentView { walk(content) }
        return out
    }
}
