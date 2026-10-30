import AppKit
import CoreData
import SwiftUI

// __APP_NAME__
//   __APP_NAME__                      the app
//   APP_STORE=<file> __APP_NAME__     use another database (tests, experiments)
//   APP_SNAPSHOT=<dir> __APP_NAME__   save a PNG of every sidebar page and Settings tab in light and dark mode, then quit
//   APP_SEED=1 __APP_NAME__           fill an empty /tmp store with sample items (tools/snap.sh)
//   __APP_NAME__ --selftest           run the self-test on a /tmp store and quit with 0 or 1 (tools/selftest.sh)

@main
struct __APP_NAME__App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(container: Store.makeContainer())

    var body: some Scene {
        Window("__APP_NAME__", id: "main") {
            ContentView()
                .environment(model)
                .environment(\.managedObjectContext, model.context)
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 1100, height: 720)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            CommandGroup(replacing: .newItem) {
                Button("New Item") { model.addItem() }
                    .keyboardShortcut("n")
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        // Background launches (the agent CLI, snapshots, the self-test) leave the front app alone.
        let env = ProcessInfo.processInfo.environment
        let testRun = !(env["APP_SNAPSHOT"] ?? "").isEmpty && env["APP_SNAPSHOT_FRONT"] != "1"
            || CommandLine.arguments.contains("--selftest")
        if env["APP_BACKGROUND"] != "1" && !testRun { NSApp.activate() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The self-test's result becomes the exit code, after a normal quit.
    /// AppModel saves pending changes on the same notification.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
        if Snapshot.requested { exit(Snapshot.exitCode) }
    }
}

/// Where the data lives: ~/Library/Application Support/__APP_NAME__/__APP_NAME__.store
enum Store {
    /// True when APP_STORE points somewhere else (tests, experiments).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    /// True when APP_STORE is a file in /tmp. Snapshots, seed data, and the
    /// self-test run only then, so they can never touch the real database.
    static var isTestStore: Bool {
        guard isOverridden else { return false }
        let path = url.resolvingSymlinksInPath().path
        return path.hasPrefix("/tmp/") || path.hasPrefix("/private/tmp/")
    }

    /// Preferences. A test run uses its own suite, cleared at start, so it never
    /// writes the real app's preferences.
    static let defaults: UserDefaults = {
        let suite = "__BUNDLE_ID__.tests"
        guard isTestStore, let testing = UserDefaults(suiteName: suite) else { return .standard }
        testing.removePersistentDomain(forName: suite)
        return testing
    }()

    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let dir = URL.applicationSupportDirectory.appending(path: "__APP_NAME__", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "__APP_NAME__.store")
    }

    /// The data model, defined in code. Add an attribute here when you add one to Item.
    /// Give every attribute a default: lightweight migration fills existing rows
    /// with it, and without one a new non-optional attribute fails to open old stores.
    /// Built once and never changed, so sharing it across threads is safe.
    nonisolated(unsafe) static let model: NSManagedObjectModel = {
        func attribute(_ name: String, _ type: NSAttributeType, default value: Any) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = false
            a.defaultValue = value
            return a
        }
        let item = NSEntityDescription()
        item.name = "Item"
        item.managedObjectClassName = NSStringFromClass(Item.self)
        item.properties = [
            attribute("title", .stringAttributeType, default: ""),
            attribute("notes", .stringAttributeType, default: ""),
            attribute("isStarred", .booleanAttributeType, default: false),
            // Rows that exist before a migration get these; new rows get fresh
            // values in Item.awakeFromInsert. A per-row value added later (a new
            // uuid) gives every old row the same default: after the migration,
            // assign real values to rows that still hold it.
            attribute("createdAt", .dateAttributeType, default: Date(timeIntervalSince1970: 0)),
            attribute("uuid", .UUIDAttributeType, default: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!),
        ]
        let model = NSManagedObjectModel()
        model.entities = [item]
        return model
    }()

    static func makeContainer() -> NSPersistentContainer {
        // Snapshots, seed data, and the self-test never open the real database.
        let env = ProcessInfo.processInfo.environment
        let testRun = !(env["APP_SNAPSHOT"] ?? "").isEmpty || env["APP_SEED"] == "1"
            || CommandLine.arguments.contains("--selftest")
        if testRun && !isTestStore {
            print("refused: set APP_STORE to a file in /tmp")
            exit(1)
        }
        let container = NSPersistentContainer(name: "__APP_NAME__", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        // Adding or removing an attribute migrates the store on launch.
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            guard let error else { return }
            // Say what failed and where, instead of crashing on every launch.
            let alert = NSAlert(error: error)
            alert.messageText = "__APP_NAME__ could not open its database"
            alert.informativeText = "\(url.path)\n\n\(error.localizedDescription)\n\nQuit the app and preserve the entire database folder, including its -wal and -shm files, before attempting recovery. Check permissions and available storage. Only start empty deliberately, after preserving the complete folder."
            alert.runModal()
            exit(1)
        }
        return container
    }
}
