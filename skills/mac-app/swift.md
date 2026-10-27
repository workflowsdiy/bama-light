# Swift and SwiftUI on macOS

Done means zero warnings in Swift 6 language mode and the feature works. For looks, see [design.md](design.md). For system hooks (hotkeys, Accessibility, capture), see [system.md](system.md).

## Isolation

The app target defaults to the main actor (`defaultIsolation(MainActor.self)` in Package.swift). Its types and functions run on the main actor unless marked otherwise. The `<App>Kit` library keeps Swift's default (nonisolated), so its logic builds and tests without the app.

| Work | Put it in |
| --- | --- |
| Views, UI state, view models | App target, default |
| Rules and pure logic | Kit target |
| Heavy pure work off the main thread | `nonisolated` function marked `@concurrent` |
| Shared mutable state used off the main thread | `actor` |
| C callback (event tap, Carbon hotkey, CoreAudio listener) | `nonisolated` static func that hops back with `Task { @MainActor in ... }` |

Values that cross actors must be `Sendable`. A type in the app target that background code uses must be `nonisolated`, or it stays on the main actor:

```swift
nonisolated struct Chunk: Sendable { var bytes: [UInt8] }

@concurrent nonisolated func checksum(_ chunk: Chunk) async -> Int { chunk.bytes.reduce(0) { $0 &+ Int($1) } }
```

**Runtime trap the compiler misses.** A closure written in a `@MainActor` type, and passed to an API whose closure parameter is not `@Sendable` (`DispatchSource.setEventHandler`, `DispatchWorkItem`, C block APIs), inherits the main actor. When the API runs that closure on a background queue, the app traps. The compiler accepts the unsafe form. Mark the closure `@Sendable` and hop back:

```swift
import Foundation

@MainActor final class Ticker {
    private var source: DispatchSourceTimer?
    private(set) var count = 0

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.setEventHandler { @Sendable [weak self] in
            Task { @MainActor in self?.count += 1 }
        }
        timer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(10))
        timer.resume()
        source = timer
    }
}
```

- After any concurrency change, run each background path once. The compiler does not catch this class of bug.
- `MainActor.assumeIsolated { }` only in a callback you know runs on the main thread, such as a main run loop timer or a main queue observer.
- `Task { }` inherits the actor. Use `Task.detached` only when it must not.
- A task's result can land after newer state: a newer request, a reset, another selection. Tag the work with a generation number or the item's id, and drop a stale result instead of applying it.
- Fix a concurrency error at its type. `@unchecked Sendable` and `nonisolated(unsafe)` are last resorts, each with a comment that says why.
- The Kit target has no default isolation, so a static stored property of a non-Sendable type is an error there. `ISO8601DateFormatter` is one such type on the macOS 26 SDK. Fix it with a `@MainActor` enclosing type, or a computed property that builds a new value per call.

## State

- `@Observable` classes for models. The view that owns one holds it in `@State`, `@Bindable` binds its properties, and `.environment(model)` shares it.
- `@State` for view-local values, `@AppStorage` for small preferences, Keychain for secrets. Mark caches, timers, and handles `@ObservationIgnored`.
- Never write `model.child?.field = f(model.child)` on an `@Observable` type. The read and the write overlap, and the app traps in debug and release builds. Read the value into a `let` first, then write.
- `ForEach(items)` over values. Never `ForEach($items)` over data the user can delete: a row can read an index that no longer exists and crash. Build each row's binding by looking up the item by id, inside `Binding(get:set:)`.

## Menu commands

SwiftUI `Commands` do not reliably update from an `@Observable` model. A title or `.disabled(...)` that reads the model goes stale. Mirror the selection into an `ObservableObject` that the `App` observes, and pass the values into the commands:

```swift
import SwiftUI

@MainActor final class MenuState: ObservableObject {
    static let shared = MenuState()
    @Published private(set) var selection: Set<UUID> = []
    func update(_ ids: Set<UUID>) { if selection != ids { selection = ids } }
}

@Observable final class Library {
    var selection: Set<UUID> = [] { didSet { MenuState.shared.update(selection) } }
    func deleteSelected() { /* remove the rows in selection */ }
}

struct AppCommands: Commands {
    let library: Library
    let selectedIDs: Set<UUID>
    var body: some Commands {
        CommandMenu("Items") {
            Button("Delete Selected") { library.deleteSelected() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(selectedIDs.isEmpty)
        }
    }
}

@main struct DemoApp: App {
    @State private var library = Library()
    @ObservedObject private var menu = MenuState.shared
    var body: some Scene {
        Window("Demo", id: "main") { Text("Demo") }
            .commands { AppCommands(library: library, selectedIDs: menu.selection) }
    }
}
```

- SwiftUI sets menu titles and shortcuts when a menu opens. A test that reads `NSApp.mainMenu`
  first calls `submenu.delegate?.menuNeedsUpdate?(submenu)`.
- `NavigationSplitView` adds a hidden "Toggle Sidebar" item on Option-Command-S (Help menu). Avoid that shortcut for your own commands.

Resolve the target again when the item fires. Never leave an item enabled that does nothing. Do not use Delete, Command-Delete, arrows, or Return as menu shortcuts: a menu shortcut also fires while a text field has focus. Handle those keys on the list with `.onDeleteCommand` and `.onKeyPress`.

## AppKit bridges

SwiftUI covers windows, lists, and forms. Use AppKit for:

- Floating panels that do not take focus: an `NSPanel` with `.nonactivatingPanel` that hosts SwiftUI in an `NSHostingView` (`sizingOptions = []` for a fixed size).
- Key and mouse monitors: `NSEvent.addLocalMonitorForEvents`. Remove the monitor in a stop method.

A menu item subclass in the app target fails to compile unless the class is `nonisolated` and its action is `@MainActor @objc func`.

## Compiler errors

| Error | Fix |
| --- | --- |
| `cannot find 'X' in scope` right after adding a file | Delete the build folder (the scratch path in the build script) and build again |
| `Main actor-isolated ... from a nonisolated context` | Make the caller `@MainActor`, or move the call into `await MainActor.run { }` |
| `Sending 'x' risks causing data races` | Make the type `Sendable` (a struct of `Sendable` values), or keep it on one actor |
| `static property 'x' is not concurrency-safe because non-'Sendable' type` | Use the fix in Isolation above |
| `main actor-isolated initializer ... different actor isolation from nonisolated overridden declaration` | The `NSMenuItem` subclass fix above |
| `The compiler is unable to type-check this expression` | Split the view into subviews, or name the parts with `let` |

Fix the first error first. Later errors often come from it. Never name a type `Task`, `View`, `Color`, `Image`, `Text`, `Section`, `Label`, `Menu`, `Group`, or `Settings`. Use `TaskItem` or `NoteSection`.

## Data: Core Data with the model in code

Command Line Tools have no SwiftData macros (`@Model`), so the template uses Core Data with the model in code. An app built with Xcode may use SwiftData instead. Source: the template's `App.swift` and `Models.swift`.

- `Store.model` defines the entity in code. `Item` is an `NSManagedObject` subclass with `@objc(Item)` and `@NSManaged` properties. `Store.makeContainer()` opens the store in `~/Library/Application Support/<App>/`, and `APP_STORE` overrides the path for tests.
- `AppModel` saves each change on the next run loop turn, so views never call `save()`. If a save fails, `save()` rolls back the unsaved changes and throws.
- To add an attribute, change two places, and give it a default in the model:
  1. `@NSManaged var priority: Int64` in `Item`.
  2. `attribute("priority", .integer64AttributeType, default: 0)` in `Store.model`.
  Existing rows get the default when the store migrates. Migration needs only the in-code model: each store keeps its own copy of the old model (table `Z_MODELCACHE`).
- Set per-row values (ids, dates) in `awakeFromInsert`. A per-row attribute added later gives old rows one shared default, so assign them real values once.
- A new non-optional attribute with no default makes a store that has rows fail to open, with "missing attribute values on mandatory destination attribute".
- Do not rename or change the type of an attribute in place. Add a new attribute and copy the values.
- A view holding an item (`@ObservedObject`: a form, a row) can draw once more after the item is deleted, and reading a deleted object's attribute traps. Guard every such `body` with `if !item.isGone` (the template's `Item.isGone`).
- An `objectID` is temporary until the first save. Select items by your own `uuid`, or save first.

Codable files have the same trap. Adding a non-optional property makes old files fail to decode (`keyNotFound`), and a re-saved file gains the new key, so its bytes change. Decode new keys with `decodeIfPresent` in a custom `init(from:)`. If other tools compare the file byte for byte, keep a test that loads an old file, saves it, and compares the bytes.

Files a record names (images, attachments): write the file before the record, and delete it only after the save that drops the record succeeds. A stored file name is untrusted input: accept only a plain name inside the app's folder.
