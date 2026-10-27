---
name: mac-app
description: Build or change a small native macOS app in SwiftUI, with or without Xcode, from a working template with snapshot checks and a self-test. Use when the user wants a Mac app, a menu bar utility, or a change to an app made from this template.
---

# Mac app

Small, personal, native Mac apps: one person's tool, local data, no server.
You already know Swift and SwiftUI. This skill adds a template that builds
without Xcode, a way to see every page as a PNG, and the Mac-specific
traps that are easy to get wrong.

## Toolchain

Run `xcode-select -p`. Everything works either way; Xcode only adds extras.

| | Command Line Tools only | With Xcode |
| --- | --- | --- |
| Build, run, sign | `./build.sh` | same |
| Unit tests | `tools/test.sh` adds the framework flags | same script |
| App icon | flat `.icns` from the layers | Liquid Glass icon (`actool`) |
| Data | Core Data, model in code (the template) | same, or SwiftData |
| Profiling | `sample`, `footprint`, `leaks` | plus Instruments |
| App Intents, widgets, extensions | not available | need an Xcode project |

Never ask the user to install Xcode for something the left column covers.

## How to build an app

1. **Agree the scope in chat.** What the app does, its main pages, its one
   data type, and what it leaves out (accounts, sync, sharing). Keep the
   plan in the conversation, not in a file in the repository.
2. **Design, when the layout is not obvious.** Otherwise go straight to
   SwiftUI. [design.md](design.md): real Mac apps, galleries for mood, two
   or three mockups, and the user picks.
3. **Scaffold.** `scripts/new-app.sh <AppName> <bundle-id> <parent-folder>`
   creates the app and its first commit. Rename `Item`, the sidebar pages,
   and `firstItem(on:)` to the app's own, then `./build.sh`. Add `--open` only
   when the person wants the app brought forward: it takes focus. For a
   menu bar app, delete the main window and sidebar, start the model from
   the app delegate, and point `Snapshot.swift`, `SelfTest.swift`, and the
   two tool scripts at the panel and its states instead of sidebar pages.
4. **Build one feature at a time.** For each: write the code, add sample
   data and a self-test check for its logic, then:

   ```bash
   ./build.sh && tools/selftest.sh && tools/test.sh && tools/snap.sh
   ```

   Read the light and dark PNGs in `/tmp/<AppName>-shots/`. Fix what looks
   wrong, run again, and commit with a message that says what the user can
   now do.

The app's own `AGENTS.md` (also read through `CLAUDE.md`) repeats the
commands and rules for later sessions.

## Rules that matter most

- Apple's controls, system colors, the system accent, SF Symbols. Window
  chrome, menus, sheets, and alerts stay native.
- Every action has a menu item and a keyboard shortcut.
- Windows open calm: no focus ring or selected text on open
  (`.noInitialFocus()`), and sheets and Settings sized to their content
  (`.fitsContent()`). See native.md.
- Tests, snapshots, and seed data use a store in /tmp, never the real one.
- The snapshot PNGs are the check for anything visual. Without Screen
  Recording permission they fall back to a drawing that leaves sidebars and
  glass blank; say so instead of trusting those areas.

## References

Read the one you need:

- [native.md](native.md): what makes it feel like a Mac app (toolbars,
  menus, windows, Settings, sheets and popovers, Liquid Glass).
- [swift.md](swift.md): Swift 6 and SwiftUI traps, and the Core Data
  pattern the template uses.
- [system.md](system.md): global hotkeys, menu bar, panels, other apps'
  windows, screen capture, permissions, and signing that keeps them.
- [performance.md](performance.md): measuring and fixing slowness.
- [design.md](design.md): inspiration and mockups.

To let Claude, Codex, or scripts drive the finished app, use the
`agent-cli` skill.
