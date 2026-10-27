# Native Mac app rules (SwiftUI, macOS 26)

Use the system parts first. Add custom design only where the system has nothing.
**macOS 26** items need the macOS 26 SDK.
Template helpers: `.noInitialFocus()`, `.fitsContent()` (`UI/WindowBehavior.swift`), `AppModel`, `SidebarItem`, `SettingsTab`.

## Start here

- Pick the shape first: a sidebar window (most apps), a single-document window, a
  menu bar app, or a quick-capture panel. Write each action down with its menu item and
  shortcut before you build.
- Do not copy iOS layouts. These do not compile for macOS: `.bottomBar`,
  `.topBarLeading`, `.navigationBarTitleDisplayMode`. No bottom bars,
  large titles, floating add buttons, or 44 pt touch targets.

## Windows and focus

- Put `.noInitialFocus()` on every sheet, Settings, and secondary window. Two
  exceptions: a main window whose sidebar list takes focus (it shows a selected row,
  not a ring, and the arrow keys work at once), and a window whose only job is typing
  (quick add, a search panel), which focuses its field on purpose.
- Use `Window` for the one main window and `WindowGroup` only for documents. Open
  another window only from "Open in New Window" or File > New Window.
- Pass a `Codable` value to `openWindow(value:)`, such as the item's `uuid`, never a
  Core Data `objectID`.
- Titles name the content ("Today"), never the app. Every page has a subtitle, or none
  does: one that comes and goes changes the toolbar height, which crashed AppKit on reopen.
- Sheets, popovers, and Settings tabs size to their content with `.fitsContent()`.

## Layout and sidebar

- `NavigationSplitView`: sidebar, content, detail. With one level of navigation, drop
  the sidebar. Keep it to two levels. Rows are pages only, with an SF Symbol and the
  system row height. No "New..." rows.
- Keep the sidebar toggle the split view adds. Never draw a second one. Add
  `SidebarCommands()` so View > Show Sidebar exists.
- Selection details go in a trailing inspector or the detail column.
- An empty page shows one `ContentUnavailableView` with the first action as a button.
- No controls or critical information at the bottom edge of a window.

## Toolbars

- Each toolbar item sits over the column it acts on:
  - Sidebar column: nothing of yours. The system adds the toggle.
  - Content column: actions that make or order rows (New, Sort). Use `.primaryAction`.
  - Detail column: actions on the selection (Share, Flag, Delete). Start with
    `ToolbarSpacer(.flexible)` to push them to the trailing edge.
- Put `.inspector` on the `NavigationSplitView`. Inside the detail view, the inspector
  shares the detail toolbar and items slide over it.
- Do not put `.toolbar` on the `NavigationSplitView` itself. A `.primaryAction` there
  lands at the leading edge of the detail column.
- An empty detail (`ContentUnavailableView`) with no toolbar items lets the content column's
  `.primaryAction` move over it. Give the placeholder `.toolbar { ToolbarSpacer(.flexible) }`.
- The inspector toggle is one button in the inspector's own `.toolbar`, after
  `ToolbarSpacer(.flexible)`. Without the spacer, it jumps when the inspector opens.
  Add no second toggle in the detail toolbar: it shows twice.
- `InspectorCommands()` adds View > Show Inspector (Control-Command-I). Give the toggle
  no second shortcut.
- At most three toolbar groups, split with `ToolbarSpacer(.fixed)`. Borderless,
  monochrome SF Symbols, each with `.help` that starts with a verb and ends with the
  shortcut. Write `Button("New Note", systemImage:)` so the title shows in the overflow menu.
- At most one prominent action (Done, Send), trailing. No Settings button.
- No background, border, or dimming behind the toolbar. Never set the scroll edge
  effect to `.hard`.
- Window-wide search: `.searchable(text:placement: .toolbar)` on the split view. A
  `.searchable` on one column does not move over that column; use `placement: .sidebar`
  to filter only the sidebar. Command-F focuses search (`.searchFocused`).
- Toolbar placement changed between macOS 26 releases. Snapshot the toolbar after each
  OS update. A custom item that does not fit is dropped silently: check the minimum width.

```swift
NavigationSplitView {
    FolderList()                        // no toolbar items of your own
} content: {
    NoteList()
        .navigationSubtitle("\(notes.count) notes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Note", systemImage: "square.and.pencil") { model.addNote() }
                    .help("Create a note (Command-N)")
            }
        }
} detail: {
    NoteEditor()
        .toolbar {
            ToolbarSpacer(.flexible)    // pushes these to the trailing edge
            ToolbarItem { ShareLink(item: note.text) }
        }
}
.inspector(isPresented: $showInspector) {   // on the split view, not the detail
    NoteInfo()
        .toolbar {
            ToolbarSpacer(.flexible)    // keeps the toggle in place when closed
            ToolbarItem {
                Button("Inspector", systemImage: "sidebar.trailing") { showInspector.toggle() }
                    .help("Show or hide the inspector (Control-Command-I)")
            }
        }
}
.searchable(text: $query, placement: .toolbar, prompt: "Search all notes")
```

## Menus and shortcuts

- Every feature has a menu bar item with its shortcut (`.commands`, `CommandGroup`,
  `CommandMenu`). Toolbar buttons and context menu items repeat them; they do not replace them.
- Menu order: App, File, Edit, Format, View, your menus, Window, Help. Keep Window even
  with one window.
- App: About, Settings... (Command-comma), Hide, Quit. File: "New <Noun>", never plain
  "New"; Duplicate, not Save As. Edit: Undo and Redo name the action ("Undo Add Task");
  "Delete", never "Erase". View: Show/Hide Sidebar, Show/Hide Toolbar, Show/Hide
  Inspector, Enter Full Screen.
- Labels are verb phrases in title case. Add "..." only when the command asks for more
  input first ("Export..."). A toggle label follows its state: "Show Map", "Hide Map".
- Disable items that do not apply. Keep them visible. Never ship an item that does nothing.
- Menu titles and enabled state go stale easily; swift.md (Menu commands) has the
  pattern. Check the real menu.
- Standard shortcuts keep their meaning. Every shortcut gives feedback in the same frame.
  Return is the default button, Escape cancels, and new items take focus at once.
- Context menus: `.contextMenu` on every actionable item. Hide items that do not apply
  (Cut, Copy, Paste may dim). Show no shortcuts. Three groups at most, one submenu level.
- A `MenuBarExtra` is an always-on entry point, never the only route to a feature. A menu
  bar app (LSUIElement) returns `false` from `applicationShouldTerminateAfterLastWindowClosed`.

## Settings

- One `Settings` scene, opened with Command-comma. Never a sheet or a page in the main window.
  A menu bar app (LSUIElement) with no other window cannot open the `Settings` scene
  reliably: host `SettingsView` in an `NSWindow` (`NSHostingController`, `.preferredContentSize`,
  `isReleasedWhenClosed = false`) and call `NSApp.activate()` before showing it.
- `TabView` with one tab per topic (two to six tabs; a tab needs more than about three rows).
  Each tab is one `Form` with `.formStyle(.grouped)`, `.fitsContent()`, and `.frame(width: 520)`.
  The scene gets `.windowResizability(.contentSize)`. Put `.noInitialFocus()` on the `TabView`.
- Settings apply at once. No Save, Apply, or Cancel.
- Labels state what the setting does: "Show the menu bar item", not "Enable menu bar".
  Help text goes in the section footer.
- Do not repeat system settings (accent, text size, appearance). Add a button that opens
  the System Settings pane instead. Permission rows show state plus that button.

## Sheets, popovers, panels, and alerts

| The need | Use |
| --- | --- |
| Change one value already on screen | Inline edit |
| Details of the selection while people keep working | Inspector |
| A few related choices tied to one control | Popover |
| Repeated input with live results, or a tool kept beside the work | Panel (`UtilityWindow`, macOS 15 or later) |
| One short task that must finish or cancel | Sheet |
| A long or self-contained task | New window |
| A rare action that destroys data and cannot be undone | Confirmation dialog |
| A problem that needs action now | Alert |

- One modal at a time: never a popover from a popover, or a sheet from a sheet.
  A popover closes on an outside click and keeps its changes; only Cancel discards.
- A sheet has a fixed width and fits its height to content. Its title names the task
  ("Rename Project", not "Edit"). Return runs the confirm button; Escape runs Cancel.
  A sheet that needs a sidebar or a long scroll should be a window.
- Information that needs no action goes inline. Alerts never appear at launch, never just
  to inform, and never for a delete Undo covers. Buttons name the action.
- Ask before closing only when typed work would be lost.
- A quick-capture panel is borderless and non-activating. Its field takes focus. Return
  saves and closes at once, with the save running in the background. Escape closes.

## Liquid Glass and color

- Glass is for the control layer only: toolbars, sidebars, floating controls, popovers,
  and a quick-capture panel. Never on rows, cards, or document content.
- Never glass on glass. Group neighboring custom glass in `GlassEffectContainer`. **macOS 26**
- Standard bars, sidebars, and sheets get glass on their own. Delete custom backgrounds
  behind them.
- `.glassEffect()` only on a custom floating control, applied to the control itself.
  Interactive glass only on controls, sparingly. Tint only to carry meaning, and tint the
  background, never the glyph.
- Rich content under a sidebar or inspector: `.backgroundExtensionEffect()`. **macOS 26**
- Nested corners are concentric. Use `ConcentricRectangle` (or
  `.rect(corners: .concentric(minimum:))`) for a part that is both nested and alone. **macOS 26**
- Custom sidebar and toolbar parts dim with the window: read `@Environment(\.appearsActive)`.
  Not for HUDs or non-activating panels.
- Text uses `.primary`, `.secondary`, and `.tertiary`. Backgrounds use system colors.
  Never fixed white, black, or gray in chrome, and never copy a system color's value.
- One accent color. A status color always comes with an icon or a word.
- Accent-colored text uses one token: a deep shade in light mode, a light shade in dark
  mode. Text on an accent fill uses the matching on-accent color, never fixed `.white`,
  which fails on yellow and green.
- Hover and press never lower contrast. Text over screenshots or video sits on a dark scrim.
- Body text contrast is at least 4.5:1 in both modes. Add an appearance setting only if
  the owner asks, defaulting to System.
- Use text styles, not fixed sizes. Body is 13 pt, headline is bold 13 pt, nothing under
  10 pt. No Ultralight, Thin, or Light weights in UI text.

## Lists, tables, search, and drag

- A `List` whose rows change with the sidebar page gets `.id(page)`, or AppKit warns about a
  reentrant table update on page switches.
- Lists support multi-select. Every action applies to every selected row. When an action
  removes the selected row, select the next one. Tables sort on a header click and
  reverse on a second; columns remember widths (`customizationID`).
- A search with no results shows `ContentUnavailableView.search(text:)`.
- Selectable rows are a `List(selection:)`. Rows you draw yourself (a non-activating
  panel, where `List` logs reentrant table warnings) need a label and the button and
  selected traits, or VoiceOver cannot use them.
- Drag out gives a real file or plain text, never an internal id. Build it with
  `Transferable`, and offer a menu alternative.

## Undo, state, and quitting

- Every destructive or bulk action has Undo, in Settings too. A one-click trash button
  needs Undo in place.
- Register undo yourself on `@Environment(\.undoManager)`, name it with `setActionName`,
  and look up the object again by a stable id inside the closure. Do not set
  `context.undoManager = UndoManager()`: a separate manager never reaches Edit > Undo.
- With Core Data and `groupsByEvent` off, wrap each registration in
  `beginUndoGrouping()` and `endUndoGrouping()`. Otherwise the undo manager raises an
  exception that crashes later inside SwiftUI.
- Relaunch restores UI state with `@SceneStorage`: selection, scroll position, column
  widths, the open tab. Store the item's `uuid`, never its data.
- Quit never asks unless typed work would be lost. A toast that hides itself is never
  the only way to act, and an error never lives only in a toast.
- An app that keeps running with no window (a menu bar app) hides its main window
  instead of closing it: on macOS 26, closing a SwiftUI `Window`, reopening it, and
  changing state crashed AppKit. Give the window an `NSWindowDelegate` (get the window
  from an `NSViewRepresentable`'s `view.window`, as `WindowHook` does) whose `windowShouldClose` calls `orderOut(nil)` and returns `false`.

## Words and checks

- Say "click", never "tap"; "window", never "scene"; "Settings", never "Preferences".
  Use Delete only when the item cannot come back.
- Snapshot every page, Settings tab, sheet, and panel in light and dark. Shots run behind
  the person's windows (gray traffic lights and selection); `--front` shows the active
  look but takes the keyboard, so use it only when nobody is at the Mac.
- To check labels in the self-test, use `AXText` (in the template's `SelfTest.swift`): it sets
  `AXManualAccessibility` (the call returns -25205 and still works), then reads each node's
  `accessibilityValue`, since SwiftUI text is not a label, and walks table row views for list rows.
- Look for a focus ring, selected text, an unneeded scroll bar, an empty band under short
  content, and a toolbar item over the wrong column. Check the real menu bar too.
