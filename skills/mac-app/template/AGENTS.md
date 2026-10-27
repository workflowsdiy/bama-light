# __APP_NAME__

A native macOS app in SwiftUI. It runs on this Mac only, with a local Core
Data database and no server. It builds with Xcode or with only the Command
Line Tools.

## Layout

- `Sources/__APP_NAME__/` the app. `App.swift` has the window, menus, and the database (`Store`).
- `Sources/__APP_NAME__Kit/` logic with no SwiftUI, so tests can run it. Tests in `Tests/`.
- `Package.swift` a Swift package; there is no Xcode project.
- `build.sh` builds, signs, and installs `~/Applications/__APP_NAME__.app`.
- `Icon/AppIcon.icon` the app icon (Icon Composer JSON plus SVG layers). With Xcode it compiles to a Liquid Glass icon; without, `tools/flat_icon.swift` draws a flat one.

## Build and check

- `./build.sh` builds and installs. `--open` restarts the app on the new build and takes focus; leave it out while the person is using the Mac. Fix every warning.
- `tools/test.sh` runs the unit tests. `tools/selftest.sh` runs the app's real functions on a /tmp store and exits 0 when every check passes; add a check in `SelfTest.swift` for new logic.
- `tools/snap.sh` writes `/tmp/__APP_NAME__-shots/<page>-light.png` and `-dark.png` for every sidebar page (newest item selected, `firstItem(on:)`) and Settings tab, with sample data from `SeedData.swift`. Look at them after every UI change. They are taken behind your windows, never taking the keyboard, so they show the inactive look; `--front` shows the active look but takes over the Mac while it runs. Add a capture to `Snapshot.swift` for every state a person can see: sheets, panels, empty, no results, a confirmation, a brief message.
- A check must fail when the code it covers is removed. Write test cases out by hand, never derived from the list the code uses.
- Snapshots, seed data, and the self-test run only when `APP_STORE` is a file in /tmp. Never test against `~/Library/Application Support/__APP_NAME__/`. Tests use `NSPasteboard(name:)`, not `.general`, and preferences go through `Store.defaults`.
- Data: add an attribute to `Item` and to `Store.model` together, with a default.
- A change is done when it builds without warnings, the checks pass, and the light and dark snapshots look right. Then commit, saying what the user can now do.

## Design

- Apple's controls, system colors, the system accent, SF Symbols, `Label`, `ContentUnavailableView` for empty states. No fixed colors for text.
- `.noInitialFocus()` on sheets, Settings, and secondary windows (the main window's sidebar keeps focus), `.fitsContent()` on sheets and Settings tabs (`UI/WindowBehavior.swift`).
- Every action has a menu item and a keyboard shortcut.
- Settings: one tab per topic in `SettingsView.swift`, one grouped Form each.
